#!/usr/bin/perl

use strict;
use warnings;

use XML::Twig;
use Storable;

my $twig = XML::Twig->new(
    twig_roots => {
        'umod:elem'  => \&store_simple,
        'umod:mod'   => \&store_mod,
        'umod:aa'    => \&store_simple,
        'umod:brick' => \&store_simple,
    },
);

my $masses = {};

$twig->parsefile($ARGV[0]);

store $masses => 'unimod.stor';

exit;

sub store_simple {

    my ($twig, $elt) = @_;

    my $tag   = $elt->tag;
    $tag =~ s/^umod://;
    my $mono  = $elt->att('mono_mass');
    my $avg   = $elt->att('avge_mass');
    my $title = $elt->att('title');
    die "missing meta for elt"
        if (! defined $title || ! defined $mono || !  defined $avg);
    $masses->{$tag}->{ $title }->{mono} = $mono;
    $masses->{$tag}->{ $title }->{avg}  = $avg;

    for ($elt->children('umod:element')) {
        $masses->{$tag}->{$title}->{atoms}->{ $_->att('symbol') }
            = $_->att('number');
    }

    $twig->purge;

}

sub store_mod {
    
    my ($twig, $elt) = @_;

    my $tag   = $elt->tag;
    $tag =~ s/^umod://;
    my $title = $elt->att('title');
    my $delta = $elt->first_child('umod:delta')
        or die "failed to find delta elt";
    my $mono  = $delta->att('mono_mass');
    my $avg   = $delta->att('avge_mass');
    die "missing meta for mod"
        if (! defined $title || ! defined $mono || !  defined $avg);
    $masses->{$tag}->{ $title }->{mono} = $mono;
    $masses->{$tag}->{ $title }->{avg} = $avg;

    $twig->purge;

}
