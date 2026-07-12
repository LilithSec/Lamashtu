# Configuration

The config file is TOML, by default `/usr/local/etc/lamashtu.toml` (overridable
with `lamashtu start --config <path>`). Top level keys are daemon settings; each
hash under `sets` defines one capture set, named for the hash — the hash at
`sets.wan` is the set `wan`. Names must match `/^[0-9A-Za-z_]+$/`.

## Daemon settings

| key                 | default                  | what                                                       |
|---------------------|--------------------------|------------------------------------------------------------|
| `pcap_dir`          | `/var/log/lamashtu/pcap` | where the captures are hoarded                             |
| `run_dir`           | `/var/run/lamashtu`      | the control socket and PID file live under here            |
| `socket_group`      | root's default group     | group ownership of the control socket                      |
| `socket_mode`       | `"0660"`                 | perms on the control socket, as a string, processed via oct |
| `sub_dir`           | `true`                   | give each set its own directory under `pcap_dir`           |
| `verify_interfaces` | `true`                   | check each set's interface against `tcpdump -D`            |
| `rotate`            | `"secs"`                 | default rotation dimension for sets that omit one          |
| `stdout`            | `false`                  | also print log lines to stdout, not only syslog            |
| `stderr_warn`       | `false`                  | send error log lines to stderr as warnings                 |

## Set settings

Inside a `[sets.<name>]` hash...

| key         | what                                                                              |
|-------------|-----------------------------------------------------------------------------------|
| `type`      | `tcpdump` (default) or `command`                                                  |
| `interface` | capture interface; defaults to the set name. Verified against `tcpdump -D`.        |
| `rotate`    | `secs` (-G), `size` (-C), or `both`. Defaults to the top level `rotate`, else `secs`. |
| `secs`      | rotate seconds (`tcpdump -G`); used when rotate is `secs` or `both`. Default `10`. |
| `size`      | rotate MiB (`tcpdump -C`); used when rotate is `size` or `both`. Default `32`.     |
| `args`      | optional extra tcpdump flags/filter, e.g. `"tcp port 443"`. May **not** contain `-C/-G/-w/-W/-i`. |
| `program`   | required when `type = command`; the program to run verbatim instead of tcpdump.    |

The daemon builds the tcpdump command itself — `-w <pcap>`, `-i <interface>`, and
the rotation flag(s) are injected. That is why those flags are forbidden in
`args`: `args` is only the filter/extra flags you want on top.

## How rotate layers

    per-set rotate  >  top level rotate  >  "secs"

Only the value(s) the chosen mode uses are defaulted and validated: `rotate =
secs` needs a valid `secs`, `rotate = size` needs a valid `size`, `rotate = both`
needs both. An unused knob may be absent.

Filenames follow the mode: with `-G` present (`secs` or `both`) the `-w` template
carries a `%s` epoch stamp (`wan.pcap-<epoch>`); with `size` alone tcpdump
appends an incrementing counter instead (`wan.pcap1`, `wan.pcap2`, ...).

## Set types

- **tcpdump** — the real thing: a supervised `tcpdump` writing rotating pcaps.
- **command** — runs `program` verbatim under the same supervision, ignoring the
  tcpdump-specific keys and skipping the interface check. It is the seam that
  lets the daemon and its control socket be exercised without root or a live
  interface (the test suite uses `cat`), and it is handy for a quick unprivileged
  try (see [examples.md](examples.md)).

## A complete example

```toml
# the daemon
pcap_dir          = "/var/log/lamashtu/pcap"
run_dir           = "/var/run/lamashtu"
socket_group      = "wheel"     # who may drive her, via group membership on the socket
socket_mode       = "0660"
sub_dir           = true        # a directory per set under pcap_dir
verify_interfaces = true        # refuse a set whose interface tcpdump -D doesn't list
rotate            = "secs"      # the default a set inherits

# the WAN uplink, a fresh file every five minutes
[sets.wan]
interface = "igb0"
rotate    = "secs"
secs      = 300

# the LAN, rotating by size, and only the interesting ports
[sets.lan]
interface = "igb1"
rotate    = "size"
size      = 128
args      = "tcp port 80 or tcp port 443"

# the DMZ, rotating on whichever of time or size trips first
[sets.dmz]
interface = "igb2"
rotate    = "both"
secs      = 600
size      = 256
```

Config changes take effect on `lamashtu reload` or a restart. Sets added at
runtime with `lamashtu add` are not written back to this file — to make one
permanent, add its hash here.
