package Lamashtu;

use 5.006;
use strict;
use warnings;
use Sys::Syslog;
use String::ShellQuote;
use POE;
use POE::Wheel::Run::DaemonHelper;
use POE::Component::Server::JSONUnix;
use File::Path qw(make_path);
use JSON::MaybeXS ();
use Lamashtu::Config;

# used for a holder for DH
our $TCPDUMP_DH_HOLDER = {};

=head1 NAME

Lamashtu - A daemon for managing PCAP capture instances.

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1';

=head1 SYNOPSIS

    use Lamashtu;
    use POE;

    my $lamashtu;
    eval{
        # setup two sets for monitoring interface em0 and em1 and name them respectively
        $lamashtu = Lamashtu->new(
            tcpdump_sets=>{
                em0=>{args=>'-i em0',},
                em1=>{args=>'-i em1',},
            },
        );
    };
    if ($@) {
        die('Failed to create Lamashtu instance... '.$@);
    }

    $lamashtu->create_sessions;

    POE::Kernel->run();


=head1 METHODS

=head2 new

    - tcpdump_sets :: A hash ref of configured sets. They keys of the
              hash is used as the set names. Sets names must match
              /^0-9a-zA-Z\_$/
        Default :: undef

    - stdout :: If set to true, it will print log messages to standard out as well,
                instead of just sending to syslog.
        Default :: 0

    - stderr_warn :: If set to true, it will print error log messages to standard out as well,
                instead of just sending to syslog.
        Default :: 0

    - pcap_dir :: The PCAP base directory to use.
        Default :: /var/log/lamashtu/pcap

    - sub_dir :: If true each set will be created as it's own dir under the pcap_dir.
        Default :: 0

    - run_dir :: The directory to use the PID file and 
        Default :: /var/run/lamashtu

Tcpdump Set keys are as below.

    - args :: Args to pass to tcpdump. These should not include to the -w flag
              for tcpdump. If not defined, defaults to '-i $name' where $name is
              the name of the current set. These should not contain -G, -C, -w,
              or -W.

    - secs :: Rotate seconds. This will be passed to -G for tcpdump.
        Default :: 10

    - size :: Rotation size in MiB. This will be passed to -C for tcpdump.
        Default :: 32

    my $lamashtu;
    eval{
        # setup two sets for monitoring interface em0 and em1 and name them respectively
        $lamashtu = Lamashtu->new(
            tcpdump_sets=>{
                em0=>{args=>'-i em0',},
                em1=>{args=>'-i em1',},
            },
        );
    };
    if ($@) {
        die('Failed to create Lamashtu instance... '.$@);
    }

=cut

sub new {
	my ( $blank, %opts ) = @_;

	if ( !defined( $opts{pcap_dir} ) ) {
		$opts{pcap_dir} = '/var/log/lamashtu/pcap';
	}

	if ( !defined( $opts{stdout} ) ) {
		$opts{stdout} = 0;
	}

	if ( !defined( $opts{stderr_warn} ) ) {
		$opts{stderr_warn} = 0;
	}

	if ( !defined( $opts{sub_dir} ) ) {
		$opts{sub_dir} = 1;
	}
	if ( !defined( $opts{tcpdump_sets} ) ) {
		die('$opts{sets} is undef');
	} elsif ( ref( $opts{tcpdump_sets} ) ne 'HASH' ) {
		die( '$opts{tcpdump_sets} ref is "' . ref( $opts{tcpdump_set} ) . '" and not HASH' );
	}

	# Validate and default the sets in place. This is the single validator
	# shared with the config path and the runtime add_set/reload commands, and
	# includes the `tcpdump -D` interface check. Pass verify_interfaces => 0
	# (or set it in the config) to skip the interface check when embedding on a
	# host without tcpdump.
	Lamashtu::Config::validate_sets(
		$opts{tcpdump_sets},
		( exists $opts{verify_interfaces} ? ( verify_interfaces => $opts{verify_interfaces} ) : () ),
		( exists $opts{interfaces}        ? ( interfaces        => $opts{interfaces} )        : () ),
		( defined $opts{rotate}           ? ( default_rotate    => $opts{rotate} )            : () ),
	);

	my $self = {
		pcap_dir          => $opts{pcap_dir},
		stdout            => $opts{stdout},
		stderr_warn       => $opts{stderr_warn},
		tcpdump_sets      => $opts{tcpdump_sets},
		sub_dir           => $opts{sub_dir},
		verify_interfaces => $opts{verify_interfaces},
		rotate            => $opts{rotate},
	};
	bless $self;

	return $self;
} ## end sub new

