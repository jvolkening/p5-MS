package MS::Reader::MzIdentML::PeptideEvidence;

use strict;
use warnings;

use base qw/MS::Reader::XML::Record/;

sub _pre_load {

    my ($self) = @_;
    $self->{_toplevel} = 'PeptideEvidence';

}

# TODO: add class methods

1;
