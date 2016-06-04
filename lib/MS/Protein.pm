package MS::Protein;

use strict;
use warnings;

use overload
    '""' => \&seq,
    fallback => 1;

use Carp;
use Exporter qw/import/;
use List::Util qw/any sum/;
use List::MoreUtils qw/uniq/;
use Scalar::Util qw/blessed/;

use MS::Mass qw/:all/;
use MS::CV   qw/:MS regex_for/;
use MS::Peptide;

BEGIN {

    *ec = \&extinction_coefficient; 
    *pI = \&isoelectric_point; 
    *ai = \&aliphatic_index; 
    *mw = \&molecular_weight; 

}

our @EXPORT_OK = qw/
    digest
    isoelectric_point
    pI
    molecular_weight
    mw
    gravy
    aliphatic_index
    ai
    n_residues
    n_atoms
    extinction_coefficient
    ec
    charge_at_pH
/;

our %EXPORT_TAGS = (
    all => \@EXPORT_OK,
);

# build lookup tables
my $kyte_doolittle = _kyte_doolittle();
my $pK  = _pK();
my $pKt = _pKt();

sub new {

    my ($class, $seq) = @_;

    $seq = uc $seq;
    my $self = bless {seq => $seq} => $class;

    $self->{length} = length $seq;

    return $self;

}

sub seq { return $_[0]->{seq} }

