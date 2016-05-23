#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use MS::CV qw/:MS :MI :MOD is_a regex_for units_for/;

require_ok ("MS::CV");

ok( my $a = is_a( MS_EXPECT_VALUE,
    MS_SPECTRUM_IDENTIFICATION_RESULT_DETAILS), "is_a() 1" );
ok( $a, "parent-child true" );
ok( defined (my $b = is_a( MS_EXPECT_VALUE, MS_MS_LEVEL )), "is_a() 2" );
ok( ! $b, "parent-child false" );

ok( my $tryp_re = regex_for(MS_TRYPSIN), "regex_for()" );

my $pep = 'PEPTIDERPEPTIDEKRAPPLE';
my @parts = split $tryp_re, $pep;
ok( scalar(@parts) == 3, "tryptic digest 1" );
ok( $parts[2] eq 'APPLE', "tryptic digest 2" );

done_testing();
