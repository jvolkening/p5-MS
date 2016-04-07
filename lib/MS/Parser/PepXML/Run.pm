package MS::Parser::PepXML::Run;

use strict;
use warnings;

sub new {

    my $class = shift;
    my $self = bless {}, $class;
    return $self;

}

sub next_query {

    my ($self) = @_;

    if (! defined $self->{pos}) {
        $self->{pos} = $self->{start_record};
        return undef;
    }
    my $idx = $self->{pos};
    my $q = $self->fetch_query( $self->{pos} );
    $self->{pos} = $self->{links}->{ $self->{pos} } // undef;
    return $q;

}

sub next_index {

    my ($self) = @_;

    if (! defined $self->{pos}) {
        $self->{pos} = $self->{start_record};
        return undef;
    }
    my $idx = $self->{pos};
    $self->{pos} = $self->{links}->{ $self->{pos} } // undef;
    return $idx;

}

sub _read_element {

    my ($self, $offset, $to_read) = @_;

    seek $self->{fh}, $offset, 0;
    my $r = read($self->{fh}, my $el, $to_read);
    die "returned unexpected byte count" if ($r != $to_read);

    return $el;

}


sub fetch_query {

    my ($self, $query_num) = @_;

    my $offset  = $self->{offsets}->{ $query_num };
    die "offset $offset not defined" if (! defined $offset);
    my $to_read = $self->{lengths}->{ $query_num };

    my $el = $self->_read_element($offset, $to_read);

    return MS::Parser::PepXML::Query->new(xml => $el);

}

1;
