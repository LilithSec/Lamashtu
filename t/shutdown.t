use strict;
use warnings;
use Test::More;
use lib 't/lib';
use LamashtuTest qw(
	test_dir write_config wait_for_socket spawn_daemon
	proc_alive wait_for_exit wait_for_proc_gone
);
use Lamashtu::Client;

# Exercises the graceful-shutdown path in Lamashtu::run: the `stop` command and
# the POE-native INT/TERM signal handlers must (a) make the daemon process
# actually exit, (b) reap the supervised capture children instead of orphaning
# them, and (c) tear the control socket down. Everything uses a type=command
# set (cat) so no root/tcpdump/live interface is needed.
#
# NOTE: LamashtuTest's END block TERMs any surviving daemon as a backstop, so a
# broken shutdown can't wedge the suite -- but these tests assert the daemon is
# already gone *before* that net catches it.

# bring a daemon up with a single command set and hand back
# ( daemon_pid, $client, capture_child_pid, $socket, $stderr_path ).
sub bring_up {
	my ($dir) = @_;

	my $config = write_config( $dir, <<TOML );
pcap_dir = "$dir/pcap"
run_dir  = "$dir/run"

[sets.selftest]
type    = "command"
program = "cat"
TOML

	my $socket = $dir . '/run/socket';
	my $stderr = $dir . '/daemon.stderr';
	my $pid    = spawn_daemon( config => $config, socket => $socket, stderr => $stderr );

	wait_for_socket( $socket, 15 ) || BAIL_OUT('daemon never came up');

	my $client = Lamashtu::Client->new( socket => $socket );
	my $status = $client->call_ok('status');
	my $child  = $status->{sets}{selftest}{pid};

	return ( $pid, $client, $child, $socket, $stderr );
}

# after the daemon has exited, assert it never hit POE's end-of-run fallback
# reaper -- i.e. every capture child was reaped under a live session.
sub assert_clean_reap {
	my ( $stderr, $label ) = @_;
	my $log = '';
	if ( open( my $fh, '<', $stderr ) ) {
		local $/;
		$log = <$fh>;
		close($fh);
	}
	unlike( $log, qr/ready to return|child process\(es\)/, "$label: no POE fallback-reaper warning" );
}

# ---------------------------------------------------------------------------
subtest 'stop command: daemon exits, child reaped, socket closed' => sub {
	my $dir = test_dir();
	my ( $pid, $client, $child, $socket, $stderr ) = bring_up($dir);

	ok( $child,              'status reported a pid for the capture child' );
	ok( proc_alive($child),  'capture child is running before stop' );

	is_deeply( $client->call_ok('stop'), { stopping => 1 }, 'stop was accepted' );

	ok( wait_for_exit( $pid, 15 ),         'daemon process exited on its own after stop' );
	ok( wait_for_proc_gone( $child, 15 ),  'capture child was reaped, not orphaned' );

	# a fresh connect must now fail -- the control socket is gone
	my $refused = !eval { $client->call('list'); 1 };
	ok( $refused, 'control socket refuses connections after shutdown' );

	ok( !-e "$dir/run/pid", 'pid file was removed on clean exit' );
	assert_clean_reap( $stderr, 'stop' );
};

# ---------------------------------------------------------------------------
subtest 'SIGTERM: same graceful teardown as stop (rc/systemd path)' => sub {
	my $dir = test_dir();
	my ( $pid, $client, $child, undef, $stderr ) = bring_up($dir);

	ok( proc_alive($child), 'capture child is running before TERM' );

	is( kill( 'TERM', $pid ), 1, 'sent SIGTERM to the daemon' );

	ok( wait_for_exit( $pid, 15 ),        'daemon exited on SIGTERM' );
	ok( wait_for_proc_gone( $child, 15 ), 'capture child was reaped on SIGTERM' );
	assert_clean_reap( $stderr, 'SIGTERM' );
};

# ---------------------------------------------------------------------------
# Regression guard for the reap open-item: repeated add_set/remove_set must not
# leak or orphan capture children, and the daemon must stay responsive.
subtest 'sets reap across many add/remove cycles' => sub {
	my $dir = test_dir();
	my ( $pid, $client, undef, undef, $stderr ) = bring_up($dir);

	my @churn_pids;
	for my $i ( 1 .. 20 ) {
		$client->call_ok( 'add_set', { set => 'churn', def => { type => 'command', program => 'cat' } } );

		my $st    = $client->call_ok( 'status_set', { set => 'churn' } );
		my $child = $st->{pid};
		ok( $child && proc_alive($child), "cycle $i: churn child $child came up" )
			or last;
		push @churn_pids, $child;

		$client->call_ok( 'remove_set', { set => 'churn' } );
		ok( wait_for_proc_gone( $child, 10 ), "cycle $i: churn child $child reaped after remove" )
			or last;
	}

	# nothing we spun up should still be alive
	my @survivors = grep { proc_alive($_) } @churn_pids;
	is( scalar(@survivors), 0, 'no churn children survived their removals' );

	# and the daemon is still healthy after all that
	is_deeply( $client->call_ok('list'), { sets => ['selftest'] }, 'daemon still responsive, only selftest left' );

	$client->call_ok('stop');
	ok( wait_for_exit( $pid, 15 ), 'daemon shut down cleanly at end' );
	assert_clean_reap( $stderr, 'add/remove churn' );
};

done_testing;
