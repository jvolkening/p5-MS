package MS::Parser::MzIdentML::SpectrumIdentificationResult;

use strict;
use warnings;

use base qw/MS::Parser::MzIdentML::Record/;
use MS::CV qw/:constants/;
use List::Util qw/any/;

sub _toplevel { return 'SpectrumIdentificationResult'; }

# TODO: add class methods

1;
