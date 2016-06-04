package MS::Reader::MzML;

use strict;
use warnings;

use parent qw/MS::Reader::XML/;

use Carp;
use Data::Lock qw/dlock dunlock/;
use Data::Dumper;
use Digest::SHA;
use List::Util qw/first/;

use MS::Reader::MzML::Spectrum;
use MS::Reader::MzML::Chromatogram;
use MS::CV qw/:MS/;

our $VERSION = 0.005;

sub _pre_load {

    my ($self) = @_;

    # ---------------------------------------------------------------------------#
    # These tables are the main configuration point between the parser and the
    # specific document schema. For more information, see the documentation
    # for the parent class MS::Reader::XML
    # ---------------------------------------------------------------------------#

    $self->{_toplevel} = 'MzML';
    $self->{rt_index} = undef;

    $self->{record_classes} = {
        spectrum     => 'MS::Reader::MzML::Spectrum',
        chromatogram => 'MS::Reader::MzML::Chromatogram',
    };

    $self->{_skip_inside} = { map {$_ => 1} qw/
        spectrum
        chromatogram
        indexList
    / };

    $self->{_make_index} = { map {$_ => 'id'} qw/
        spectrum
        chromatogram
    / };

    $self->{_make_named_array} = {
        cvParam   => 'accession',
        userParam => 'name',
    };

    $self->{_make_named_hash} = { map {$_ => 'id'} qw/
        cv
        dataProcessing
        instrumentConfiguration
        referenceableParamGroup
        sample
        scanSettings
        software
        sourceFile
    / };

    $self->{_make_anon_array} = { map {$_ => 1} qw/
        analyzer
        contact
        detector
        processingMethod
        referenceableParamGroupRef
        source
        sourceFileRef
        target
    / };

}


sub _post_load {

    my ($self) = @_;

    if (defined $self->{indexedmzML}->{fileChecksum}) {

        # compare supplied and calculated SHA1 sums to validate
        my $sha1_given = $self->{indexedmzML}->{fileChecksum}->{pcdata};
        croak "ERROR: SHA1 digest mismatch\n"
            if ($sha1_given ne $self->_calc_sha1);

    }

    # Outer <mzML> may optionally be wrapped in <indexedmxML> tags. For
    # consistent downstream handling, everything outside <mzML> should be
    # discarded before returning.
    if (defined $self->{indexedmzML}) {
        $self->{mzML}->{$_} = $self->{indexedmzML}->{mzML}->{$_}
            for (keys %{ $self->{indexedmzML}->{mzML} });
        delete $self->{indexedmzML};
    }

    $self->SUPER::_post_load();

    return;

}

sub fetch_spectrum {

    my ($self, $idx, %args) = @_;
    return $self->fetch_record('spectrum', $idx, %args);

}

sub next_spectrum {

    my ($self, %args) = @_;
    return $self->next_record( 'spectrum', %args );

}

