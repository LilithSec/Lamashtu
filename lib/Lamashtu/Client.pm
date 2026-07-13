package Lamashtu::Client;

use 5.006;
use strict;
use warnings;
use IO::Socket::UNIX ();
use JSON::MaybeXS qw( encode_json decode_json );
use File::Temp ();

=head1 NAME

Lamashtu::Client - blocking Unix-socket JSON client for the Lamashtu daemon.

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1';

=head1 SYNOPSIS

    use Lamashtu::Client;

    my $client = Lamashtu::Client->new( socket => '/var/run/lamashtu/socket' );

    my $result = $client->call_ok( 'restart', { set => 'em0' } );

Speaks the newline-delimited JSON protocol of
L<POE::Component::Server::JSONUnix>: one C<< {"command":...,"args":...} >> per
request, one C<< {"status":...,"result"|"error":...} >> per reply.

=head1 METHODS

=head2 new

    - socket  :: path to the daemon control socket. Required.
    - timeout :: seconds before a call aborts. Default :: 30

=cut

sub new {
	my ( $blank, %opts ) = @_;

	die('No socket specified') if !defined( $opts{socket} );

	my $self = {
		socket  => $opts{socket},
		timeout => defined( $opts{timeout} ) ? $opts{timeout} : 30,
	};
	bless $self;

	return $self;
}

=head2 call

    my $response = $client->call( $command, \%args );

Sends one command and returns the decoded response hashref (with C<status> and
either C<result> or C<error>). Dies on connect/timeout/protocol failure.

=cut

sub call {
	my ( $self, $command, $args ) = @_;

	die('No command specified') if !defined($command);

	my $response;
	eval {
		local $SIG{ALRM} = sub { die( "timed out after " . $self->{timeout} . " seconds\n" ); };
		alarm( $self->{timeout} );

		my $sock = IO::Socket::UNIX->new(
			Type => IO::Socket::UNIX::SOCK_STREAM(),
			Peer => $self->{socket},
		) || die( 'connect to ' . $self->{socket} . ' failed: ' . $! );

		my $request = { command => $command };
		$request->{args} = $args if defined($args);

		$response = $self->_send_request( $sock, $request );

		# the daemon's Neti gate (enable_auth) rejects the first command with
		# "authentication required"; auth state is per connection, so complete
		# the unix-ownership challenge on this same socket and resend.
		if (   defined( $response->{status} )
			&& $response->{status} eq 'error'
			&& defined( $response->{error} )
			&& $response->{error} =~ /^authentication required/ )
		{
			$self->_authenticate($sock);
			$response = $self->_send_request( $sock, $request );
		}

		close($sock);
		alarm(0);
	};
	my $error = $@;
	alarm(0);
	die($error) if $error;

	return $response;
}

# sends one request on the socket and returns the decoded response hashref
sub _send_request {
	my ( $self, $sock, $request ) = @_;

	print $sock encode_json($request) . "\n";
	my $line = <$sock> || die( 'no response from ' . $self->{socket} );
	my $response = decode_json($line);
	die('response is not a JSON object') if ref($response) ne 'HASH';

	return $response;
}

# completes the POE::Component::Server::JSONUnix unix-ownership challenge on the
# passed connection: auth_start hands back a cookie and a temp dir, we write the
# cookie to a file there (which we own -- that ownership is the proof), and point
# auth_verify at it.
sub _authenticate {
	my ( $self, $sock ) = @_;

	my $start = $self->_send_request( $sock, { command => 'auth_start' } );
	if ( !defined( $start->{status} ) || $start->{status} ne 'ok' ) {
		die( 'auth_start failed: ' . ( $start->{error} // 'unknown error' ) . "\n" );
	}
	my $cookie   = $start->{result}{cookie};
	my $temp_dir = $start->{result}{temp_dir};
	die("auth_start did not return a cookie and temp_dir\n") if !defined($cookie) || !defined($temp_dir);

	my ( $cookie_fh, $cookie_file )
		= File::Temp::tempfile( 'lamashtu-auth-XXXXXXXX', DIR => $temp_dir, UNLINK => 0 );
	print $cookie_fh $cookie;
	close($cookie_fh);

	my $verify;
	eval { $verify = $self->_send_request( $sock, { command => 'auth_verify', args => { path => $cookie_file } } ); };
	my $verify_error = $@;
	# the server unlinks it on success; make sure it is gone either way
	unlink($cookie_file) if -e $cookie_file;
	die($verify_error) if $verify_error;

	if ( !defined( $verify->{status} ) || $verify->{status} ne 'ok' ) {
		die( 'auth_verify failed: ' . ( $verify->{error} // 'unknown error' ) . "\n" );
	}

	return;
}

=head2 call_ok

    my $result = $client->call_ok( $command, \%args );

Like L</call> but dies with the server error string unless C<status> is C<ok>,
returning just the C<result> payload.

=cut

sub call_ok {
	my ( $self, $command, $args ) = @_;

	my $response = $self->call( $command, $args );
	if ( !defined( $response->{status} ) || $response->{status} ne 'ok' ) {
		die( ( $response->{error} // 'unknown error' ) . "\n" );
	}

	return $response->{result};
}

=head1 AUTHOR

Zane C. Bowers-Hadley, C<< <vvelox at vvelox.net> >>

=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2023 by Zane C. Bowers-Hadley.

This is free software, licensed under The Artistic License 2.0 (GPL Compatible).

=cut

1;
