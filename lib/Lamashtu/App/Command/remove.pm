package Lamashtu::App::Command::remove;

use 5.006;
use strict;
use warnings;
use Lamashtu::App -command;
use Lamashtu::Client ();
use JSON::MaybeXS ();

our $VERSION = '0.0.1';

sub abstract { return 'stop and forget a capture set' }

sub usage_desc { return '%c remove %o <set>'; }

sub validate_args {
	my ( $self, $opt, $args ) = @_;

	$self->usage_error('exactly one set name is required') if @{$args} != 1;

	return;
}

sub execute {
	my ( $self, $opt, $args ) = @_;

	my $client = Lamashtu::Client->new( socket => $self->app->global_options->{socket} );
	my $result = $client->call_ok( 'remove_set', { set => $args->[0] } );

	print JSON::MaybeXS->new( pretty => 1, canonical => 1 )->encode($result);

	return;
}

1;
