package MS::Parser::PepXML::Result;

use strict;
use warnings;

use parent qw/MS::Parser::XML::Record/;

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
