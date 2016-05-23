package MS::Reader::ProtXML;

use strict;
use warnings;

use parent qw/MS::Reader::XML/;

use Carp;

use MS::Reader::ProtXML::Group;

our $VERSION = 0.003;

sub _pre_load {

    my ($self) = @_;

    # ---------------------------------------------------------------------------#
    # These tables are the main configuration point between the parser and the
    # specific document schema. For more information, see the documentation
    # for the parent class MS::Reader::XML
    # ---------------------------------------------------------------------------#

    $self->{_toplevel} = 'protein_summary';

    $self->{record_classes} = {
        protein_group => 'MS::Reader::ProtXML::Group',
    };

    $self->{_skip_inside} = { map {$_ => 1} qw/
        protein_group
    / };

    $self->{_make_index} = { map {$_ => 'spectrum'} qw/
        protein_group
    / };

    $self->{_make_named_array} = {
        cvParam   => 'accession',
        userParam => 'name',
    };

    $self->{_make_named_hash} = {
        parameter => 'name'
    };

    $self->{_make_anon_array} = { map {$_ => 1} qw/
        analysis_summary
        nsp_distribution
        ni_distribution
        protein_summary_data_filter
    / };

}

sub next_group {

    my ($self) = @_;
    return $self->next_record('protein_group');


}


sub fetch_group {

    my ($self, $idx) = @_;

    return $self->fetch_record('protein_group' => $idx);

}


1;
