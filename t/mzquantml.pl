#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use FindBin;
use MS::Parser::MzQuantML;

chdir $FindBin::Bin;

require_ok ("MS::Parser::MzQuantML");

# check that compressed and uncompressed FHs return identical results
my $fn = 'corpus/test.mzq.gz';

ok (my $p = MS::Parser::MzQuantML->new($fn), "created parser object");

done_testing();
