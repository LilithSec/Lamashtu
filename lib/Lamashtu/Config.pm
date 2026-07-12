package Lamashtu::Config;

use 5.006;
use strict;
use warnings;
use TOML::Tiny qw( from_toml );

=head1 NAME

Lamashtu::Config - load and validate the Lamashtu TOML config.

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1';

=head1 SYNOPSIS

    use Lamashtu::Config;

    my $opts = Lamashtu::Config::load( '/usr/local/etc/lamashtu.toml' );
    my $lamashtu = Lamashtu->new( %{$opts} );

=head1 DESCRIPTION

Parses the TOML config into the same in-memory structure that
C<< Lamashtu->new >> accepts, applying defaults and running the per-set sanity
checks (via L</validate_sets>). The top-level keys become manager options; the
C<[sets.NAME]> tables become C<tcpdump_sets>.

=head1 SUBROUTINES

=head2 load

    my $opts = Lamashtu::Config::load( $path, %opts );

Returns a hashref suitable for C<< Lamashtu->new( %{$opts} ) >>. Dies on parse
failure or invalid set definitions.

C<%opts> is forwarded to L</validate_sets>; the useful keys are
C<verify_interfaces> (bool, overrides the config's C<verify_interfaces>) and
C<interfaces> (an injected interface list, mainly for tests). If neither the
option nor the config sets C<verify_interfaces>, it defaults on.

=cut

sub load {
	my ( $path, %opts ) = @_;

	die('no config path given')                     if !defined($path);
	die( 'config "' . $path . '" does not exist' )  if !-f $path;

	open( my $fh, '<', $path ) || die( 'open ' . $path . ': ' . $! );
	local $/ = undef;
	my $raw = <$fh>;
	close($fh);

	my ( $config, $err ) = from_toml($raw);
	die( 'failed to parse ' . $path . ': ' . $err ) if !defined($config);

	my $out = {};

	# manager settings, straight passthrough of the ones Lamashtu knows
	foreach my $key (qw( pcap_dir run_dir socket_group socket_mode sub_dir stdout stderr_warn verify_interfaces rotate )) {
		$out->{$key} = $config->{$key} if defined $config->{$key};
	}

	# [sets.NAME] tables -> tcpdump_sets
	$out->{tcpdump_sets} = ( defined $config->{sets} && ref $config->{sets} eq 'HASH' )
		? $config->{sets}
		: {};

	# resolve the verify flag: explicit option beats config beats default-on
	my %vopts;
	if ( exists $opts{verify_interfaces} ) {
		$vopts{verify_interfaces} = $opts{verify_interfaces};
	} elsif ( defined $config->{verify_interfaces} ) {
		$vopts{verify_interfaces} = $config->{verify_interfaces};
	}
	$vopts{interfaces} = $opts{interfaces} if exists $opts{interfaces};

	# global rotate default: explicit option beats config
	if ( exists $opts{default_rotate} ) {
		$vopts{default_rotate} = $opts{default_rotate};
	} elsif ( defined $config->{rotate} ) {
		$vopts{default_rotate} = $config->{rotate};
	}

	validate_sets( $out->{tcpdump_sets}, %vopts );

	return $out;
}

=head2 validate_sets

    Lamashtu::Config::validate_sets( \%sets, %opts );

Validates the sets in place, filling defaults (C<type>, C<interface>, C<args>,
C<secs>, C<size>) and dying on anything invalid. This is the single validator
shared by the config path, C<< Lamashtu->new >>, and the runtime C<add_set> /
C<reload> control commands.

For a C<tcpdump> set:

    - interface :: capture interface. Defaults to the set name. Verified against
                   `tcpdump -D` unless verification is off.
    - args      :: optional extra tcpdump flags/filter. May NOT contain
                   -C/-G/-w/-W/-i (Lamashtu injects those). Default :: ''
    - rotate    :: which dimension rotates the pcap: 'secs' (-G), 'size' (-C),
                   or 'both' (-G and -C). Default :: 'secs' (or C<default_rotate>).
    - secs      :: rotate seconds (-G). Positive integer. Used when rotate is
                   secs or both. Default :: 10
    - size      :: rotate MiB (-C). Positive integer. Used when rotate is size
                   or both. Default :: 32

For a C<command> set: C<program> is required and everything else is ignored.

C<%opts>:

    - verify_interfaces :: if false, skip the `tcpdump -D` check. Default :: 1
    - interfaces        :: hashref of C<< name => 1 >> to check against instead
                           of shelling out to `tcpdump -D`. Mainly for tests.
    - default_rotate    :: rotate value ('secs'|'size') for sets that omit one.
                           Default :: 'secs'

=cut

sub validate_sets {
	my ( $sets, %opts ) = @_;

	die('no sets defined') if !defined($sets) || ref($sets) ne 'HASH';
	my @names = keys %{$sets};
	die('no sets defined') if !@names;

	my $verify = defined( $opts{verify_interfaces} ) ? $opts{verify_interfaces} : 1;
	my $known;    # hashref of known interface names, or undef when not verifying
	if ($verify) {
		$known = $opts{interfaces} // tcpdump_interfaces();
	}

	foreach my $name (@names) {
		die( 'set name "' . $name . '" must match /^[0-9A-Za-z_]+$/' )
			if $name !~ /^[0-9A-Za-z_]+$/;

		my $def = $sets->{$name};
		die( 'set "' . $name . '" definition must be a hash' ) if ref($def) ne 'HASH';
		$def->{type} //= 'tcpdump';

		if ( $def->{type} eq 'command' ) {
			die( 'set "' . $name . '" is type=command but has no program' )
				if !defined( $def->{program} );
			next;
		}
		if ( $def->{type} ne 'tcpdump' ) {
			die( 'set "' . $name . '" has unknown type "' . $def->{type} . '"' );
		}

		# --- tcpdump set ---

		# interface defaults to the set name and is checked against tcpdump -D
		$def->{interface} //= $name;
		die( 'set "' . $name . '" interface must be a plain string' )
			if ref( $def->{interface} );
		if ( defined($known) && !$known->{ $def->{interface} } ) {
			die(      'set "' . $name . '" interface "' . $def->{interface}
					. '" is not listed by `tcpdump -D`'
					. ' (available: ' . join( ', ', sort keys %{$known} ) . ')' );
		}

		# args: optional extra flags/filter; the injected flags are forbidden here
		if ( defined( $def->{args} ) ) {
			foreach my $flag (qw( -C -G -w -W -i )) {
				die( 'set "' . $name . '" args may not include ' . $flag )
					if $def->{args} =~ /(?:^|\s)\Q$flag\E(?:\s|=|$)/;
			}
		} else {
			$def->{args} = '';
		}

		# rotate: which dimension triggers a new pcap file -- 'secs' (tcpdump -G,
		# time based), 'size' (tcpdump -C, size based), or 'both' (-G and -C).
		# Only the dimension(s) in use are defaulted, validated, and later
		# emitted by Lamashtu::_build_program.
		$def->{rotate} //= ( defined( $opts{default_rotate} ) ? $opts{default_rotate} : 'secs' );
		if ( $def->{rotate} ne 'secs' && $def->{rotate} ne 'size' && $def->{rotate} ne 'both' ) {
			die( 'set "' . $name . '" rotate must be "secs", "size", or "both", not "' . $def->{rotate} . '"' );
		}

		if ( $def->{rotate} eq 'secs' || $def->{rotate} eq 'both' ) {
			# secs -> -G (rotate seconds)
			$def->{secs} //= 10;
			die( 'set "' . $name . '" secs must be a positive integer' )
				if $def->{secs} !~ /^[0-9]+$/ || $def->{secs} == 0;
		}
		if ( $def->{rotate} eq 'size' || $def->{rotate} eq 'both' ) {
			# size -> -C (MiB)
			$def->{size} //= 32;
			die( 'set "' . $name . '" size must be a positive integer' )
				if $def->{size} !~ /^[0-9]+$/ || $def->{size} == 0;
		}
	} ## end foreach my $name (@names)

	return;
} ## end sub validate_sets

=head2 tcpdump_interfaces

    my $ifaces = Lamashtu::Config::tcpdump_interfaces();

Runs C<tcpdump -D> and returns a hashref of C<< name => 1 >> for every capture
interface it lists. Parses both C<< "1.em0 [Up, Running]" >> and bare C<< "em0" >>
line forms. Dies if C<tcpdump -D> cannot be run or lists nothing (e.g. tcpdump
missing, or insufficient privileges to enumerate).

Not cached: a fresh enumeration each call so a set added at runtime sees
interfaces that appeared after the daemon started.

=cut

sub tcpdump_interfaces {
	my $out = `tcpdump -D 2>/dev/null`;
	if ( $? != 0 || !defined($out) || $out eq '' ) {
		die('could not enumerate interfaces via `tcpdump -D`'
				. ' (is tcpdump installed and do we have privileges?)');
	}

	my %ifaces;
	foreach my $line ( split( /\n/, $out ) ) {
		# "1.em0 [Up, Running]" | "9.ue0" | "any"
		next if $line !~ /^\s*(?:\d+\.)?([^\s\[]+)/;
		$ifaces{$1} = 1;
	}

	die('`tcpdump -D` listed no interfaces') if !keys(%ifaces);

	return \%ifaces;
}

=head1 AUTHOR

Zane C. Bowers-Hadley, C<< <vvelox at vvelox.net> >>

=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2023 by Zane C. Bowers-Hadley.

This is free software, licensed under The Artistic License 2.0 (GPL Compatible).

=cut

1;
