package MS::Reader::MzIdentML::Record;

use strict;
use warnings;

use Compress::Zlib;
use MIME::Base64;
use XML::Parser;
use List::Util qw/first/;

# Lookup tables to quickly check elements
our %_make_named_array = (
    cvParam   => 'accession',
    userParam => 'name',
);
our %_make_named_hash = (
    SpectrumIdentificationResult => 'id',
);
our %_make_anon_array = map {$_ => 1} qw/
    Modification
    PeptideEvidenceRef
    SubstitutionModification
/;


sub new {

    my ($class, %args) = @_;
    my $self = bless {}, $class;

    # parse XML into object
    if (defined $args{xml}) {

        # initialize pointer
        $self->{_curr_ref} = $self;

        my $p = XML::Parser->new();
        $p->setHandlers(
            Start => sub{ $self->_handle_start( @_ ) },
            End   => sub{ $self->_handle_end(   @_ ) },
            Char  => sub{ $self->_handle_char(  @_ ) },
        );
        $p->parse($args{xml});

        delete $self->{_curr_ref}; # avoid circular reference mem leak

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

    }

    # Elements that should be grouped by name/id
    elsif ($_make_named_hash{ $el }) {
        my $id_name = $_make_named_hash{ $el };
        my $id = $attrs{$id_name};
        die "Colliding XS::id $id"
            if (defined $self->{_curr_ref}->{$el}->{$id});
        delete $new_ref->{$id_name};
        $self->{_curr_ref}->{$el}->{$id} = $new_ref;
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

sub dump {

    my ($self) = @_;

    use Data::Dumper;

    local $Data::Dumper::Indent   = 1;
    local $Data::Dumper::Terse    = 1;
    local $Data::Dumper::Sortkeys = 1;

    return Dumper $self;

}

1;
