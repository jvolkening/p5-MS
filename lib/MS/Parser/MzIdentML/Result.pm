package MS::Parser::MzIdentML::Result;

use strict;
use warnings;

use parent qw/MS::Parser::XML::Record/;
use MS::CV qw/:constants/;

sub _pre_load {

    my ($self) = @_;
    $self->{_toplevel} = 'SpectrumIdentificationResult';

}

# TODO: add class methods

1;
