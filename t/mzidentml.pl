#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use FindBin;
use MS::Reader::MzIdentML;

chdir $FindBin::Bin;

require_ok ("MS::Reader::MzIdentML");

# check that compressed and uncompressed FHs return identical results
my $fn = 'corpus/test.mzid.gz';

ok (my $p = MS::Reader::MzIdentML->new($fn), "created parser object");

done_testing();
