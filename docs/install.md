# Installation

## Dependencies

| CPAN module                         | FreeBSD pkg           | Debian pkg                |
|-------------------------------------|-----------------------|---------------------------|
| App::Cmd                            | p5-App-Cmd            | libapp-cmd-perl           |
| JSON::MaybeXS                       | p5-JSON-MaybeXS       | libjson-maybexs-perl      |
| Net::Server (Net::Server::Daemonize)| p5-Net-Server         | libnet-server-perl        |
| POE                                 | p5-POE                | libpoe-perl               |
| POE::Component::Server::JSONUnix    | (cpanm)               | (cpanm)                   |
| POE::Wheel::Run::DaemonHelper       | (cpanm)               | (cpanm)                   |
| String::ShellQuote                  | p5-String-ShellQuote  | libstring-shellquote-perl |
| TOML::Tiny                          | (cpanm)               | libtoml-tiny-perl         |

Plus `tcpdump` itself on the `PATH`, and Sys::Syslog (core).

Test-time only: Test::More (core) and App::Cmd::Tester (ships with App::Cmd).

Package names are current as of writing. Anything marked `(cpanm)` — or missing
from your release — installs cleanly from CPAN via
[cpanminus](https://metacpan.org/pod/App::cpanminus).

## From source

From a checkout or an unpacked release tarball...

```shell
cpanm --installdeps .
perl Makefile.PL
make
make test
make install
```

The test suite never invokes `tcpdump` for real capture (it uses a `command`
type set and skips the `tcpdump -D` check), so `make test` runs unprivileged.

## FreeBSD

```shell
pkg install p5-App-Cmd p5-JSON-MaybeXS p5-Net-Server p5-POE \
    p5-String-ShellQuote p5-App-cpanminus tcpdump
cpanm TOML::Tiny POE::Component::Server::JSONUnix \
    POE::Wheel::Run::DaemonHelper
```

## Debian

```shell
apt-get install libapp-cmd-perl libjson-maybexs-perl libnet-server-perl \
    libpoe-perl libstring-shellquote-perl libtoml-tiny-perl tcpdump \
    cpanminus build-essential
cpanm POE::Component::Server::JSONUnix POE::Wheel::Run::DaemonHelper
```

## First run

Write a config (see [configuration](configuration.md)), then...

```shell
lamashtu start
lamashtu status
```

`start` reads `/usr/local/etc/lamashtu.toml`, daemonizes, and looses a tcpdump
per set. Capturing raw packets and enumerating interfaces (`tcpdump -D`) both
need privilege, so in practice Lamashtu runs as root — see
[security](security.md) for what that implies. To try her out unprivileged,
use a `command` type set (see the examples), which runs a harmless program
instead of tcpdump.

## Running at boot

`lamashtu start` daemonizes itself and writes `/var/run/lamashtu/pid`, so it fits
both worlds easily. Ready-made startup scripts ship in the source tree's `rc/`
directory — `make install` does not install them, so copy the one for your
system into place.

### FreeBSD rc.d

The rc.d script ships at `rc/freebsd/lamashtu`...

```shell
cp rc/freebsd/lamashtu /usr/local/etc/rc.d/lamashtu
chmod 555 /usr/local/etc/rc.d/lamashtu
sysrc lamashtu_enable=YES
service lamashtu start

# point it at a non-default config
sysrc lamashtu_config=/usr/local/etc/foo.toml
```

### Debian systemd

The unit ships at `rc/systemd/lamashtu.service`...

```shell
cp rc/systemd/lamashtu.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now lamashtu
```

It is `Type=forking` against `/var/run/lamashtu/pid`; edit the `ExecStart` line
for a non-default config path.

On systems where `/var/run` is a tmpfs, `/var/run/lamashtu` is created
automatically at startup — but if you point `run_dir` somewhere deeper, make sure
the parents exist at boot (a `RuntimeDirectory=` line or a tmpfiles.d entry does
it on systemd). Unix socket paths are limited to roughly 104 characters on the
BSDs, so keep `run_dir` short. And make sure `pcap_dir` lives somewhere with room
to spare — the hoard only grows (see [security](security.md)).
