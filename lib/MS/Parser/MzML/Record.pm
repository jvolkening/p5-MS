package MS::Parser::MzML::Record;

use strict;
use warnings;

use Compress::Zlib;
use MIME::Base64;
use XML::Parser;
use List::Util qw/first/;
use MS::CV qw/:constants/;

# Lookup tables to quickly check elements
our %_make_named_array = (
    cvParam   => 'accession',
    userParam => 'name',
);
our %_make_anon_array = map {$_ => 1} qw/
    referenceableParamGroupRef
    product
    binaryDataArray
    precursor
    selectedIon
    scanWindow
    scan
/;

# Abbreviate some constants
use constant NUMPRESS_LIN  => MS_NUMPRESS_LINEAR_PREDICTION_COMPRESSION;
use constant NUMPRESS_PIC  => MS_NUMPRESS_POSITIVE_INTEGER_COMPRESSION;
use constant NUMPRESS_SLOF => MS_NUMPRESS_SHORT_LOGGED_FLOAT_COMPRESSION;


sub new {

    my ($class, %args) = @_;
    my $self = bless {}, $class;

    # parse XML into object
    if (defined $args{xml}) {

        # initialize pointer
        $self->{_curr_ref} = $self;
        $self->{filter}    = $args{filter}; # may be undef

        my $p = XML::Parser->new();
        $p->setHandlers(
            Start => sub{ $self->_handle_start( @_ ) },
            End   => sub{ $self->_handle_end(   @_ ) },
            Char  => sub{ $self->_handle_char(  @_ ) },
        );
        $p->parse($args{xml});

        delete $self->{_curr_ref}; # avoid circular reference mem leak
        delete $self->{filter};

        # strip toplevel
        my $toplevel = $self->_toplevel();
        $self->{$_} = $self->{$toplevel}->{$_}
            for (keys %{ $self->{$toplevel} });
        delete $self->{$toplevel};

    }
    return $self;

}

sub _parse_id {

    my ($id) = @_;
    if ($id =~ /\bscan=(\d+)\b/) {
        $id = $1;
    }
    return $id;

}

sub _handle_start {

    my ($self, $p, $el, %attrs) = @_;

    if ($el eq 'spectrum') { # handle ID conversion
        $attrs{native_id} = $attrs{id};
        $attrs{id} = _parse_id( $attrs{id} );
    }

    my $new_ref = \%attrs;
    $new_ref->{back} = $self->{_curr_ref};

    
    # Elements that should be grouped by name/id
    if ($_make_named_array{ $el }) {

        my $id_name = $_make_named_array{ $el };
        my $id = $attrs{$id_name};
        delete $new_ref->{$id_name};
        push @{ $self->{_curr_ref}->{$el}->{$id} }, $new_ref;

        # filters are used to short-circuit parses that don't match a given
        # criteria. In some cases this can speed up sequential parsing
        # significantly
        if ($el eq 'cvParam' && defined $self->{filter}) {
            if ($id eq $self->{filter}->[0]
            && $attrs{value} != $self->{filter}->[1]) {
                $self->{filtered} = 1;
                $p->finish;
            }
        }

    }

    # Elements that should be grouped with no name
    elsif ( $_make_anon_array{ $el } ) {
        push @{ $self->{_curr_ref}->{$el} }, $new_ref;
    }

    # Everything else
    else {  
        $self->{_curr_ref}->{$el} = $new_ref;
    }
    $self->{_curr_ref} = $new_ref;

    return;

}

sub _handle_end {

    my ($self, $p, $el) = @_;

    # step back down linked list
    my $last_ref = $self->{_curr_ref}->{back};
    delete $self->{_curr_ref}->{back}; # avoid memory leak!
    $self->{_curr_ref} = $last_ref;

    return;

}

sub _handle_char {

    my ($self, $p, $data) = @_;

    $self->{_curr_ref}->{pcdata} .= $data
        if ($data =~ /\S/);

    return;

}

