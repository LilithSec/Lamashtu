package LamashtuTest;

# Test helpers for the Lamashtu suite, modeled on Ereshkigal's t/lib/EreshkigalTest.pm.

use strict;
use warnings;
use Cwd qw( abs_path );
use File::Temp qw( tempdir );
use File::Basename qw( dirname );
use POSIX qw( :sys_wait_h );
use Exporter qw( import );

our @EXPORT_OK = qw(
	dist_root test_dir write_config wait_for_socket spawn_daemon
	proc_alive wait_for_exit wait_for_proc_gone
);

my $DIST_ROOT = abs_path( dirname(__FILE__) . '/../..' );
my @PIDS;
my $PARENT = $$;

sub dist_root { return $DIST_ROOT; }

# a fresh CLEANUP tempdir
sub test_dir { return tempdir( CLEANUP => 1 ); }

# write a minimal TOML config into $dir and return its path
sub write_config {
	my ( $dir, $body ) = @_;
	my $path = $dir . '/lamashtu.toml';
	open( my $fh, '>', $path ) || die($!);
	print $fh $body;
	close($fh);
	return $path;
}

# poll for a Unix socket to appear; returns 1 on success, 0 on timeout
sub wait_for_socket {
	my ( $path, $timeout ) = @_;
	$timeout //= 10;
	my $waited = 0;
	while ( $waited < $timeout ) {
		return 1 if -S $path;
		select( undef, undef, undef, 0.1 );
		$waited += 0.1;
	}
	return 0;
}

# fork+exec src_bin/lamashtu start -f against an in-tree lib; returns the pid.
# TODO: point --config at a config that uses only type=command sets so tcpdump
# (root + a live interface) is never required.
sub spawn_daemon {
	my (%opts) = @_;
	my $pid = fork();
	die('fork failed') if !defined($pid);
	if ( $pid == 0 ) {
		# optionally capture the daemon's stderr so a test can assert on it
		# (e.g. that POE never falls back to its end-of-run child reaper).
		if ( defined $opts{stderr} ) {
			open( STDERR, '>', $opts{stderr} ) || exit(254);
		}
		exec( $^X, '-I' . $DIST_ROOT . '/lib',
			$DIST_ROOT . '/src_bin/lamashtu',
			'--socket', $opts{socket},
			'start', '--config', $opts{config}, '--foreground' );
		exit(255);
	}
	push( @PIDS, $pid );
	return $pid;
}

# is $pid still around? works for our own children AND for the daemon's
# grandchildren (the supervised capture processes) which we can't waitpid().
sub proc_alive {
	my ($pid) = @_;
	return 0 if !defined($pid);
	return kill( 0, $pid ) ? 1 : 0;
}

# poll waitpid() for one of OUR children (e.g. the foreground daemon) to exit.
# returns 1 once reaped, 0 on timeout.
sub wait_for_exit {
	my ( $pid, $timeout ) = @_;
	$timeout //= 15;
	my $waited = 0;
	while ( $waited < $timeout ) {
		my $reaped = waitpid( $pid, WNOHANG );
		return 1 if $reaped == $pid || $reaped == -1;
		select( undef, undef, undef, 0.1 );
		$waited += 0.1;
	}
	return 0;
}

# poll until $pid is no longer alive (for processes we don't own and so can't
# waitpid, i.e. the daemon's supervised children). returns 1 gone, 0 on timeout.
sub wait_for_proc_gone {
	my ( $pid, $timeout ) = @_;
	$timeout //= 15;
	my $waited = 0;
	while ( $waited < $timeout ) {
		return 1 if !proc_alive($pid);
		select( undef, undef, undef, 0.1 );
		$waited += 0.1;
	}
	return 0;
}

END {
	return if $$ != $PARENT;
	kill( 'TERM', @PIDS );
}

1;
