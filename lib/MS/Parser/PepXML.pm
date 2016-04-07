package MS::Parser::PepXML;

use strict;
use warnings;

use parent qw/MS::Parser/;

use Digest::MD5;
use IO::Handle;
use XML::Twig;
use Storable qw/store retrieve/;
use Carp;
use MS::Parser::PepXML::Query;
use MS::Parser::PepXML::Run;
use Scalar::Util qw/blessed/;

our $VERSION = 0.200;
use constant BGZF_MAGIC => pack 'H*', '1f8b0804';

# A few lookup tables to speed up checks
our %_skip_inside = map {$_ => 1} qw/
    spectrum_query
    mixturemodel
/;
our %_make_index = map {$_ => 1} qw/
    spectrum_query
/;

our %_name_value = (
    parameter    => ['name','value'],
);
our %_make_anon_array = map {$_ => 1} qw/
    analysis_summary
    msms_run_summary
    specificity
    search_summary
    sequence_search_constraint
    aminoacid_modification
    terminal_modification
    analysis_timestamp
    inputfile
    roc_error_data
    mixture_model
    distribution_point
    mixturemodel_distribution
    posmodel_distribution
    negmodel_distribution
    mixturemodel
    point
    roc_data_point
    error_point
/;

sub new {

    my ($class,@other) = @_;

    # this hack is necessary so Run objects can access the underlying
    # filehandle
    my $self = $class->SUPER::new(@other);
    for (@{ $self->{runs} }) {
        $_->{fh} = $self->{fh};
    }

    return $self;

}

sub _load_new {

    my ($self) = @_;

    my $fh = $self->{fh};

    $self->{runs} = [];

    $self->{_curr_ref} = $self;
    my $p = XML::Parser->new();
    $p->setHandlers(
        Start => sub{ $self->_handle_start( @_) },
        End   => sub{ $self->_handle_end( @_) },
        Char  => sub{ $self->_handle_char( @_) },
    );
    $p->parse($fh);
    seek $fh, 0, 0;

    $self->_tidy_up();
    $self->{next_run} = 0;

    return;

}

sub _tidy_up {

    my ($self) = @_;
    
    # delete temporary entries (start with "_")
    for my $key (qw/_last_record _skip_parse _curr_ref/) {
        delete $self->{$key}
    }

    # clean toplevel
    my $toplevel = 'msms_pipeline_analysis';
    $self->{$_} = $self->{$toplevel}->{$_}
        for (keys %{ $self->{$toplevel} });
    delete $self->{$toplevel};

    return;

}

sub _handle_start {

    my ($self, $p, $el, %attrs) = @_;

    my $run;
    if ($el eq 'msms_run_summary') {
        $run = MS::Parser::PepXML::Run->new;
        $run->{raw_file} = $attrs{base_name} . $attrs{raw_data};
        $run->{parent} = $self;
        $self->{curr_run} = $run;
    }
    else {
        $run = $self->{curr_run};
    }

    # track offsets of certain items
    if ($_make_index{ $el }) {
        my $id = $attrs{index}
            or croak "'index' attribute missing on indexed element";
        $run->{offsets}->{$id} = $p->current_byte;
        if (defined $run->{_last_record}) {
            $run->{links}->{ $run->{_last_record} } = $id;
            $run->{backlinks}->{$id} = $run->{_last_record};
        }
        else {
            $run->{start_record} = $id;
            $run->{pos} = $id;
        }
        $run->{end_record}   = $id;
        $run->{_last_record} = $id;
    }

    # skip parsing inside certain elements
    if ($_skip_inside{ $el }) {
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
    
    # Elements that should be grouped by name/id
    if ($_name_value{ $el }) {

        my ($id_name, $val_name) = @{ $_name_value{ $el } };
        my $id  = $attrs{$id_name};
        my $val = $attrs{$val_name};
        $self->{_curr_ref}->{$el}->{$id} = $val
            if (! defined $self->{_curr_ref}->{$el}->{$id});
        delete $new_ref->{$id_name};
        delete $new_ref->{$val_name};

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

    my $run = $self->{curr_run};
    if ($el eq 'msms_run_summary') {
        push @{$self->{runs}}, $self->{curr_run};
        delete $self->{curr_run};
    }

    if ($_make_index{$el}) {
        my $id = $run->{_last_record};
        my $offset = $run->{offsets}->{$id};
        $run->{lengths}->{$id} = $p->current_byte + length($el) + 3 - $offset;
    }

    if ($_skip_inside{$el}) {
        $p->setHandlers(
            Start => sub{ $self->_handle_start( @_) },
            End   => sub{ $self->_handle_end( @_) },
            Char  => sub{ $self->_handle_char( @_) },
        );
        delete $self->{_skip_parse};
        return;
    }

    return if ($self->{_skip_parse});

    # step back down linked list
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

sub next_run {

    my ($self) = @_;

    if (! defined $self->{next_run}) {
        $self->{next_run} = 0;
        return undef;
    }
    my $idx = $self->{next_run};
    my $run_count = scalar( @{ $self->{runs} } );
    $self->{next_run} = $self->{next_run} < $run_count - 1
        ? $self->{next_run} + 1
        : undef;
    return $self->{runs}->[$idx];

}

sub next_run_index {

    my ($self) = @_;

    if (! defined $self->{next_run}) {
        $self->{next_run} = 0;
        return undef;
    }
    my $idx = $self->{next_run};
    my $run_count = scalar( @{ $self->{runs} } );
    $self->{next_run} = $self->{next_run} < $run_count - 1
        ? $self->{next_run} + 1
        : undef;
    return $idx;

}

sub fetch_run {

    my ($self,$run_idx) = @_;
    return $self->{runs}->[$run_idx];

}


# this subroutine will read in and return the first complete XML element from
# the filehandle given. I had to do this to avoid memory leaks with all of the
# XML parser options I tried when I just want to parse a single element at a
# time. Its possible I may be able to remove this in the future if I can
# figure out something wrong in my parser code (e.g. circular references?)


1;
