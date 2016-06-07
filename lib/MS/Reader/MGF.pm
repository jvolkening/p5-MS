package MS::Reader::MGF;

use strict;
use warnings;

use parent qw/MS::Reader/;

use Carp;
use Data::Dumper;
use Data::Lock;

use MS::Reader::MGF::Spectrum;

our $VERSION = 0.001;

# Perform parsing of the MGF (this is called by the parent class - do not
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
    my $in_spectrum;

    LINE:
    while (my $line = <$fh>) {
        
        next if ($line =~ /^#/);
        next if ($line !~ /\S/);
        chomp $line;

        if ($line eq 'BEGIN IONS') {
            $offset = tell $fh;
            $in_spectrum = 1;
            next LINE;
        }

        if ($line eq 'END IONS') {
            die "No spectrum TITLE found\n" if (! defined $title);
            push @{ $self->{offsets} }, $offset;
            push @{ $self->{lengths} }, $last_offset - $offset;
            $self->{index}->{$title} = $#{ $self->{offsets} };
            $in_spectrum = 0;
            $title = undef;
            next LINE;
        }

        $last_offset = tell $fh;

        next LINE if ($in_spectrum && defined $title);

        if ($line =~ /^(\w+)\=(.+)$/) {
            my ($key, $val) = ($1, $2);
            if ($in_spectrum) {
                $title = $val if ($key eq 'TITLE');
            }
            else {
                croak "$key already defined\n"
                    if (exists $self->{params}->{$key});
                $self->{params}->{$key} = $val;
            }
            next LINE;
        }

    }

    $self->{count} = scalar @{ $self->{offsets} };

}

sub fetch_spectrum {

    my ($self, $idx) = @_;
    
    my $offset = $self->{offsets}->[$idx];
    croak "Record not found for $idx" if (! defined $offset);
    
    my $to_read = $self->{lengths}->[ $idx ];
    my $el = $self->_read_element($offset,$to_read);

    return MS::Reader::MGF::Spectrum->new($el);

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

MS::Reader::MGF - A simple but complete MGF parser

=head1 SYNOPSIS

    use MS::Reader::MGF;

    my $p = MS::Reader::MGF->new('run.mgf');

=cut
