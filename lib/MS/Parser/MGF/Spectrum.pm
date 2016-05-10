package MS::Parser::MGF::Spectrum;

use strict;
use warnings;

use Carp;

use parent qw/MS::Spectrum/;

sub new {

    my ($class, $data) = @_;

    my $self = bless {}, $class;
    $self->{mz}  = [];
    $self->{int} = [];
    $self->_parse($data);

    return $self;

}

sub _parse {

    my ($self, $data) = @_;

    my @mz;
    my @int;
    LINE:
    for my $line (split /\r?\n/, $data) {
        
        chomp $line;
        if ($line =~ /^(\w+)\=(.+)$/) {
            my ($key, $val) = ($1, $2);
            croak "$key already defined\n"
                if (exists $self->{$key});
            $self->{$key} = $val;
            next LINE;
        }
        my ($mz,$int) = split ' ', $line;
        push @mz, $mz;
        push @int, $int;

    }

    $self->{mz} = [@mz];
    $self->{int} = [@int];

}

sub id  { return $_[0]->{TITLE}    }

sub mz  { return @{ $_[0]->{mz} }  }

sub int { return @{ $_[0]->{int} } }

sub ms_level { return -1 } # unknown - usually MS2 but not guaranteed

sub rt {

    my ($self) = @_;
    die "Spectrum does not contain retention time annotation\n"
        if (! defined $self->{RTINSECONDS} );
    return $self->{RTINSECONDS};

}


sub dump {

    my ($self) = @_;

    use Data::Dumper;

    local $Data::Dumper::Indent = 1;
    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Sortkeys = 1;

    return Dumper $self;

}

1;