=head2 create_sessions

This creates the L<POE> sessions via
L<POE::Wheel::Run::DaemonHelper>.

    $lamashtu->create_sessions;

=cut

sub create_sessions {
	my $self = $_[0];

	foreach my $set ( keys( %{ $self->{tcpdump_sets} } ) ) {
		$self->_create_set_session($set);
	}

	return;
} ## end sub create_sessions

=head2 _create_set_session

Creates and stores the L<POE::Wheel::Run::DaemonHelper> session for a single
set. Used by L</create_sessions> and by the runtime C<add_set> / C<reload>
control commands.

=cut

sub _create_set_session {
	my ( $self, $set ) = @_;

	$self->log_message( status => 'Creating POE session for ' . $set );

	my $program = $self->_build_program($set);
	$self->log_message( status => $set . ' Logger: ' . $program );

	my $dh = POE::Wheel::Run::DaemonHelper->new(
		program            => $program,
		syslog_name        => 'Lamashtu-' . $set,
		status_print       => $self->{stdout},
		status_print_warn  => $self->{stderr_warn},
		status_syslog_warn => $self->{stderr_warn},
	);
	$dh->create_session;
	$TCPDUMP_DH_HOLDER->{$set} = $dh;

	return $dh;
} ## end sub _create_set_session

=head2 _build_program

Builds the command line for a set. For a C<command> set it returns the raw
C<program>. For a C<tcpdump> set it assembles the rotating-capture command,
injecting C<-w> (the pcap output template) and C<-i> (the validated interface);
any per-set C<args> are appended as extra flags/filter.

=cut

sub _build_program {
	my ( $self, $set ) = @_;

	my $def = $self->{tcpdump_sets}{$set};

	if ( defined( $def->{type} ) && $def->{type} eq 'command' ) {
		return $def->{program};
	}

	my $rotate = defined( $def->{rotate} ) ? $def->{rotate} : 'secs';

	# a %s strftime template is only honored when -G is present (secs or both);
	# with -C alone tcpdump appends an incrementing counter instead, so drop %s.
	my $basename = $rotate eq 'size' ? $set . '.pcap' : $set . '.pcap-%s';

	my $outfile = $basename;
	if ( $self->{sub_dir} ) {
		$outfile = $set . '/' . $outfile;
		eval { make_path( $self->{pcap_dir} . '/' . $set ) };
	} else {
		eval { make_path( $self->{pcap_dir} ) };
	}
	$outfile = $self->{pcap_dir} . '/' . $outfile;

	my $iface = defined( $def->{interface} ) ? $def->{interface} : $set;

	# emit the flag(s) for the configured rotation dimension(s)
	my @rotate_flags;
	push( @rotate_flags, '-G ' . $def->{secs} ) if $rotate eq 'secs' || $rotate eq 'both';
	push( @rotate_flags, '-C ' . $def->{size} ) if $rotate eq 'size' || $rotate eq 'both';

	my $program
		= 'tcpdump ' . join( ' ', @rotate_flags )
		. ' -w ' . shell_quote($outfile)
		. ' -i ' . shell_quote($iface);
	$program .= ' ' . $def->{args} if defined( $def->{args} ) && $def->{args} ne '';

	return $program;
} ## end sub _build_program

=head2 log_message

Logs a message.

    - status :: What to log.
      Default :: undef

    - error :: If true, this will set the log level from info to err.
      Default :: 0

=cut

sub log_message {
	my ( $self, %opts ) = @_;

	if ( !defined( $opts{status} ) ) {
		return;
	}

	my $level = 'info';
	if ( $opts{error} ) {
		$level = 'err';
	}

	my $warned = 0;
	if ( $self->{stdout} ) {
		if ( $self->{stdout_warn} && $opts{error} ) {
			warn( 'Lamashtu[' . $$ . ']: ' . $opts{status} );
		} else {
			print 'Lamashtu[' . $$ . ']: ' . $opts{status} . "\n";
		}
	}

	eval {
		if ( $self->{stdout_warn} && $opts{error} && !$warned ) {
			warn( 'Lamashtu[' . $$ . ']: ' . $opts{status} );
		}
		openlog( 'Lamashtu', '', 'daemon' );
		syslog( $level, $opts{status} );
		closelog();
	};
	if ($@) {
		warn( 'Errored logging message... ' . $@ );
	}
} ## end sub log_message

