#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use FindBin;
use MS::Parser::MzML;

chdir $FindBin::Bin;

require_ok ("MS::Parser::MzML");

my $fn = 'corpus/test.mzML.gz';

ok (my $p = MS::Parser::MzML->new($fn), "created parser object");

ok( my $s = $p->next_spectrum, "read first record"  );
ok(    $s = $p->next_spectrum, "read second record" );
ok( are_equal( $s->rt,  5063.2261, 3), "read RT" );
ok( my $mz  = $s->mz,  "read m/z array" );
ok( my $int = $s->int, "read m/z array" );
ok( scalar(@$mz) == scalar(@$int), "identical array lengths" );
ok( scalar(@$mz) == 764, "identical array lengths" );

ok( $p->record_count('spectrum') == 35, "correct spectrum count" );
ok( $p->curr_index('spectrum') == 2, "correct index" );
my $idx = $p->get_index_by_id( 'spectrum' =>
    'controllerType=0 controllerNumber=1 scan=10014' );
ok( $idx == 13, "get_index_by_id()" );
$p->goto('spectrum' => $idx);
ok( $p->curr_index('spectrum') == 13, "goto()" );
ok( $s = $p->next_spectrum, "read second record" );
$int = $s->int;
$mz  = $s->mz;
ok( are_equal($mz->[4], 300.0572, 3), "mz()" );
ok( are_equal($int->[6], 3538.943, 3),  "int()" );
ok( $s->ms_level == 1, "ms_level()" );
my $last_id;
while ($s = $p->next_spectrum) {
    # do nothing - just want to check that end is reached
    $last_id = $s->id;
}
ok( $last_id eq 'controllerType=0 controllerNumber=1 scan=10035', "id()" );
my $idx = $p->find_by_time(5074.6);
ok( $idx == 29, "find_by_time()" );

done_testing();

sub are_equal {

    my ($v1, $v2, $dp) = @_;
    return sprintf("%.${dp}f", $v1) eq sprintf("%.${dp}f", $v2);

}
