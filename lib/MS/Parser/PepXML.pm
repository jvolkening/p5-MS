package MS::Parser::PepXML;

use strict;
use warnings;

use parent qw/MS::Parser::XML/;

use Carp;

use MS::Parser::PepXML::Result;
use MS::CV qw/:constants/;

our $VERSION = 0.006;

sub _pre_load {

    my ($self) = @_;

    # ---------------------------------------------------------------------------#
    # These tables are the main configuration point between the parser and the
    # specific document schema. For more information, see the documentation
    # for the parent class MS::Parser::XML
    # ---------------------------------------------------------------------------#

    $self->{_toplevel} = 'msms_pipeline_analysis';

    $self->{record_classes} = {
        spectrum_query => 'MS::Parser::PepXML::Result',
    };

    $self->{_skip_inside} = { map {$_ => 1} qw/
        spectrum_query
    / };

    $self->{_make_index} = { map {$_ => 'spectrum'} qw/
        spectrum_query
    / };

    $self->{_store_child_iters} = {
        msms_run_summary => 'spectrum_query',
    };

    $self->{_make_named_array} = {
        cvParam   => 'accession',
        userParam => 'name',
    };

    $self->{_make_named_hash} = {
        parameter => 'name'
    };

    $self->{_make_anon_array} = { map {$_ => 1} qw/
        data_filter
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
    / };

}

sub next_result {

    my ($self) = @_;
    return $self->next_record ('spectrum_query');

}

sub next_list_result {

    my ($self, $list_id) = @_;
    my $curr_pos = $self->{pos}->{spectrum_query};
    my $max_pos = $self->{msms_run_summary}->[$list_id]->{last_child_idx};
    return undef if ($curr_pos > $max_pos);
    return $self->next_record('spectrum_query');

}

sub result_lists {

    my ($self) = @_;
    return (0..scalar(@{$self->{msms_run_summary}})-1);

}

sub goto_list {

    my ($self, $idx) = @_;
    $self->{pos}->{spectrum_query} = $self->{msms_run_summary}
        ->[$idx]->{first_child_idx};

}

1;


__END__

=head1 NAME

MS::Parser::PepXML - A simple but complete PepXML parser

=head1 SYNOPSIS

    use MS::Parser::PepXML;

    my $p = MS::Parser::PepXML->new('search.pep.xml');

=cut
