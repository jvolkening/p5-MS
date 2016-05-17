#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use FindBin;
use MS::Parser::PepXML;

chdir $FindBin::Bin;

require_ok ("MS::Parser::PepXML");

# check that compressed and uncompressed FHs return identical results
my $fn = 'corpus/test.pep.xml.gz';

ok (my $p = MS::Parser::PepXML->new($fn), "created parser object");

done_testing();
