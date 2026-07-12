use 5.006;
use strict;
use warnings;
use ExtUtils::MakeMaker;

my %WriteMakefileArgs = (
	NAME               => 'Lamashtu',
	AUTHOR             => q{Zane C. Bowers-Hadley <vvelox@vvelox.net>},
	VERSION_FROM       => 'lib/Lamashtu.pm',
	ABSTRACT_FROM      => 'lib/Lamashtu.pm',
	LICENSE            => 'artistic_2',
	MIN_PERL_VERSION   => '5.006',
	CONFIGURE_REQUIRES => {
		'ExtUtils::MakeMaker' => '0',
	},
	EXE_FILES     => ['src_bin/lamashtu'],
	TEST_REQUIRES => {
		'Test::More'      => '0',
		'App::Cmd::Tester' => '0',
	},
	PREREQ_PM => {
		'App::Cmd'                         => '0',
		'JSON::MaybeXS'                    => '0',
		'Net::Server::Daemonize'           => '0',
		'POE'                              => '0',
		'POE::Component::Server::JSONUnix' => '0.1.0',
		'POE::Wheel::Run::DaemonHelper'    => '0.1.0',
		'String::ShellQuote'               => '0',
		'Sys::Syslog'                      => '0',
		'TOML::Tiny'                       => '0',
	},
	dist       => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
	clean      => { FILES    => 'Lamashtu-*' },
	META_MERGE => {
		"meta-spec" => { version => 2 },
		resources   => {
			repository => {
				type => 'git',
				url  => 'https://github.com/LilithSec/Lamashtu.git',
				web  => 'https://github.com/LilithSec/Lamashtu',
			},
		},
	},
);

# Compatibility with old versions of ExtUtils::MakeMaker
unless ( eval { ExtUtils::MakeMaker->VERSION('6.64'); 1 } ) {
	my $test_requires = delete $WriteMakefileArgs{TEST_REQUIRES} || {};
	@{ $WriteMakefileArgs{PREREQ_PM} }{ keys %$test_requires } = values %$test_requires;
}

unless ( eval { ExtUtils::MakeMaker->VERSION('6.55_03'); 1 } ) {
	my $build_requires = delete $WriteMakefileArgs{BUILD_REQUIRES} || {};
	@{ $WriteMakefileArgs{PREREQ_PM} }{ keys %$build_requires } = values %$build_requires;
}

delete $WriteMakefileArgs{CONFIGURE_REQUIRES}
	unless eval { ExtUtils::MakeMaker->VERSION('6.52'); 1 };
delete $WriteMakefileArgs{MIN_PERL_VERSION}
	unless eval { ExtUtils::MakeMaker->VERSION('6.48'); 1 };
delete $WriteMakefileArgs{LICENSE}
	unless eval { ExtUtils::MakeMaker->VERSION('6.31'); 1 };

WriteMakefile(%WriteMakefileArgs);
