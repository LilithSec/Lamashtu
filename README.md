# Lamashtu

Lamashtu is a Mesopotamian demoness, a daughter of the sky god Anu cast down
among mortals. She prowls unbidden, slips through gaps no door can close, and
seizes what she pleases — she takes, she carries off, and she keeps.

In the world above, Lamashtu is a packet capture manager. A `lamashtu` daemon
prowls one or more network interfaces and seizes a copy of everything that
crosses them, hoarding it in rotating pcap files. Each interface she stalks is a
capture *set*, one supervised `tcpdump` apiece; the daemon looses them, watches
them, and raises any that fall. A control socket lets you see her hoard and send
her after new prey while she runs.

She keeps company with [Ereshkigal](https://github.com/LilithSec/Ereshkigal),
who punishes, and [Baphomet](https://github.com/LilithSec/Baphomet), who
accuses. Lamashtu is the one who *remembers*: where they act on the traffic, she
records it, so that after the fact there are packets to read — and
[Virani](https://github.com/LilithSec/Virani), the dark one, is who reads them.
Given a span of time and a filter, Virani divines the matching traffic back out
of Lamashtu's hoard: Lamashtu seizes and keeps, Virani carves and answers.
Lamashtu answers to none of them and needs none of them — but she shares the
household's bones (a TOML config, a captures-in-*sets* layout) and stalks the
same network.

Setting her on two interfaces looks like this in `/usr/local/etc/lamashtu.toml`...

```toml
pcap_dir = "/var/log/lamashtu/pcap"

# each [sets.<name>] is one tcpdump; the interface is verified against `tcpdump -D`
[sets.wan]
interface = "igb0"
rotate    = "secs"     # a fresh file every `secs` seconds
secs      = 300

[sets.lan]
interface = "igb1"
rotate    = "size"     # a fresh file every `size` MiB
size      = 128
```

...and running her looks like this...

```shell
# loose her on every configured interface
lamashtu start

# see what she has seized and where it is piling up
lamashtu status --all

# set her on a new interface, right now
lamashtu add dmz --interface igb2 --rotate both --secs 600 --size 256

# call her off one interface
lamashtu remove dmz
```

The captures rotate on time (`tcpdump -G`), on size (`tcpdump -C`), or on
`both`, per set. See [docs/index.md](docs/index.md) for the whole story.

**A word of warning up front:** her hoard is raw traffic — credentials,
payloads, everything on the wire — and it grows without end unless you prune it.
Read [docs/security.md](docs/security.md) before you loose her anywhere real.

## Install

### From source

Dependencies are declared in Makefile.PL, so with
[cpanminus](https://metacpan.org/pod/App::cpanminus)...

```shell
cpanm --installdeps .
perl Makefile.PL
make
make test
make install
```

She needs `tcpdump` on the `PATH` and, in practice, root — capturing raw
packets and enumerating interfaces both want the privilege.

### FreeBSD

```shell
pkg install p5-App-Cmd p5-JSON-MaybeXS p5-Net-Server p5-POE \
    p5-String-ShellQuote p5-App-cpanminus tcpdump
cpanm TOML::Tiny POE::Component::Server::JSONUnix \
    POE::Wheel::Run::DaemonHelper Lamashtu
```

Startup script for running at boot [rc/freebsd/lamashtu](rc/freebsd/lamashtu).

### Debian

```shell
apt-get install libapp-cmd-perl libjson-maybexs-perl libnet-server-perl \
    libpoe-perl libstring-shellquote-perl libtoml-tiny-perl tcpdump cpanminus
cpanm POE::Component::Server::JSONUnix POE::Wheel::Run::DaemonHelper Lamashtu
```

Startup script for running at boot
[rc/systemd/lamashtu.service](rc/systemd/lamashtu.service).

## Documentation

To continue your journey go to [docs/index.md](docs/index.md).

Also...

- `perldoc Lamashtu`
- `perldoc Lamashtu::Config`
- `perldoc Lamashtu::Client`

## License

This software is Copyright (c) 2023 by Zane C. Bowers-Hadley, and is free
software licensed under the Artistic License 2.0 (GPL compatible).
