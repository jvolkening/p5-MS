package MS::Parser::MzML;

use strict;
use warnings;

use parent qw/MS::Parser/;

use Carp;
use Data::Dumper;
use Digest::SHA;
use List::Util qw/first/;
use XML::Parser;

use MS::Parser::MzML::Spectrum;
use MS::Parser::MzML::Chromatogram;
use MS::CV qw/:constants/;

our $VERSION = 0.004;


# ---------------------------------------------------------------------------#
# Membership tables to speed up checks
#
# These tables are the main configuration point between the parser and the
# specific document schema
# ---------------------------------------------------------------------------#

# these elements will not be individually parsed
# (usually these are "records" that will be parsed upon request)
our %_skip_inside = map {$_ => 1} qw/
    spectrum
    chromatogram
    indexList
/;

# these elements will be indexed for direct retrieval
our %_make_index = map {$_ => 1} qw/
    spectrum
    chromatogram
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
    instrumentConfiguration => 'id',
    dataProcessing          => 'id',
    referenceableParamGroup => 'id',
    cv                      => 'id',
    sample                  => 'id',
    scanSettings            => 'id',
    software                => 'id',
    sourceFile              => 'id',
);

# these elements can occur multiple times and should be parsed into an
# anonymous array
our %_make_anon_array = map {$_ => 1} qw/
    referenceableParamGroupRef
    sourceFileRef
    processingMethod
    contact
    target
    source
    analyzer
    detector
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
        
    if (defined $self->{indexedmzML}->{fileChecksum}) {

        # compare supplied and calculated SHA1 sums to validate
        my $sha1_given = $self->{indexedmzML}->{fileChecksum}->{pcdata};
        croak "ERROR: SHA1 digest mismatch\n"
            if ($sha1_given ne $self->_calc_sha1);

    }

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

    # Outer <mzML> may optionally be wrapped in <indexedmxML> tags. For
    # consistent downstream handling, everything outside <mzML> should be
    # discarded before returning.
    if (defined $self->{indexedmzML}) {
        $self->{mzML}->{$_} = $self->{indexedmzML}->{mzML}->{$_}
            for (keys %{ $self->{indexedmzML}->{mzML} });
        delete $self->{indexedmzML};
    }

    return;

}

# Define the XML stream handlers
    
