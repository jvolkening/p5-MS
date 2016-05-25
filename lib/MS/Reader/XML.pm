package MS::Reader::XML;

use strict;
use warnings;

use parent qw/MS::Reader/;

use Carp;
use Data::Dumper;
use Data::Lock qw/dlock dunlock/;
use XML::Parser;

our $VERSION = 0.001;


# this will be called at the end of the new() constructor (prior to parsing)
sub _post_load {

    my ($self) = @_;

    # set indexed record counts
    $self->{count}->{$_} = $self->{_iters}->{$_}
        for (keys %{$self->{_make_index}});

    # always reset record indices regardless of whether object was parsed or
    # loaded from index
    $self->{pos}->{$_} = 0 for (keys %{$self->{record_classes}} );

    # clean toplevel
    my $toplevel = $self->{_toplevel};
    if (defined $toplevel) {
        $self->{$_} = $self->{$toplevel}->{$_}
            for (keys %{ $self->{$toplevel} });
        delete $self->{$toplevel};
    }

    # delete temporary entries (start with "_")
    for (keys %{$self}) {
        delete $self->{$_} if ($_ =~ /^_/);
    }

    return;

}


sub _load_new {

    my ($self) = @_;

    my $fh = $self->{fh};

    $self->{_iters}->{$_} = 0 for (keys %{$self->{_make_index}});
    $self->{_curr_ref} = $self;

    my $p = XML::Parser->new();
    $p->setHandlers(
        Start => sub{ $self->_handle_start( @_) },
        End   => sub{ $self->_handle_end( @_) },
        Char  => sub{ $self->_handle_char( @_) },
    );

    $p->parse($fh);

    
    seek $fh, 0, 0;

    return;

}


# XML stream handlers
    
sub _handle_start {

    my ($self, $p, $el, %attrs) = @_;

    # track offsets of requested items
    if (defined $self->{_make_index}->{ $el }) {

        my $id = $attrs{ $self->{_make_index}->{$el} }
            or croak "ID attribute missing on indexed element";

        my $iter = $self->{_iters}->{$el};
        $self->{offsets}->{$el}->[$iter] = $p->current_byte;
        $self->{index}->{$el}->{$id} = $iter;

    }

    # skip parsing inside certain elements
    if (defined $self->{_skip_inside}->{ $el }) {
        $p->setHandlers(
            Start => undef,
            End   => sub{ $self->_handle_end( @_) },
            Char  => undef,
        );
        $self->{_skip_parse} = 1;
        return;
    }

    my $new_ref = {%attrs};
    $new_ref->{_back} = $self->{_curr_ref};

    # track starting iters for certain elements
    if (defined $self->{_store_child_iters}->{ $el }) {
        $new_ref->{first_child_idx}
            = $self->{_iters}->{ $self->{_store_child_iters}->{$el} };
    }
    
    # Elements that should be grouped by name/id
    if (defined $self->{_make_named_array}->{ $el }) {

        my $id_name = $self->{_make_named_array}->{ $el };
        my $id = $attrs{$id_name};
        delete $new_ref->{$id_name};
        push @{ $self->{_curr_ref}->{$el}->{$id} }, $new_ref;

    }

    # Elements that should be grouped by name/id
    elsif (defined $self->{_make_named_hash}->{ $el }) {
        my $id_name = $self->{_make_named_hash}->{ $el };
        my $id = $attrs{$id_name};
        die "Colliding ID $id"
            if (defined $self->{_curr_ref}->{$el}->{$id});
        delete $new_ref->{$id_name};
        $self->{_curr_ref}->{$el}->{$id} = $new_ref;
    }

    # Elements that should be grouped with no name
    elsif (defined $self->{_make_anon_array}->{ $el } ) {
        push @{ $self->{_curr_ref}->{$el} }, $new_ref;
    }

    # Everything else
    else {  
        $self->{_curr_ref}->{$el} = $new_ref;
    }

    # Step up linked list
    $self->{_curr_ref} = $new_ref;

    return;

}

