package MS::Reader::MzML;

use strict;
use warnings;

use parent qw/MS::Reader::XML/;

use Carp;
use Data::Lock qw/dlock dunlock/;
use Data::Dumper;
use Digest::SHA;
use List::Util qw/first/;

use MS::Reader::MzML::Spectrum;
use MS::Reader::MzML::Chromatogram;
use MS::CV qw/:MS/;

our $VERSION = 0.005;

sub _pre_load {

    my ($self) = @_;

    # ---------------------------------------------------------------------------#
    # These tables are the main configuration point between the parser and the
    # specific document schema. For more information, see the documentation
    # for the parent class MS::Reader::XML
    # ---------------------------------------------------------------------------#

    $self->{_toplevel} = 'MzML';
    $self->{rt_index} = undef;

    $self->{record_classes} = {
        spectrum     => 'MS::Reader::MzML::Spectrum',
        chromatogram => 'MS::Reader::MzML::Chromatogram',
    };

    $self->{_skip_inside} = { map {$_ => 1} qw/
        spectrum
        chromatogram
        indexList
    / };

    $self->{_make_index} = { map {$_ => 'id'} qw/
        spectrum
        chromatogram
    / };

    $self->{_make_named_array} = {
        cvParam   => 'accession',
        userParam => 'name',
    };

    $self->{_make_named_hash} = { map {$_ => 'id'} qw/
        cv
        dataProcessing
        instrumentConfiguration
        referenceableParamGroup
        sample
        scanSettings
        software
        sourceFile
    / };

    $self->{_make_anon_array} = { map {$_ => 1} qw/
        analyzer
        contact
        detector
        processingMethod
        referenceableParamGroupRef
        source
        sourceFileRef
        target
    / };

}


sub _post_load {

    my ($self) = @_;

    if (defined $self->{indexedmzML}->{fileChecksum}) {

        # compare supplied and calculated SHA1 sums to validate
        my $sha1_given = $self->{indexedmzML}->{fileChecksum}->{pcdata};
        croak "ERROR: SHA1 digest mismatch\n"
            if ($sha1_given ne $self->_calc_sha1);

    }

    # Outer <mzML> may optionally be wrapped in <indexedmxML> tags. For
    # consistent downstream handling, everything outside <mzML> should be
    # discarded before returning.
    if (defined $self->{indexedmzML}) {
        $self->{mzML}->{$_} = $self->{indexedmzML}->{mzML}->{$_}
            for (keys %{ $self->{indexedmzML}->{mzML} });
        delete $self->{indexedmzML};
    }

    $self->SUPER::_post_load();

    return;

}

sub fetch_spectrum {

    my ($self, $idx, %args) = @_;
    return $self->fetch_record('spectrum', $idx, %args);

}

sub next_spectrum {

    my ($self, %args) = @_;
    return $self->next_record( 'spectrum', %args );

}

sub find_by_time {

    my ($self, $ret, $ms_level) = @_;

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

    my $i = $sorted[$lower]->[0]; #return closest scan index >= $ret
    while (defined $ms_level
      && $self->fetch_record('spectrum' => $i)->ms_level() != $ms_level) {
        ++$i;
    }
    return $i;

}

sub _index_rt {

    my ($self) = @_;

    my @spectra;
    my $saved_pos = $self->{pos}->{spectrum};
    $self->goto('spectrum' => 0);
    my $curr_pos  = $self->{pos}->{spectrum};
    while (my $spectrum = $self->next_spectrum) {

        my $ret = $spectrum->rt;
        push @spectra, [$curr_pos, $ret];
        $curr_pos = $self->{pos}->{spectrum};

    }
    @spectra = sort {$a->[1] <=> $b->[1]} @spectra;
    $self->{pos}->{spectrum} = $saved_pos;
    dunlock $self->{rt_index};
    $self->{rt_index} = [@spectra];
    dlock $self->{rt_index};

    # Since we took the time to index RTs, go ahead and store the updated
    # structure to file
    $self->write_index;

    return;

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

    my ($self, $force) = @_;

    my $idx = $self->{index}->{chromatogram}->{TIC};
    if (! $force && defined $self->{offsets}->{chromatogram}->[$idx]) {
        my $offset = $self->{offsets}->{chromatogram}->[$idx];
        my $to_read = $self->{lengths}->{chromatogram}->[$idx];
#
        my $el   = $self->_read_element($offset,$to_read);
        return MS::Reader::MzML::Chromatogram->new(xml => $el);
    }
    return MS::Reader::MzML::Chromatogram->new(type => 'tic', raw => $self);

}

sub get_xic {

    my ($self,%args) = @_;
    return MS::Reader::MzML::Chromatogram->new(type => 'xic',raw => $self,%args);

}

sub get_bpc {

    my ($self) = @_;

    if (my $chrom = first { defined $_->{cvParam}->{&BASEPEAK_CHROMATOGRAM} }
      @{ $self->{mzML}->{run}->{chromatogramList}->{chromatogram} } ) {
        my $idx = $self->{index}->{chromatogram}->{ $chrom->{id} };
        my $offset = $self->{offsets}->{chromatogram}->[$idx];
        croak "No offset found for chromatogram"
            if (! defined $offset);
        my $to_read = $self->{lengths}->{chromatogram}->[$idx];

        my $el   = $self->_read_element($offset,$to_read);
        return MS::Reader::MzML::Chromatogram->new(xml => $el);
    }

    return MS::Reader::MzML::Chromatogram->new(type => 'bpc',raw => $self);

}

1;

__END__

=head1 NAME

MS::Reader::MzML - A simple but complete mzML parser

=head1 SYNOPSIS

    use MS::Reader::MzML;

    my $p = MS::Reader::MzML->new('run.mzML');

=cut
