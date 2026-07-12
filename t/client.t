use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use IO::Socket::UNIX ();
use JSON::MaybeXS qw( encode_json decode_json );
use Lamashtu::Client;

# fork a tiny mock JSONUnix-style server: read one JSON line, reply with a framed
# response keyed off the command.
my $dir  = tempdir( CLEANUP => 1 );
my $sock = $dir . '/socket';

my $pid = fork();
die('fork failed') if !defined($pid);
if ( $pid == 0 ) {
	my $listen = IO::Socket::UNIX->new( Type => IO::Socket::UNIX::SOCK_STREAM(), Local => $sock, Listen => 5 )
		|| die($!);
	while ( my $conn = $listen->accept ) {
		my $line = <$conn>;
		my $req  = decode_json($line);
		my $resp
			= $req->{command} eq 'list'
			? { status => 'ok', result => { sets => [ 'em0', 'em1' ] } }
			: { status => 'error', error => 'unknown command: ' . $req->{command} };
		print $conn encode_json($resp) . "\n";
		close($conn);
	}
	exit(0);
}

# wait for the socket
my $waited = 0;
while ( !-S $sock && $waited < 10 ) { select( undef, undef, undef, 0.1 ); $waited += 0.1; }
ok( -S $sock, 'mock server socket is up' ) || BAIL_OUT('mock server never came up');

my $client = Lamashtu::Client->new( socket => $sock );

is_deeply( $client->call_ok('list'), { sets => [ 'em0', 'em1' ] }, 'list round-trips' );

# call_ok dies on an error reply
eval { $client->call_ok('bogus'); };
like( $@, qr/unknown command/, 'call_ok dies on server error' );

# connect failure on a missing socket
my $bad = Lamashtu::Client->new( socket => $dir . '/nope', timeout => 2 );
eval { $bad->call('list'); };
like( $@, qr/connect .* failed/, 'connect failure is fatal' );

kill( 'TERM', $pid );
done_testing;
