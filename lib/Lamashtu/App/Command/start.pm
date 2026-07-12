package Lamashtu::App::Command::start;

use 5.006;
use strict;
use warnings;
use Lamashtu::App -command;
use Lamashtu ();
use Net::Server::Daemonize qw( daemonize );

our $VERSION = '0.0.1';

sub abstract { return 'start the daemon and a tcpdump for every configured set' }

sub description { return 'Read the config, daemonize unless told otherwise, and supervise the capture sets.'; }

sub usage_desc { return '%c start %o'; }

sub opt_spec {
	return (
		[ 'config=s',     'path of the config file', { default => '/usr/local/etc/lamashtu.toml' } ],
		[ 'foreground|f', 'do not daemonize' ],
	);
}

sub validate_args {
	my ( $self, $opt, $args ) = @_;

	$self->usage_error('start takes no args') if @{$args};

	return;
}

sub execute {
	my ( $self, $opt, $args ) = @_;

	# builds $self from the TOML config; dies on bad config before we fork
	my $lamashtu = Lamashtu->new_from_config( config => $opt->config );

	if ( $opt->foreground ) {
		open( my $pid_fh, '>', $lamashtu->pid_path ) || die($!);
		print $pid_fh $$;
		close($pid_fh);
	} else {
		daemonize( $>, ( split( /\s+/, $) ) )[0], $lamashtu->pid_path );
	}

	# sets up POE sessions + JSONUnix control server, then runs the kernel (blocks)
	$lamashtu->run;

	unlink( $lamashtu->pid_path ) if -e $lamashtu->pid_path;

	return;
}

1;
