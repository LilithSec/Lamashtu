package Lamashtu::App::Command::status;

use 5.006;
use strict;
use warnings;
use Lamashtu::App -command;
use Lamashtu::Client ();
use JSON::MaybeXS ();

our $VERSION = '0.0.1';

sub abstract { return 'show status of the daemon and its capture sets' }

sub description { return 'Query the running daemon and print its status as JSON.'; }

sub usage_desc { return '%c status %o [<set>]'; }

sub opt_spec {
	return ( [ 'all', 'include full status of every capture set' ], );
}

sub validate_args {
	my ( $self, $opt, $args ) = @_;

	$self->usage_error('status takes at most one set name') if @{$args} > 1;
	$self->usage_error('--all and a set name may not be used together')
		if @{$args} && $opt->all;

	return;
}

sub execute {
	my ( $self, $opt, $args ) = @_;

	my $client = Lamashtu::Client->new( socket => $self->app->global_options->{socket} );

	my $result;
	if ( @{$args} ) {
		$result = $client->call_ok( 'status_set', { set => $args->[0] } );
	} elsif ( $opt->all ) {
		$result = $client->call_ok('status_all');
	} else {
		$result = $client->call_ok('status');
	}

	print JSON::MaybeXS->new( pretty => 1, canonical => 1 )->encode($result);

	return;
}

1;
