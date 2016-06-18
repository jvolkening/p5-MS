package MS::Reader::MzIdentML::PeptideEvidence;

use strict;
use warnings;

use base qw/MS::Reader::XML::Record::CV/;

sub _pre_load {

    my ($self) = @_;
    $self->{_toplevel} = 'PeptideEvidence';

    # Lookup tables to quickly check elements
    $self->{_make_named_array} = {
        cvParam   => 'accession',
        userParam => 'name',
    };

}

sub id       { return $_[0]->{id}                   } 
sub pep_ref  { return $_[0]->{peptide_ref}          } 
sub seq_ref  { return $_[0]->{dBSequence_ref}       }
sub start    { return $_[0]->{start}                }
sub end      { return $_[0]->{end}                  }
sub pre      { return $_[0]->{pre}                  }
sub post     { return $_[0]->{post}                 }
sub frame    { return $_[0]->{frame}                }
sub is_decoy { return $_[0]->{isDecoy}              }
sub trl_ref  { return $_[0]->{translationTable_ref} }

# TODO: add class methods

1;

__END__

=pod

=encoding UTF-8

=head1 NAME

MS::Reader::MzIdentML::PeptideEvidence - mzIdentML sequence object

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
