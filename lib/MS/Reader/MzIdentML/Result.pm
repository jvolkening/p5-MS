package MS::Reader::MzIdentML::Result;

use strict;
use warnings;

use parent qw/MS::Reader::XML::Record/;

sub _pre_load {

    my ($self) = @_;
    $self->{_toplevel} = 'SpectrumIdentificationResult';

}

# TODO: add class methods

1;