=head2 new_from_config

    my $lamashtu = Lamashtu->new_from_config( config => $path );

Loads the TOML config via L<Lamashtu::Config> and passes the resulting options
to L</new>, then records the run directory used for the PID file and control
socket. Dies on any config or validation error before the daemon forks.

=cut

sub new_from_config {
	my ( $blank, %args ) = @_;

	my $opts = Lamashtu::Config::load( $args{config} );

	my $run_dir      = delete( $opts->{run_dir} ) // '/var/run/lamashtu';
	my $socket_group = delete( $opts->{socket_group} );
	my $socket_mode  = delete( $opts->{socket_mode} ) // '0660';

	# Lamashtu::Config::load already validated the sets (interface check
	# included); tell new() not to re-run it against a possibly-different tcpdump.
	my $self = Lamashtu->new( %{$opts}, verify_interfaces => 0 );

	$self->{run_dir}           = $run_dir;
	$self->{socket_group}      = $socket_group;
	$self->{socket_mode}       = oct($socket_mode);
	$self->{config}            = $args{config};
	$self->{verify_interfaces} = $opts->{verify_interfaces};

	make_path($run_dir) if !-d $run_dir;

	return $self;
}

=head2 pid_path

Path of the daemon PID file (C<< <run_dir>/pid >>).

=cut

