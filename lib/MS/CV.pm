package MS::CV;

use strict;
use warnings;

use Exporter qw/import/;
use File::ShareDir qw/dist_file/;
use List::Util qw/any/;

my $terms = {};
my @roots = ();
our @EXPORT_OK;

BEGIN {

    # read in ontology file
    my $fn_obo = dist_file('MS' => 'psi-ms.obo');
    open my $in, '<', $fn_obo or die "Failed to open OBO file for reading";

    my $is_term = 0;
    my $curr_term;
    my %seen;

    no strict 'refs';

    LINE:
    while (my $line = <$in>) {

        chomp $line;
        next if ($line !~ /\S/);

        if ($line =~ /^\[([^\]]+)\]/) {
            $is_term = $1 eq 'Term';

            next LINE if (! defined $curr_term->{id});
            my $id = $curr_term->{id};
            delete $curr_term->{id};

            my $tmp_term = $curr_term;
            $curr_term = {};

            next LINE if ($tmp_term->{is_obsolete});

            if (defined $tmp_term->{is_a}) {
                for my $parent (@{ $tmp_term->{is_a}}) {
                    $MS::CV::terms->{$parent}->{children}->{$id} = 1;
                }
            }
            else {
                push @MS::CV::roots, $id;
            }

            my $const_name = $tmp_term->{name};

            if (defined $const_name) {

                $const_name =~ s/\W/_/g;
                $const_name =~ s/^(\d)/_$1/;
                $const_name = uc $const_name;

                my $i = 1;
                my $tmp = $const_name;
                while (defined $seen{$const_name}) {
                    $const_name = $tmp . '_' . $i++;
                }
                $seen{$const_name} = 1;

                *$const_name = sub () {$id};
                $tmp_term->{constant} = $const_name;

                push @EXPORT_OK, $const_name;

            }
            
            # copy values individually in case hash entry already exists
            $MS::CV::terms->{$id}->{$_} = $tmp_term->{$_}
                for (keys %{$tmp_term});

        }
        elsif ($is_term) {
            if ( $line =~ /^(\w+):\s*(.+)$/ ) {
                my $key = $1;
                next if (! any {$key eq $_} qw/id name def is_a is_obsolete/);
                my $val = $2;
                $val =~ s/\s*(?<!\\)\!.*$//; # remove comments
                if ($key eq 'is_a') {
                    push @{$curr_term->{$key}}, $val;
                }
                else {
                    $curr_term->{$key} = $val;
                }
            }
        }

    } 

    use strict 'refs';

    close $fn_obo;

} # end BEGIN

our %EXPORT_TAGS = (
    constants => [ @EXPORT_OK ],
);

sub is_a {

    my ($child, $parent) = @_;

    warn "testing $child v $parent\n";
    return undef if (! defined $MS::CV::terms->{$child});
    return 0 if (! defined $MS::CV::terms->{$child}->{is_a});

    my @parents = @{ $MS::CV::terms->{$child}->{is_a} };
    my $retval = 0;
    for (@parents) {
        return 1 if ($_ eq $parent);
        $retval += is_a( $_ => $parent );
    }
    return $retval;

}

sub print_tree {

    my ($level, @parents) = @_;

    $level = $level // 0;
    if (! @parents) {
        @parents = @MS::CV::roots;
    }

    for my $parent (@parents) {
        print "---" x $level . $parent,
        "\t" . $MS::CV::terms->{$parent}->{name},
        "\t" . $MS::CV::terms->{$parent}->{constant}, "\n";
        ++$level;
        if (defined $MS::CV::terms->{$parent}->{children}) {
            print_tree ($level, keys %{ $MS::CV::terms->{$parent}->{children}});
        }
        --$level;
    }
    return;

}

1;
