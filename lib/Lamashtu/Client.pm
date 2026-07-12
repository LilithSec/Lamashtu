package Lamashtu::Client;

use 5.006;
use strict;
use warnings;
use IO::Socket::UNIX ();
use JSON::MaybeXS qw( encode_json decode_json );

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

		print $sock encode_json($request) . "\n";
		my $line = <$sock> || die( 'no response from ' . $self->{socket} );
		$response = decode_json($line);

		close($sock);
		alarm(0);
	};
	my $error = $@;
	alarm(0);
	die($error) if $error;

	return $response;
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