sub molecular_weight {

    my ($seq, $type) = @_;
    return sum( map {aa_mass($_, $type) // return undef}
        split('', $seq) ) + formula_mass('H2O');

}

sub n_atoms {

    my ($seq) = @_;
    my %counts;
    ++$counts{$_} for (split '', $seq);
    my %atoms = (H => 2, O => 1);
    for my $aa (keys %counts) {
        my $a = atoms('aa' => $aa);
        $atoms{$_} += $a->{$_}*$counts{$aa} for (keys %$a);
    }
    return \%atoms; 

}

sub n_residues {

    my ($seq) = @_;
    my %counts;
    ++$counts{$_} for (split '', $seq);
    return \%counts;

}

sub aliphatic_index {

    my ($seq) = @_;

    $seq = "$seq";
    my $mf_A   = $seq =~ tr/A//;
    my $mf_V   = $seq =~ tr/V//;
    my $mf_IL  = $seq =~ tr/IL//;

    return ($mf_A + 2.9*$mf_V + 3.9*$mf_IL) * 100 / length($seq);

}

sub extinction_coefficient {

    my ($seq, %args) = @_;

    my $is_reduced = $args{reduced};

    $seq = "$seq";
    my $Y = $seq =~ tr/Y//;
    my $W = $seq =~ tr/W//;
    my $C = $seq =~ tr/C//;

    return $is_reduced
        ? 1490*$Y + 5500*$W
        : 1490*$Y + 5500*$W + 125*int($C/2);

}

sub gravy {

    my ($seq) = @_;
    return sum( map {$kyte_doolittle->{$_}} split( '', $seq) )
        / length($seq);

}

sub digest {

    my ($arg1, %args) = @_;

    # can be used as function or method, so test whether first argument is
    # MS::Protein object (otherwise should be simple string)
    my $as_method = ref($arg1) && blessed($arg1) && $arg1->isa('MS::Protein');

    my $seq     = $as_method ? $arg1->seq : $arg1;
    my $enzymes = $args{enzymes} // croak "enzyme must be specified";
    my $missed  = $args{missed}  // 0;

    my @re = map {regex_for($_)} @$enzymes;
    croak "one or more enzyme CVs are not valid" if (any {! defined $_} @re);

    my @cut_sites = (0);

    for (@re) {
        while ($seq =~ /$_/ig) {
            push @cut_sites, $-[0];
        }
    }

    my $seq_len = length $seq;
    push @cut_sites, $seq_len;
    @cut_sites = sort {$a <=> $b} uniq @cut_sites;

    my @peptides;
    for my $i (0..$#cut_sites) {
        A:
        for my $a (1..$missed+1) {
            $a = $i + $a;
            last A if ($a > $#cut_sites);
            my $str = substr $seq, $cut_sites[$i],
                $cut_sites[$a]-$cut_sites[$i];
            if ($as_method) {

                # return MS::Peptide objects
                my $prev = $cut_sites[$i] == 0 ? ''
                    : substr $seq, $cut_sites[$i]-1, 1;
                my $next = $cut_sites[$a] == $seq_len-1 ? ''
                    : substr $seq, $cut_sites[$a], 1;
                push @peptides, MS::Peptide->new($str,
                    prev => $prev,
                    next => $next,
                    start => $cut_sites[$i]+1,
                    end   => $cut_sites[$a],
                );
                
            }
            else {

                #return simple strings
                push @peptides, $str;

            }
        }
    }
    
    return @peptides

}

sub isoelectric_point {

    my ($seq) = @_;
    $seq = "$seq"; # convert object to string if needed

    # the ProMoST webserver counts charged terminal residues twice
    # (maybe a bug). Swap comments to emulate this behavior.
    #my $nt  = substr $seq, 0,  1;
    #my $ct  = substr $seq, -1, 1;
    my $nt  = substr $seq, 0,  1, '';
    my $ct  = substr $seq, -1, 1, '';
    my $res = n_res($seq);

    my $z        = 1;
    my $pH       = 7;
    my $cut      = 0.002;
    my $upper    = 14;
    my $lower    = 0;
    my $max_iter = 100;

    for (1..$max_iter) {
        $z     = _charge_at_pH( $nt, $ct, $res, $pH );
        $upper = $z < 0 ? $pH    : $upper;
        $lower = $z < 0 ? $lower : $pH;
        $pH    = ($upper+$lower)/2;
        last if (abs($z) <= $cut);
    }
    return undef if (abs($z) > $cut); # failed to converge
    return $pH;

}

sub charge_at_pH {

    my ($seq, $pH) = @_;
    $seq = "$seq";

    # the ProMoST webserver counts charged terminal residues twice
    # (maybe a bug). Swap comments to emulate this behavior.
    #my $nt  = substr $seq, 0,  1;
    #my $ct  = substr $seq, -1, 1;
    my $nt  = substr $seq, 0,  1, '';
    my $ct  = substr $seq, -1, 1, '';
    my $res = n_res($seq);

    return _charge_at_pH( $nt, $ct, $res, $pH );

}
        

sub _charge_at_pH {

    my ($nt, $ct, $other, $pH) = @_;

    my @p = map { ($pK->{$_}->[0]) x ($other->{$_} // 0) } qw/K R H  /;
    my @n = map { ($pK->{$_}->[0]) x ($other->{$_} // 0) } qw/D E C Y/;

    # terminal charges
    push @p, $pKt->{$nt}->[0];
    push @n, defined $ct ? $pKt->{$ct}->[1] : $pKt->{$nt}->[1];

    push @p, $pK->{$nt}->[1] if (any {$nt eq $_} qw/K R H  /); # N-term res
    push @p, $pK->{$ct}->[2] if (any {$ct eq $_} qw/K R H  /); # C-term res
    push @n, $pK->{$nt}->[1] if (any {$nt eq $_} qw/D E C Y/); # N-term res
    push @n, $pK->{$ct}->[2] if (any {$ct eq $_} qw/D E C Y/); # C-term res

    my $Ct = 0;
    $Ct += sum map { 1/(1 + 10**($pH-$_))} @p if (scalar @p);
    $Ct += sum map {-1/(1 + 10**($_-$pH))} @n if (scalar @n);

    return $Ct;

}

sub _kyte_doolittle {

    return {
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
        X =>  0.0,
    };

}

sub _pK {

    return {   #  in  Nterm  Cterm
        K => [  9.80, 10.00, 10.30 ],
        R => [ 12.50, 11.50, 11.50 ],
        H => [  6.08,  4.89,  6.89 ],
        D => [  4.07,  3.57,  4.57 ],
        E => [  4.45,  4.15,  4.75 ],
        C => [  8.28,  8.00,  9.00 ],
        Y => [  9.84,  9.34, 10.34 ],
    };

}

sub _pKt {

    return {    # N     C
        G => [ 7.50, 3.70 ],
        A => [ 7.58, 3.75 ],
        S => [ 6.86, 3.61 ],
        P => [ 8.36, 3.40 ],
        V => [ 7.44, 3.69 ],
        T => [ 7.02, 3.57 ],
        C => [ 8.12, 3.10 ],
        I => [ 7.48, 3.72 ],
        L => [ 7.46, 3.73 ],
        N => [ 7.22, 3.64 ],
        D => [ 7.70, 3.50 ],
        Q => [ 6.73, 3.57 ],
        K => [ 6.67, 3.40 ],
        E => [ 7.19, 3.50 ],
        M => [ 6.98, 3.68 ],
        H => [ 7.18, 3.17 ],
        F => [ 6.96, 3.98 ],
        R => [ 6.76, 3.41 ],
        Y => [ 6.83, 3.60 ],
        W => [ 7.11, 3.78 ],
    };

}

1;
