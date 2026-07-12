# Lamashtu documentation

Lamashtu is a Mesopotamian demoness who prowls, seizes, and keeps. In the world
above she is a packet capture manager: a daemon that stalks one or more network
interfaces, seizes a copy of everything crossing them with a supervised
`tcpdump`, and hoards it in rotating pcap files.

She is a member of the LilithSec household alongside
[Ereshkigal](https://github.com/LilithSec/Ereshkigal) (the firewall ban manager,
the punisher), [Baphomet](https://github.com/LilithSec/Baphomet) (the log
watcher, the accuser), and [Virani](https://github.com/LilithSec/Virani) (the
dark one, who reads and searches the captures). Lamashtu is the one who
remembers — the forensic memory of the network; Virani is the one who reads that
memory. She depends on none of them, but shares their architecture and stands
beside them; see [architecture.md](architecture.md) for how she relates.

- [architecture.md](architecture.md) :: the one daemon, its supervised tcpdumps,
  the control socket and protocol, how the pcaps rotate, and where Lamashtu sits
  in the pantheon

- [install.md](install.md) :: dependencies in detail, per-OS install, and
  running at boot

- [configuration.md](configuration.md) :: the `lamashtu.toml` reference and a
  complete example

- [usage.md](usage.md) :: commanding Lamashtu via the CLI or the socket

- [security.md](security.md) :: the heavy part — pcaps are raw traffic, disks
  fill, capture has consequences

- [examples.md](examples.md) :: copy-paste scenarios

Also...

- `perldoc Lamashtu`
- `perldoc Lamashtu::Config`
- `perldoc Lamashtu::Client`
