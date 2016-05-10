package MS::Parser::MzIdentML;

use strict;
use warnings;

use parent qw/MS::Parser/;

use Carp;
use Data::Dumper;
use Digest::SHA;
use List::Util qw/first/;
use XML::Parser;

use MS::CV qw/:constants/;
use MS::Parser::MzIdentML::SpectrumIdentificationResult;
use MS::Parser::MzIdentML::DBSequence;
use MS::Parser::MzIdentML::Peptide;
use MS::Parser::MzIdentML::PeptideEvidence;

our $VERSION = 0.001;


# ---------------------------------------------------------------------------#
# Membership tables to speed up checks
#
# These tables are the main configuration point between the parser and the
# specific document schema
# ---------------------------------------------------------------------------#

# these elements will not be individually parsed
# (usually these are "records" that will be parsed upon request)
our %_skip_inside = map {$_ => 1} qw/
    Peptide
    DBSequence
    PeptideEvidence
    SpectrumIdentificationResult
/;

# these elements will be indexed for direct retrieval
our %_make_index = map {$_ => 1} qw/
    Peptide
    DBSequence
    PeptideEvidence
    SpectrumIdentificationResult
/;

# these elements can occur multiple times, but should be referenced according
# to the unique attribute key specified
our %_make_named_array = (
    cvParam                 => 'accession',
    userParam               => 'name',
);

# these elements can occur multiple times, but should be referenced according
# to the unique attribute key specified
our %_make_named_hash = (
    AnalysisSoftware               => 'id',
    BibliographicReference         => 'id',
    cv                             => 'id',
    DBSequence                     => 'id',
    Enzyme                         => 'id',
    MassTable                      => 'id',
    Measure                        => 'id',
    Organization                   => 'id',
    Peptide                        => 'id',
    PeptideEvidence                => 'id',
    Person                         => 'id',
    ProteinAmbiguityGroup          => 'id',
    ProteinDetectionHypothesis     => 'id',
    SampleType                     => 'id',
    SearchDatabase                 => 'id',
    SourceFile                     => 'id',
    SpectraData                    => 'id',
    SpectrumIdentification         => 'id',
    SpectrumIdentificationItem     => 'id',
    SpectrumIdentificationList     => 'id',
    SpectrumIdentificationProtocol => 'id',
    TranslationTable               => 'id',
);

# these elements can occur multiple times and should be parsed into an
# anonymous array
our %_make_anon_array = map {$_ => 1} qw/
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
/;    

# Perform parsing of the XML (this is called by the parent class - do not
# change the method name )

sub _load_new {

    my ($self) = @_;

    my $fh = $self->{fh};

    $self->{_curr_ref} = $self;
    my $p = XML::Parser->new();
    $p->setHandlers(
        Start => sub{ $self->_handle_start( @_) },
        End   => sub{ $self->_handle_end( @_) },
        Char  => sub{ $self->_handle_char( @_) },
    );
    $p->parse($fh);
        
    $self->_tidy_up();
    seek $fh, 0, 0;

    return;

}

# Clean up the internal structure somewhat before returning the object

sub _tidy_up {

    my ($self) = @_;
    
    # delete temporary entries (start with "_")
    for (keys %{$self}) {
        delete $self->{$_} if ($_ =~ /^_/);
    }

    return;

}

# Define the XML stream handlers
    
