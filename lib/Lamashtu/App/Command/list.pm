package Lamashtu::App::Command::list;

use 5.006;
use strict;
use warnings;
use Lamashtu::App -command;
use Lamashtu::Client ();
use JSON::MaybeXS ();

our $VERSION = '0.0.1';

sub abstract { return 'list the configured capture sets' }

sub usage_desc { return '%c list %o'; }

sub validate_args {
	my ( $self, $opt, $args ) = @_;

	$self->usage_error('list takes no args') if @{$args};

	return;
}

sub execute {
	my ( $self, $opt, $args ) = @_;

	my $client = Lamashtu::Client->new( socket => $self->app->global_options->{socket} );
	my $result = $client->call_ok('list');

	print JSON::MaybeXS->new( pretty => 1, canonical => 1 )->encode($result);

	return;
}

1;
