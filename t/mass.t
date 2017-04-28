#!/usr/bin/perl

use strict;
use warnings;

use Test::More;
use MS::Mass qw/:all/;

require_ok ("MS::Mass");

ok( db_version() eq '2.0', "db version" );

# test elem_mass()
ok( are_equal( elem_mass('Fe'           ), 55.935, 3), "elem_mass(mono)" );
ok( are_equal( elem_mass('Fe', 'average'), 55.845, 3), "elem_mass(avg)"  );

# test aa_mass()
ok( are_equal( aa_mass('G'           ), 57.021, 3), "elem_mass(mono)" );
ok( are_equal( aa_mass('G', 'average'), 57.051, 3), "elem_mass(avg)"  );

# test mod_mass()
my $id = mod_id_from_name('Phospho');
ok ($id eq 21, "mod_id_from_name");
ok( are_equal( mod_mass($id),             79.9663 , 3), "mod_mass(mono)" );
ok( are_equal( mod_mass($id, 'average'),  79.9799 , 3), "mod_mass(avg)"  );

# test brick_mass() 
ok( are_equal( brick_mass('Water'), 18.010565, 3), "brick_mass()" );

# test formula_mass()
ok( are_equal( formula_mass('H2O'), 18.010565, 3), "formula_mass()" );

# test atoms()
ok( my $atoms = atoms('brick' => 'Water'), "atoms()" );
ok( are_equal( atoms_mass($atoms), 18.010565, 3), "atoms_mass()" );




done_testing();

sub are_equal {

    my ($v1, $v2, $dp) = @_;
    return sprintf("%.${dp}f", $v1) eq sprintf("%.${dp}f", $v2);

}
