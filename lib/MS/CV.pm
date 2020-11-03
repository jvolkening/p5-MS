package MS::CV;

use strict;
use warnings;

use Carp;
use Exporter qw/import/;
use File::ShareDir qw/dist_file/;
use Storable;

my  $terms;
my  %exports;
my  %roots;
our %EXPORT_TAGS;
our @EXPORT_OK;

BEGIN {

    # read in ontology file
    my $fn_obo = dist_file('MS' => 'cv.stor');
    $terms = retrieve $fn_obo;

    # necessary for symbol table manipulation
    no strict 'refs';
    
    # generate constants and track root terms
    for my $id (keys %{$terms} ) {

        my $ref = $terms->{$id};
        my $const_name = $ref->{constant} ;
        next if (! defined $const_name);
        my $cv = $ref->{cv};
        die "name undefined for $id" if (! defined $const_name);

        # define constant
        *$const_name = sub () {$id};

        push @{ $exports{$cv} }, $const_name;
        push @MS::CV::EXPORT_OK, $const_name;
        push @{$roots{$cv} }, $id if (! exists $ref->{is_a});

    } 

    use strict 'refs';

    # update exportable constants and functions
    %MS::CV::EXPORT_TAGS = map {$_ => \@{ $exports{$_} }} keys %exports;
    push @MS::CV::EXPORT_OK, qw/is_a print_tree units_for regex_for cv_name/;

} # end BEGIN

sub cv_name {

    return $terms->{$_[0]}->{name};

}


sub is_a {
    
    my ($child, $parent) = @_;

    return undef if (! defined $terms->{$child});
    return 0 if (! defined $terms->{$child}->{is_a});

    my @parents = @{ $terms->{$child}->{is_a} };
    my $retval = 0;
    for (@parents) {
        return 1 if ($_ eq $parent);
        $retval += is_a( $_ => $parent );
    }
    return $retval ? 1 : 0;

}

sub units_for {

    my ($id) = @_;

    return undef if (! defined $terms->{$id}->{has_units});
    return [ @{ $terms->{$id}->{has_units} } ];

}

sub regex_for {

    my ($id) = @_;

    return undef if (! defined $terms->{$id}->{has_regexp});
    croak "Multiple regular expressions not supported for $id\n"
        if (defined $terms->{$id}->{has_regexp}->[1]);
    my $rid = $terms->{$id}->{has_regexp}->[0];
    return qr/$terms->{$rid}->{name}/;

}

sub print_tree {

    my ($cv, $level, @parents) = @_;

    croak "CV $cv not valid" if (! defined $roots{$cv});

    $level = $level // 0;
    if (! @parents) {
        @parents = @{ $roots{$cv} };
    }

    for my $parent (@parents) {
        next if (! defined $terms->{$parent}->{constant});
        print "---" x $level . $parent,
        "\t" . $terms->{$parent}->{name},
        "\t" . $terms->{$parent}->{constant}, "\n";
        ++$level;
        if (defined $terms->{$parent}->{children}) {
            print_tree ($cv, $level, keys %{ $terms->{$parent}->{children}});
        }
        --$level;
    }
    return;

}

1;


__END__

=head1 NAME

MS::CV - interface to HUPO PSI controlled vocabularies

=head1 SYNOPSIS

    use MS::CV qw/:MS :MOD :MI is_a regex_for units_for/;

    # use PSI terms directly as constants
    if ('MS:1000894' eq MS_RETENTION_TIME) {
        # do something
    }

    # check for child/parent relationships
    say "model param is valid!"
        if (is_a( MS_Q_TRAP, MS_INSTRUMENT_MODEL ));


    # PSI:MS conveniently provides cleavage regular expressions
    my $pep = 'PEPTIDERPEPTIDEKRAPPLE';
    my $re  = regex_for(MS_TRYPSIN);
    say $_ for split( $re, $pep );


=head1 DESCRIPTION

C<MS::CV> provides a simple interface to the HUPO PSI controlled vocabularies.
Currently the MS, MOD, and MI ontologies are indexed and available.

The module utilizes a functional interface for speed and simplicity. It's
primarily functionality is to export sets of constants (one for each ontology)
directly mapping the term names to ids.

=head1 CONSTANT NAMING

Constant names are autogenerated from the C<name> field of the ontology OBO
files. The rules for mapping are defined in the following code:

    my $symb = uc( $ontology . '_' . $term->{name} );
    $symb =~ s/\W/_/g;
    $symb =~ s/^(\d)/_$1/;

For example, the term "CRM spectrum" in the MS ontology becomes C<MS_CRM_SPECTRUM>.

In addition, very rarely there are namespace collisions between terms after
applying these transformations. In this case, increasing integer suffixes are
appended to each colliding term. As of this writing, this only occurs for the
following terms:

=over 1
    
=item MOD_DESMOSINE
    
MOD:00949 ("desmosine") becomes MOD_DESMOSINE_1

MOD:01933 ("desmosine") becomes MOD_DESMOSINE_2

=item MI_TEXT_MINING
    
MI:0110 ("text mining") becomes MI_TEXT_MINING_1

MI:1056 ("text-mining") becomes MI_TEXT_MINING_2

=item UO_MILLI

UO:0000297 ("milli") becomes UO_MILLI_1

UO:0010009 ("milli") becomes UO_MILLI_2

=item UO_RATIO

UO:0000190 ("ratio") becomes UO_RATIO_1

UO:0010006 ("ratio") becomes UO_RATIO_2

=back

In rare cases, we have chosen to override the above suffixing for colliding
terms. As of this writing, the following terms are overridden:

=over 1

=item MS_M_H_ION

MS:1002820 ("M+H ion") becomes M_PLUS_H_ION

MS:1002821 ("M-H ion") becomes M_MINUS_H_ION

=back


=head1 FUNCTIONS

=head2 is_a

    if ( is_a( $child, $parent ) ) {
        say "model param is valid!";
    }

Takes two required arguments (child ID and parent ID) and returns a
boolean value indicating whether the first term is a descendant of the second.

=head2 units_for

    my $valid_units = units_for( $term );

Takes one argument (a CV ID) and returns a reference to an array of valid
unit terms from the Unit Ontology, or undef if no units are defined.

=head2 regex_for

    my $re = regex_for(MS_TRYPSIN);
    say $ for split( $re, $peptide );

Takes one argument (a CV ID representing a cleavage enzyme) and returns a
regular expression that can be used to split a string based on the specificity
of that enzyme.

=head2 cv_name

    my $name = cv_name( $term );

Takes one argument (a CV ID) and returns the text description of the term

=head2 print_tree

    print_tree ( 'MS' );

Takes one argument (a CV name) and prints a textual tree representation of the
CV hierarchy to STDOUT (or the currently selected output filehandle). This is
mainly of use for debugging the use of CV terms in your program, as it
includes the constant name exported by this module for each term in the CV.

=head1 CAVEATS AND BUGS

Please report any bugs or feature requests to the issue tracker
at L<https://github.com/jvolkening/p5-MS>.


=head1 AUTHOR

Jeremy Volkening <jdv@base2bio.com>

=head1 COPYRIGHT AND LICENSE

Copyright 2016-2017 Jeremy Volkening

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

