package MS::Reader::PepXML::Result;

use strict;
use warnings;

use parent qw/MS::Reader::XML::Record/;

# Lookup tables to quickly check elements

sub _pre_load {

    my ($self) = @_;

    $self->{_toplevel} = 'spectrum_query';

    $self->{_make_named_hash} = { map {$_ => 'name'} qw/
        parameter
        search_score
    / };

    $self->{_make_anon_array} = { map {$_ => 1} qw/
        search_result
        search_hit
        search_id
        alternative_protein
        mod_aminoacid_mass
        analysis_result
    / };

}

sub get_hit {

    my ($self, $idx) = @_;
    return $self->{search_result}->[0]->{search_hit}->[$idx];

}

sub mod_delta_array {

    my ($self, $hit) = @_;
    $hit = $hit // 0;
    $hit = $self->{search_result}->[0]->{search_hit}->[$hit];
    my $pep = $hit->{peptide};
    my @deltas = (0) x (length($pep)+2);
    $deltas[0] += $hit->{mods}->{mod_nterm_mass} - elem_mass('H')
        if (defined $hit->{mods}->{mod_nterm_mass});
    $deltas[-1] += $hit->{mods}->{mod_cterm_mass} - elem_mass('OH')
        if (defined $hit->{mods}->{mod_cterm_mass});
    for my $mod (@{ $hit->{mods}->{other} }) {
        my $pos = $mod->{position};
        my $mass = $mod->{mass} - aa_mass( substr $pep, $pos-1, 1 );
        $deltas[$pos] += $mass;
    }
    return \@deltas;

}

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MS::Reader::PepXML::Result - pepXML search result object

=head1 SYNOPSIS

    while (my $result = $search->next_result) {
    
        my $top_hit = $result->get_hit(0);
        my $peptide = $top_hit->{peptide};
        my $deltas  = $result->mod_delta_array(0);

    }

=head1 DESCRIPTION

The C<MS::Reader::PepXML::Result> class represent search query results
(<<spectrum_query>> elements in the pepXML schema).
mass spectrometry data. It aims to provide complete access to the data
contents while not being overburdened by detailed class infrastructure.
Convenience methods are provided for accessing commonly used data. Users who
want to extract data not accessible through the available methods should
examine the data structure of the parsed object. The C<dump()> method of
L<MS::Result>, from which this class inherits, provides an easy method of
doing so.

=head1 INHERITANCE

C<MS::Reader::PepXML::Result> is a subclass of L<MS::Result> and inherits the
methods of the parental class. Please see the documentation for that class for
details of available methods not detailed below.

=head1 METHODS

=head2 new

    my $run = MS::Reader::MzML->new( $fn,
        use_cache => 0,
        paranoid  => 0,
    );

Takes an input filename (required) and optional argument hash and returns an
C<MS::Reader::MzML> object. This constructor is inherited directly from
L<MS::Reader>. Available options include:

=over

=item * use_cache — cache fetched records in memory for repeat access
(default: FALSE)

=item * paranoid — when loading index from disk, recalculates MD5 checksum
each time to make sure raw file hasn't changed. This adds (typically) a few
seconds to load times. By default, only file size and mtime are checked.

=back

=head2 next_spectrum

    while (my $s = $run->next_spectrum) { # do something }

Returns an C<MS::Reader::MzML::Spectrum> object representing the next spectrum
in the file, or C<undef> if the end of records has been reached. Typically
used to iterate over each spectrum in the run.

=head2 fetch_spectrum

    my $s = $run->fetch_spectrum($idx);

Takes a single argument (zero-based spectrum index) and returns an
C<MS::Reader::MzML::Spectrum> object representing the spectrum at that index.
Throws an exception if the index is out of range.

=head2 find_by_time

    my $idx = $run->find_by_time($rt);

Takes a single argument (retention time in SECONDS) and returns the index of
the nearest spectrum with retention time equal to or greater than that given.
Throws an exception if the given retention time is out of range.

NOTE: The first time this method is called, the spectral indices are sorted by
retention time for subsequent access. This can be a bit slow. The retention
time index is saved and subsequent calls should be relatively quick. This is
done because the mzML specification doesn't guarantee that the spectra are
ordered by RT (even though they invariably are).

=head2 n_spectra

    my $n = $run->n_spectra;

Returns the number of spectra present in the file.

=head2 get_tic

    my $tic = $run->get_tic;
    my $tic = $run->get_tic($force);

Returns an C<MS::Reader::MzML::Chromatogram> object containing the total ion
current chromatogram for the run. By default, first searches the chromatogram
list to see if a TIC is already defined, and returns it if so. Otherwise,
walks the MS1 spectra and calculates the TIC. Takes a single optional boolean
argument which, if true, forces recalculation of the TIC even if one exists in
the file.

=head2 get_bpc

    my $tic = $run->get_bpc;
    my $tic = $run->get_bpc($force);

Returns an C<MS::Reader::MzML::Chromatogram> object containing the base peak
chromatogram for the run. By default, first searches the chromatogram
list to see if a BPC is already defined, and returns it if so. Otherwise,
walks the MS1 spectra and calculates the BPC. Takes a single optional boolean
argument which, if true, forces recalculation of the BPC even if one exists in
the file.

=head2 get_xic

    my $xic = $run->get_xic(%args);

Returns an C<MS::Reader::MzML::Chromatogram> object containing an extracted
ion chromatogram for the run. Required arguments include:

=over 4

=item * C<mz> — The m/z value to extract (REQUIRED)

=item * C<err_ppm> — The allowable m/z error tolerance (in PPM)

=back

Optional arguments include:

=over

=item * C<rt> — The center of the retention time window, in seconds 

=item * C<rt_win> — The window scanned on either size of C<rt>, in seconds

=item * C<charge> — Expected charge of the target species at C<mz>

=item * C<iso_steps> — The number of isotopic shifts to consider

=back

If C<rt> and C<rt_win> are not given, the full range of the run will be used.
If C<charge> and C<iso_steps> are given, will include peaks falling within the
expected isotopic envelope (up to C<iso_steps> shifts in either direction) -
otherwise the isotopic envelope will not be considered.


=head2 id

Returns the ID of the run as specified in the C<<mzML>> element.

=head1 CAVEATS AND BUGS

The API is in alpha stage and is not guaranteed to be stable.

Please reports bugs or feature requests through the issue tracker at
L<https://github.com/jvolkening/p5-MS/issues>.

=head1 SEE ALSO

=over 4

=item * L<InSilicoSpectro>

=item * L<MzML::Parser>

=back

=head1 AUTHOR

Jeremy Volkening <jdv@base2bio.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2015-2016 Jeremy Volkening

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
