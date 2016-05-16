package MS::Parser::MzML::Spectrum;

use parent qw/MS::Spectrum MS::Parser::MzML::Record/;
use MS::CV qw/:constants/;

sub _pre_load {

    my ($self) = @_;
    $self->{_toplevel} = 'spectrum';
    $self->SUPER::_pre_load();

}

sub id {

    my ($self) = @_;
    return $self->{id};

}

sub ms_level {

    my ($self) = @_;
    my $level = $self->{cvParam}->{&MS_LEVEL}->[0]->{value}
        or die "missing scan level";
    return $level;

}

sub mz {

    my ($self) = @_;
    return $self->get_array(M_Z_ARRAY);

}

sub int {

    my ($self) = @_;
    return $self->get_array(INTENSITY_ARRAY);

}

sub rt {

    # get retention time in seconds
    #
    my ($self) = @_;

    die "rt() only valid for single scan spectra, use direct access.\n"
        if ($self->{scanList}->{count} != 1);
    my $scan = $self->{scanList}->{scan}->[0];
    my $rt    = $scan->{cvParam}->{&SCAN_START_TIME}->[0]->{value};
    die "missing RT value" if (! defined $rt);
    my $units = $scan->{cvParam}->{&SCAN_START_TIME}->[0]->{unitName};
    $rt *= 60 if ($units eq 'minute');
    
    return $rt;
 
 }

 sub precursor {

    my ($self) = @_;
    die "precursor() only valid for MS2 spectra"
        if ($self->{cvParam}->{&MS_LEVEL}->[0]->{value} < 2);
    die "precursor() only valid for single precursor spectra, use direct access.\n"
        if ($self->{precursorList}->{count} != 1);
    my $pre = $self->{precursorList}->{precursor}->[0];
    my $id = $pre->{spectrumRef};
    my $iso_mz = $pre->{isolationWindow}->{cvParam}->
        {&ISOLATION_WINDOW_TARGET_M_Z}->[0]->{value};
    my $iso_lower = $iso_mz - $pre->{isolationWindow}->{cvParam}->
        {&ISOLATION_WINDOW_LOWER_OFFSET}->[0]->{value};
    my $iso_upper = $iso_mz + $pre->{isolationWindow}->{cvParam}->
        {&ISOLATION_WINDOW_UPPER_OFFSET}->[0]->{value};
    die "missing precursor id"    if (! defined $id);
    die "missing precursor m/z"   if (! defined $iso_mz);
    die "missing precursor lower" if (! defined $iso_lower);
    die "missing precursor upper" if (! defined $iso_upper);

    die "precursor() only valid for single precursor spectra, use direct access.\n"
        if ($pre->{selectedIonList}->{count} != 1);
    my $charge = $pre->{selectedIonList}->{selectedIon}->[0]->
        {cvParam}->{&CHARGE_STATE }->[0]->{value};
    my $mono_mz = $pre->{selectedIonList}->{selectedIon}->[0]->
        {cvParam}->{&SELECTED_ION_M_Z}->[0]->{value};
    my $int = $pre->{selectedIonList}->{selectedIon}->[0]->
        {cvParam}->{&PEAK_INTENSITY}->[0]->{value};
    #die "missing precursor charge" if (! defined $charge);
    die "missing monoisotopic m/z" if (! defined $mono_mz);
    return {
        scan_id   => $id,
        iso_mz    => $iso_mz,
        iso_lower => $iso_lower,
        iso_upper => $iso_upper,
        mono_mz   => $mono_mz,
        charge    => $charge,
        intensity => $int,
    };

}

1;

__END__

=head1 NAME

MS::Parser::MzML::Spectrum - An MzML spectrum object

=head1 SYNOPSIS

    use MS::Parser::MzML;
    use MS::CV qw/:constants/;

    my $reader = MS::Parser::MzML->new('run.mzML');

    while (my $spectrum = $reader->next_spectrum) {
        
        # $spectrum inherits from MS::Spectrum, so you can do:
        my $id  = $spectrum->id;
        my $rt  = $spectrum->rt;
        my $mz  = $spectrum->mz;
        my $int = $spectrum->int;
        my $lvl = $spectrum->ms_level;

        # in addition,

        my $precursor = $spectrum->precursor;
        my $pre_mz = $precursor->{mono_mz};

        # or access the guts directly
        my $peak_count = $spectrum->{defaultArrayLength};

        # print the underlying data structure
        $spectrum->dump;

    }

=head1 DESCRIPTION

C<MS::Parser::MzML::Spectrum> represents spectra parsed from an mzML file. The
underlying hash is a nested data structure containing all information present
in the original mzML record. This information can be accessed directly (see
below for details of the data structure) or via the methods described.

=head1 METHODS

In addition to the methods inherited from C<MS::Spectrum> and
C<MS::Parser::MzML::Record>, the following methods are provided:

=over

=item B<precursor>

    my $pre = $spectrum->precursor;
    my $pre_mz = $pre->{mono_mz};

Returns a reference to a hash containing information about the precursor ion
for MSn spectra. Throws an exception if called on an MS1 spectrum. Note that
this information is pulled directly from the MSn record. The actual
spectrum object for the precursor ion could be fetched e.g. by:

    my $pre_obj = $reader->fetch_spectrum( $spectrum->{scan_id} );

=back

=head1 SEE ALSO

MS::Spectrum
MS::Parser::MzML::Record

=head1 CAVEATS AND BUGS

Please reports bugs to the author.

=head1 AUTHOR

Jeremy Volkening <jdv@base2bio.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2016 Jeremy Volkening

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program.  If not, see <http://www.gnu.org/licenses/>.

=cut