sub _handle_end {

    my ($self, $p, $el) = @_;

    # Track length of indexed elements
    if (defined $self->{_make_index}->{$el}) {
        my $iter = $self->{_iters}->{$el};
        my $offset = $self->{offsets}->{$el}->[$iter];

        # Don't forget to add length of tag and "</>" chars
        $self->{lengths}->{$el}->[$iter] = $p->current_byte
            + length($el) + 3 - $offset;

        ++$self->{_iters}->{$el};
    }

    # Reset handlers for skipped elements
    if (defined $self->{_skip_inside}->{$el}) {
        $p->setHandlers(
            Start => sub{ $self->_handle_start( @_) },
            End   => sub{ $self->_handle_end( @_) },
            Char  => sub{ $self->_handle_char( @_) },
        );
        delete $self->{_skip_parse};
        return;
    }

    # Don't do anything if inside skipped element
    return if ($self->{_skip_parse});

    # track ending iters for certain elements
    if (defined $self->{_store_child_iters}->{ $el }) {
        $self->{_curr_ref}->{last_child_idx}
            = $self->{_iters}->{ $self->{_store_child_iters}->{$el} } - 1;
    }

    # Step back down linked list
    my $last_ref = $self->{_curr_ref}->{_back};
    delete $self->{_curr_ref}->{_back};
    $self->{_curr_ref} = $last_ref;

    return;

}

sub _handle_char {

    my ($self, $p, $data) = @_;
    $self->{_curr_ref}->{pcdata} .= $data
        if ($data =~ /\S/);
    return;

}

sub goto {

    my ($self, $type, $idx) = @_;
    die "Bad record type D: $type\n" if (! exists $self->{pos}->{$type});
    $self->{pos}->{$type} = $idx;
    return;

}

sub fetch_record {

    my ($self, $type, $idx, %args) = @_;

    croak "Bad record type E: $type\n" if (! exists $self->{pos}->{$type});
    
    # check record cache if used
    return $self->{memoized}->{$type}->{$idx}
        if ($self->{use_cache} && exists $self->{memoized}->{$type}->{$idx});

    my $offset = $self->{offsets}->{$type}->[ $idx ];
    croak "Record not found for $idx" if (! defined $offset);

    my $to_read = $self->{lengths}->{$type}->[ $idx ];
    my $el   = $self->_read_element($offset,$to_read);

    my $class = $self->{record_classes}->{$type};
    croak "No class defined for record type $type\n" if (! defined $class);
    my $record = $class->new( xml => $el,
        use_cache => $self->{use_cache}, %args );

    # cache record if necessary
    $self->{memoized}->{$type}->{$idx} = $record
        if ($self->{use_cache});
    
    return $class->new(xml => $el, %args);

}

sub next_record {

    my ($self, $type, %args) = @_;

    my $pos = $self->{pos}->{$type};
    return if ($pos == $self->{count}->{$type}); #EOF

    my $record;

    # There is a while loop here because a return value of -1 from
    # fetch_record() means the record was filtered out, in which case we
    # keep trying to find a valid record to return
    my $c = 0;
    while ($record = $self->fetch_record( $type => $pos, %args)) {
        ++$pos;
        $self->{pos}->{$type} = $pos;

        return $record if (! defined $record || ! $record->{filtered}); 
        return undef if ($pos == $self->{count}->{$type}); #EOF
    }

    return $record;

}

sub record_count {

    my ($self, $type) = @_;
    die "Bad record type B: $type\n" if (! exists $self->{pos}->{$type});
    return $self->{count}->{$type};

}

sub get_index_by_id {

    my ($self, $type, $id) = @_;
    die "Bad record type A: $type\n" if (! exists $self->{pos}->{$type});
    return $self->{index}->{$type}->{$id};

}

sub curr_index {

    my ($self, $type) = @_;
    die "Bad record type C: $type\n" if (! exists $self->{pos}->{$type});
    return $self->{pos}->{$type};

}

sub dump {

    my ($self) = @_;

    my $copy = {};
    %$copy = %$self;

    delete $copy->{$_} 
        for qw/count md5sum version fh offsets fn index fh pos lengths/;

    {
        local $Data::Dumper::Indent   = 1;
        local $Data::Dumper::Terse    = 1;
        local $Data::Dumper::Sortkeys = 1;
        print Dumper $copy;
    }

    return;

}

sub _finalize {} # can be defined by subclasses

1;


__END__

=head1 NAME

MS::Reader::XML - Base class for XML-based parsers

=head1 SYNOPSIS

    package MS::Reader::Foo;

    use parent MS::Reader::XML;

    sub _init {}
    sub _finalize{}

=cut
