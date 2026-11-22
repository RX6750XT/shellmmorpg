# Running a server (over ssh)

The world server listens on `127.0.0.1` only. Players reach it by logging
into the machine with ssh - nothing else is exposed and ssh provides the
encryption. **Heroes live on the server** (since 6.2): every hero is a file in
`/var/lib/shellmmorpg/chars/` (owned by the `shellmmo` user, mode 700, so the
players cannot read each other's heroes or password hashes), protected by a
password the player chooses when creating the hero. Nothing is stored in
the players' home directories.

## Deploy

```bash
git clone <repo> && cd shellmmorpg
sudo deploy/install.sh          # port 4747; or: sudo deploy/install.sh 5000
```

This installs the game to `/opt/shellmmorpg`, creates the system user
`shellmmo`, starts the systemd service `shellmmorpg` (dedicated server,
`--bind 127.0.0.1`) and installs the command `shellmmorpg-play`.
Without systemd: `sudo -u shellmmo /opt/shellmmorpg/shellmmorpg.sh --server 4747 --bind 127.0.0.1`.

Back up `/var/lib/shellmmorpg/chars/` - that is all the state there is.

Give every player an ssh account (any normal unix user). To make that
account game-only, put this in `sshd_config`:

```
Match Group shellmmo-players
    ForceCommand /usr/local/bin/shellmmorpg-play
    AllowTcpForwarding no
    X11Forwarding no
```

## Admins

The server decides who is an admin (v6.4): the heroes listed in
`/var/lib/shellmmorpg/admins`, one name per line. Edit it with

```bash
sudo -u shellmmo SHELLMMO_DIR=/var/lib/shellmmorpg /opt/shellmmorpg/shellmmorpg.sh --admin add NAME
sudo -u shellmmo SHELLMMO_DIR=/var/lib/shellmmorpg /opt/shellmmorpg/shellmmorpg.sh --admin remove NAME
sudo -u shellmmo SHELLMMO_DIR=/var/lib/shellmmorpg /opt/shellmmorpg/shellmmorpg.sh --admin list
```

The running server reads the file for every command - no restart needed.
Admins can also `/admin grant NAME` and `/admin revoke NAME` in the game.
Every admin command lands in the server's log (`journalctl -u shellmmorpg`,
lines `admin NAME: ...`). When a player hosts a world with plain
`./shellmmorpg.sh`, their own hero is an admin there; the list lives in
`~/.shellmmorpg/admins`.

## Play

```bash
ssh -t user@host shellmmorpg-play
./shellmmorpg.sh --ssh user@host[:sshport]      # same thing, adds --ascii/--hd if given first
```

`SHELLMMO_REMOTE` changes the remote command. Everybody who joins the same
server shares one world. The hero's name defaults to the unix user name
(`--name` overrides, 12 letters/digits/`_`/`-`); the game asks for the
hero's password (`SHELLMMO_PASS` skips the question). Heroes saved by older
versions in a player's `~/.shellmmorpg` move to the server on the first login.

## Without ssh

`./shellmmorpg.sh --server 4747` listens on all interfaces; players use
`--join host:4747`. The line protocol is plain text - only do this on a LAN
or a VPN, or tunnel it: `ssh -L 4747:127.0.0.1:4747 user@host` and
`--join 127.0.0.1`.
