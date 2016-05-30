package MS::Peptide;

use strict;
use warnings;

use overload
    '""' => \&_stringify,
    fallback => 1;

use Carp;
use Storable qw/dclone/;
use List::Util qw/sum/;

use MS::Mass qw/:all/;

my %light = (
    '2H' => 'H',
    '13C' => 'C',
    '15N' => 'N',
    '18O' => 'O',
);

my %heavy = (
    'H' => '2H',
    'C' => '13C',
    'N' => '15N',
    'O' => '18O',
);


sub new {

    my ($class, $seq) = @_;

    $seq = uc $seq;
    my $self = bless {seq => $seq} => $class;

    my @atoms = map {atoms('aa', $_)} (split '', $seq);

    $self->{atoms}  = \@atoms;
    $self->{length} = length $seq;

    return $self;

}

sub copy {

    return dclone($_[0]);

}

sub make_heavy {

    my ($self, $loc, $atom) = @_;

    # $loc and $atom can be scalar or arrayref
    my @locs  = ref($loc)  ? @$loc  : ($loc);
    my @atoms = ref($atom) ? @$atom : ($atom);

    for my $i (@locs) { # 1-based residue

        croak "Residue index out of range\n"
            if ( $i < 1 && $i > length($self->{seq}) );

        for my $a (@atoms) {
            my $heavy = $heavy{$a} or croak "No heavy atom defined for $a\n";
            $self->{atoms}->[$i-1]->{$heavy}
                = delete $self->{atoms}->[$i-1]->{$a};
        }
    }

    return;

}

sub mass {

    my ($self, %args) = @_;

    my $type = $args{type} // 'mono';
    my $z    = $args{charge} // 1;

    my $M = formula_mass('H2O', $type)
        + sum map {atoms_mass($_, $type)} @{ $self->{atoms} };

    return ($M + $z * elem_mass('H', $type))/$z;

}

sub add_mod {

    my ($self, $loc, $mod) = @_;

    # $loc and $atom can be scalar or arrayref
    my @locs  = ref($loc)  ? @$loc  : ($loc);
    my $atoms = atoms('mod' => $mod);

    for my $i (@locs) { # 1-based residue

        croak "Residue index out of range\n"
            if ( $i < 1 && $i > $self->{length});

        for my $a (keys %$atoms) {
            
            my $delta = $atoms->{$a};

            # removal of heavy atoms is a special case 
            if ($delta < 0 && exists $self->{atoms}->[$i-1]->{ $heavy{$a} }) {
                $a = $heavy{$a};
            }

            $self->{atoms}->[$i-1]->{$a} += $delta;

        }

        ++$self->{mods}->[$i-1]->{$mod};
                
    }

    return;

}

sub get_mods {

    my ($self, $loc) = @_;

    croak "Residue index out of range\n"
        if ( $loc < 1 && $loc > $self->{length});

    return () if ! defined $self->{mods}->[$loc-1];
    return keys %{ $self->{mods}->[$loc-1] };

}

sub has_mod {

    my ($self, $loc, $mod) = @_;

    my @locs  = ref($loc)    ? @$loc
              : defined $loc ? ($loc)
              : (1..$self->{length});

    my @mods  = ref($mod) ? @$mod : ($mod);
    
    my $ret_val = 0;

    for my $i (@locs) {

        croak "Residue index out of range\n"
            if ( $i < 1 && $i > $self->{length});

        for my $m (@mods) {

            if (! defined $m) {
                $ret_val += defined $self->{mods}->[$i-1];
            }
            else {
                $ret_val += defined $self->{mods}->[$i-1]->{$m};
            }

        }

    }

    return $ret_val;

}

sub length { return $_[0]->{length} }
sub seq    { return $_[0]->{seq} }

sub _stringify {

    my ($self) = @_;

    my @aa = split '', $self->{seq};
    return join '', map {
        $self->has_mod($_+1) ? lc($aa[$_]) : $aa[$_]
    } 0..$#aa;

}

sub mod_array {

    my ($self, $type) = @_;

    my @aa = split '', $self->{seq};
    my @delta = (0) x $self->{length};
    for my $i (0..$#aa) {
        my $d = sprintf '%4f', atoms_mass($self->{atoms}->[$i], $type)
            - aa_mass($aa[$i], $type);
        $delta[$i] = $d == 0 ? 0 : $d;
    }
    return @delta;

}

sub mod_string {

    my ($self) = @_;

    my @aa = split '', $self->{seq};
    my @mods = $self->mod_array;
    my $str;
    for my $i (0..$#aa) {
        $str .= $aa[$i];
        my $delta = sprintf('%.0f', $mods[$i]);
        $str .= "[$delta]" if ($delta != 0);
    }
    return $str;

}

sub round {
    
    my ($val, $places) = @_;
    return int($val*10**$places+0.5)/10**$places;

}

    

1;
