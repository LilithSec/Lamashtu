#!perl
use 5.006;
use strict;
use warnings;
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Lamashtu' ) || print "Bail out!\n";
}

diag( "Testing Lamashtu $Lamashtu::VERSION, Perl $], $^X" );
