#!perl
use 5.006;
use strict;
use warnings;
use Test::More;

my @modules = qw(
	Lamashtu
	Lamashtu::Config
	Lamashtu::Client
	Lamashtu::LogDrek
	Lamashtu::App
	Lamashtu::App::Command::start
	Lamashtu::App::Command::stop
	Lamashtu::App::Command::status
	Lamashtu::App::Command::list
	Lamashtu::App::Command::restart
	Lamashtu::App::Command::add
	Lamashtu::App::Command::remove
	Lamashtu::App::Command::reload
);

plan tests => scalar(@modules);

use_ok($_) || print "Bail out!\n" for @modules;

diag("Testing Lamashtu $Lamashtu::VERSION, Perl $], $^X");
