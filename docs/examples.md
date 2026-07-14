# Examples

Worked scenarios to copy from. Paths assume the defaults; adjust to taste. Mind
[security](security.md) before any of these touch real traffic.

## Capture the WAN uplink, rotating every five minutes

`/usr/local/etc/lamashtu.toml`...

```toml
pcap_dir     = "/var/log/lamashtu/pcap"
socket_group = "wheel"

[sets.wan]
interface = "igb0"
rotate    = "secs"
secs      = 300
```

```shell
lamashtu start
lamashtu status wan
```

Every five minutes a fresh `wan/wan.pcap-<epoch>` begins. The old files stay
until you prune them.

## One set per interface, rotating by size

```toml
socket_group = "wheel"
rotate       = "size"           # the default all sets inherit

[sets.wan]
interface = "igb0"
size      = 256

[sets.lan]
interface = "igb1"
size      = 128
args      = "tcp port 80 or tcp port 443"   # only the web traffic

[sets.dmz]
interface = "igb2"
rotate    = "both"              # override: time OR size, whichever first
secs      = 600
size      = 256
```

`lamashtu status --all` shows all three at once.

## Setting her on an interface at runtime

```shell
# loose a capture on igb3 right now, 512 MiB files, ssh excluded
lamashtu add mgmt --interface igb3 --rotate size --size 512 --args "not port 22"

lamashtu status mgmt

# start a fresh file on demand
lamashtu restart mgmt

# call her off... TERM the tcpdump and forget the set
lamashtu remove mgmt
```

None of these edit `lamashtu.toml` — to keep the `mgmt` set across restarts, add
its `[sets.mgmt]` hash to the config.

## Reloading after a config edit

```shell
$EDITOR /usr/local/etc/lamashtu.toml     # add/remove/adjust some [sets.*]
lamashtu reload                          # reconcile without a restart
```

If the edited config does not parse or a set is invalid (say an interface
`tcpdump -D` doesn't list), `reload` reports the error and changes nothing — the
running captures keep going.

## A capture of pure imagination

The `command` set type runs a program verbatim instead of tcpdump and skips the
interface check, so everything can be tried unprivileged...

```toml
pcap_dir     = "/tmp/lamashtu-play/pcap"
run_dir      = "/tmp/lamashtu-play/run"
socket_group = "wheel"          # any group you are in

[sets.selftest]
type    = "command"
program = "cat"
```

```shell
lamashtu start --config ./play.toml --foreground &
lamashtu -s /tmp/lamashtu-play/run/socket list
lamashtu -s /tmp/lamashtu-play/run/socket add two --type command --program cat
lamashtu -s /tmp/lamashtu-play/run/socket status --all
lamashtu -s /tmp/lamashtu-play/run/socket stop
```

No root, no interface, no tcpdump — just the supervision and the socket, which is
exactly what the test suite exercises.

## Reading the hoard back with Virani

Lamashtu writes; [Virani](https://github.com/LilithSec/Virani) reads. Point a
Virani set at the directory a Lamashtu set fills and she can carve traffic back
out of it by time and BPF filter. This only works by time when the pcap names
carry a timestamp, so capture with `rotate = "secs"` or `"both"` (which stamp the
`%s` epoch into the filename).

Lamashtu side...

```toml
[sets.wan]
interface = "igb0"
rotate    = "secs"       # names files wan.pcap-<epoch>
secs      = 300
```

Virani side, in `virani.toml`...

```toml
default_set = "wan"

[sets.wan]
path     = "/var/log/lamashtu/pcap/wan"     # pcap_dir + set name (sub_dir on)
regex    = '\.pcap-(?<timestamp>\d+)$'       # match the epoch Lamashtu stamped
strptime = "%s"
```

Then...

```shell
# all port 53 traffic Lamashtu captured in the last hour
virani -t wan -s now-1h -e now port 53
```

A `rotate = "size"` Lamashtu set names files with a counter and no timestamp, so
Virani can still filter their contents but cannot narrow by time — pick `secs` or
`both` for anything you intend to search by time.

## Pruning the hoard

Lamashtu never deletes; do it outside her. A daily cron sweep of anything older
than a week...

```sh
#!/bin/sh
# /etc/periodic/daily/500.lamashtu-prune  (or a cron entry)
find /var/log/lamashtu/pcap -type f -name '*.pcap*' -mtime +7 -delete
```

Size it to your disk and your retention needs — see [security](security.md)
for why holding less is holding less liability.
