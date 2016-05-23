package MS::Reader::MzQuantML;

use strict;
use warnings;

use parent qw/MS::Reader::XML/;

use Carp;

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
    };

    $self->{_skip_inside} = { map {$_ => 1} qw/
    / };

    $self->{_make_index} = { map {$_ => 'id'} qw/
    / };

    $self->{_make_named_array} = {
        cvParam   => 'accession',
        userParam => 'name',
    };

    $self->{_make_named_hash} = { map {$_ => 'id'} qw/
        Assay
        AssayQuantLayer
        BibliographicReference
        Cv
        DataProcessing
        Organization
        Person
        Feature
        FeatureQuantLayer
        FeatureList
        GlobalQuantLayer
        IdentificationFile
        MethodFile
        MS2AssayQuantLayer
        MS2StudyVariableQuantLayer
        PeptideConsensus
        PeptideConsensusList
        ProteinGroup
        Protein
        Provider
        RatioQuantLayer
        Ratio
        RawFile
        RawFilesGroup
        SearchDatabase
        SmallMolecule
        Software
        SourceFile
        StudyVariable
        StudyVariableQuantLayer

    / };

    $self->{_make_anon_array} = { map {$_ => 1} qw/
        Affiliation
        Column
        DBIdentificationRef
        EvidenceRef
        IdentificationRef
        Modification
        ProcessingMethod
        ProteinRef
        Row
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
