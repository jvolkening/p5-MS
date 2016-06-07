package MS::Reader;

use strict;
use warnings;

use Carp;
use Digest::MD5;
use Data::Lock qw/dlock dunlock/;
use File::stat;
use Storable qw/nstore_fd retrieve_fd/;
use Scalar::Util qw/blessed/;
use PerlIO::gzip;

our $VERSION = 0.202;
$VERSION = eval $VERSION;

use constant BGZF_MAGIC => pack 'H*', '1f8b0804';

sub new {

    my ($class, $fn, %args) = @_;

    my $self = bless {} => $class;

    $self->{__use_cache} = $args{use_cache} ? 1 : 0; # remember accessed records
    $self->{__paranoid}  = $args{paranoid}  ? 1 : 0; # calc MD5 each time
    $self->{__fn}        = undef; # to allow dunlock even if not loaded
    $self->{__fh}        = undef; # to allow dunlock even if not loaded
    $self->{__version}   = $VERSION;
    $self->{__lock}      = $args{lock} // 0;

    $self->load($fn) if (defined $fn);

    # check expected methods in subclasses
    $self->_check_interface;

    return $self;

}

# to be defined by subclass
sub _check_interface { return }

sub _read_element {

    my ($self, $offset, $to_read) = @_;

    seek $self->{__fh}, $offset, 0;
    my $r = read($self->{__fh}, my $el, $to_read);
    croak "returned unexpected byte count" if ($r != $to_read);

    return $el;

}

sub load {

    my ($self, $fn) = @_;

    my $use_cache = $self->{__use_cache};

    croak "input file not found" if (! -e $fn);
    $self->{__fn} = $fn;
    open my $fh, '<', $fn;
    my $old_layers = join '', map {":$_"} PerlIO::get_layers($fh);
    binmode $fh;

    # check for BGZIP compression
    read($fh, my $magic, 4);
    binmode($fh, $old_layers);
    if ($magic eq BGZF_MAGIC) {
        require Compress::BGZF::Reader
            or croak "Compress::BGZF::Reader required to handle BGZF files";
        close $fh;
        $fh = Compress::BGZF::Reader->new_filehandle($fn);
    }
    
    $self->{__fh} = $fh;
    seek $fh, 0, 0;
    
    # Use a simple/fast file check (file size + mod time)
    my $st = stat($fn);
    my $statsum = $st->size . $st->mtime;

    my $checksum;
    if ($self->{__paranoid}) {

        # Calculate MD5 on whole file (NOTE: currently addfile() (XS-based) will
        # fail on tied filehandle - don't use.
        my $d = Digest::MD5->new();
        while (my $r = read $fh, my $buf, 8192) {
            $d->add($buf);
        }
        $checksum = $d->hexdigest;
        seek $fh, 0, 0;

    }

    # Check for existing index. If present, compare checksums and load
    # existing index upon match. Croak if no match.
    my $fn_idx = $fn . '.idx';
    while (-r $fn_idx) { # 'while' instead of 'if' so we can break out

        open my $fhi, '<:gzip', $fn_idx or die "Error opening index: $!\n";
        my $existing = retrieve_fd($fhi);
        close $fhi;
        if ($existing->{__version} < $VERSION) {
            croak "Index files were generated by an older version of "
            . blessed($self) . ". Not all versions are backwards compatible"
            . " - please remove the old indices and try again\n";
        }
        elsif ($statsum  ne $existing->{__statsum}) {
            croak "size/mtime check in existing index $fn_idx failed. If"
            . " data file has changed, please remove existing index and"
            . " try again.\n";
        }
        elsif ($self->{__paranoid}) {
            if (! exists $existing->{__md5sum}) {
                carp "No MD5 sum in existing index $fn_idx. Will regenerate"
                . " index with MD5 sum";
                last;
            }
            if ($checksum ne $existing->{__md5sum}) {
                croak "MD5 check in existing index $fn_idx failed. If data file"
                . " has changed, please remove existing index and try again.\n";
            }
        }
        %$self = %$existing;
        $self->{__fh} = $fh;
        $self->{__fn} = $fn;
        $self->{__use_cache} = $use_cache;
        
        # defined in subclasses
        $self->_post_load;
        dlock($self) if ($self->{__lock});

        return;

    }

    # Otherwise, do full file parse and store index
    $self->{__statsum} = $statsum;
    $self->{__md5sum}  = $checksum if ($self->{__paranoid});
    delete $self->{__paranoid};

    # This is where the actual file parsing takes place. The _load_new()
    # method must be defined for each format-specific subclass.
    $self->_pre_load;
    $self->_load_new;
    $self->_post_load;

    # Store data structure as index
    $self->_write_index;
    dlock($self) if ($self->{__lock});

    return;

}

sub _write_index {

    my ($self) = @_;
    
    dunlock($self) if ($self->{__lock});
    my $tmp_fh = delete $self->{__fh};
    my $fn_idx = $self->{__fn} . '.idx';
    open my $fh, '>:gzip', $fn_idx;
    nstore_fd($self => $fh) or die "failed to store self: $!\n";
    close $fh;
    $self->{__fh} = $tmp_fh;
    dlock($self) if ($self->{__lock});

    return;

}

sub _pre_load {}  # defined by subclass
sub _post_load {} # defined by subclass

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MS::Reader - Base class for all file parsers

=head1 SYNOPSIS

    package MS::Reader::Foo;

    use parent qw/MS::Reader/;


=head1 DESCRIPTION

C<MS::Reader> is the base class from which all MS::Reader parsers are derived.
It's sole purpose (currently) is to transparently handle on-disk indexes and
opening of BGZF-compressed files.

=head1 METHODS

All subclasses by default inherit the following constructor

=head2 new

    my $parser = MS::Reader::Foo->new( $fn,
        use_cache => 0,
        paranoid  => 0,
    );

Takes an input filename (required) and optional argument hash and returns an
C<MS::Reader> object. Available options include:

=over

=item * use_cache — cache fetched records in memory for repeat access
(default: FALSE)

=item * paranoid — when loading index from disk, recalculates MD5 checksum
each time to make sure raw file hasn't changed. This adds (typically) a few
seconds to load times. By default, only file size and mtime are checked.

=back

=head1 CAVEATS AND BUGS

The API is in alpha stage and is not guaranteed to be stable.

Please reports bugs or feature requests through the issue tracker at
L<https://github.com/jvolkening/p5-MS/issues>.

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
