package MS::Parser::MzIdentML;

use strict;
use warnings;

use parent qw/MS::Parser::XML/;

use Carp;

use MS::Parser::MzIdentML::Result;
use MS::Parser::MzIdentML::DBSequence;
use MS::Parser::MzIdentML::Peptide;
use MS::Parser::MzIdentML::PeptideEvidence;
use MS::CV qw/:constants/;

our $VERSION = 0.001;


sub _pre_load {

    my ($self) = @_;

    # ---------------------------------------------------------------------------#
    # These tables are the main configuration point between the parser and the
    # specific document schema. For more information, see the documentation
    # for the parent class MS::Parser::XML
    # ---------------------------------------------------------------------------#


    $self->{record_classes} = {
        DBSequence                   => 'MS::Parser::MzIdentML::DBSequence',
        Peptide                      => 'MS::Parser::MzIdentML::Peptide',
        PeptideEvidence              => 'MS::Parser::MzIdentML::PeptideEvidence',
        SpectrumIdentificationResult => 'MS::Parser::MzIdentML::Result',
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

MS::Parser::MzIdentML - A simple but complete mzIdentML parser

=head1 SYNOPSIS

    use MS::Parser::MzIdentML;

    my $p = MS::Parser::MzIdentML->new('search.mzid');

=cut
