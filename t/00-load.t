#!perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'App::Rad' );
}

diag( "Testing App::Rad $App::Rad::VERSION, Perl $], $^X" );
