#!/usr/bin/env perl

use strict;
use warnings;
use 5.012;

use File::Find;
use File::Temp;
use File::Copy qw/copy/;

my $version = $ARGV[0];

find(\&wanted, '.');

sub wanted {

    if ($_ !~ /\.pm$/) {
        return;
    }

    my $class = $File::Find::name;
    $class =~ s/^\.\///;
    $class =~ s/\.pm$//;
    $class =~ s/\//::/g;
    say $class;

    my $tmp = File::Temp->new;

    open my $in, '<', $_;

    my $line = <$in>;
    chomp $line;

    if ($line =~ /^(package $class)/) {
        say {$tmp} "$1 $version;";
    }
    else {
        say {$tmp} $line;
    }
    while (my $line = <$in>) {
        print {$tmp} $line;
    }
    close $in;
    close $tmp;
    copy "$tmp", $_;
        

}