sub _handle_start {

    my ($self, $p, $el, %attrs) = @_;

    # track offsets of requested items
    if ($_make_index{ $el }) {

        my $id = _parse_id( $attrs{id} )
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
        $self->{_curr_ref}->{$el}->{$id} = []
            if (! defined $self->{_curr_ref}->{$el}->{$id});
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

# Simply resets the current position to the first spectrum

sub reset_spectrum {

    my ($self) = @_;
    $self->{pos}->{spectrum} = $self->{start_record}->{spectrum};
    return;

}

# Sets the current position to the specified spectrum

sub goto_spectrum {

    my ($self,$scan_num) = @_;
    $scan_num = _parse_id($scan_num);
    $self->{pos}->{spectrum} = $scan_num;
    return;

}

sub next_spectrum {

    my ($self, %args) = @_;

    my $pos = $self->{pos}->{spectrum};
    return if (! defined $self->{offsets}->{spectrum}->{$pos});

    my $scan;

    # There is a while loop here because a return value of -1 from
    # fetch_record() means the spectrum was filtered out, in which case we
    # keep trying to find a valid spectrum to return
    my $c = 0;
    while ($scan = $self->fetch_record( 'spectrum' => $pos, %args)) {
        if (! defined $self->{links}->{spectrum}->{$pos}) { # last scan
            $self->{pos}->{spectrum} = '';
            return $scan eq -1 ? undef : $scan;
        }
        $self->{pos}->{spectrum} = $self->{links}->{spectrum}->{$pos};
        $pos = $self->{pos}->{spectrum};

        return $scan if (! defined $scan || $scan != -1); 
    }

    return $scan;

}

sub prev_spectrum_index {

    my ($self, $scan_num) = @_;
    $scan_num = _parse_id($scan_num);
    return $self->{backlinks}->{spectrum}->{ $scan_num } // undef;

}

sub next_spectrum_index {

    my ($self, $scan_num) = @_;
    $scan_num = _parse_id($scan_num);
    return $self->{links}->{spectrum}->{ $scan_num } // undef;

}

sub first_spectrum_index {

    my ($self) = @_;
    return $self->{start_record}->{spectrum};

}

sub last_spectrum_index {

    my ($self) = @_;
    return $self->{end_record}->{spectrum};

}


sub find_by_time {

    my ($self,$ret) = @_;

    # lazy load
    if (! defined $self->{rt_index}) {
        $self->_index_rt();
    }

    my @sorted = @{ $self->{rt_index} };

    # binary search
    my ($lower, $upper) = (0, $#sorted);
    while ($lower != $upper) {
        my $mid = int( ($lower+$upper)/2 );
        ($lower,$upper) = $ret < $sorted[$mid]->[1]
            ? ( $lower , $mid   )
            : ( $mid+1 , $upper );
    }

    return $sorted[$lower]->[0]; #return closest scan index >= $ret

}

sub dump {

    my ($self) = @_;

    my $copy = {};
    %$copy = %$self;

    delete $copy->{$_} 
        for qw/fh offsets fn links backlinks fh pos lengths/;

    {
        local $Data::Dumper::Indent = 1;
        local $Data::Dumper::Terse = 1;
        local $Data::Dumper::Sortkeys = 1;
        print Dumper $copy;
    }

    return;

}

sub _index_rt {

    my ($self) = @_;

    my @spectra;
    my $saved_pos = $self->{pos}->{spectrum};
    $self->reset_spectrum();
    my $curr_pos  = $self->{pos}->{spectrum};
    while (my $spectrum = $self->next_spectrum) {

        my $ret = $spectrum->rt;
        push @spectra, [$curr_pos, $ret];
        $curr_pos = $self->{pos}->{spectrum};

    }
    @spectra = sort {$a->[1] <=> $b->[1]} @spectra;
    $self->{pos}->{spectrum} = $saved_pos;
    $self->{rt_index} = [@spectra];

    # Since we took the time to index RTs, go ahead and store the updated
    # structure to file
    $self->write_index;

    return;

}

sub fetch_spectrum {

    my ($self) = shift;
    return $self->fetch_record('spectrum' => @_);

}

sub fetch_record_xml {

    my ($self, $type, $id, %args) = @_;

    $id += 0 if ($id =~ /^\d+$/); #ignore leading zeros
    $id = _parse_id($id);
    my $offset = $self->{offsets}->{$type}->{ $id };
    croak "Record not found" if (! defined $offset);
    my $to_read = $self->{lengths}->{$type}->{ $id };

    my $el   = $self->_read_element($offset,$to_read);

    return $el;

}


sub fetch_record {

    my ($self, $type, $id, %args) = @_;

    $id += 0 if ($id =~ /^\d+$/); #ignore leading zeros
    $id = _parse_id($id);
    my $offset = $self->{offsets}->{$type}->{ $id };
    croak "Record not found for $id" if (! defined $offset);
    my $to_read = $self->{lengths}->{$type}->{ $id };

    my $el   = $self->_read_element($offset,$to_read);
    my $record;
    if ($type eq 'spectrum') {
        $record = MS::Parser::MzML::Spectrum->new(xml => $el, filter => $args{'filter'});
    }
    elsif ($type eq 'chromatogram') {
        $record = MS::Parser::MzML::Chromatogram->new(xml => $el);
    }
    else {
        croak "unkonwn record type: $type\n";
    }

    # return -1 if the "filtered" flag is set
    return -1 if ($record->{filtered});

    return $record;

}

sub _read_element {

    my ($self, $offset, $to_read) = @_;

    seek $self->{fh}, $offset, 0;
    my $r = read($self->{fh}, my $el, $to_read);
    croak "returned unexpected byte count" if ($r != $to_read);

    return $el;

}

sub _calc_sha1 {

    my ($self) = @_;

    my $fh = $self->{fh};
    seek $fh, 0, 0;

    my $sha1 = Digest::SHA->new(1);
    local $/ = '>';
    while (my $chunk = <$fh>) {
        $sha1->add($chunk);
        last if (substr($chunk, -14) eq '<fileChecksum>');
    }

    return $sha1->hexdigest;

}

sub get_tic {

    my ($self) = @_;

    my $id = 'TIC';
    if (defined $self->{offsets}->{chromatogram}->{$id}) {
        my $offset = $self->{offsets}->{chromatogram}->{$id};
        my $to_read = $self->{lengths}->{chromatogram}->{$id};
#
        my $el   = $self->_read_element($offset,$to_read);
        return MS::Parser::MzML::Chromatogram->new(xml => $el);
    }
    return MS::Parser::MzML::Chromatogram->new(type => 'tic', raw => $self);

}

sub get_xic {

    my ($self,%args) = @_;
    my $c = scalar keys %args;
    return MS::Parser::MzML::Chromatogram->new(type => 'xic',raw => $self,%args);

}

sub get_bpc {

    my ($self) = @_;

    if (my $chrom = first { defined $_->{cvParam}->{&BASEPEAK_CHROMATOGRAM} }
      @{ $self->{mzML}->{run}->{chromatogramList}->{chromatogram} } ) {
        my $offset = $self->{offsets}->{chromatogram}->{$chrom->{id}};
        croak "No offset found for chromatogram"
            if (! defined $offset);
        my $to_read = $self->{lengths}->{chromatogram}->{$chrom->{id}};

        my $el   = $self->_read_element($offset,$to_read);
        return MS::Parser::MzML::Chromatogram->new(xml => $el);
    }

    return MS::Parser::MzML::Chromatogram->new(type => 'bpc',raw => $self);

}

sub _parse_id {

    my ($id) = @_;
    if ($id =~ /\bscan=(\d+)\b/) {
        $id = $1;
    }
    return $id;

}

1;


__END__

=head1 NAME

MS::Parser::MzML - A simple but complete mzML parser

=head1 SYNOPSIS

    use MS::Parser::MzML;

    my $p = MS::Parser::MzML->new('run.mzML');


