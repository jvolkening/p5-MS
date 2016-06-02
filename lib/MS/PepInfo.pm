package MS::PepInfo;

use strict;
use warnings;

use List::Util qw/sum/;
use List::MoreUtils qw/uniq/;
use Exporter qw/import/;
use MS::Mass qw/:all/;


our @EXPORT_OK = qw/calc_mw calc_gravy calc_aliphatic calc_fragments digest/;

my %ave_mass = (
    A => 71.0788,
    R => 156.1875,
    N => 114.1038,
    D => 115.0886,
    C => 103.1388,
    Q => 128.1307,
    E => 129.1155,
    G => 57.0519,
    H => 137.1411,
    I => 113.1594,
    L => 113.1594,
    K => 128.1741,
    M => 131.1926,
    F => 147.1766,
    P => 97.1167,
    S => 87.0782,
    T => 101.1051,
    W => 186.2132,
    Y => 163.1760,
    V => 99.1326,
    H2O => 18.01524,
);

my %kyte_doolittle = (
    A =>  1.8,
    R => -4.5,
    N => -3.5,
    D => -3.5,
    C =>  2.5,
    Q => -3.5,
    E => -3.5,
    G => -0.4,
    H => -3.2,
    I =>  4.5,
    L =>  3.8,
    K => -3.9,
    M =>  1.9,
    F =>  2.8,
    P => -1.6,
    S => -0.8,
    T => -0.7,
    W => -0.9,
    Y => -1.3,
    V =>  4.2,
);

