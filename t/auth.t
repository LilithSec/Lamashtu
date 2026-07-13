use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use Lamashtu;
use Lamashtu::Config;

# Unit tests for the Neti gate: config parsing of the auth keys and the
# _authorize / _user_in_lists logic. No socket/daemon here -- a FakeCtx stands
# in for the POE::Component::Server::JSONUnix auth context.

package FakeCtx;
sub new      { my ( $c, $uid, $user ) = @_; return bless { uid => $uid, username => $user }, $c; }
sub uid      { return $_[0]->{uid}; }
sub username { return $_[0]->{username}; }

package main;

my $dir = tempdir( CLEANUP => 1 );

sub write_cfg {
	my ($body) = @_;
	my $path = $dir . '/cfg.toml';
	open( my $fh, '>', $path ) || die($!);
	print $fh $body;
	close($fh);
	return $path;
}

# a Lamashtu built around a single command set (no tcpdump/root needed)
sub build {
	return Lamashtu->new(
		pcap_dir          => "$dir/pcap",
		tcpdump_sets      => { selftest => { type => 'command', program => 'cat' } },
		verify_interfaces => 0,
		@_,
	);
}

# --- config passthrough ---
my $opts = Lamashtu::Config::load( write_cfg( <<'TOML' ), verify_interfaces => 0 );
pcap_dir      = "/tmp/pcap"
enable_auth   = true
authed_users  = [ "alice" ]
authed_groups = [ "wheel" ]
auth_temp_dir = "/tmp/lamashtu-auth"
[sets.selftest]
type    = "command"
program = "cat"
TOML
ok( $opts->{enable_auth}, 'enable_auth parsed from config' );
is_deeply( $opts->{authed_users},  ['alice'], 'authed_users parsed' );
is_deeply( $opts->{authed_groups}, ['wheel'], 'authed_groups parsed' );
is( $opts->{auth_temp_dir}, '/tmp/lamashtu-auth', 'auth_temp_dir parsed' );

# --- new() normalizes + validates ---
my $authed = build( enable_auth => 1, authed_users => ['alice'], authed_groups => ['wheel'] );
is( $authed->{enable_auth}, 1, 'enable_auth normalized to 1' );

my $plain = build();
is( $plain->{enable_auth}, 0, 'enable_auth defaults off' );
is_deeply( $plain->{authed_users},  [], 'authed_users defaults to []' );
is_deeply( $plain->{authed_groups}, [], 'authed_groups defaults to []' );

eval { build( authed_users => 'notanarray' ); };
like( $@, qr/authed_users must be an array/, 'a non-array authed_users is a config error' );
eval { build( authed_groups => { not => 'array' } ); };
like( $@, qr/authed_groups must be an array/, 'a non-array authed_groups is a config error' );

# --- _authorize: the Neti gate itself ---
ok( eval { $plain->_authorize( FakeCtx->new( 1000, 'nobody' ) ); 1 }, 'auth off: anyone passes' );
ok( eval { $authed->_authorize( FakeCtx->new( 0, 'root' ) ); 1 },     'UID 0 always passes the gate' );
ok( eval { $authed->_authorize( FakeCtx->new( 1001, 'alice' ) ); 1 }, 'a listed user passes' );

ok( !eval { $authed->_authorize( FakeCtx->new( 1002, 'mallory' ) ); 1 }, 'an unlisted user is refused' );
like( $@, qr/Neti gate/, 'refusal names the Neti gate' );

ok( !eval { $authed->_authorize( FakeCtx->new( undef, undef ) ); 1 }, 'a context with no uid is refused' );
like( $@, qr/authentication required/, 'missing uid demands authentication' );

# --- group membership path: authorize the current user via their primary group ---
my $me         = getpwuid($<);
my $primary    = defined($me) ? getgrgid( ( getpwuid($<) )[3] ) : undef;
SKIP: {
	skip 'could not resolve current user/primary group', 1 if !defined($me) || !defined($primary);
	my $bygroup = build( enable_auth => 1, authed_groups => [$primary] );
	ok( eval { $bygroup->_authorize( FakeCtx->new( $<, $me ) ); 1 }, "membership of primary group '$primary' passes" );
}

done_testing;
