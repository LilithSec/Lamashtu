# Security considerations

Lamashtu seizes and keeps raw traffic. That makes her the most sensitive of the
household to run: her hoard is the very thing an attacker would love to read,
and it accumulates on your disk by design. Read this before you loose her
anywhere real.

## The hoard is raw traffic

A pcap is everything that crossed the wire — packet headers and payloads both.
Unless the traffic was itself encrypted end to end, that includes credentials,
session tokens, cookies, email bodies, queries, and personal data in the clear.
Consequences:

- **`pcap_dir` is a trove.** Keep it owned by root and readable by no one else.
  Whoever can read the pcaps can read everything Lamashtu saw.
- **Backups and log shippers inherit the sensitivity.** If something replicates
  `pcap_dir` offsite, it is replicating captured credentials offsite.
- **Retention is a liability, not just a cost.** Data you never captured cannot
  leak; data you kept forever can. Prune deliberately (see below).
- **Filter down to what you actually need.** A set's `args` is a tcpdump filter —
  `"tcp port 443"`, `"not port 22"`, `"host 192.0.2.0/24"`. Capturing less is the
  cheapest way to hold less that matters.

## It fills the disk

Lamashtu never deletes. Rotation starts new files; it does not remove old ones.
On a busy interface the hoard grows without bound and will eventually fill
`pcap_dir`'s filesystem — which, if that is the same filesystem as your logs or
spool, can take other services down with it.

- Put `pcap_dir` on its own filesystem so a runaway capture cannot starve the
  rest of the host.
- Prune outside Lamashtu — a cron job deleting pcaps older than N days, or a size
  cap sweep. (`tcpdump`'s own `-W` ring-buffer limit is deliberately **not**
  exposed, since Lamashtu manages `-w`/`-C`/`-G` itself; pruning is an external
  concern.)
- Size your rotation so individual files are a manageable unit to move or delete
  (`rotate`, `secs`, `size` — see [configuration.md](configuration.md)).

## Virani reads the hoard

[Virani](https://github.com/LilithSec/Virani) is the household's sanctioned
reader of Lamashtu's captures, and reading is exactly as sensitive as the hoard
itself — anyone who can run Virani against `pcap_dir`, or reach a `mojo-virani`
web service that serves it, can pull back the credentials and payloads in there.
Points that follow from that:

- Virani only needs **read** access to `pcap_dir`; do not grant it more, and do
  not widen the directory's perms just to let it in (run it as a user that shares
  a group with the pcaps, or as root, rather than making the trove group- or
  world-readable).
- `mojo-virani` turns the hoard into an HTTP endpoint. Its `allowed_subnets` and
  optional `apikey` are the gate on that endpoint — keep the subnet list tight,
  set an apikey, and prefer not exposing it off-host at all. An open mojo-virani
  is an open window onto everything Lamashtu saw.
- Virani's cache (default `/var/cache/virani`) holds the carved-out results of
  past searches — smaller than the hoard but every bit as sensitive. Guard it
  like `pcap_dir`.

## Capture has consequences beyond the host

Recording other people's traffic can carry legal, regulatory, and policy weight —
wiretap and privacy law, PCI/HIPAA/GDPR-style regimes, and your own
organization's rules. That is your call to make, not this software's, but make it
knowingly and with authorization before pointing Lamashtu at a network that
carries traffic you do not own.

## The socket is the gate

The control socket is created with the configured `socket_mode` (default 0660)
and chowned to `socket_group` (default: the root user's default group — `wheel`
on the BSDs, `root` on Linux). Group membership on that socket is the access
control: whoever can write to it can add, remove, and restart captures, and read
the daemon's view of the hoard. Pick the group accordingly.

## Neti at the gate: the enable_auth trust model

By default the socket perms are the whole story. Setting `enable_auth = true`
layers an identity challenge on top — Neti, the gatekeeper of Kur, at the door.
Mechanically this is the
[POE::Component::Server::JSONUnix](https://metacpan.org/pod/POE::Component::Server::JSONUnix)
unix-ownership challenge: the caller writes a cookie handed to it into a file
inside `auth_temp_dir`, and because a correctly-named cookie file owned by UID
*N* can only have been written by UID *N*, the daemon learns which user is on the
other end. Only UID 0, users in `authed_users`, and members of `authed_groups`
are honored; everyone else is refused past the Neti gate. Membership is resolved
at request time, so passwd/group changes apply without a restart, and
`Lamashtu::Client` (and the `lamashtu` CLI) complete the challenge transparently.

The gate is defense in depth, not a replacement for the perms: anyone who can
write to the socket at all is still speaking to the daemon (and can, e.g., stall
it) before the challenge, and anyone who can write into `auth_temp_dir` as
another user could forge that user's identity — so keep both the socket, the
`run_dir` it lives in, and `auth_temp_dir` guarded with the file mode.

## Running as root

Capturing raw packets, opening `/dev/bpf` (or `AF_PACKET`), and enumerating
interfaces with `tcpdump -D` all need privilege, so in practice Lamashtu runs as
root. Consequences:

- `lamashtu.toml` must be owned by root and not group- or world-writable. It
  names the `program` for `command` type sets and the tcpdump invocation is built
  from it — write access to the config is code execution as root.
- A set's `args` becomes part of a `tcpdump` command line. The daemon injects the
  managed flags and rejects `-C/-G/-w/-W/-i` in `args`, but `args` is still an
  operator-supplied filter expression run as root — treat the ability to set it
  (i.e. socket access) as privileged.
- `command` type sets run an arbitrary `program` as root. Convenient for testing;
  another reason the config and the socket are privileged surfaces.

## The interface check needs the privilege too

`verify_interfaces` calls `tcpdump -D`, which itself wants the capture privilege.
If Lamashtu runs somewhere it cannot enumerate interfaces, the check will fail
every set at load. Setting `verify_interfaces = false` skips it — reasonable on a
host without tcpdump, or for an interface that only appears after boot — but then
a typo'd interface simply produces a tcpdump that never captures, silently. Leave
it on where you can.
