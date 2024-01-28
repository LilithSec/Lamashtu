package Lamashtu;

use 5.006;
use strict;
use warnings;
use Sys::Syslog;
use String::ShellQuote;
use POE::Wheel::Run::DaemonHelper;
use File::Path qw(make_path);

# used for a holder for DH
our $TCPDUMP_DH_HOLDER = {};

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
	if ( !defined( $opts{tcpdump_sets} ) ) {
		die('$opts{sets} is undef');
	} elsif ( ref( $opts{tcpdump_sets} ) ne 'HASH' ) {
		die( '$opts{tcpdump_sets} ref is "' . ref( $opts{tcpdump_set} ) . '" and not HASH' );
	}

	#
	# begin set sanity checking
	#
	my @sets = keys( %{ $opts{tcpdump_sets} } );
	# can't do anything if if this is undef
	if ( !defined( $sets[0] ) ) {
		die('No sets defined');
	}

	# make sure each set and it's data is likely sane
	foreach my $set (@sets) {
		if ( !defined( $opts{tcpdump_sets}{$set}{type} ) ) {
			$opts{sets}{$set}{type} = 'tcpdump';
		}    # make sure we what the type is
		elsif ( $opts{tcpdump_sets}{$set}{type} ne 'tcpdump' ) {
			die(      '$opts{tcpdump_sets}{'
					. $set
					. '}{type} is set to "'
					. $opts{tcpdump_sets}{$set}{type}
					. '" which is not a known set type' );
		}
		# handle tcpdump related args
		if ( $opts{tcpdump_sets}{$set}{type} eq 'tcpdump' ) {
			# if args is not set and is tcpdump, fill it in
			# if set, do a basic sanity check
			if ( !defined( $opts{tcpdump_sets}{$set}{args} ) ) {
				$opts{tcpdump_sets}{$set}{args} = '-i ' . shell_quote($set);
			} elsif ( $opts{tcpdump_sets}{$set}{args} =~ /^\-C/ || $opts{tcpdump_sets}{$set}{args} =~ /\ \-C/ ) {
				die(      '$opts{sets}{'
						. $set
						. '}{args} may not include -C ... '
						. shell_quote( $opts{sets}{$set}{args} ) );
			} elsif ( $opts{tcpdump_sets}{$set}{args} =~ /^\-G/ || $opts{tcpdump_sets}{$set}{args} =~ /\ \-G/ ) {
				die(      '$opts{tcpdump_sets}{'
						. $set
						. '}{args} may not include -G ... '
						. shell_quote( $opts{tcpdump_sets}{$set}{args} ) );
			} elsif ( $opts{tcpdump_sets}{$set}{args} =~ /^\-w/ || $opts{tcpdump_sets}{$set}{args} =~ /\ \-w/ ) {
				die(      '$opts{tcpdump_sets}{'
						. $set
						. '}{args} may not include -w ... '
						. shell_quote( $opts{sets}{$set}{args} ) );
			} elsif ( $opts{tcpdump_sets}{$set}{args} =~ /^\-W/ || $opts{tcpdump_sets}{$set}{args} =~ /\ \-W/ ) {
				die(      '$opts{sets}{'
						. $set
						. '}{args} may not include -W ... '
						. shell_quote( $opts{tcpdump_sets}{$set}{args} ) );
			} elsif ( $opts{tcpdump_sets}{$set}{args} !~ /^\-i/ && $opts{tcpdump_sets}{$set}{args} !~ /\ \-i/ ) {
				die(      '$opts{tcpdump_sets}{'
						. $set
						. '}{args} is set, but does not include -i ... '
						. shell_quote( $opts{tcpdump_sets}{$set}{args} ) );
			}
			# make sure we have something sane for size
			if ( !defined( $opts{tcpdump_sets}{$set}{size} ) ) {
				$opts{tcpdump_sets}{$set}{size} = 32;
			} elsif ( $opts{tcpdump_sets}{$set}{size} !~ /^\d+$/ ) {
				die(      '$opts{tcpdump_sets}{'
						. $set
						. '}{size} is set to "'
						. $opts{tcpdump_sets}{$set}{size}
						. '" which not a positive integer' );
			} elsif ( $opts{tcpdump_sets}{$set}{size} == 0 ) {
				die(      '$opts{tcpdump_sets}{'
						. $set
						. '}{size} is set to "'
						. $opts{tcpdump_sets}{$set}{size}
						. '" needs to be a positive integer equal to or greater than 1' );
			}
			# make sure we have something sane for secs
			if ( !defined( $opts{tcpdump_sets}{$set}{secs} ) ) {
				$opts{tcpdump_sets}{$set}{secs} = 10;
			} elsif ( $opts{tcpdump_sets}{$set}{secs} !~ /^[0-9]+$/ ) {
				die(      '$opts{tcpdump_sets}{'
						. $set
						. '}{secs} is set to "'
						. $opts{tcpdump_sets}{$set}{secs}
						. '" which not a positive integer' );
			} elsif ( $opts{tcpdump_sets}{$set}{secs} == 0 ) {
				die(      '$opts{tcpdump_sets}{'
						. $set
						. '}{secs} is set to "'
						. $opts{tcpdump_sets}{$set}{secs}
						. '" needs to be a positive integer equal to or greater than 1' );
			}
		} ## end if ( $opts{tcpdump_sets}{$set}{type} eq 'tcpdump')
	} ## end foreach my $set (@sets)

	my $self = {
		pcap_dir     => $opts{pcap_dir},
		stdout       => $opts{stdout},
		stderr_warn  => $opts{stderr_warn},
		tcpdump_sets => $opts{tcpdump_sets},
		sub_dir      => $opts{sub_dir},
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

	my @tcpdump_sets = keys( %{ $self->{tcpdump_sets} } );

	foreach my $set (@tcpdump_sets) {
		$self->log_message( status => 'Creating POE session for ' . $set );

		my $outfile = $set . '.pcap-%s';
		if ( $self->{sub_dir} ) {
			$outfile = $set . '/' . $outfile;
			eval { make_path( $self->{pcap_dir} . '/' . $set ) };
		} else {
			eval { make_path( $self->{pcap_dir} ) };
		}
		$outfile = $self->{pcap_dir} . '/' . $outfile;

		my $program
			= 'tcpdump -G '
			. $self->{tcpdump_sets}{$set}{secs} . ' -C '
			. $self->{tcpdump_sets}{$set}{size} . ' -w '
			. $outfile . ' '
			. $self->{tcpdump_sets}{$set}{args};

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
	} ## end foreach my $set (@tcpdump_sets)
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

	my @tcpdump_sets = keys( %{$Lamashtu::TCPDUMP_DH_HOLDER} );

	foreach my $set (@tcpdump_sets) {
		eval { $Lamashtu::TCPDUMP_DH_HOLDER->{$set}->restart_ctl( restart_ctl => 0 ); };
		eval { $Lamashtu::TCPDUMP_DH_HOLDER->{$set}->kill( signal => 'KILL' ); };
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
