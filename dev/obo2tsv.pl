#!/usr/bin/perl

use strict;
use warnings;

my $curr_id;
my $term_flag = 0;
while (<STDIN>) {
    chomp;
    if (/^\[([^\]]+)\]/) {
        $term_flag = $1 eq 'Term' ? 1 : 0;
        next;
    }
    next if (! $term_flag);
    if (/^id: (\S+)/) {
        $curr_id = $1;
    }
    elsif (/^name: (.+)/) {
        print "$curr_id\t$1\n";
        $curr_id = undef;
    }
}
    
