use strict;
use warnings;
use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'App::Rad',
    AUTHOR              => 'Breno G. de Oliveira <garu at cpan.org>',
    VERSION_FROM        => 'lib/App/Rad.pm',
    ABSTRACT_FROM       => 'lib/App/Rad.pm',
    PL_FILES            => {},
    PREREQ_PM => {
        'Test::More'   => 0,
        'Getopt::Long' => 2.36,
        'Carp'         => 0,
        'File::Temp'   => 0,
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'App-Rad-*' },
);
