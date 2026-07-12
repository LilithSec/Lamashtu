# Architecture

## The shape of it

```
                 /usr/local/etc/lamashtu.toml
                              |
                              v
  lamashtu(1) ------- the one daemon
   App::Cmd CLI        |  socket: /var/run/lamashtu/socket
                       |  pid:    /var/run/lamashtu/pid
                       |
                       |  supervises, in-process (POE::Wheel::Run::DaemonHelper)
          +------------+------------+
          v                         v
     set "wan"                 set "lan"
     tcpdump -G 300 ...        tcpdump -C 128 ...
      -i igb0                   -i igb1
          |                         |
          v                         v
   /var/log/lamashtu/pcap/   /var/log/lamashtu/pcap/
     wan/wan.pcap-<epoch>      lan/lan.pcap1, .pcap2, ...
```

Unlike her siblings — where an `ereshkigal` or `baphomet` manager spawns a
separate worker *process* per unit — Lamashtu is a **single daemon**. Each
capture set is a `tcpdump` supervised **in-process** by
[POE::Wheel::Run::DaemonHelper](https://metacpan.org/pod/POE::Wheel::Run::DaemonHelper),
so there is one process, one PID, one socket. The daemon reads the config, looses
one tcpdump per `[sets.<name>]`, watches them, and serves a control socket
alongside them under the same POE kernel.

## What lives where

| path                                          | what                                          |
|-----------------------------------------------|-----------------------------------------------|
| `/usr/local/etc/lamashtu.toml`                | the config                                    |
| `/var/run/lamashtu/socket`                    | the control socket (mode 0660, configured group) |
| `/var/run/lamashtu/pid`                       | the daemon PID                                |
| `/var/log/lamashtu/pcap/<set>/<set>.pcap-...` | a set's hoard (with `sub_dir`, the default)   |
| `/var/log/lamashtu/pcap/<set>.pcap-...`       | a set's hoard (with `sub_dir = false`)        |

`pcap_dir` and `run_dir` are configurable; the layout under them is not.

## Supervision

Each set's tcpdump is run under `DaemonHelper`, which watches the child and, with
an exponential backoff, raises it again if it falls — a prowl that dies is
loosed anew. `status` reports whether each set is currently up and its PID. On
`stop` (or `SIGINT`/`SIGTERM`), the daemon disables restart on every set, sends
each tcpdump a `TERM`, closes the socket, and lets the kernel wind down.

## The protocol

The control socket speaks the newline-delimited JSON of
[POE::Component::Server::JSONUnix](https://metacpan.org/pod/POE::Component::Server::JSONUnix):
one JSON object per line in each direction.

```
-> {"command":"restart","args":{"set":"wan"}}
<- {"status":"ok","result":{"set":"wan","restarted":1}}

-> {"command":"status_set","args":{"set":"nope"}}
<- {"status":"error","error":"no such set \"nope\""}
```

The commands are `status`, `status_all`, `status_set`, `list`, `restart`,
`add_set`, `remove_set`, `reload`, and `stop`. See [usage.md](usage.md) for
driving the socket from your own integrations.

## Sets, interfaces, and rotation

A set is one tcpdump. The daemon injects `-w` (the pcap path), `-i` (the
interface), and the rotation flag(s); the set's `args` are appended as an
optional extra filter and may not carry `-C/-G/-w/-W/-i` themselves.

The `interface` is checked against `tcpdump -D` before a set is created — at
startup, at `reload`, and for a set added at runtime. An interface the local
tcpdump does not list is refused, with the available names in the error. This can
be turned off with `verify_interfaces = false` (for hosts without tcpdump, or an
interface that only appears later).

`rotate` picks when a fresh pcap begins:

- `secs` → `tcpdump -G <secs>`, time based. The `-w` name uses a strftime
  template, so files carry a `%s` epoch stamp: `wan.pcap-1720000000`.
- `size` → `tcpdump -C <size>`, size based (MiB). tcpdump appends an
  incrementing counter, so no `%s`: `lan.pcap1`, `lan.pcap2`, ...
- `both` → both flags; a new file whenever either limit trips first (the `%s`
  name is kept, since `-G` is present).

## Runtime changes

`add_set`, `remove_set`, and `reload` change the running herd without a restart.
`add_set` and `reload` run the same validation as config load — the `tcpdump -D`
interface check included — so a set added over the socket is checked exactly like
one from the file. `reload` re-reads the config and dies before touching anything
if the new file is bad, so a broken edit cannot take the daemon down; otherwise
it adds what appeared, removes what vanished, and bounces sets whose definition
changed. None of these write back to the config — a runtime `add` vanishes on the
next restart unless you also add its `[sets.<name>]` hash to the file.

## Where Lamashtu sits in the pantheon

The LilithSec tools share a family resemblance — a TOML config, captures or units
kept in named *sets* — but play different parts on the same network:

- **[Baphomet](https://github.com/LilithSec/Baphomet)** reads the logs and
  *accuses*: it consigns repeat offenders to Ereshkigal.
- **[Ereshkigal](https://github.com/LilithSec/Ereshkigal)** works the firewall
  and *punishes*: it holds the banned and releases them when their time is up.
- **Lamashtu** *remembers*: she keeps the packets, so that when Baphomet flags an
  IP and Ereshkigal bans it, the traffic that earned it is already on disk.
- **[Virani](https://github.com/LilithSec/Virani)**, the dark one, *reads*: given
  a span of time and a BPF filter she finds the pcaps overlapping that window,
  carves the matching packets back out with tcpdump/tshark, and hands you the
  distilled capture (over the CLI, or over HTTP via `mojo-virani`).

Baphomet and Ereshkigal are wired together (bans flow from one to the other);
Lamashtu and Virani are wired only by the pcaps on disk. Lamashtu is the *writer*
of the hoard and Virani the *reader* of it — she never calls Virani and Virani
never calls her; Virani just points a set at the directory Lamashtu fills.

### Making the hoard searchable by Virani

Virani time-ranges its search off the timestamp in each pcap's **filename**, so
for her to read a Lamashtu set by time, the names must carry one — use
`rotate = "secs"` or `"both"`, which stamp the file with a `%s` epoch
(`wan.pcap-1720000000`). A `rotate = "size"` set names files `wan.pcap1`,
`wan.pcap2`, ... with no timestamp; Virani can still filter their contents but
cannot narrow by time. A matching Virani set looks like:

```toml
# in virani.toml — read what Lamashtu's "wan" set writes
[sets.wan]
path     = "/var/log/lamashtu/pcap/wan"     # Lamashtu's pcap_dir + set (sub_dir on)
regex    = '\.pcap-(?<timestamp>\d+)$'       # the %s Lamashtu stamped in
strptime = "%s"
```

Then `virani -t wan -s now-1h -e now port 53` pulls the last hour of port-53
traffic out of what Lamashtu captured. See
[Virani](https://github.com/LilithSec/Virani) for the rest.

## The bits and pieces

| module              | what                                                              |
|---------------------|-------------------------------------------------------------------|
| `Lamashtu`          | the daemon: config-to-object, tcpdump supervision, the socket + control handlers |
| `Lamashtu::Config`  | TOML load, set validation, and the `tcpdump -D` interface check   |
| `Lamashtu::Client`  | a small blocking Unix-socket JSON client                          |
| `Lamashtu::LogDrek` | the syslog helper                                                 |
| `Lamashtu::App`     | the `App::Cmd` application and its subcommands                    |
