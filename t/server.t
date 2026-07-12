use strict;
use warnings;
use Test::More;
use lib 't/lib';
use LamashtuTest qw( test_dir write_config wait_for_socket spawn_daemon );
use Lamashtu::Client;

# End-to-end: bring the daemon up with a single type=command set (so no tcpdump,
# no root, no live interface), then drive the control socket.

my $dir = test_dir();
my $config = write_config( $dir, <<TOML );
pcap_dir = "$dir/pcap"
run_dir  = "$dir/run"

[sets.selftest]
type    = "command"
program = "cat"
TOML

my $socket = $dir . '/run/socket';
spawn_daemon( config => $config, socket => $socket );

ok( wait_for_socket( $socket, 15 ), 'control socket came up' )
	|| BAIL_OUT('daemon never came up');

my $client = Lamashtu::Client->new( socket => $socket );

is_deeply( $client->call_ok('list'), { sets => ['selftest'] }, 'list returns the set' );

my $status = $client->call_ok('status');
ok( exists $status->{sets}{selftest}, 'status includes the set' );

# add a second command set at runtime (command type skips the tcpdump -D check)
$client->call_ok( 'add_set', { set => 'two', def => { type => 'command', program => 'cat' } } );
is_deeply( $client->call_ok('list'), { sets => [ 'selftest', 'two' ] }, 'add_set registered the set' );

# restarting and removing it
$client->call_ok( 'restart',    { set => 'two' } );
$client->call_ok( 'remove_set', { set => 'two' } );
is_deeply( $client->call_ok('list'), { sets => ['selftest'] }, 'remove_set dropped the set' );

# adding a duplicate is an error
eval { $client->call_ok( 'add_set', { set => 'selftest', def => { type => 'command', program => 'cat' } } ); };
like( $@, qr/already exists/, 'duplicate add_set rejected' );

# clean shutdown
$client->call_ok('stop');

done_testing;
