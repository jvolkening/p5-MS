package MS::Search::DB::Source::uniprot;

use strict;
use warnings;

use HTTP::Tiny;
use URI::Escape;
use FileHandle;

sub new {

    my ($class, %args) = @_;

    die "Odd number of arguments\n" if ( (scalar keys %args)%2 != 0 );
    my $self = bless {%args} => $class;

    return $self;

}

sub fetch_fh {

    my ($self) = @_;


    my ($rdr, $wtr) = FileHandle::pipe;
    my $pid = fork;

    if ($pid) {

        close $wtr;
        return($rdr, $pid);

    }
    else {

        close $rdr;

        my $ref_only = $self->{reference_only} ? 'yes' : 'no';
        my $top_node = $self->{taxid} // die "No taxon specified\n";
        die "Taxon must be integer ID\n" if ($top_node =~ /\D/);

        my $list_url = "http://www.uniprot.org/proteomes/?query=reference:$ref_only+taxonomy:$top_node&format=list";

        my $resp = HTTP::Tiny->new->get($list_url);
        die "Failed to fetch proteome list: $resp->{status} $resp->{reason}\n"
            if (! $resp->{success});

        my $fasta;
        my $want;
        for (split /\r?\n/, $resp->{content}) {
            my $id = uri_escape($_);
            warn "Fetching $id\n";
            my $fetch_url = "http://www.uniprot.org/uniprot/?query=proteome:$id&format=fasta";
            my $resp = HTTP::Tiny->new->get( $fetch_url, { data_callback
                => sub { print {$wtr} $_[0] if ($_[1]->{status} < 300 ) } } );
            die "Failed to fetch sequencesf for $_: $resp->{status} $resp->{reason}\n"
                if (! $resp->{success});
        }
        close $wtr;
        exit;

    }

}

1;
        
