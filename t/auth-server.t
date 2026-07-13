use strict;
use warnings;
use Test::More;
use lib 't/lib';
use LamashtuTest qw( test_dir write_config wait_for_socket spawn_daemon wait_for_exit );
use Lamashtu::Client;

# End-to-end Neti gate: bring the daemon up with enable_auth on and drive it
# over the real control socket. The client completes the unix-ownership
# challenge transparently; a type=command set keeps tcpdump/root out of it.

my $me = getpwuid($<);
plan skip_all => 'cannot resolve the current username' if !defined($me);

# ---------------------------------------------------------------------------
# a user in authed_users passes the gate and can drive the daemon
{
	my $dir     = test_dir();
	my $authtmp = "$dir/authtmp";
	mkdir($authtmp) || BAIL_OUT("mkdir $authtmp: $!");

	my $config = write_config( $dir, <<TOML );
pcap_dir      = "$dir/pcap"
run_dir       = "$dir/run"
enable_auth   = true
authed_users  = [ "$me" ]
auth_temp_dir = "$authtmp"

[sets.selftest]
type    = "command"
program = "cat"
TOML

	my $socket = "$dir/run/socket";
	my $pid    = spawn_daemon( config => $config, socket => $socket );
	ok( wait_for_socket( $socket, 15 ), 'daemon came up with the Neti gate on' )
		|| BAIL_OUT('daemon never came up');

	my $client = Lamashtu::Client->new( socket => $socket );
	is_deeply( $client->call_ok('list'), { sets => ['selftest'] },
		'authed user completes the challenge and drives the daemon' );

	$client->call_ok('stop');
	ok( wait_for_exit( $pid, 15 ), 'authed stop shut the daemon down' );
}

# ---------------------------------------------------------------------------
# a user NOT on the list is refused at the gate (root always passes, so skip)
SKIP: {
	skip 'running as root, which always passes the Neti gate', 2 if $< == 0;

	my $dir     = test_dir();
	my $authtmp = "$dir/authtmp";
	mkdir($authtmp) || BAIL_OUT("mkdir $authtmp: $!");

	my $config = write_config( $dir, <<TOML );
pcap_dir      = "$dir/pcap"
run_dir       = "$dir/run"
enable_auth   = true
authed_users  = [ "definitely-not-$me" ]
auth_temp_dir = "$authtmp"

[sets.selftest]
type    = "command"
program = "cat"
TOML

	my $socket = "$dir/run/socket";
	my $pid    = spawn_daemon( config => $config, socket => $socket );
	wait_for_socket( $socket, 15 ) || BAIL_OUT('daemon never came up');

	my $client  = Lamashtu::Client->new( socket => $socket );
	my $refused = !eval { $client->call_ok('list'); 1 };
	my $err     = $@;
	ok( $refused, 'an unlisted user is refused even after authenticating' );
	like( $err, qr/Neti gate/, 'the refusal names the Neti gate' );

	# we cannot stop() (we are refused); TERM it directly
	kill( 'TERM', $pid );
	wait_for_exit( $pid, 15 );
}

done_testing;
