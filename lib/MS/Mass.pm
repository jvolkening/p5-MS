package MS::Mass;

use strict;
use warnings;

use Storable;
use File::ShareDir qw/dist_file/;
use Exporter qw/import/;

our @EXPORT_OK = qw/
    aa_mass
    mod_mass
    elem_mass
    brick_mass
    formula_mass
    elem_count
/;

our %EXPORT_TAGS = (

    all => [ qw/
        aa_mass
        mod_mass
        elem_mass
        brick_mass
        formula_mass
        elem_count
    / ],
); 
        

my $fn_unimod = dist_file('MS' => 'unimod.stor');
our $masses = retrieve $fn_unimod
    or die "failed to read masses from storage";


sub aa_mass {
    my ($aa, $type) = @_;
    $type = $type // 'mono';
    return $masses->{aa}->{$aa}->{$type};
}

sub mod_mass {
    my ($mod, $type) = @_;
    $type = $type // 'mono';
    return $masses->{mod}->{$mod}->{$type};
}

sub elem_mass {
    my ($elem, $type) = @_;
    $type = $type // 'mono';
    return $masses->{elem}->{$elem}->{$type};
}

sub brick_mass {
    my ($brick, $type) = @_;
    $type = $type // 'mono';
    return $masses->{brick}->{$brick}->{$type};
}


sub formula_mass {

    my ($formula,$type) = @_;
    $type = $type // 'mono';

    die "unsupported characters in formula"
        if ($formula =~ /[^0-9A-Za-z]/);

    my $mass;
    while ($formula =~ /([A-Z][a-z]?)(\d*)/g) {
        my $single_mass = elem_mass($1,$type);
        my $multiplier = $2 || 1;
        die "mass not found for $1" if (! defined $single_mass);
        $mass += $single_mass * $multiplier;
    }

    return $mass;

}

sub elem_count {

    my ($type,$name,$elem) = @_;
    return $masses->{$type}->{$name}->{atoms}->{$elem};

}

1;
