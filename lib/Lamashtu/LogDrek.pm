package Lamashtu::LogDrek;

use 5.006;
use strict;
use warnings;
use Sys::Syslog qw( closelog openlog syslog );
use Exporter qw( import );

our @EXPORT_OK = qw( log_drek );

=head1 NAME

Lamashtu::LogDrek - syslog helper for Lamashtu.

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1';

=head1 SYNOPSIS

    use Lamashtu::LogDrek qw( log_drek );

    log_drek( 'info', 'started' );
    log_drek( 'err',  'capture set em0 died' );
    log_drek( 'info', 'consigned a set', undef, 'lamashtu-em0' );

=head1 SUBROUTINES

=head2 log_drek

    log_drek( $level, $message, $tracking_int, $ident );

    - $level        :: syslog level. Default :: 'info'
    - $message      :: message text. Default :: ''
    - $tracking_int :: optional request id, prepended to the message.
    - $ident        :: syslog ident. Default :: 'lamashtu'

Logs to the C<daemon> facility. Wrapped in an eval so logging never kills the
daemon.

=cut

sub log_drek {
	my ( $level, $message, $tracking_int, $ident ) = @_;

	$level   //= 'info';
	$message //= '';
	$message = $tracking_int . ' : ' . $message if defined $tracking_int;
	$ident //= 'lamashtu';

	eval {
		openlog( $ident, 'cons,pid', 'daemon' );
		syslog( $level, '%s', $message );
		closelog();
	};

	return;
}

=head1 AUTHOR

Zane C. Bowers-Hadley, C<< <vvelox at vvelox.net> >>

=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2023 by Zane C. Bowers-Hadley.

This is free software, licensed under The Artistic License 2.0 (GPL Compatible).

=cut

1;
