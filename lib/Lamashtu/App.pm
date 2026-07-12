package Lamashtu::App;

use 5.006;
use strict;
use warnings;
use App::Cmd::Setup -app;

=head1 NAME

Lamashtu::App - App::Cmd front end for the Lamashtu PCAP daemon.

=head1 VERSION

Version 0.0.1

=cut

our $VERSION = '0.0.1';

=head1 DESCRIPTION

Dispatches the C<lamashtu> subcommands (see C<lib/Lamashtu/App/Command/>). Every
subcommand except C<start> talks to a running daemon over the control socket
named by the global C<--socket> option.

=head2 global_opt_spec

Adds C<--socket>/C<-s>, available to every subcommand.

=cut

sub global_opt_spec {
	return ( [ 'socket|s=s', 'path of the control socket', { default => '/var/run/lamashtu/socket' } ], );
}

=head1 AUTHOR

Zane C. Bowers-Hadley, C<< <vvelox at vvelox.net> >>

=head1 LICENSE AND COPYRIGHT

This software is Copyright (c) 2023 by Zane C. Bowers-Hadley.

This is free software, licensed under The Artistic License 2.0 (GPL Compatible).

=cut

1;