sub _handle_start {

    my ($self, $p, $el, %attrs) = @_;

    # track offsets of requested items
    if ($_make_index{ $el }) {

        my $id = $attrs{id}
            or croak "'id' attribute missing on indexed element";

        $self->{offsets}->{$el}->{$id} = $p->current_byte;

        # link adjacent records
        if (defined $self->{_last_record}->{$el}) {
            $self->{links}->{$el}->{ $self->{_last_record}->{$el} } = $id;
            $self->{backlinks}->{$el}->{$id} = $self->{_last_record}->{$el};
        }
        else {
            $self->{ start_record }->{$el} = $id;
            $self->{ pos          }->{$el} = $id;
        }

        $self->{ end_record   }->{$el} = $id;
        $self->{ _last_record }->{$el} = $id;
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
    if ($_make_named_array{ $el }) {

        my $id_name = $_make_named_array{ $el };
        my $id = $attrs{$id_name};
        delete $new_ref->{$id_name};
        push @{ $self->{_curr_ref}->{$el}->{$id} }, $new_ref;

    }

    # Elements that should be grouped by name/id
    elsif ($_make_named_hash{ $el }) {
        my $id_name = $_make_named_hash{ $el };
        my $id = $attrs{$id_name};
        die "Colliding XS::id $id"
            if (defined $self->{_curr_ref}->{$el}->{$id});
        delete $new_ref->{$id_name};
        $self->{_curr_ref}->{$el}->{$id} = $new_ref;
    }

    # Elements that should be grouped with no name
    elsif ( $_make_anon_array{ $el } ) {
        push @{ $self->{_curr_ref}->{$el} }, $new_ref;
    }

    # Everything else
    else {  
        $self->{_curr_ref}->{$el} = $new_ref;
    }

    # Step up linked list
    $self->{_curr_ref} = $new_ref;

    return;

}

sub _handle_end {

    my ($self, $p, $el) = @_;

    # Track length of indexed elements
    if ($_make_index{$el}) {
        my $id = $self->{_last_record}->{$el};
        my $offset = $self->{offsets}->{$el}->{$id};

        # Don't forget to add length of tag and "</>" chars
        $self->{lengths}->{$el}->{$id} = $p->current_byte
            + length($el) + 3 - $offset;
    }

    # Reset handlers for skipped elements
    if ($_skip_inside{$el}) {
        $p->setHandlers(
            Start => sub{ $self->_handle_start( @_) },
            End   => sub{ $self->_handle_end( @_) },
            Char  => sub{ $self->_handle_char( @_) },
        );
        delete $self->{_skip_parse};
        return;
    }

    # Don't do anything if inside skipped element
    return if ($self->{_skip_parse});

    # Step back down linked list
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

sub dump {

    my ($self) = @_;

    my $copy = {};
    %$copy = %$self;

    delete $copy->{$_} for qw/fh offsets fn links backlinks fh pos lengths
        md5sum start_record end_record version/;

    {
        local $Data::Dumper::Indent = 1;
        local $Data::Dumper::Terse = 1;
        local $Data::Dumper::Sortkeys = 1;
        print Dumper $copy;
    }

    return;

}

sub _read_element {

    my ($self, $offset, $to_read) = @_;

    seek $self->{fh}, $offset, 0;
    my $r = read($self->{fh}, my $el, $to_read);
    croak "returned unexpected byte count" if ($r != $to_read);

    return $el;

}

sub fetch_record {

    my ($self, $type, $id, %args) = @_;

    $id += 0 if ($id =~ /^\d+$/); #ignore leading zeros
    my $offset = $self->{offsets}->{$type}->{ $id };
    croak "Record not found for $id" if (! defined $offset);
    my $to_read = $self->{lengths}->{$type}->{ $id };

    my $el   = $self->_read_element($offset, $to_read);
    return "MS::Parser::MzIdentML::$type"->new(xml => $el);

}

sub next_result {

    my ($self, %args) = @_;

    my $pos = $self->{pos}->{SpectrumIdentificationResult};
    return if (! defined $self->{offsets}->{SpectrumIdentificationResult}->{$pos});

    my $result;

    # There is a while loop here because a return value of -1 from
    # fetch_record() means the spectrum was filtered out, in which case we
    # keep trying to find a valid spectrum to return
    my $c = 0;
    while ($result = $self->fetch_record( 'SpectrumIdentificationResult' => $pos, %args)) {
        if (! defined $self->{links}->{SpectrumIdentificationResult}->{$pos}) { # last scan
            $self->{pos}->{SpectrumIdentificationResult} = '';
            return $result eq -1 ? undef : $result;
        }
        $self->{pos}->{SpectrumIdentificationResult}
            = $self->{links}->{SpectrumIdentificationResult}->{$pos};
        $pos = $self->{pos}->{spectrum}; 
        return $result if (! defined $result || $result != -1); 
    }

    return $result;

}

1;


__END__

=head1 NAME

MS::Parser::MzIdentML - A simple but complete mzIdentML parser

=head1 SYNOPSIS

    use MS::Parser::MzIdentML;

    my $p = MS::Parser::MzIdentML->new('search.mzid');

