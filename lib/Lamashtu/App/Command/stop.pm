package Lamashtu::App::Command::stop;

use 5.006;
use strict;
use warnings;
use Lamashtu::App -command;
use Lamashtu::Client ();
use JSON::MaybeXS ();

our $VERSION = '0.0.1';

sub abstract { return 'stop the running daemon' }

sub usage_desc { return '%c stop %o'; }

sub validate_args {
	my ( $self, $opt, $args ) = @_;

	$self->usage_error('stop takes no args') if @{$args};

	return;
}

sub execute {
	my ( $self, $opt, $args ) = @_;

	my $client = Lamashtu::Client->new( socket => $self->app->global_options->{socket} );
	my $result = $client->call_ok('stop');

	print JSON::MaybeXS->new( pretty => 1, canonical => 1 )->encode($result);

	return;
}

1;
