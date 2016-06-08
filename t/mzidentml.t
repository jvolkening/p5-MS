#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use FindBin;
use MS::Reader::MzIdentML;

chdir $FindBin::Bin;

require_ok ("MS::Reader::MzIdentML");

# check that compressed and uncompressed FHs return identical results
my $fn = 'corpus/test3.mzid.gz';

ok (my $p = MS::Reader::MzIdentML->new($fn), "created parser object");

ok ($p->n_ident_lists == 2, "n_ident_lists()");

ok ($p->raw_file('LCMALDI_spectra') eq
    'proteinscape://www.medizinisches-proteom-center.de/PSServer/Project/Sample/Separation_1D_LC/Fraction_X',
    "raw_file()");

ok (my $g = $p->next_protein_group, "next_protein_group()");
ok ($g->id eq 'group1', "id()");
my $i = 1;
++$i while ( $g = $p->next_protein_group );
ok ($i == 7, "next_protein_group() 2");

$p->goto_ident_list(1);
ok (my $r = $p->next_spectrum_result, "next_spectrum_result()");
ok ($r->id eq 'Mas_spec2b', "id()");
$i = 1;
while (my $r = $p->next_spectrum_result) {
    ++$i;
}
ok ($i == 9, "next_spectrum_result() 2");

done_testing();
