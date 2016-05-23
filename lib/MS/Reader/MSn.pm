package MS::Reader::MSn;

use strict;
use warnings;

use parent qw/MS::Reader/;

use Carp;
use Data::Dumper;

use MS::Reader::MSn::Spectrum;

our $VERSION = 0.001;

# Perform parsing of the MS1/MS2 (this is called by the parent class - do not
# change the method name )

sub _load_new {

    my ($self) = @_;

    $self->_parse;
    $self->{pos} = 0;
        
    return;

}

sub _post_load {

    my ($self) = @_;
    $self->{pos} = 0;

}

sub _parse {

    my ($self) = @_;

    my $fh = $self->{fh};
    my $last_offset = tell $fh;
    my $offset;
    my $title;
    my $seen_spectra = 0;

    LINE:
    while (my $line = <$fh>) {
        
        chomp $line;

        my ($f1, $f2) = split ' ', $line;

        if ($f1 eq 'H') {
            my ($str) = ($line =~ /^H\s+$f2\s+(.+)$/);
            die "Error parsing header line: $line\n" if (! defined $str);
            $self->{headers}->{$f2} = $str;
        }

        elsif ($f1 eq 'S') {
            push @{ $self->{offsets} }, $last_offset;
            $self->{index}->{$f2} = $#{ $self->{offsets} };
            if ($seen_spectra) { # if not at first record
                push @{ $self->{lengths} }, $last_offset - $self->{offsets}->[-2];
            }
            $seen_spectra = 1;
        }
        $last_offset = tell $fh;

    }
    if ($seen_spectra) { # if not at first record
        push @{ $self->{lengths} }, $last_offset - $self->{offsets}->[-1];
    }

    $self->{count} = scalar @{ $self->{offsets} };

}

sub fetch_spectrum {

    my ($self, $idx) = @_;
    
    my $offset = $self->{offsets}->[$idx];
    croak "Record not found for $idx" if (! defined $offset);
    
    my $to_read = $self->{lengths}->[ $idx ];
    my $el = $self->_read_element($offset,$to_read);

    return MS::Reader::MSn::Spectrum->new($el);

}

sub next_spectrum {

    my ($self) = @_;

    return undef if ($self->{pos} == $self->{count}); #EOF
    return $self->fetch_spectrum($self->{pos}++);

}

sub goto {

    my ($self, $idx) = @_;
    die "Index out of bounds in goto()\n"
        if ($idx < 0 || $idx >= $self->{count});
    $self->{pos} = $idx;
    return;

}

sub get_index_by_id {

    my ($self, $id) = @_;
    return $self->{index}->{$id};

}

sub curr_index {

    my ($self) = @_;
    return $self->{pos};

}

sub record_count {

    my ($self) = @_;
    return $self->{count};

}

1;


__END__

=head1 NAME

MS::Reader::MSn - A simple but complete parser of MS1 and MS2 file formats

=head1 SYNOPSIS

    use MS::Reader::MSn;

    my $p = MS::Reader::MSn->new('run.ms2');

    while (my $s = $p->next_spectrum) {

        # do something - see MS::Reader::MSn::Spectrum

    }

=cut
