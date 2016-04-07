package MS::Parser::MzML::Chromatogram;

use strict;
use warnings;

use base qw/MS::Parser::MzML::Record/;
use MS::CV qw/:constants/;
use List::Util qw/any/;

sub _toplevel { return 'chromatogram'; }

sub new {

    my ($class, %args) = @_;
    my $self = bless {}, $class;

    # if xml is provided, we read chromatogram from that
    if (defined $args{xml}) {
        return $class->SUPER::new(%args);
    }

    # else we generate it based on other parameters
    die "must specify either 'xml' or 'type' for new chromatogram"
        if (! defined $args{type});
    die "must provide mzML object to generate chromatogram on-the-fly"
        if (! defined $args{raw} || ! $args{raw}->isa("MS::Parser::MzML"));

    # save current spectrum position
    my $mzml = $args{raw};
    my $last_pos = $mzml->{pos}->{spectrum};

    if ($args{type} eq 'xic') {
        $self->_calc_xic(%args);
    }
    elsif ($args{type} eq 'tic') {
        $self->_calc_ic(%args);
    }

    # restore current spectrum position
    $mzml->{pos}->{spectrum} = $last_pos;

    return $self;

}

sub _calc_xic {

    my ($self, %args) = @_;

    die "XIC generation requires parameters 'mz', 'err_ppm'"
        if (any {! defined $args{$_} } qw/mz err_ppm/);

    my $mzml = $args{raw};
    my @rt;
    my @int;

    my $mz_lower = $args{mz} - $args{err_ppm} * $args{mz} / 1000000;
    my $mz_upper = $args{mz} + $args{err_ppm} * $args{mz} / 1000000;
    my $rt_lower = defined $args{rt} ? $args{rt} - $args{rt_win} : undef;
    my $rt_upper = defined $args{rt} ? $args{rt} + $args{rt_win} : undef;

    $mzml->{pos}->{spectrum} = defined $rt_lower
        ? $mzml->find_by_time($rt_lower)
        : $mzml->{start_record}->{spectrum};
    while (my $spectrum = $mzml->next_spectrum( filter => [&MS_LEVEL => 1] )) {
        last if (defined $rt_upper && $spectrum->rt > $rt_upper);
        my $ion_sum = 0;
        my @mz  = $spectrum->mz;
        my @scan_int = $spectrum->int;
        for (0..$#mz) {
            next if ($mz[$_] < $mz_lower);
            last if ($mz[$_] > $mz_upper);
            $ion_sum += $scan_int[$_];
        }
        push @rt, $spectrum->rt;
        push @int, $ion_sum;
    }
    $self->{rt}  = [@rt];
    $self->{int} = [@int];

    return;

}

sub _calc_ic {

    my ($self, %args) = @_;
       
    my $mzml = $args{raw};
    my $acc = $args{type} eq 'tic' ? TOTAL_ION_CURRENT
            : $args{type} eq 'bpc' ? BASE_PEAK_INTENSITY
            : die "unexpected chromatogram type requested";
    my @rt;
    my @int;
    $mzml->reset_spectrum();
    while (my $spectrum = $mzml->next_spectrum( filter => [&MS_LEVEL => 1] )) {
        my $current = $spectrum->{cvParam}->{$acc}->[0]->{value};
        push @rt, $spectrum->rt;
        push @int, $current;
    }
    $self->{rt}  = [@rt];
    $self->{int} = [@int];

    return;

}

sub int {
    my ($self) = @_;
    return @{$self->{int}} if (defined $self->{int});
    return $self->get_array(INTENSITY_ARRAY);
}

sub rt {
    my ($self) = @_;
    return @{$self->{rt}} if (defined $self->{rt});
    return $self->get_array(TIME_ARRAY);
}

1;
