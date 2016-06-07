package MS::Reader::MzIdentML::Peptide;

use strict;
use warnings;

use parent qw/MS::Reader::XML::Record/;

sub _pre_load {

    my ($self) = @_;
    $self->{_toplevel} = 'Peptide';

    # Lookup tables to quickly check elements
    $self->{_make_named_array} = {
        cvParam   => 'accession',
        userParam => 'name',
    };

    $self->{_make_anon_array} = { map {$_ => 1} qw/
        Modification
        SubstitutionModification
    / };

}

sub id         { return $_[0]->{id}         } 
sub name       { return $_[0]->{name}       }
sub seq        { return $_[0]->{PeptideSeq} }

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MS::Reader::MzIdentML::Peptide - mzIdentML peptide object

=head1 SYNOPSIS

    my $seq = $search->fetch_seq($id);

=head1 DESCRIPTION

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
