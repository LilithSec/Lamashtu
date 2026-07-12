package Lamashtu::App::Command::reload;

use 5.006;
use strict;
use warnings;
use Lamashtu::App -command;
use Lamashtu::Client ();
use JSON::MaybeXS ();

our $VERSION = '0.0.1';

sub abstract { return 'reload the config, reconciling capture sets' }

sub usage_desc { return '%c reload %o'; }

sub validate_args {
	my ( $self, $opt, $args ) = @_;

	$self->usage_error('reload takes no args') if @{$args};

	return;
}

sub execute {
	my ( $self, $opt, $args ) = @_;

	my $client = Lamashtu::Client->new( socket => $self->app->global_options->{socket} );
	my $result = $client->call_ok('reload');

	print JSON::MaybeXS->new( pretty => 1, canonical => 1 )->encode($result);

	return;
}

1;
