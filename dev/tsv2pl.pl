#!/usr/bin/perl

use strict;
use warnings;

use List::Util qw/max/;

my %cv;
my @constants;
while (my $line = <STDIN>) {
    chomp $line;
    my ($id,$constant) = split "\t", $line;
    $cv{$constant} = $id;
    push @constants, $constant;
}

for (@constants) {
    print "$_\n";
}
my $field_len = max map {length $_} @constants;
print "\n";
for (@constants) {
    printf "use constant %-${field_len}s => '%s';\n", $_, $cv{$_};
}
