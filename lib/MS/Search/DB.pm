package MS::Search::DB;

use strict;
use warnings;

use BioX::Seq::Stream;
use BioX::Seq::Fetch;
use Net::FTP;
use HTTP::Tiny;
use URI;
use FileHandle;
use List::Util qw/shuffle/;
use Module::Pluggable
    require => 1, sub_name => 'sources', search_path => ['MS::Search::DB::Source'];

sub new {

    my ($class, $fn) = @_;

    my $self = bless {} => $class;

    $self->add_from_file($fn) if (defined $fn);

    return $self;

}

sub add_decoys {

    my ($self, %args) = @_;

    $self->{decoys} = [];
    my $type   = $args{type}   // 'reverse';
    my $prefix = $args{prefix} // 'DECOY_';
    my $added = 0;
    for my $seq (@{ $self->{seqs} }) {

        my $new = $type eq 'reverse' ? reverse $seq
                : $type eq 'shuffle' ? join( '', shuffle( split '', $seq ) )
                : die "Unknown decoy type: $type\n";
        my $decoy = BioX::Seq->new(
            $new,
            $prefix . $seq->id,
            $seq->desc,
            undef
        );

        push @{ $self->{decoys} }, $decoy;
        ++$added;
    } 

    return $added;

}

sub add_from_source {

    my ($self, %args) = @_;

    my $added = 0;
    for my $src ($self->sources) {
        next if ($src ne "MS::Search::DB::Source::$args{source}");
        delete $args{source};
        my $f = $src->new(%args);
        my ($fh, $pid) = $f->fetch_fh;
        my $p = BioX::Seq::Stream->new($fh);
        while (my $seq = $p->next_seq) {
            push @{ $self->{seqs} }, $seq;
            ++$added;
        }
        close $fh;
        waitpid($pid, 0);
        last;
    }

    return $added;

}

sub add_from_file {

    my ($self, $fn) = @_;

    die "File not found\n" if (! -e $fn);

    my $added = 0;
    my $p = BioX::Seq::Stream->new($fn);
    while (my $seq = $p->next_seq) {
        push @{ $self->{seqs} }, $seq;
        ++$added;
    }

    return $added;

}


sub add_from_url {

    my ($self, $url) = @_;

    my ($rdr, $wtr) = FileHandle::pipe;

    my $pid = fork;
    my $added = 0;

    if ($pid) {

        close $wtr;
        my $p = BioX::Seq::Stream->new($rdr);
        while (my $seq = $p->next_seq) {
            push @{ $self->{seqs} }, $seq;
            ++$added;
        }
        waitpid($pid,0);
        close $rdr;
        

    }
    else {

        close $rdr;
        my $u = URI->new($url);
        if ($u->scheme eq 'ftp') {
            my $ftp = Net::FTP->new($u->host, Passive => 1);
            $ftp->login or die "Failed login: $@\n";
            $ftp->get($u->path => $wtr)
                or die "Download failed\n";
        }
        elsif ($u->scheme eq 'http') {
            my $resp = HTTP::Tiny->new->get($u, { data_callback
                => sub { print {$wtr} $_[0] } } );
            die "Download failed\n" if (! $resp->{success});
        }
        else {
            die "Only FTP and HTTP downloads are currently supported\n";
        }
        close $wtr;
        exit;

    }

    return $added;

}

sub write {

    my ($self, %args) = @_;

    my $fh = $args{fh} // \*STDOUT;

    my @pool;
    push @pool, map {[$_,'seqs']} 0..$#{ $self->{seqs}   };
    push @pool, map {[$_,'decoys']} 0..$#{ $self->{decoys} };

    @pool = shuffle @pool if ($args{randomize});

    for (@pool) {
        print {$fh} $self->{$_->[1]}->[$_->[0]]->as_fasta;
    }

    return;

}

sub add_crap {

    my ($self, $url) = @_;

    $url //= 'ftp://ftp.thegpm.org/fasta/cRAP/crap.fasta';

    $self->add_from_url($url);

}


1;
