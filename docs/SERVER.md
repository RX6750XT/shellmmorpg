# Running a server (over ssh)

**Players reach the game only over ssh** (since 7.0 nothing else is
possible): the game - the gate on port 4747, the hub on 4748 - listens on
`127.0.0.1` only. Players log into the machine with ssh, `shellmmorpg-play`
opens their game, and the game itself runs on the server as the `shellmmo`
user. Nothing but sshd is exposed and ssh provides the encryption. **Heroes live on the server** (since 6.2): every hero is a file in
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
`shellmmo`, starts the systemd service `shellmmorpg` (dedicated server) and
installs the command `shellmmorpg-play` (`shellmmorpg.sh --join 4747`: a
terminal for the game on this machine). The server needs python3.
Without systemd: `sudo -u shellmmo /opt/shellmmorpg/shellmmorpg.sh --server 4747`.

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
./shellmmorpg.sh --ssh user@host[:sshport]      # same thing, passes --ascii/--hd and --name along
```

`SHELLMMO_REMOTE` changes the remote command. Everybody who joins the same
server shares one world. The hero's name defaults to the unix user name
(`--name` overrides, 12 letters/digits/`_`/`-`); the game asks for the
hero's password. Since 7.0 every player's game runs as the `shellmmo` user
(one process per player, behind the gate); `shellmmorpg-play` is only a
terminal for it. At most 32 players at a time (`SHELLMMO_MAX_PLAYERS` in the
service's environment). Heroes saved by versions before 6.2 in a player's
`~/.shellmmorpg` are not moved any more.

## Hosting from your own game

`./shellmmorpg.sh` starts a world on your machine and you play in it. It
listens on 127.0.0.1 too: friends need an ssh login on your machine and run
`ssh -t friend@your-host /path/to/shellmmorpg.sh --join 4747` (the game
shows the exact line when the world is online). Their games run on your
machine, as your user - give them game-only accounts as above (with that
command as `ForceCommand`), or use a dedicated server.

There is no way to join without ssh: `--join` only reaches a world on the
same machine, and `--bind` is gone.