# binary arrays are only decoded upon request, to increase parse speed
sub get_array {

    my ($self, $accession) = @_;

    # Find data array reference by CV accession
    my $array = first {defined $_->{cvParam}->{$accession}}
        @{ $self->{binaryDataArrayList}->{binaryDataArray} };
    return if (! defined $array);

    return if ($self->{defaultArrayLength} == 0);

    # Extract metadata necessary to unpack array
    my $raw = $array->{binary}->{pcdata};
    my $is_zlib  = 0;
    my $numpress = 'none';
    if (! defined $array->{cvParam}->{&NO_COMPRESSION}) {
        $is_zlib  = defined $array->{cvParam}->{&ZLIB_COMPRESSION};
        $numpress
            = defined $array->{cvParam}->{ &NUMPRESS_LIN  } ? 'np-lin'
            : defined $array->{cvParam}->{ &NUMPRESS_PIC  } ? 'np-pic'
            : defined $array->{cvParam}->{ &NUMPRESS_SLOF } ? 'np-slof'
            : 'none';
        # Compression type (or lack thereof) MUST be specified!
        die "Uknown compression scheme (no known schemes specified) ??"
            if (! $is_zlib && $numpress eq 'none');
    }
    my $precision   = defined $array->{cvParam}->{&_64_BIT_FLOAT} ? 64
                    : defined $array->{cvParam}->{&_32_BIT_FLOAT} ? 32
                    : undef;
    die "floating point precision required if numpress not used"
        if (! defined $precision && $numpress eq 'none');

    my $data = _decode_raw(
        $raw,
        $precision,
        $is_zlib,
        $numpress,
    );
    # Convert minutes to seconds
    if ($accession eq TIME_ARRAY) {
        if ($array->{cvParam}->{&TIME_ARRAY}->[0]->{unitName} eq 'minute') {
            $data = [ map {$_*60} @{$data} ];
        }
    }

    # Sanity checks (no noticeable effect on speed during benchmarking)
    #die "ERROR: array data compressed length mismatch"
        #if ($is_compressed && $len != $array->{encodedLength});
    my $c = scalar @{$data};
    my $e = $self->{defaultArrayLength};
    die "ERROR: array list count mismatch ($e v $c) for record"
        if (scalar(@{$data}) != $self->{defaultArrayLength});

    return @{$data};

}

sub _decode_raw {

    my ($data, $precision, $is_zlib, $numpress) = @_;

    return [] if (length($data) < 1);

    my $un64 = decode_base64($data);
    $un64 = uncompress($un64) if ($is_zlib);
    my $array;
    if ($numpress eq 'none') {
        my $float_code = $precision == 64 ? 'd' : 'f';
        $array = [ unpack "$float_code<*", $un64 ];
    }
    elsif ($numpress eq 'np-pic') {
        $array = _decode_trunc_ints( $un64 );
    }
    elsif ($numpress eq 'np-slof') {
        $array = _decode_np_slof( $un64 );
    }
    elsif ($numpress eq 'np-lin') {
        $array = _decode_np_linear( $un64 );
    }

    return $array;

}

sub _decode_np_linear {

    my ($data) = @_;

    my $fp = unpack 'd>', substr($data,0,8,'');
    my @v  = unpack 'VV', substr($data,0,8,'');
    push @v, 2*$v[-1] - $v[-2] + $_
        for ( @{ _decode_trunc_ints($data) } );
    @v = map {$_/$fp} @v;

    return \@v;

}

sub _decode_np_slof {

    my ($data) = @_;

    my $fp = unpack 'd>', substr($data,0,8,'');
    my @v  = map {exp($_/$fp)-1} unpack 'v*', $data;

    return \@v;

}

sub _decode_trunc_ints {

    # Unpack string of truncated integer nybbles into longs

    my ($data) = (@_);

    my @nybbles;
    for (unpack 'C*', $data) {
        # push most-significant first!
        push @nybbles, ($_ >> 4);
        push @nybbles, ($_ & 0xf);
    }
    my $array;
    while (scalar(@nybbles)) {

        my $long = 0;
        my $head = shift @nybbles;
        # ignore trailing non-zero nybble
        last if (!scalar(@nybbles) && $head != 0x8);
        my $n = 0;
        if ($head <= 8) {
            $n = $head;
        }
        else {
            $n = $head - 8;
            my $shift = (8-$n)*4;
            $long = $long | ((0xffffffff >> $shift) << $shift);
        }

        my $i = $n;
        while ($i < 8) {
            my $nyb = shift @nybbles;
            $long = $long | ($nyb << (($i-$n)*4));
            ++$i;
        }
        $long = unpack 'l<', pack 'l<',$long; # cast to signed long, slow?
        push @{$array}, $long;
    }

    return $array;

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
