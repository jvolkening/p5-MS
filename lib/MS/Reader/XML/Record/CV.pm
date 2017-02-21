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


    if (defined $ref->{cvParam}->{$cv}) {

        if (defined $ref->{cvParam}->{$cv}->[$idx]) {
            my $val   = exists $ref->{cvParam}->{$cv}->[$idx]->{value}
                ? $ref->{cvParam}->{$cv}->[$idx]->{value}
                : '';
            my $units = exists $ref->{cvParam}->{$cv}->[$idx]->{unitAccession}
                ? $ref->{cvParam}->{$cv}->[$idx]->{unitAccession}
                : undef;
            return wantarray ? ($val, $units) : $val;
        }
        else {
            # need to track index across potentially multiple ParamGroups
            --$idx;
            return undef if ($idx < 0);
        }

    }

    # try groups if not found initially
    else {

        for (@{ $ref->{referenceableParamGroupRef} }) {

            my $r = $self->{__param_groups}->{ $_->{ref} };
            next if (! exists $r->{cvParam}->{$cv});

            if (defined $r->{cvParam}->{$cv}->[$idx]) {
                my $val   = exists $r->{cvParam}->{$cv}->[$idx]->{value}
                    ? $r->{cvParam}->{$cv}->[$idx]->{value}
                    : '';
                my $units = exists $r->{cvParam}->{$cv}->[$idx]->{unitAccession}
                    ? $r->{cvParam}->{$cv}->[$idx]->{unitAccession}
                    : undef;
                return wantarray ? ($val, $units) : $val;
            }
            else {
                # need to track index across potentially multiple ParamGroups
                --$idx;
                return undef if ($idx < 0);
            }

        }

    }
        
    return undef;

}

1;
