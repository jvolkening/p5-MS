#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use FindBin;
use MS::Reader::PepXML;

chdir $FindBin::Bin;

require_ok ("MS::Reader::PepXML");

# check that compressed and uncompressed FHs return identical results
my $fn = 'corpus/test.pep.xml.gz';

ok (my $p = MS::Reader::PepXML->new($fn), "created parser object");

ok ($p->n_lists == 4, "n_lists()");

ok ($p->raw_file(0) eq
    '/home/jeremy/Documents/school/research/thermal/greg/mzML/K562_Ctrl_thermo-denat_TMT.mzML',
    "raw_file()" );

my $i = 0;
ok ($p->goto_list(2), "goto_list()");
ok ($p->result_count() == 2450, "result_count()");
++$i while (my $s = $p->next_result);
ok ($i == 2450, "next_result()");

    
$p->goto_list(1);
ok ($s = $p->next_result(), "next_result()" );
ok (my $h = $s->get_hit(0), "get_hit()" );
ok ($h->{peptide} eq 'QAPLSMAAIRPEPK', "hit_check" );
done_testing();
