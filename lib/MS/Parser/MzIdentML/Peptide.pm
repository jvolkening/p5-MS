package MS::Parser::MzIdentML::Peptide;

use strict;
use warnings;

use parent qw/MS::Parser::XML::Record/;
use MS::CV qw/:constants/;

sub _pre_load {

    my ($self) = @_;
    $self->{_toplevel} = 'Peptide';

}

# TODO: add class methods

1;
