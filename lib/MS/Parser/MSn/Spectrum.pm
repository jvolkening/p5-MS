package MS::Parser::MSn::Spectrum;

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

        my ($field, @data) = split ' ', $line;

        if ($field eq 'S') {
            my ($lo_scan, $hi_scan, $pre_mz) = @data;
            $self->{ms_level} = defined $pre_mz ? 2 : 1;
            $self->{start_scan}      = $lo_scan;
            $self->{end_scan}        = $hi_scan;
            $self->{precursor}->{mz} = $pre_mz if (defined $pre_mz);
        }
        elsif ($field eq 'Z') {
            $self->{precursor}->{charge} = $data[0];
            $self->{precursor}->{MH}     = $data[1];
        }
        elsif ($field eq 'I') {
            $self->{I}->{$data[0]} = $data[1];
        }
        elsif ($field eq 'D') {
            $self->{D}->{$data[0]} = $data[1];
        }
        else {
            push @mz,  $field;
            push @int, $data[0];
        }

    }

    $self->{mz} = [@mz];
    $self->{int} = [@int];

}

sub id  { return $_[0]->{start_scan} }

sub mz  { return $_[0]->{mz} }

sub int { return $_[0]->{int}}

sub ms_level { return $_[0]->{ms_level} }

sub rt {

    my ($self) = @_;
    for (qw/RT RTime/) {
        return $self->{I}->{$_} if (exists $self->{I}->{$_});
    }
    die "Spectrum does not contain retention time annotation\n";

}

1;
