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
        SpectrumIdentificationResult => 'MS::Reader::MzIdentML::Result',
    };

    $self->{_skip_inside} = { map {$_ => 1} qw/
        Peptide
        DBSequence
        PeptideEvidence
        SpectrumIdentificationResult
    / };

    $self->{_make_index} = { map {$_ => 'id'} qw/
        Peptide
        DBSequence
        PeptideEvidence
        SpectrumIdentificationResult
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
        DBSequence
        Enzyme
        MassTable
        Measure
        Organization
        Peptide
        PeptideEvidence
        Person
        ProteinAmbiguityGroup
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


1;


__END__

=head1 NAME

MS::Reader::MzIdentML - A simple but complete mzIdentML parser

=head1 SYNOPSIS

    use MS::Reader::MzIdentML;

    my $p = MS::Reader::MzIdentML->new('search.mzid');

=cut
