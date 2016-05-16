package MS::Parser::ProtXML::Group;

use strict;
use warnings;

use parent qw/MS::Parser::XML::Record/;

sub _pre_load {

    my ($self) = @_;

    $self->{_toplevel} = 'protein_group';

    $self->{_make_named_hash} = { map {$_ => 'name'} qw/
        parameter
    / };

    $self->{_make_anon_array} = { map {$_ => 1} qw/
        protein
        analysis_result
        indistinguishable_protein
        peptide
        modification_info
        mod_aminoacid_mass
        peptide_parent_protein
        indistinguishable_peptide
    / };

}

1;
