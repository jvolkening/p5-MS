package MS::Parser::MzIdentML::PeptideEvidence;

use strict;
use warnings;

use base qw/MS::Parser::XML::Record/;
use MS::CV qw/:constants/;

sub _pre_load {

    my ($self) = @_;
    $self->{_toplevel} = 'PeptideEvidence';

}

# TODO: add class methods

1;
