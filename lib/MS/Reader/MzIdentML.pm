package MS::Reader::MzIdentML;

use strict;
use warnings;

use parent qw/MS::Reader::XML/;

use Carp;

use MS::Reader::MzIdentML::Result;
use MS::Reader::MzIdentML::DBSequence;
use MS::Reader::MzIdentML::Peptide;
use MS::Reader::MzIdentML::PeptideEvidence;
use MS::CV qw/:MS/;

our $VERSION = 0.001;


sub _pre_load {

    my ($self) = @_;

    # ---------------------------------------------------------------------------#
    # These tables are the main configuration point between the parser and the
    # specific document schema. For more information, see the documentation
    # for the parent class MS::Reader::XML
    # ---------------------------------------------------------------------------#


    $self->{record_classes} = {
        DBSequence                   => 'MS::Reader::MzIdentML::DBSequence',
        Peptide                      => 'MS::Reader::MzIdentML::Peptide',
        PeptideEvidence              => 'MS::Reader::MzIdentML::PeptideEvidence',
        SpectrumIdentificationResult => 'MS::Reader::MzIdentML::SpectrumIdentificationResult',
        ProteinAmbiguityGroup        => 'MS::Reader::MzIdentML::ProteinAmbiguityGroup',
    };

    $self->{_skip_inside} = { map {$_ => 1} qw/
        Peptide
        DBSequence
        PeptideEvidence
        SpectrumIdentificationResult
        ProteinAmbiguityGroup
    / };

    $self->{_make_index} = { map {$_ => 'id'} qw/
        Peptide
        DBSequence
        PeptideEvidence
        SpectrumIdentificationResult
        ProteinAmbiguityGroup
    / };

    $self->{_store_child_iters} = {
        SpectrumIdentificationList => 'SpectrumIdentificationResult',
    };

    $self->{_make_named_array} = {
        cvParam   => 'accession',
        userParam => 'name',
    };

    $self->{_make_named_hash} = { map {$_ => 'id'} qw/
        AnalysisSoftware
        BibliographicReference
        cv
        Enzyme
        MassTable
        Measure
        Organization
        Person
        ProteinDetectionHypothesis
        SampleType
        SearchDatabase
        SourceFile
        SpectraData
        SpectrumIdentification
        SpectrumIdentificationItem
        SpectrumIdentificationList
        SpectrumIdentificationProtocol
        TranslationTable
    / };

    $self->{_make_anon_array} = { map {$_ => 1} qw/
        Affiliation
        AmbiguousResidue
        ContactRole
        Filter
        FragmentArray
        InputSpectra
        InputSpectrumIdentifications
        IonType
        PeptideHypothesis
        Residue
        SearchDatabaseRef
        SearchModification
        SpecificityRules
        SpectrumIdentificationItemRef
        SubSample
    / };

}

sub next_spectrum_result {

    my ($self) = @_;
    return $self->next_record ('SpectrumIdentificationResult');

}

sub next_protein_group {

    my ($self) = @_;
    return $self->next_record ('ProteinAmbiguityGroup');

}

sub fetch_spectrum_result {

    my ($self, $idx) = @_;
    return $self->fetch_record('SpectrumIdentificationResult', $idx);

}

sub fetch_protein_group {

    my ($self, $idx) = @_;
    return $self->fetch_record('ProteinAmbiguityGroup', $idx);

}

sub next_spectrum_list_result {

    my ($self, $list_id) = @_;
    my $curr_pos = $self->{pos}->{spectrum_query};
    my $max_pos = $self->{msms_run_summary}->[$list_id]->{last_child_idx};
    return undef if ($curr_pos > $max_pos);
    return $self->next_record('spectrum_query');

}

sub n_ident_lists {

    my ($self) = @_;

    return scalar @{ $self->{SpectrumIdentificationList} };

}

sub goto_ident_list {

    my ($self, $idx) = @_;
    $self->{pos}->{spectrum_query} = $self->{SpectrumIdentificationList}
        ->[$idx]->{first_child_idx};

}

1;


__END__

=head1 NAME

MS::Reader::MzIdentML - A simple but complete mzIdentML parser

=head1 SYNOPSIS

    use MS::Reader::MzIdentML;

    my $p = MS::Reader::MzIdentML->new('search.mzid');

=cut
