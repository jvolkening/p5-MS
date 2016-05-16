package MS::Parser::MzIdentML::DBSequence;

use strict;
use warnings;

use base qw/MS::Parser::XML::Record/;

sub _pre_load {

    my ($self) = @_;
    $self->{_toplevel} = 'DBSequence';

}

# TODO: add class methods

1;