sub pid_path {
	my ($self) = @_;
	return ( $self->{run_dir} // '/var/run/lamashtu' ) . '/pid';
}

=head2 socket_path

Path of the JSON control socket (C<< <run_dir>/socket >>).

=cut

sub socket_path {
	my ($self) = @_;
	return ( $self->{run_dir} // '/var/run/lamashtu' ) . '/socket';
}

=head2 run

Sets up the tcpdump supervision sessions (L</create_sessions>), spawns the
L<POE::Component::Server::JSONUnix> control server, installs POE-native signal
handling, and runs the kernel. Blocks until the daemon is stopped.

=cut

sub run {
	my ($self) = @_;

	$self->create_sessions;

	my $server = POE::Component::Server::JSONUnix->spawn(
		socket_path => $self->socket_path,
		socket_mode => $self->{socket_mode},
		alias       => 'lamashtu_server',
		on_error    => sub {
			my ( $op, $errnum, $errstr ) = @_;
			$self->log_message( status => 'socket ' . $op . ': ' . $errstr . ' (' . $errnum . ')', error => 1 );
		},
		commands => {
			status     => sub { return $self->_cmd_status; },
			status_all => sub { return $self->_cmd_status( all => 1 ); },
			status_set => sub { my ( undef, $req ) = @_; return $self->_cmd_status_set($req); },
			list       => sub { return { sets => [ sort keys %{ $self->{tcpdump_sets} } ] }; },
			restart    => sub { my ( undef, $req ) = @_; return $self->_cmd_restart($req); },
			add_set    => sub { my ( undef, $req ) = @_; return $self->_cmd_add_set($req); },
			remove_set => sub { my ( undef, $req ) = @_; return $self->_cmd_remove_set($req); },
			reload     => sub { return $self->_cmd_reload; },
			stop       => sub {
				$self->log_message( status => 'stop requested' );
				$POE::Kernel::poe_kernel->post( 'lamashtu_ctl', 'shutdown' );
				return { stopping => 1 };
			},
		},
	);
	$self->{server} = $server;

	# chown the socket to the configured group so membership gates access
	if ( defined $self->{socket_group} ) {
		my $gid = getgrnam( $self->{socket_group} );
		chown( $>, $gid, $self->socket_path ) if defined $gid;
	}

	# a tiny control session that owns signal handling and shutdown
	POE::Session->create(
		inline_states => {
			_start => sub {
				$_[KERNEL]->alias_set('lamashtu_ctl');
				$_[KERNEL]->sig( INT  => 'shutdown' );
				$_[KERNEL]->sig( TERM => 'shutdown' );
			},
			shutdown => sub {
				my $kernel = $_[KERNEL];
				# graceful teardown: stop the sets (restart off + TERM; DaemonHelper
				# reaps them and won't respawn), shut the control socket, drop our
				# alias and signal watchers. With no children, no aliases, and no
				# pending events, POE::Kernel->run returns on its own -- no ->stop,
				# which would kill the pending reply and leak the child.
				$self->_shutdown_sets;
				$kernel->post( 'lamashtu_server', 'shutdown' ) if $self->{server};
				$kernel->alias_remove('lamashtu_ctl');
				$kernel->sig('INT');
				$kernel->sig('TERM');
			},
		},
	);

	$self->{started} = time;
	$self->log_message( status => 'started, socket=' . $self->socket_path );

	POE::Kernel->run;

	$self->log_message( status => 'stopped' );

	return;
}

=head2 _shutdown_sets

Stops every supervised tcpdump: disables restart and sends C<TERM>. Replaces the
old C<DESTROY>-as-signal-handler teardown.

=cut

sub _shutdown_sets {
	my ($self) = @_;

	foreach my $set ( keys %{$Lamashtu::TCPDUMP_DH_HOLDER} ) {
		eval { $Lamashtu::TCPDUMP_DH_HOLDER->{$set}->restart_ctl( restart_ctl => 0 ); };
		eval { $Lamashtu::TCPDUMP_DH_HOLDER->{$set}->kill( signal => 'TERM' ); };
	}

	return;
}

#
# Control handlers. Each returns a plain hashref on success or dies with a
# message the JSONUnix server frames as an error reply. status/status_set read
# DaemonHelper accessors; add_set/remove_set/reload mutate the running sets
# through the shared validator and _create_set_session.
#

sub _cmd_status {
	my ( $self, %opts ) = @_;

	my $sets = {};
	foreach my $set ( sort keys %{$Lamashtu::TCPDUMP_DH_HOLDER} ) {
		my $dh = $Lamashtu::TCPDUMP_DH_HOLDER->{$set};
		$sets->{$set} = {
			running    => ( defined( eval { $dh->pid } ) ? 1 : 0 ),
			pid        => scalar( eval { $dh->pid } ),
			started_at => scalar( eval { $dh->started_at } ),
			restart    => scalar( eval { $dh->restart_ctl } ),
		};
	}

	return {
		pid      => $$,
		started  => $self->{started},
		pcap_dir => $self->{pcap_dir},
		sets     => $sets,
	};
}

sub _cmd_status_set {
	my ( $self, $req ) = @_;
	my $set = $req->{args}{set};
	die('args.set is required')                          if !defined($set);
	die( 'no such set "' . $set . '"' )                  if !defined( $Lamashtu::TCPDUMP_DH_HOLDER->{$set} );
	my $status = $self->_cmd_status;
	my $def    = $self->{tcpdump_sets}{$set} // {};
	return {
		set       => $set,
		type      => $def->{type},
		interface => $def->{interface},
		rotate    => $def->{rotate},
		secs      => $def->{secs},
		size      => $def->{size},
		%{ $status->{sets}{$set} },
	};
}

sub _cmd_restart {
	my ( $self, $req ) = @_;
	my $set = $req->{args}{set};
	die('args.set is required')         if !defined($set);
	die( 'no such set "' . $set . '"' ) if !defined( $Lamashtu::TCPDUMP_DH_HOLDER->{$set} );
	$Lamashtu::TCPDUMP_DH_HOLDER->{$set}->kill( signal => 'TERM' );    # DaemonHelper restarts it
	return { set => $set, restarted => 1 };
}

=head2 _cmd_add_set

Defines and starts a new set at runtime. Validates the supplied definition with
the same L<Lamashtu::Config/validate_sets> used at load time (so the C<tcpdump -D>
interface check applies to runtime adds too), records it in C<tcpdump_sets>, and
spins up its DaemonHelper session.

    args :: { set => <name>, def => { type, interface, args, secs, size } }

=cut

sub _cmd_add_set {
	my ( $self, $req ) = @_;

	my $set = $req->{args}{set};
	my $def = $req->{args}{def};
	die('args.set is required')                        if !defined($set);
	die('args.def must be a hash')                     if ref($def) ne 'HASH';
	die( 'set "' . $set . '" already exists' )         if exists $self->{tcpdump_sets}{$set};

	# same checks as config load, incl. the tcpdump -D interface verification
	Lamashtu::Config::validate_sets(
		{ $set => $def },
		( defined( $self->{verify_interfaces} ) ? ( verify_interfaces => $self->{verify_interfaces} ) : () ),
		( defined( $self->{rotate} )            ? ( default_rotate    => $self->{rotate} )            : () ),
	);

	$self->{tcpdump_sets}{$set} = $def;
	$self->_create_set_session($set);

	return { set => $set, added => 1 };
} ## end sub _cmd_add_set

=head2 _cmd_remove_set

Stops a set's tcpdump (disabling restart, then C<TERM>) and forgets it.

    args :: { set => <name> }

=cut

sub _cmd_remove_set {
	my ( $self, $req ) = @_;

	my $set = $req->{args}{set};
	die('args.set is required')                  if !defined($set);
	die( 'no such set "' . $set . '"' )          if !exists $self->{tcpdump_sets}{$set};

	my $dh = delete $TCPDUMP_DH_HOLDER->{$set};
	if ( defined($dh) ) {
		eval { $dh->restart_ctl( restart_ctl => 0 ); };
		eval { $dh->kill( signal => 'TERM' ); };
	}
	delete $self->{tcpdump_sets}{$set};

	return { set => $set, removed => 1 };
} ## end sub _cmd_remove_set

=head2 _cmd_reload

Re-reads the on-disk config and reconciles the running sets against it: adds
sets that appeared, removes sets that vanished, and restarts sets whose
definition changed. If the new config is invalid, L<Lamashtu::Config/load> dies
before anything is touched, leaving the running daemon intact.

=cut

sub _cmd_reload {
	my ($self) = @_;

	die('daemon was not started from a config file') if !defined( $self->{config} );

	# dies (leaving current state intact) if the new config is invalid
	my $new     = Lamashtu::Config::load( $self->{config} );
	my $desired = $new->{tcpdump_sets};

	my %current = map { $_ => 1 } keys %{ $self->{tcpdump_sets} };
	my %want    = map { $_ => 1 } keys %{$desired};

	my ( @added, @removed, @restarted );

	# additions
	foreach my $set ( sort keys %want ) {
		next if $current{$set};
		$self->{tcpdump_sets}{$set} = $desired->{$set};
		$self->_create_set_session($set);
		push @added, $set;
	}

	# removals
	foreach my $set ( sort keys %current ) {
		next if $want{$set};
		$self->_cmd_remove_set( { args => { set => $set } } );
		push @removed, $set;
	}

	# definition changes -> bounce the set
	foreach my $set ( sort keys %want ) {
		next if !$current{$set};
		next if _def_eq( $self->{tcpdump_sets}{$set}, $desired->{$set} );
		$self->_cmd_remove_set( { args => { set => $set } } );
		$self->{tcpdump_sets}{$set} = $desired->{$set};
		$self->_create_set_session($set);
		push @restarted, $set;
	}

	return { added => \@added, removed => \@removed, restarted => \@restarted };
} ## end sub _cmd_reload

# canonical-JSON equality of two set definitions
sub _def_eq {
	my ( $a, $b ) = @_;
	my $j = JSON::MaybeXS->new( canonical => 1 );
	return $j->encode($a) eq $j->encode($b);
}

=head1 AUTHOR

Zane C. Bowers-Hadley, C<< <vvelox at vvelox.net> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-lamashtu at rt.cpan.org>, or through
the web interface at L<https://rt.cpan.org/NoAuth/ReportBug.html?Queue=Lamashtu>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Lamashtu


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<https://rt.cpan.org/NoAuth/Bugs.html?Dist=Lamashtu>

=item * Search CPAN

L<https://metacpan.org/release/Lamashtu>

=back


=head1 ACKNOWLEDGEMENTS


=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2023 by Zane C. Bowers-Hadley.

This is free software, licensed under:

  The Artistic License 2.0 (GPL Compatible)


=cut

1;    # End of Lamashtu
