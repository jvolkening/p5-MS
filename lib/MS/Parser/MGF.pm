package MS::Parser::MGF;

use strict;
use warnings;

use parent qw/MS::Parser/;

use Carp;
use Data::Dumper;

use MS::Parser::MGF::Spectrum;

our $VERSION = 0.001;

# Perform parsing of the MGF (this is called by the parent class - do not
# change the method name )

sub _load_new {

    my ($self) = @_;

    $self->_parse;
    $self->{pos} = 0;
        
    return;

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

}


# Simply resets the current position to the first spectrum

sub reset_spectrum {

    my ($self) = @_;
    $self->{pos} = 0;
    return;

}

# Sets the current position to the specified spectrum

sub goto_spectrum {

    my ($self, $title) = @_;
    die "spectrum $title not found\n" if (! defined $self->{index}->{$title});
    $self->{pos} = $self->{index}->{$title};
    return;

}

sub next_spectrum {

    my ($self, %args) = @_;

    return undef if ($self->{pos} > $#{ $self->{offsets} } );
    return $self->fetch_spectrum( $self->{pos}++ );

}

sub fetch_spectrum {

    my ($self, $idx) = @_;

    my $offset  = $self->{offsets}->[$idx];
    my $to_read = $self->{lengths}->[$idx];

    my $el = $self->_read_element($offset,$to_read);

    return MS::Parser::MGF::Spectrum->new($el);
    
}

sub _read_element {

    my ($self, $offset, $to_read) = @_;

    seek $self->{fh}, $offset, 0;
    my $r = read($self->{fh}, my $el, $to_read);
    croak "returned unexpected byte count" if ($r != $to_read);

    return $el;

}

1;


__END__

=head1 NAME

MS::Parser::MGF - A simple but complete MGF parser

=head1 SYNOPSIS

    use MS::Parser::MGF;

    my $p = MS::Parser::MGF->new('run.mgf');

=cut
