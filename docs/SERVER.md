# Running a server (over ssh)

**In short (v7.2):** `sudo deploy/install.sh` - then everybody plays with
`ssh play@your-host`. No ssh password; the game asks for the hero's name
and password, and a new name makes a new hero.

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

### Update

```bash
cd shellmmorpg && sudo deploy/update.sh     # --no-pull: install what is checked out; --yes: don't ask
```

A `git pull` alone changes nothing on the server: the game runs from
`/opt/shellmmorpg`, and the running service keeps the old version until it
restarts. `update.sh` pulls, backs up the heroes to
`/var/lib/shellmmorpg/backups/`, runs `install.sh` again with the port and
open account already in use (that copies the game and restarts the service)
and checks that the new version is live. Players online get disconnected
(it asks first).

### The open account (v7.2)

`install.sh` also creates the open ssh account `play` (`--guest NAME` for
another name, `--no-guest` for none): a system user with an **empty
password** whose login shell, `/usr/local/bin/shellmmorpg-guest`, can only
start the game (`shellmmorpg.sh --join PORT --ask-name`). The sshd rules go
to `/etc/ssh/sshd_config.d/shellmmorpg.conf` (checked with `sshd -t`, then
sshd is reloaded; without a `sshd_config.d` include the script prints them
for the end of `sshd_config`):

```
Match User play
    PermitEmptyPasswords yes
    PasswordAuthentication yes
    KbdInteractiveAuthentication yes
    AuthenticationMethods any
    ForceCommand /usr/local/bin/shellmmorpg-guest
    PermitTTY yes
    DisableForwarding yes
    PermitTunnel no
    PermitUserRC no
    MaxSessions 1
```

They only apply to `play` - your other ssh settings (e.g. keys only) stay
as they are. The empty password needs PAM to allow it (`nullok` on
`pam_unix`, the default on Debian, Ubuntu, Arch and Fedora); the script
warns if it finds none.

What a player sees:

- **sid has played before:** `ssh play@host` -> `Hero name: sid` ->
  `Password for sid:` -> in the world.
- **ron is new:** `ssh play@host` -> `Hero name: ron` -> a password ->
  `There is no hero called ron yet. Create ron? [y/n]` -> `y` -> the
  password again -> class and look -> in the world.

The heroes' passwords protect them (at least 8 characters for a new hero;
5 wrong ones lock a hero for a minute, every lock-out in a row twice as
long, at most 30 minutes); everybody who can reach your sshd can make
heroes, at most 32 play at a time (`SHELLMMO_MAX_PLAYERS`), at most 4 from
one address (`SHELLMMO_MAX_PER_IP`). `./shellmmorpg.sh --ssh play@host [--name sid]`
works too (only `--hd`, `--ascii` and `--name` are passed on).

### On a public server

An open account on the internet is found by scanners within hours. The
game limits what they can do (4 games per address, 32 in all, 5 password
checks a second, lock-outs), but the machine is yours to harden:

- **a machine of its own** (a small VPS or VM) - not the one with your other things;
- **keys only for every other account**, in `/etc/ssh/sshd_config`
  (before any `Match` block - the rules for `play` stay):
  ```
  PermitRootLogin no
  PasswordAuthentication no
  KbdInteractiveAuthentication no
  MaxStartups 10:30:60
  PerSourcePenalties yes        # OpenSSH 9.8+: slows down addresses that misbehave
  ```
- **back up `/var/lib/shellmmorpg/chars/` regularly** (a cron job; `update.sh`
  makes one before every update);
- limits live in the service: `systemctl edit shellmmorpg` and
  `Environment=SHELLMMO_MAX_PLAYERS=32 SHELLMMO_MAX_PER_IP=4`.

Passwords are stored as PBKDF2-SHA256 (v8.1, 200,000 rounds; heroes from
older versions move over at their next login). The server only ever checks
5 a second, so a flood of logins slows logins down, never the world.
Locking out is per hero: somebody who keeps guessing a hero's password
also keeps its owner out (at most 30 minutes at a time).

Safer still is no open account at all: `sudo deploy/install.sh --no-guest`
and an ssh login with a key for every player (below).

### Players with a login of their own

You can also give a player an ssh account of their own (any normal unix
user): `ssh -t user@host shellmmorpg-play`, their hero is named after the
unix user. To make that account game-only, put this in `sshd_config`:

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
ssh play@host                                   # the open account: the game asks for name and password
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
