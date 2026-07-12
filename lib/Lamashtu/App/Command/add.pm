package Lamashtu::App::Command::add;

use 5.006;
use strict;
use warnings;
use Lamashtu::App -command;
use Lamashtu::Client ();
use JSON::MaybeXS ();

our $VERSION = '0.0.1';

sub abstract { return 'define and start a new capture set at runtime' }

sub usage_desc { return '%c add %o <set>'; }

sub opt_spec {
	return (
		[ 'type=s',      'set type: tcpdump or command', { default => 'tcpdump' } ],
		[ 'interface=s', 'capture interface (verified against `tcpdump -D`); defaults to the set name' ],
		[ 'rotate=s',    'rotate on "secs" (-G), "size" (-C), or "both"' ],
		[ 'args=s',      'extra tcpdump args (must not include -C/-G/-w/-W/-i)' ],
		[ 'secs=i',      'rotate seconds (tcpdump -G); used when rotate=secs' ],
		[ 'size=i',      'rotate size in MiB (tcpdump -C); used when rotate=size' ],
		[ 'program=s',   'program to run when --type=command' ],
	);
}

sub validate_args {
	my ( $self, $opt, $args ) = @_;

	$self->usage_error('exactly one set name is required') if @{$args} != 1;
	$self->usage_error('set name must match /^[0-9A-Za-z_]+$/')
		if $args->[0] !~ /^[0-9A-Za-z_]+$/;

	return;
}

sub execute {
	my ( $self, $opt, $args ) = @_;

	my $set = { type => $opt->type };
	$set->{interface} = $opt->interface if defined $opt->interface;
	$set->{rotate}    = $opt->rotate    if defined $opt->rotate;
	$set->{args}      = $opt->args      if defined $opt->args;
	$set->{secs}      = $opt->secs      if defined $opt->secs;
	$set->{size}      = $opt->size      if defined $opt->size;
	$set->{program}   = $opt->program   if defined $opt->program;

	my $client = Lamashtu::Client->new( socket => $self->app->global_options->{socket} );
	my $result = $client->call_ok( 'add_set', { set => $args->[0], def => $set } );

	print JSON::MaybeXS->new( pretty => 1, canonical => 1 )->encode($result);

	return;
}

1;
