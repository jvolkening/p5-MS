package MS::Reader::MzIdentML::Peptide;

use strict;
use warnings;

use parent qw/MS::Reader::XML::Record/;

sub _pre_load {

    my ($self) = @_;
    $self->{_toplevel} = 'Peptide';

}

# TODO: add class methods

1;
