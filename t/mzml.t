#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use FindBin;
use MS::Reader::MzML;

chdir $FindBin::Bin;

require_ok ("MS::Reader::MzML");

my $fn = 'corpus/test.mzML.gz';

ok (my $p = MS::Reader::MzML->new($fn), "created parser object");

ok ($p->id eq 'Medicago_TMT_POOL1_2ug', "id()");
ok ($p->n_spectra == 35, "n_spectra()");

ok( my $s = $p->next_spectrum, "read first record"  );
ok( $s = $p->next_spectrum, "read second record" );
ok( are_equal( $s->rt,  5063.2261, 3), "rt()" );
ok( my $mz  = $s->mz,  "mz()" );
ok( my $int = $s->int, "int()" );
ok( scalar(@$mz) == scalar(@$int), "identical array lengths" );
ok( scalar(@$mz) == 764, "correct array lengths" );

ok( $p->record_count('spectrum') == 35, "record_count()" );
ok( $p->curr_index('spectrum')   == 2, "curr_index()" );

my $idx = $p->get_index_by_id( 'spectrum' =>
    'controllerType=0 controllerNumber=1 scan=10014' );
ok( $idx == 13, "get_index_by_id()" );
$p->goto('spectrum' => $idx);
ok( $p->curr_index('spectrum') == 13, "goto()" );

ok( $s = $p->next_spectrum, "read second record" );
$int = $s->int;
$mz  = $s->mz;
ok( are_equal($mz->[4],  300.0572, 3), "mz()"  );
ok( are_equal($int->[6], 3538.943, 3), "int()" );
ok( $s->ms_level == 1, "ms_level()" );
my $last_id;
while ($s = $p->next_spectrum) {
    $last_id = $s->id;
}
ok( $last_id eq 'controllerType=0 controllerNumber=1 scan=10035', "id()" );
$idx = $p->find_by_time(5074.6);
ok( $idx == 29, "find_by_time()" );
$p->goto('spectrum' => 29);
$s = $p->next_spectrum;
ok (my $pre = $s->precursor, "precursor()");
ok ($pre->{scan_id} eq 'controllerType=0 controllerNumber=1 scan=10026',
    "precursor id" );
ok ($pre->{iso_mz}    == 423.75, "precursor iso_mz");
ok ($pre->{iso_lower} == 422.75, "precursor iso_lower");
ok ($pre->{iso_upper} == 424.75, "precursor iso_upper");
ok ($pre->{charge}    == 2, "precursor charge");
ok (are_equal($pre->{mono_mz},    423.748, 3), "precursor mono_mz");
ok (are_equal($pre->{intensity}, 8347.699, 3), "precursor intensity");

$idx = $p->find_by_time(5072.5);
$s = $p->fetch_spectrum($idx);
ok ($s->scan_number == 10025, "find_by_time()");

ok ($p->get_tic->isa('MS::Reader::MzML::Chromatogram'), "get_tic()");
ok ($p->get_bpc->isa('MS::Reader::MzML::Chromatogram'), "get_bpc()");
ok ($p->get_xic(mz => '157.117', err_ppm => 10)->isa('MS::Reader::MzML::Chromatogram'), "get_bpc()");

done_testing();

sub are_equal {

    my ($v1, $v2, $dp) = @_;
    return sprintf("%.${dp}f", $v1) eq sprintf("%.${dp}f", $v2);

}