sub find_by_time {

    my ($self, $rt, $ms_level) = @_;

    # lazy load
    if (! defined $self->{rt_index}) {
        $self->_index_rt();
    }

    my @sorted = @{ $self->{rt_index} };

    croak "Retention time out of bounds"
        if ($rt < 0 || $rt > $self->{rt_index}->[-1]->[1]);

    # binary search
    my ($lower, $upper) = (0, $#sorted);
    while ($lower != $upper) {
        my $mid = int( ($lower+$upper)/2 );
        ($lower,$upper) = $rt < $sorted[$mid]->[1]
            ? ( $lower , $mid   )
            : ( $mid+1 , $upper );
    }

    my $i = $sorted[$lower]->[0]; #return closest scan index >= $ret
    while (defined $ms_level
      && $self->fetch_record('spectrum' => $i)->ms_level() != $ms_level) {
        ++$i;
    }
    return $i;

}

sub _index_rt {

    my ($self) = @_;

    my @spectra;
    my $saved_pos = $self->{pos}->{spectrum};
    $self->goto('spectrum' => 0);
    my $curr_pos  = $self->{pos}->{spectrum};
    while (my $spectrum = $self->next_spectrum) {

        my $ret = $spectrum->rt;
        push @spectra, [$curr_pos, $ret];
        $curr_pos = $self->{pos}->{spectrum};

    }
    @spectra = sort {$a->[1] <=> $b->[1]} @spectra;
    $self->{pos}->{spectrum} = $saved_pos;
    dunlock $self->{rt_index};
    $self->{rt_index} = [@spectra];
    dlock $self->{rt_index};

    # Since we took the time to index RTs, go ahead and store the updated
    # structure to file
    $self->_write_index;

    return;

}

sub _calc_sha1 {

    my ($self) = @_;

    my $fh = $self->{fh};
    seek $fh, 0, 0;

    my $sha1 = Digest::SHA->new(1);
    local $/ = '>';
    while (my $chunk = <$fh>) {
        $sha1->add($chunk);
        last if (substr($chunk, -14) eq '<fileChecksum>');
    }

    return $sha1->hexdigest;

}

sub get_tic {

    my ($self, $force) = @_;

    if (! $force) {
        $self->goto('chromatogram' => 0);
        while (my $c = $self->next_record('chromatogram')) {
            next if (! exists $c->{cvParam}->{&MS_TOTAL_ION_CURRENT_CHROMATOGRAM});
            return $c;
        }
    }

    return MS::Reader::MzML::Chromatogram->new(type => 'tic', raw => $self);

}

sub get_xic {

    my ($self, %args) = @_;
    return MS::Reader::MzML::Chromatogram->new(type => 'xic',raw => $self, %args);

}

sub get_bpc {

    my ($self, $force) = @_;

    if (! $force) {
        $self->goto('chromatogram' => 0);
        while (my $c = $self->next_record('chromatogram')) {
            next if (! exists $c->{cvParam}->{&MS_BASEPEAK_CHROMATOGRAM});
            return $c;
        }
    }

    return MS::Reader::MzML::Chromatogram->new(type => 'bpc',raw => $self);

}

sub n_spectra { return $_[0]->record_count('spectrum') }

sub id { return $_[0]->{mzML}->{id} }

1;

__END__

=head1 NAME

MS::Reader::MzML - A simple but complete mzML parser

=head1 SYNOPSIS

    use MS::Reader::MzML;

    my $run = MS::Reader::MzML->new('run.mzML');

    while (my $spectrum = $run->next_spectrum) {
       
        # only want MS1
        next if ($spectrum->ms_level > 1);

        my $rt = $spectrum->rt;
        # see MS::Reader::MzML::Spectrum and MS::Spectrum for all available
        # methods

    }

    $spectrum = $run->fetch_spectrum(0);  # first spectrum
    $spectrum = $run->find_by_time(1500); # in seconds


=head1 DESCRIPTION

C<MS::Reader::MzML> is a parser for the HUPO PSI standard mzML format for raw
mass spectrometry data. It aims to provide complete access to the data
contents while not being overburdened by detailed class infrastructure.
Convenience methods are provided for accessing commonly used data. Users who
want to extract data not accessible through the available methods should
examine the data structure of the parsed object. The C<dump()> method of
L<MS::Reader::XML>, from which this class inherits, provides an easy method of
doing so.

=head1 INHERITANCE

C<MS::Reader::MzML> is a subclass of L<MS::Reader::XML>, which in turn
inherits from L<MS::Reader>, and inherits the methods of these parental
classes. Please see the documentation for those classes for details of
available methods not detailed below.

=head1 METHODS

=over 4

=item B<next_spectrum>

    while (my $s = $run->next_spectrum) { # do something }

Returns an C<MS::Reader::MzML::Spectrum> object representing the next spectrum
in the file, or C<undef> if the end of records has been reached. Typically
used to iterate over each spectrum in the run.

=item B<fetch_spectrum> <index>

    my $s = $run->fetch_spectrum($idx);

Returns an C<MS::Reader::MzML::Spectrum> object representing the spectrum at
index <index>. Indices are zero-based. Throws an exception if the index is out
of range.

=item B<find_by_time> <retention time>

    my $idx = $run->find_by_time($rt);

Returns the index of the nearest spectrum with retention time (IN SECONDS)
equal to or greater than that given.  Throws an exception if the given
retention time is out of range.

NOTE: The first time this method is called, the spectral indices are sorted by
retention time for subsequent access. This can be a bit slow. The retention
time index is saved and subsequent calls should be relatively quick. This is
done because the mzML specification doesn't guarantee that the spectra are
ordered by RT (even though they invariably are).

=item B<n_spectra>

    my $n = $run->n_spectra;

Returns the number of spectra present in the file.

=item B<get_tic> [<force>]

    my $tic = $run->get_tic;

Returns an C<MS::Reader::MzML::Chromatogram> object containing the total ion
current chromatogram for the run. By default, first searches the chromatogram
list to see if a TIC is already defined, and returns it if so. Otherwise,
walks the MS1 spectra and calculates the TIC. Takes a single optional boolean
argument which, if true, forces recalculation of the TIC even if one exists in
the file.

=item B<get_bpc> [<force>]

    my $tic = $run->get_bpc;

Returns an C<MS::Reader::MzML::Chromatogram> object containing the base peak
chromatogram for the run. By default, first searches the chromatogram
list to see if a BPC is already defined, and returns it if so. Otherwise,
walks the MS1 spectra and calculates the BPC. Takes a single optional boolean
argument which, if true, forces recalculation of the BPC even if one exists in
the file.

=item B<get_xic> [%args]

    my $xic = $run->get_xic(
        mz      => 200.0037,
        err_ppm => 10,
        rt      => 1245,
        rt_win  => 120,
    );

Returns an C<MS::Reader::MzML::Chromatogram> object containing an extracted
ion chromatogram for the run. Valid arguments are:

=over 4

=item mz

The m/z value to extract

=item err_ppm

The tolerance for extraction (in ppm)

=item rt

The center of the retention time window to extract (IN SECONDS). If not given,
the entire run will be searched.

=item rt_win

The window on either size of the target retention time to search (IN SECONDS).

=item charge

The expected charge of the species at this m/z. If specified (along with
C<iso_steps>) a search for the peaks within the isotopic envelope C<iso_steps>
steps above and below the target m/z will be included in the returned ion
flows. 

=item iso_steps

The number of isotopic steps to search above and below the target m/z for
inclusion of the isotopic envelope. C<charge> must also be specified or this
value will be ignored.

=back

=item B<id>

Returns the ID of the run as specified in the C<<mzML>> element.

=back

=head1 CAVEATS AND BUGS

The API is in alpha stage and is not guaranteed to be stable.

Please reports bugs to the author.

=head1 AUTHOR

Jeremy Volkening <jdv *at* base2bio.com>

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
