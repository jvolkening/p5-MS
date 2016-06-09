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

    my $fmt = $args{fmt} // 'case';
    my $str;

    #------------------------------------------------------------------------#

    if ($fmt eq 'original') {

        $str = $self->{seq};

    }

    #------------------------------------------------------------------------#

    elsif ($fmt eq 'case') {

        my @aa = split '', $self->{seq};
        $str = join '', map {
            $self->has_mod($_+1) ? lc($aa[$_]) : $aa[$_]
        } 0..$#aa;

    }

    #------------------------------------------------------------------------#

    elsif ($fmt eq 'deltas') {

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


1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MS::Peptide - A class representing peptide species for proteomic analysis

=head1 SYNOPSIS

    use MS::Peptide;

    my $pep = MS::Peptide->new('AAPLSYAMK');

    $pep->add_mod( 5 => 21 );        # phosphorylate S5
    my $mz = $pep->mz( charge => 2); # [MH2]2+


=head1 DESCRIPTION

C<MS::Peptide> is a class representing peptide species for use in proteomics
analysis. It provides methods for building specific isoforms and querying
common information.

=head1 METHODS

=head2 new

    my $pep = MS::Peptide->new(
        'AAPLSYAMK',
        prev  => 'K',
        next  => 'L',
        start =>  23,
        end   =>  31,
    );

Takes an amino acid sequence (required) and optional argument hash and returns
an C<MS::Peptide> object. Available options include:

=over

=item * prev — the previous residue in protein context, or an empty string if
at the protein N-terminus. Should be left undefined if not known.

=item * next — the next residue in protein context, or an empty string if
at the protein C-terminus. Should be left undefined if not known.

=item * start — the 1-based start position within the protein context. Should
be left undefined if not known.

=item * end — the 1-based end position within the protein context. Should
be left undefined if not known.

=back

=head2 seq

    my $seq = $pep->seq;

Returns the original sequence string used during initialization, preserving
case. This attribute cannot be changed after initialization.

=head2 length

    my $len = $pep->length;

Returns the length of the peptide in residues.

=head2 prev

=head2 next

=head2 start

=head2 end

    $pep->prev( 'K' );
    $pep->next( 'L' );
    $pep->start( 23 );
    $pep->end(   31 );

If an argument is provided, sets the relevant attribute to that value. Returns
the current value.

=head2 copy

    my $pep2 = $pep->copy;

Makes a deep copy of the object, usually to change the modification state.

=head2 make_heavy

    $pep->make_heavy( 3 => [qw/C N O/] );

Takes two required arguments (residue position(s) and element(s) to apply) and
replaces the relevant atoms on those residue(s) with stable heavy isotopes.
Both arguments can be either single scalar values or array references - the
change will be applied to the matrix of the arguments.

=head2 mz

    $pep->mz(%args);

Returns the m/z value of the current peptide state based on parameters
provided. Possible parameters include:

=over

=item * type — 'mono' (default) or 'average'

=item * charge — charge state to use (default: 1)

=back

=head2 as_string

    say $pep->as_string( fmt => 'original' ); # 'AAPLSYAMK'
    say $pep->as_string( fmt => 'case'     ); # 'AAPLsYAMK'
    say $pep->as_string( fmt => 'deltas'   ); # 'AAPLS[80]YAMK'

    say $pep->as_string( fmt => 'case',       # 'K.AAPLsYAMK.L'
        adjacent => 1 );

Returns a stringification of the peptide sequence in a format based on the
parameters specified. Possible arguments include:
provided. Possible parameters include:

=over

=item * fmt — format of string

=over

=item * original — as originally provided (typically all upper-case)

=item * case — modified residues as lower-case (default)

=item * deltas — delta masses in brackets

=back

=item * adjacent — include adjacent residues (will throw exception if adjacent
residues are not defined)

=back

=head2 OTHER

Other methods are available but not yet documented (to be completed shortly).

=head1 CAVEATS AND BUGS

The API is in alpha stage and is not guaranteed to be stable.

Please reports bugs or feature requests through the issue tracker at
L<https://github.com/jvolkening/p5-MS/issues>.

=head1 SEE ALSO

=over 4

=item * L<InSilicoSpectro>

=back

=head1 AUTHOR

Jeremy Volkening <jdv@base2bio.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2015-2016 Jeremy Volkening

This program is free software: you can redistribute it and/or modify it under
the terms of the GNU General Public License as published by the Free Software
Foundation, either version 3 of the License, or (at your option) any later
version.

This program is distributed in the hope that it will be useful, but WITHOUT
ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
details.

You should have received a copy of the GNU General Public License along with
this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
