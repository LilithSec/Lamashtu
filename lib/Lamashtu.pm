package Lamashtu;

use 5.006;
use strict;
use warnings;
use Sys::Syslog;
use String::ShellQuote;
use POE::Wheel::Run::DaemonHelper;
use Sys::Syslog;

=head1 NAME

Lamashtu - 

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
            sets=>{
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

    - sets :: A hash ref of configured sets. They keys of the
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
        Default :: /var/log/lamashtu

    - sub_dir :: If true each set will be created as it's own dir under the pcap_dir.
        Default :: 0

Set keys are as below.

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
            sets=>{
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
		$opts{pcap_dir} = '/var/log/lamashtu';
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
	if ( !defined( $opts{sets} ) ) {
		die('$opts{sets} is undef');
	} elsif ( ref( $opts{sets} ) ne 'HASH' ) {
		die( '$opts{sets} ref is "' . ref( $opts{set} ) . '" and not HASH' );
	}

	#
	# begin set sanity checking
	#
	my @sets = keys( %{ $opts{sets} } );
	# can't do anything if if this is undef
	if ( !defined( $sets[0] ) ) {
		die('No sets defined');
	}

	# make sure each set and it's data is likely sane
	foreach my $set (@sets) {
		if ( !defined( $opts{sets}{$set}{type} ) ) {
			$opts{sets}{$set}{type} = 'tcpdump';
		}    # make sure we what the type is
		elsif ( $opts{sets}{$set}{type} ne 'tcpdump' ) {
			die(      '$opts{sets}{'
					. $set
					. '}{type} is set to "'
					. $opts{sets}{$set}{type}
					. '" which is not a known set type' );
		}
		# handle tcpdump related args
		if ( $opts{sets}{$set}{type} eq 'tcpdump' ) {
			# if args is not set and is tcpdump, fill it in
			# if set, do a basic sanity check
			if ( !defined( $opts{sets}{$set}{args} ) ) {
				$opts{sets}{$set}{args} = '-i ' . shell_quote($set);
			} elsif ( $opts{sets}{$set}{args} =~ /^\-C/ || $opts{sets}{$set}{args} =~ /\ \-C/ ) {
				die(      '$opts{sets}{'
						. $set
						. '}{args} may not include -C ... '
						. shell_quote( $opts{sets}{$set}{args} ) );
			} elsif ( $opts{sets}{$set}{args} =~ /^\-G/ || $opts{sets}{$set}{args} =~ /\ \-G/ ) {
				die(      '$opts{sets}{'
						. $set
						. '}{args} may not include -G ... '
						. shell_quote( $opts{sets}{$set}{args} ) );
			} elsif ( $opts{sets}{$set}{args} =~ /^\-w/ || $opts{sets}{$set}{args} =~ /\ \-w/ ) {
				die(      '$opts{sets}{'
						. $set
						. '}{args} may not include -w ... '
						. shell_quote( $opts{sets}{$set}{args} ) );
			} elsif ( $opts{sets}{$set}{args} =~ /^\-W/ || $opts{sets}{$set}{args} =~ /\ \-W/ ) {
				die(      '$opts{sets}{'
						. $set
						. '}{args} may not include -W ... '
						. shell_quote( $opts{sets}{$set}{args} ) );
			} elsif ( $opts{sets}{$set}{args} !~ /^\-i/ && $opts{sets}{$set}{args} !~ /\ \-i/ ) {
				die(      '$opts{sets}{'
						. $set
						. '}{args} is set, but does not include -i ... '
						. shell_quote( $opts{sets}{$set}{args} ) );
			}
			# make sure we have something sane for size
			if ( !defined( $opts{sets}{$set}{size} ) ) {
				$opts{sets}{$set}{size} = 32;
			} elsif ( $opts{sets}{$set}{size} !~ /^\d+$/ ) {
				die(      '$opts{sets}{'
						. $set
						. '}{size} is set to "'
						. $opts{sets}{$set}{size}
						. '" which not a positive integer' );
			} elsif ( $opts{sets}{$set}{size} == 0 ) {
				die(      '$opts{sets}{'
						. $set
						. '}{size} is set to "'
						. $opts{sets}{$set}{size}
						. '" needs to be a positive integer equal to or greater than 1' );
			}
			# make sure we have something sane for secs
			if ( !defined( $opts{sets}{$set}{secs} ) ) {
				$opts{sets}{$set}{secs} = 10;
			} elsif ( $opts{sets}{$set}{secs} !~ /^[0-9]+$/ ) {
				die(      '$opts{sets}{'
						. $set
						. '}{secs} is set to "'
						. $opts{sets}{$set}{secs}
						. '" which not a positive integer' );
			} elsif ( $opts{sets}{$set}{secs} == 0 ) {
				die(      '$opts{sets}{'
						. $set
						. '}{secs} is set to "'
						. $opts{sets}{$set}{secs}
						. '" needs to be a positive integer equal to or greater than 1' );
			}
		} ## end if ( $opts{sets}{$set}{type} eq 'tcpdump' )
	} ## end foreach my $set (@sets)

	my $self = {
		pcap_dir    => $opts{pcap_dir},
		stdout      => $opts{stdout},
		stderr_warn => $opts{stderr_warn},
		sets        => $opts{sets},
				dh          => {},
				dh_inited          => [],
		sub_dir     => $opts{sub_dir},
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

	my @sets = keys( %{ $self->{sets} } );

	foreach my $set (@sets) {
		$self->log_message( status => 'Creating POE session for ' . $set );

		my $outfile = $set . '.pcap-%s';
		if ( $self->{sub_dir} ) {
			$outfile = $set . '/' . $outfile;
		}
		$outfile = $self->{pcap_dir} . '/' . $outfile;

		my $program
			= 'tcpdump -G '
			. $self->{sets}{$set}{secs} . ' -C '
			. $self->{sets}{$set}{size} . ' -w '
			. $outfile . ' '
			. $self->{sets}{$set}{args};

		$self->log_message( status => $set . ' Logger: ' . $program );

		my $dh = POE::Wheel::Run::DaemonHelper->new(
			program            => $program,
			syslog_name        => 'Lamashtu-' . $set,
			status_print       => $self->{stdout},
			status_print_warn  => $self->{stderr_warn},
			status_syslog_warn => $self->{stderr_warn},
		);
		$dh->create_session;
		$self->{dh}{$set} = $dh;
		push(@{ $self->{dh_inited} }, $set);
	} ## end foreach my $set (@sets)
} ## end sub create_sessions

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

$SIG{INT}  = \&DESTROY;
$SIG{TERM} = \&DESTROY;
$SIG{ABRT} = \&DESTROY;
$SIG{KILL} = \&DESTROY;
$SIG{QUIT} = \&DESTROY;

sub DESTROY {
	my ($self) = @_;

	foreach my $set (@{ $self->{dh_inited} }) {
		eval {
			my $pid     = $self->{dh}{$set}->pid;
			my $outputs = `kill -9 $pid 2>&1`;
		};
	}
} ## end sub DESTROY

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
