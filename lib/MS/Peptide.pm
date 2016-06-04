package MS::Peptide;

use strict;
use warnings;

use overload
    '""' => \&as_string,
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

    my ($class, $seq, %args) = @_;

    $seq = uc $seq;
    my $self = bless {seq => $seq} => $class;

    my @atoms = map {atoms('aa', $_)} (split '', $seq);

    $self->{atoms}  = \@atoms;
    $self->{length} = CORE::length $seq;
    $self->{n_mod}  = 0;
    $self->{c_mod}  = 0;

    # these can be undefined if not known or specified
    $self->{prev}  = $args{prev};
    $self->{next}  = $args{next};
    $self->{start} = $args{start};
    $self->{end}   = $args{end};

    return $self;

}

#----------------------------------------------------------------------------#
# accessors
#----------------------------------------------------------------------------#

sub length { return $_[0]->{length} }
sub seq    { return $_[0]->{seq} }

#----------------------------------------------------------------------------#
# accessors/modifiers
#----------------------------------------------------------------------------#

sub prev {

    my ($self, $new_val) = @_;
    $self->{prev} = $new_val if (defined $new_val);
    return $self->{prev};

}

sub next {

    my ($self, $new_val) = @_;
    $self->{next} = $new_val if (defined $new_val);
    return $self->{next};

}

sub start {

    my ($self,$new_val) = @_;
    $self->{start} = $new_val if (defined $new_val);
    return $self->{start};

}

sub end {

    my ($self,$new_val) = @_;
    $self->{end} = $new_val if (defined $new_val);
    return $self->{end};

}

#----------------------------------------------------------------------------#

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
            if ( $i < 1 && $i > $self->{length});

        for my $a (@atoms) {
            my $heavy = $heavy{$a} or croak "No heavy atom defined for $a\n";
            $self->{atoms}->[$i-1]->{$heavy}
                = delete $self->{atoms}->[$i-1]->{$a};
        }
    }

    return;

}

sub mz {

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


sub as_string {

    my ($self, %args) = @_;

    my $mode = $args{mode} // 'case';
    my $str;

    #------------------------------------------------------------------------#

    if ($mode eq 'original') {

        $str = $self->{seq};

    }

    #------------------------------------------------------------------------#

    elsif ($mode eq 'case') {

        my @aa = split '', $self->{seq};
        $str = join '', map {
            $self->has_mod($_+1) ? lc($aa[$_]) : $aa[$_]
        } 0..$#aa;

    }

    #------------------------------------------------------------------------#

    elsif ($mode eq 'deltas') {

        my @aa = split '', $self->{seq};
        my @mods = $self->mod_array;

        # move terminal mods to residues
        my $n_mod = shift @mods;
        my $c_mod = pop   @mods;
        $mods[0]  += $n_mod;
        $mods[-1] += $c_mod;

        for my $i (0..$#aa) {
            $str .= $aa[$i];
            my $delta = sprintf('%.0f', $mods[$i]);
            $str .= "[$delta]" if ($delta != 0);
        }

    }

    #------------------------------------------------------------------------#

    if ($args{adjacent}) {
        croak "Can't form string - adjacent residues not defined"
            if (! defined $self->{prev} || ! defined $self->{next});
        $str  =  "$self->{prev}.$str.$self->{next}";
    }

    return $str;

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
    push    @delta, $self->{n_mod};
    unshift @delta, $self->{c_mod};
    return  @delta;

}

sub round {
    
    my ($val, $places) = @_;
    return int($val*10**$places+0.5)/10**$places;

}

    

1;
