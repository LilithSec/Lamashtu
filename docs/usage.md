# Usage

Everything goes through the `lamashtu` CLI, which talks to the control socket.
The global `-s <path>` option points it at a non-default socket and works with
every subcommand...

```shell
lamashtu -s /var/run/lamashtu/socket status
```

Data commands print their result as pretty JSON and exit 0; errors print the
server's error text and exit nonzero, so the CLI scripts cleanly.

## Loosing and calling her off

```shell
lamashtu start                       # read the config, daemonize, loose every set
lamashtu start --foreground          # same, staying attached (for supervisors/testing)
lamashtu start --config /etc/l.toml
lamashtu stop                        # TERM every tcpdump, then wind the daemon down
```

## Seeing the hoard

```shell
lamashtu list                # just the set names
lamashtu status              # daemon uptime and pcap_dir, plus each set's up/down + PID
lamashtu status --all        # the above with every set's full status block
lamashtu status wan          # one set in detail... its interface, rotate/secs/size,
                             # whether it is up, PID, and when it started
```

## Setting her on new prey, and calling her off it

```shell
# loose a new set on igb2 right now, rotating on time or size
lamashtu add dmz --interface igb2 --rotate both --secs 600 --size 256

# rotate on size only, default 32 MiB
lamashtu add cap --interface igb3 --rotate size

# just igb0, with a filter
lamashtu add web --interface igb0 --args "tcp port 443"

lamashtu restart web         # bounce a set's tcpdump (new file starts)
lamashtu remove web          # TERM its tcpdump and deregister the set
```

`add` runs the same checks as the config — the interface must be listed by
`tcpdump -D` unless `verify_interfaces` is off — and `--interface` defaults to
the set name if omitted. None of these edit `lamashtu.toml`: a set added at
runtime vanishes on the next restart unless you also add it to the file, and a
removed one returns unless you delete it from there.

## Reloading the config

```shell
lamashtu reload              # re-read the config and reconcile the running sets
```

`reload` re-validates the whole config first and changes nothing if it is bad, so
a broken edit cannot take the daemon down. Otherwise it adds sets that appeared,
removes sets that vanished, and bounces sets whose definition changed. Daemon
level settings (`pcap_dir`, `socket_*`, ...) are not re-applied by `reload`; a
change to those wants a restart.

## Driving the socket directly

Integrations do not need the CLI. The control socket speaks newline-delimited
JSON: send one object, read one back.

```
{"command":"status_set","args":{"set":"wan"}}
```

A shell one-liner...

```shell
printf '%s\n' '{"command":"list"}' | nc -U /var/run/lamashtu/socket
```

From perl, `Lamashtu::Client` handles the framing and timeouts...

```perl
use Lamashtu::Client;

my $client = Lamashtu::Client->new(
    socket => '/var/run/lamashtu/socket',
);

# dies on error responses, returns the result
my $result = $client->call_ok( 'add_set',
    { set => 'dmz', def => { interface => 'igb2', rotate => 'both', secs => 600, size => 256 } } );

# or handle the envelope yourself
my $response = $client->call('status');
if ( $response->{status} eq 'ok' ) { ... }
```

The commands mirror the CLI: `status`, `status_all`, `status_set`
(`{"set":...}`), `list`, `restart` (`{"set":...}`), `add_set` (`{"set":...,
"def":{...}}`), `remove_set` (`{"set":...}`), `reload`, and `stop`. Responses are
`{"status":"ok","result":...}` or `{"status":"error","error":"..."}`.

## Reading what she captured

The `lamashtu` CLI only manages the *capturing* — it does not read the pcaps
back. For that, hand the hoard to [Virani](https://github.com/LilithSec/Virani),
the household's reader, which carves matching traffic out of a directory of pcaps
by time range and BPF filter. See
[architecture](architecture.md#making-the-hoard-searchable-by-virani) and
[examples](examples.md#reading-the-hoard-back-with-virani) for wiring a Virani
set onto a Lamashtu set.
