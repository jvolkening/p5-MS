package MS::Reader::MzML::Chromatogram;

use strict;
use warnings;

use parent qw/MS::Reader::MzML::Record/;
use MS::CV qw/:MS/;
use MS::Mass qw/elem_mass/;
use List::Util qw/any sum/;

sub _pre_load {

    my ($self) = @_;
    $self->{_toplevel} = 'chromatogram';
    $self->SUPER::_pre_load();

}

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
        if (! defined $args{raw} || ! $args{raw}->isa("MS::Reader::MzML"));

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

    my $iso_shift = elem_mass('13C') - elem_mass('C');

    $mzml->goto( 'spectrum', defined $rt_lower
        ? $mzml->find_by_time($rt_lower)
        : 0 );
    while (my $spectrum = $mzml->next_spectrum( filter => [&MS_MS_LEVEL => 1] )) {
        last if (defined $rt_upper && $spectrum->rt > $rt_upper);

        my @pairs = ( [$mz_lower, $mz_upper] );

        # include isotopic envelope if asked
        if (defined $args{charge}) {
            my $steps = $args{iso_steps} // 0;
            for (-$steps..$steps) {
                my $off = $_ * $iso_shift / $args{charge};
                push @pairs, [$mz_lower+$off, $mz_upper+$off];
            }
        }

        my ($mz, $int) = $spectrum->mz_int_by_range(@pairs);
        my $ion_sum = (defined $int && scalar(@$int)) ? sum(@$int) : 0;

        push @rt, $spectrum->rt;
        push @int, $ion_sum;
    }
    $self->{rt}  = \@rt;
    $self->{int} = \@int;

    return;

}

sub _calc_ic {

    my ($self, %args) = @_;
       
    my $mzml = $args{raw};
    my $acc = $args{type} eq 'tic' ? MS_TOTAL_ION_CURRENT
            : $args{type} eq 'bpc' ? MS_BASE_PEAK_INTENSITY
            : die "unexpected chromatogram type requested";
    my @rt;
    my @int;
    $mzml->goto('spectrum' => 0);
    while (my $spectrum = $mzml->next_spectrum( filter => [&MS_MS_LEVEL => 1] )) {
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
    return $self->{int} if (defined $self->{int});
    return $self->get_array(MS_INTENSITY_ARRAY);
}

sub rt {
    my ($self) = @_;
    return $self->{rt} if (defined $self->{rt});
    return $self->get_array(MS_TIME_ARRAY);
}

sub window {};

1;
