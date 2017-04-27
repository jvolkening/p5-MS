use 5.012;

use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name        => 'MS',
    license            => 'GPL_3',
    dist_author        => q{Jeremy Volkening <jdv@base2bio.com>},
    configure_requires => {
        'Module::Build' => 0,
    },
    build_requires => {
        'Test::More' => 0,
    },
    requires => {
        'PerlIO::gzip'   => 0,
        'Compress::BGZF' => 0,
        'XML::Parser'    => 0,
        'Data::Lock'     => 0,
    },
    meta_merge => {
        resources => {
            repository => 'https://github.com/jvolkening/p5-MS'
        }
    },
    add_to_cleanup => [
        'MS-*',
        't/corpus/*.idx',
        'cover_db',
    ],
    create_license => 1,
    share_dir => 'share',
);
$builder->create_build_script;
