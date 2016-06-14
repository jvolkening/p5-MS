package MS::Reader::XML::CV;

use strict;
use warnings;

use parent qw/MS::Reader::XML/;

use Carp;
use Scalar::Util qw/weaken/;

sub fetch_record {

    my ($self, @args) = @_;

    my $record = $self->SUPER::fetch_record(@args);

    if (exists $self->{referenceableParamGroupList}
      && $self->{referenceableParamGroupList}->{count} > 0) {
        $record->{__param_groups} =
            $self->{referenceableParamGroupList}->{referenceableParamGroup};
    }
    weaken( $record->{__param_groups} );
    
    return $record;

}

sub param {

    my ($self, $cv, %args) = @_;

    my $idx = $args{index} // 0;
    my $ref = $args{ref}   // $self;

    my $val   = $ref->{cvParam}->{$cv}->[$idx]->{value};
    my $units = $ref->{cvParam}->{$cv}->[$idx]->{unitAccession};

    # try groups if not found initially
    if (! defined $val) {
        for (@{ $ref->{referenceableParamGroupRef} }) {
            my $r = $self->{__param_groups}->{ $_->{ref} };
            next if (! exists $r->{cvParam}->{$cv});
            $val = $r->{cvParam}->{$cv}->[$idx]->{value};
            next if (! defined $val);
            $units = $ref->{cvParam}->{$cv}->[$idx]->{unitAccession};
            last;
        }
    }
        
    return wantarray ? ($val, $units) : $val;

}

1;


__END__

=pod

=encoding UTF-8

=head1 NAME

MS::Reader::XML::CV - Base class for XML-based parsers with support for
referenceableParamGroups

=head1 SYNOPSIS

    package MS::Reader::Foo;

    use parent MS::Reader::XML::CV;

    package main;

    use MS::Reader::Foo;

    my $run = MS::Reader::Foo->new('run.foo');

    while (my $record = $foo->next_record('bar') {
       
        # etc

    }

=head1 DESCRIPTION

C<MS::Reader::XML> is the base class for XML-based parsers in the package.
The class and its methods are not generally called directly, but publicly
available methods are documented below.

=head1 METHODS

=head2 fetch_record

    my $r = $parser->fetch_record($ref => $idx);

Takes two arguments (record reference and zero-based index) and returns a
record object. The types of records available and class of the object
returned depends on the subclass implementation. 

=head2 next_record

    while (my $r = $parser->next_record($ref);

Takes a single argument (record reference) and returns the next record in the
parser, or undef if the end of records has been reached. Types of records
available depend on the subclass implementation.

=head2 record_count

    my $n = $parser->record_count($ref);

Takes a single argument (record reference) and returns the number of records of
that type present. Types of records available depend on the subclass
implementation.

=head2 get_index_by_id

    my $i = $parser->get_index_by_id($ref => 'bar');

Takes two arguments (record reference and record ID) and returns the zero-based
index associated with that record ID, or undef if not found. Types of records
available and format of the ID string depend on the subclass implementation.

=head2 curr_index

    my $i = $parser->curr_index($ref);

Takes a single argument (record reference) and returns the zero-based index of the
"current" record. This is similar to the "tell" function on an iterable
filehandle and is generally used in conjuction with C<next_record>.

=head2 goto

    $parser->goto($ref => $i);

Takes two arguments (record reference and zero-based index) and sets the current
index position for that record reference. This is similar to the "seek" function on
an iterable filehandle and is generally used in conjuction with
C<next_record>.

=head2 dump

    $parser->dump();

Prints a textual serialization of the underlying data structure (via
L<Data::Dumper>) to STDOUT (or currently selected filehandle). This is useful
for developers who want to access data details not available by accessor.

NOTE: This is a destructive process - don't try to use the object after
dumping its contents!

=head1 CAVEATS AND BUGS

The API is in alpha stage and is not guaranteed to be stable.

Please reports bugs or feature requests through the issue tracker at
L<https://github.com/jvolkening/p5-MS/issues>.

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
