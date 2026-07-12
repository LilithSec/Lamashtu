use strict;
use warnings;
use Test::More;
use File::Temp qw( tempdir );
use Lamashtu::Config;

my $dir = tempdir( CLEANUP => 1 );

sub write_cfg {
	my ($body) = @_;
	my $path = $dir . '/cfg.toml';
	open( my $fh, '>', $path ) || die($!);
	print $fh $body;
	close($fh);
	return $path;
}

# --- load() with the interface check disabled ---
my $opts = Lamashtu::Config::load(
	write_cfg( <<'TOML' ), verify_interfaces => 0 );
pcap_dir = "/tmp/pcap"
[sets.em0]
interface = "em0"
secs = 5
size = 16
[sets.selftest]
type    = "command"
program = "cat"
TOML
is( $opts->{pcap_dir}, '/tmp/pcap', 'top-level setting parsed' );
ok( exists $opts->{tcpdump_sets}{em0},      'em0 set present' );
is( $opts->{tcpdump_sets}{selftest}{type}, 'command', 'command set present' );
is( $opts->{tcpdump_sets}{em0}{args}, '',   'args defaults to empty string' );

# a command set without a program is rejected
eval { Lamashtu::Config::load( write_cfg( "[sets.bad]\ntype = \"command\"\n" ), verify_interfaces => 0 ); };
like( $@, qr/no program/, 'command set requires a program' );

# a bad set name is rejected
eval { Lamashtu::Config::load( write_cfg( "[sets.\"bad name\"]\n" ), verify_interfaces => 0 ); };
like( $@, qr/must match/, 'bad set name rejected' );

# --- validate_sets: injected interface list (no tcpdump needed) ---
my $known = { em0 => 1, em1 => 1 };

# interface defaults to the set name and passes when present
my $sets = { em0 => {} };
eval { Lamashtu::Config::validate_sets( $sets, interfaces => $known ); };
is( $@, '', 'set with a known interface validates' );
is( $sets->{em0}{interface}, 'em0', 'interface defaulted to set name' );
is( $sets->{em0}{secs}, 10, 'secs defaulted' );
ok( !exists $sets->{em0}{size}, 'size not defaulted under default rotate=secs' );

# an unknown interface is rejected and the message lists the known ones
eval { Lamashtu::Config::validate_sets( { wan => { interface => 'ppp0' } }, interfaces => $known ); };
like( $@, qr/not listed by .*tcpdump -D/, 'unknown interface rejected' );
like( $@, qr/em0, em1/,                   'error lists available interfaces' );

# injected args may not carry the managed flags
foreach my $flag (qw( -C -G -w -W -i )) {
	eval { Lamashtu::Config::validate_sets( { em0 => { args => "$flag foo" } }, interfaces => $known ); };
	like( $@, qr/\Q$flag\E/, "args rejects $flag" );
}

# bad secs / size (only checked for the active rotate dimension)
eval { Lamashtu::Config::validate_sets( { em0 => { secs => 0 } }, interfaces => $known ); };
like( $@, qr/secs/, 'zero secs rejected (rotate defaults to secs)' );
eval { Lamashtu::Config::validate_sets( { em0 => { rotate => 'size', size => 'big' } }, interfaces => $known ); };
like( $@, qr/size/, 'non-integer size rejected when rotate=size' );

# --- rotate selection ---

# default rotate is secs, and defaults the secs value
my $r = { em0 => {} };
Lamashtu::Config::validate_sets( $r, interfaces => $known );
is( $r->{em0}{rotate}, 'secs', 'rotate defaults to secs' );
is( $r->{em0}{secs},   10,     'secs defaulted under rotate=secs' );
ok( !exists $r->{em0}{size}, 'size left untouched under rotate=secs' );

# explicit rotate=size defaults the size value, not secs
$r = { em0 => { rotate => 'size' } };
Lamashtu::Config::validate_sets( $r, interfaces => $known );
is( $r->{em0}{size},   32, 'size defaulted under rotate=size' );
ok( !exists $r->{em0}{secs}, 'secs left untouched under rotate=size' );

# rotate=both defaults and validates both dimensions
$r = { em0 => { rotate => 'both' } };
Lamashtu::Config::validate_sets( $r, interfaces => $known );
is( $r->{em0}{secs}, 10, 'secs defaulted under rotate=both' );
is( $r->{em0}{size}, 32, 'size defaulted under rotate=both' );
eval { Lamashtu::Config::validate_sets( { em0 => { rotate => 'both', size => 0 } }, interfaces => $known ); };
like( $@, qr/size/, 'bad size rejected under rotate=both' );

# default_rotate opt applies to sets that omit rotate
$r = { em0 => {} };
Lamashtu::Config::validate_sets( $r, interfaces => $known, default_rotate => 'size' );
is( $r->{em0}{rotate}, 'size', 'default_rotate applied' );

# an invalid rotate is rejected
eval { Lamashtu::Config::validate_sets( { em0 => { rotate => 'weekly' } }, interfaces => $known ); };
like( $@, qr/rotate must be/, 'invalid rotate rejected' );

# --- tcpdump_interfaces() parsing, if tcpdump is present ---
SKIP: {
	my $out = `tcpdump -D 2>/dev/null`;
	skip 'tcpdump -D unavailable', 1 if $? != 0 || $out eq '';
	my $ifaces = Lamashtu::Config::tcpdump_interfaces();
	ok( ( ref($ifaces) eq 'HASH' && keys %{$ifaces} ), 'tcpdump_interfaces parsed at least one interface' );
}

done_testing;
