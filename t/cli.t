use strict;
use warnings;
use Test::More;
use App::Cmd::Tester;
use Lamashtu::App;

# `commands` lists the subcommands
my $result = App::Cmd::Tester->test_app( 'Lamashtu::App', ['commands'] );
is( $result->exit_code, 0, 'commands exits 0' );
like( $result->stdout, qr/\bstatus\b/,  'status listed' );
like( $result->stdout, qr/\brestart\b/, 'restart listed' );
like( $result->stdout, qr/\bstart\b/,   'start listed' );

# restart with no set is a usage error
$result = App::Cmd::Tester->test_app( 'Lamashtu::App', [ 'restart' ] );
isnt( $result->exit_code, 0, 'restart with no set fails' );
like( $result->error // $result->stderr, qr/exactly one set/i, 'restart usage message' );

# add rejects a bad set name
$result = App::Cmd::Tester->test_app( 'Lamashtu::App', [ 'add', 'bad name!' ] );
isnt( $result->exit_code, 0, 'add with bad name fails' );

# TODO: point --socket at a forked mock JSONUnix server and assert `status`
# pretty-prints the JSON reply.

done_testing;
