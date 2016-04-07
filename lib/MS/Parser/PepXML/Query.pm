package MS::Parser::PepXML::Query;

use strict;
use warnings;
use MS::Mass qw/:all/;

# Lookup tables to quickly check elements
our %_name_value = (
    parameter    => ['name','value'],
    search_score => ['name','value'],
);
our %_make_anon_array = map {$_ => 1} qw/
    search_result
    search_hit
    search_id
    alternative_protein
    mod_aminoacid_mass
    analysis_result
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
            Start => sub{ $self->_handle_start(@_) },
            End   => sub{ $self->_handle_end(  @_) },
            Char  => sub{ $self->_handle_char( @_) },
        );
        $p->parse($args{xml});

        delete $self->{_curr_ref}; # CRITICAL - avoid circular reference memleak
        delete $self->{filter};

        # clean toplevel
        my $toplevel = 'spectrum_query';
        $self->{$_} = $self->{$toplevel}->{$_}
            for (keys %{ $self->{$toplevel} });
        delete $self->{$toplevel};

    }

    return $self;

}

sub _handle_start {

    my ($self, $p, $el, %attrs) = @_;

    my $new_ref = {%attrs};
    $new_ref->{back} = $self->{_curr_ref};
    
    # Elements that should be grouped by name/id
    if ($_name_value{ $el }) {

        my ($id_name,$val_name) = @{ $_name_value{ $el } };
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

    # step back down linked list
    my $last_ref = $self->{_curr_ref}->{back};
    delete $self->{_curr_ref}->{back};
    $self->{_curr_ref} = $last_ref;

    return;

}

sub _handle_char {

    my ($self, $p, $data) = @_;

    $self->{_curr_ref}->{pcdata} .= $data
        if ($data =~ /\S/);

    return;

}

sub top_hit {

    # convenience function to extract top hit

    my ($self) = @_;
    return $self->{search_result}->[0]->{search_hit}->[0];

}

sub mod_delta_array {

    my ($self,$hit) = @_;
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
    return @deltas;

}

1;
