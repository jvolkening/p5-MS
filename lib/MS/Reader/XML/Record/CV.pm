package MS::Reader::XML::Record::CV;

use strict;
use warnings;

use parent qw/MS::Reader::XML::Record/;

use Carp;
use Data::Dumper;

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
            my $val = $r->{cvParam}->{$cv}->[$idx]->{value};
            next if (! defined $val);
            my $units = $ref->{cvParam}->{$cv}->[$idx]->{unitAccession};
            last;
        }
    }
        
    return wantarray ? ($val, $units) : $val;

}

1;
