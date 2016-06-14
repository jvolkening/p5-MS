package MS::Reader::ImzML;

use strict;
use warnings;

use parent qw/MS::Reader::MzML/;

use Carp;
use Digest::SHA;
use File::stat;
use URI::file;

use MS::Reader::ImzML::Spectrum;
use MS::CV qw/:MS :IMS/;

our $VERSION = 0.005;

sub _pre_load {

    my ($self, @args) = @_;

    $self->SUPER::_pre_load(@args);

    $self->{__record_classes}->{spectrum} = 'MS::Reader::ImzML::Spectrum';

}

sub _post_load {

    my ($self, @args) = @_;

    $self->SUPER::_post_load(@args);

    open my $fh, '<', $self->{__fn_ibd}
        or croak "Error opening IBD file: $@";
    $self->{__fh_ibd} = $fh;

}

sub _write_index {

    my ($self) = @_;
    my $fh = $self->{__fh_ibd};
    $self->{__fh_ibd} = undef;
    $self->SUPER::_write_index();
    $self->{__fh_ibd} = $fh;

}

sub next_spectrum {

    my ($self, @args) = @_;
    my $s = $self->SUPER::next_spectrum(@args);
    return undef if (! defined $s);
    
    # the spectrum will need access to the binary filehandle
    $s->{__fh_ibd} = $self->{__fh_ibd};

    return $s;

}

sub fetch_spectrum {

    my ($self, @args) = @_;
    my $s = $self->SUPER::fetch_spectrum(@args);
    return undef if (! defined $s);

    # the spectrum will need access to the binary filehandle
    $s->{__fh_ibd} = $self->{__fh_ibd};

    return $s;

}

sub _load_new {

    my ($self, @args) = @_;

    $self->SUPER::_load_new(@args);

    # NOTE: <mzML> element hasn't been stripped yet
    my $ref = $self->{mzML}->{fileDescription}->{fileContent};

    # determine binary file type 
    $self->{__imzml_type}
        = defined $self->param(IMS_PROCESSED,  ref => $ref) ? 'processed'
        : defined $self->param(IMS_CONTINUOUS, ref => $ref) ? 'continuous'
        : croak "unknown imzML type";

    # check for existence of IBD
    my $fn_ibd;
    my $uri_ibd = $self->param(IMS_EXTERNAL_BINARY_URI, ref => $ref);
    if (defined $uri_ibd) {
        $fn_ibd = URI::file->new($uri_ibd)->file;
    }
    else {
        $fn_ibd = $self->{__fn};
        $fn_ibd =~ s/\.[^\.]+$/\.ibd/;
        croak "Unexpected input filename" if ($fn_ibd eq $self->{__fn});
    }
    croak "Failed to located IBD file" if (! -e $fn_ibd);
    $self->{__fn_ibd} = $fn_ibd;

    # check IBD hash
    my $sha1 = $self->param(IMS_IBD_SHA_1, ref => $ref);
    my $md5  = $self->param(IMS_IBD_MD5,   ref => $ref);
    if (defined $sha1) {
        my $h = Digest::SHA->new(1);
        $h->addfile($fn_ibd);
        croak "IBD SHA-1 mismatch" if (lc($sha1) ne lc($h->hexdigest));
    }
    elsif (defined $md5) {
        my $h = Digest::MD5->new();
        $h->addfile($fn_ibd);
        croak "IBD SHA-1 mismatch" if (lc($md5) ne lc($h->hexdigest));
    }
    else { croak "Missing IBD checksum cvParam" }

    # Use a simple/fast file check (file size + mod time)
    my $st = stat($fn_ibd);
    my $statsum = $st->size . $st->mtime;
    $self->{__ibd_statsum} = $statsum;

    # store IBD UUID
    my $uuid = $self->param(IMS_UNIVERSALLY_UNIQUE_IDENTIFIER, ref => $ref);
    croak "Missing IBD UUID cvParam" if (! defined $uuid);
    $uuid =~ s/[\{\}\-]//g;
    $self->{__ibd_uuid} = $uuid;

}


1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MS::Reader::ImzML - A simple but complete imzML parser

=head1 SYNOPSIS

    use MS::Reader::ImzML;

    my $run = MS::Reader::ImzML->new('run.mzML');

    while (my $spectrum = $run->next_spectrum) {
       
        # only want MS1
        next if ($spectrum->ms_level > 1);

        my $rt = $spectrum->rt;
        # see MS::Reader::ImzML::Spectrum and MS::Spectrum for all available
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

    while (my $s = $run->next_spectrum) {
        # do something
    }

Returns an C<MS::Reader::MzML::Spectrum> object representing the next spectrum
in the file, or C<undef> if the end of records has been reached. Typically
used to iterate over each spectrum in the run.

=head2 fetch_spectrum

    my $s = $run->fetch_spectrum($idx);

Takes a single argument (zero-based spectrum index) and returns an
C<MS::Reader::MzML::Spectrum> object representing the spectrum at that index.
Throws an exception if the index is out of range.

=head2 goto_spectrum

    $run->goto_spectrum($idx);

Takes a single argument (zero-based spectrum index) and sets the spectrum
record iterator to that index (for subsequent calls to C<next_spectrum>).

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