sub digest {

    my ($seq, $enzymes, $missed) = @_;

    $enzymes = [$enzymes] if (! ref $enzymes);

    $missed = $missed // 0;

    my %re = (
        'trypsin' => qr/[KR](?!P)/,
        'Asp-N'   => qr/(?=[NC])/,
        'Glu-C'   => qr/[QN]/,
        'Lys-C'   => qr/K/,
        'Arg-C'   => qr/R/,
    );

    my @cut_sites = (0);

    for (@{$enzymes}) {
        die "Unsupported enzyme specified\n"
            if (! defined $re{$_});
        while ($seq =~ /$re{$_}/ig) {
            push @cut_sites, $+[0];
        }
    }

    push @cut_sites, length($seq);
    @cut_sites = sort {$a <=> $b} uniq @cut_sites;

    my @pieces;
    for my $i (0..$#cut_sites) {
        A:
        for my $a (1..$missed+1) {
            $a = $i + $a;
            last A if ($a > $#cut_sites);
            push @pieces, substr($seq,$cut_sites[$i],$cut_sites[$a]-$cut_sites[$i]);
        }
    }

    return @pieces;

}

sub calc_gravy {

    return sum( map {$kyte_doolittle{$_}} split( '', $_[0]) )/length($_[0]);

}

sub calc_aliphatic {

    my @aa = split '', $_[0];
    my $mf_A  = grep {$_ eq 'A'} @aa;
    my $mf_V  = grep {$_ eq 'V'} @aa;
    my $mf_IL = grep {$_ =~ /[IL]/} @aa;
    return ($mf_A + 2.9*$mf_V + 3.9*$mf_IL) * 100 / scalar(@aa);

}

sub calc_mw {

    return sum map {$ave_mass{$_}} (split('',$_[0]),'H2O');

}

sub calc_fragments {

    my ($peptide,$mod_ref,$max_charge,$incl_nloss) = @_;

    my $PROTON = elem_mass('H');
    $max_charge = $max_charge // 1;
    my @masses = map {aa_mass($_)} split('',$peptide);
    unshift @masses, 0;
    push @masses, formula_mass('HOH');
    for (0..$#{$mod_ref}) {
        my $mod = $mod_ref->[$_];
        if (defined $mod) {
            if ($mod =~ /^[\d\-\.e]+$/) { # is a float, use directly
                $masses[$_] += $mod;
            }
            else {
                my $mass = mod_mass($mod);
                die "Mass for $mod not found" if (! defined $mass);
                $masses[$_] += $mass;
            }
        }
    }

    my @pre_groups = ([@masses]);
    my @cuts = ();
    
    # calculate neutral loss peptides if peptide is not non-mobile

    my $R_count = $peptide =~ tr/R/R/;
    if ($incl_nloss && $R_count < $max_charge) {
        while ($peptide =~ /P/g) {
            push @cuts, $-[0] if (
                 $-[0] > 0
              && $-[0] < 6
              && $-[0] < $#masses-1);
        }
        pos($peptide) = 0;

        while ($peptide =~ /H/g) {
            push @cuts, $-[0] if (
                 $-[0] > 1
              && $-[0] < 4
              && $-[0] < $#masses-1);
        }
        pos($peptide) = 0;

        while ($peptide =~ /D/g) {
            push @cuts, $-[0]+1 if (
                 $-[0] < 6
              && $-[0] < $#masses-2);
        }
        pos($peptide) = 0;

        @cuts = uniq @cuts;
        for (@cuts) {
            my @sub = @masses[$_+1..$#masses];

            # put on front so more common frags will overwrite
            unshift @pre_groups, [@sub];
        }
    }

    my @series = ();
    for my $g (0..$#pre_groups) {
        my @m = @{$pre_groups[$g]};
        my $tag = '';
        if ($g > 0) {
            my $lost = scalar(@masses) - scalar(@m) - 1;
            $tag = "-$lost<sub>N</sub>";
        }

        #calculate [M]
        my $pre_mz = (sum(@m) + $max_charge*$PROTON)/$max_charge;

        push @series, [$pre_mz, '[M]', '', $max_charge, $tag];
        for (1..$max_charge) {
            #push @series, _series('a', $peptide, \@m, 1);
            push @series, _series('b', $peptide, \@m, $_, $tag);
            push @series, _series('y', $peptide, \@m, $_, $tag)
                if ($g == 0);
        }
    }

    @series = sort {$a->[0] <=> $b->[0]} @series;
    @series = grep {$_->[0] > 100} @series;
    return @series;

}

sub _series {

    my ($type, $peptide, $mass_ref, $charge, $tag) = @_;

    my $PROTON = elem_mass('H');
    my @masses = @{$mass_ref};
    my @series;

    my $term = $type =~ /^[y]$/ ? 'C' : 'N';

    # calculate standard series
    for my $i ($charge..$#masses-2) {

        my ($start,$end)
            = $term eq 'N' ? (0, $i) : ($#masses-$i, $#masses);
        my $adjust 
            = $type eq 'a' ? - formula_mass('CO')
            : 0;

        my $mz = (sum(@masses[$start..$end]) + $adjust
                + $PROTON*$charge)/$charge;

        push @series, [$mz,$type,$i,$charge, $tag];

    }

    # neutral ammonia loss
    while ($peptide =~ /[RKQN]/g) {
        my $i = $-[0]+1;
        $i = $#masses - $i if ($term eq 'C');
        next if ($i < $charge);
        next if ($i >= $#masses -1);
        my ($start,$end)
            = $term eq 'N' ? (0, $i) : ($#masses-$i, $#masses);
        my $adjust 
            = $type eq 'a' ? - formula_mass('CO')
            : 0;
        my $mz = (sum(@masses[$start..$end]) + $adjust - formula_mass('NH3')
            + $PROTON*$charge)/$charge;
        push @series, [$mz,$type,$i,$charge,"-NH3$tag"];

    }
    pos($peptide) = 0;

    # neutral water loss
    if ($type ne 'a') {
        while ($peptide =~ /[STED]/g) {
            my $i = $-[0]+1;
            $i = $#masses - $i if ($term eq 'C');
            next if ($i < $charge);
            next if ($i >= $#masses -1);
            my ($start,$end)
                = $term eq 'N' ? (0, $i) : ($#masses-$i, $#masses);
            my $adjust 
                = $type eq 'a' ? - formula_mass('CO')
                : 0;
            my $mz = (sum(@masses[$start..$end]) + $adjust - formula_mass('H2O')
                + $PROTON*$charge)/$charge + $adjust;
            push @series, [$mz,$type,$i,$charge,"-H2O$tag"];

        }
    }
    return @series;
        

}

        

        
1;
