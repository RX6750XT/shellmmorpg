#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Install a shellmmorpg server that players reach over ssh (run as root).
#    sudo deploy/install.sh [PORT] [--guest NAME | --no-guest]
#      PORT       default 4747, listens on 127.0.0.1 only
#      --guest    the open ssh account everybody plays through (default: play)
#      --no-guest no open account - every player needs an ssh login of their own
#
#  With the open account (v7.2) anybody plays with   ssh play@this-host
#  - no ssh password; the game asks for the hero's name and password, and a
#  new name makes a new hero. Players with their own ssh login run
#  shellmmorpg-play (their hero is named after their unix user).
# ---------------------------------------------------------------------------
set -e
[[ $EUID == 0 ]] || { echo "run as root (sudo $0)"; exit 1; }
cd "$(dirname "$0")/.."
port=4747 guest=play
while (( $# )); do
  case $1 in
    --guest)    [[ $2 =~ ^[a-z_][a-z0-9_-]{0,30}$ ]] || { echo "--guest needs a user name"; exit 1; }; guest=$2; shift ;;
    --no-guest) guest="" ;;
    [0-9]*)     port=$1 ;;
    *)          echo "usage: $0 [PORT] [--guest NAME | --no-guest]"; exit 1 ;;
  esac
  shift
done
[[ $port =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65534 )) || { echo "bad port"; exit 1; }
[[ $guest == shellmmo ]] && { echo "the open account cannot be the server's own user (shellmmo)"; exit 1; }
[[ -f shellmmorpg.sh ]] || ./build.sh
command -v python3 >/dev/null 2>&1 || { echo "the server needs python3 (the gate runs every player's game in a terminal of its own)"; exit 1; }
id shellmmo >/dev/null 2>&1 || useradd --system --create-home --home-dir /var/lib/shellmmorpg --shell /usr/sbin/nologin shellmmo
install -d -m 755 /opt/shellmmorpg
install -m 755 shellmmorpg.sh /opt/shellmmorpg/shellmmorpg.sh
cat > /usr/local/bin/shellmmorpg-play <<PLAY
#!/usr/bin/env bash
# a terminal for the game: since 7.0 it runs on the server as the shellmmo user, behind the gate on 127.0.0.1
exec /opt/shellmmorpg/shellmmorpg.sh --join $port "\$@"
PLAY
chmod 755 /usr/local/bin/shellmmorpg-play
if command -v systemctl >/dev/null 2>&1 && [[ -d /etc/systemd/system ]]; then
  cat > /etc/systemd/system/shellmmorpg.service <<UNIT
[Unit]
Description=shellmmorpg world server
After=network.target

[Service]
User=shellmmo
Environment=SHELLMMO_DIR=/var/lib/shellmmorpg
ExecStart=/opt/shellmmorpg/shellmmorpg.sh --server $port
Restart=on-failure
KillMode=control-group
NoNewPrivileges=yes
ProtectSystem=strict
ReadWritePaths=/var/lib/shellmmorpg
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
UNIT
  systemctl daemon-reload
  systemctl enable shellmmorpg.service
  systemctl restart shellmmorpg.service
  echo "server running: systemctl status shellmmorpg"
else
  echo "no systemd: start it yourself:  sudo -u shellmmo SHELLMMO_DIR=/var/lib/shellmmorpg /opt/shellmmorpg/shellmmorpg.sh --server $port"
fi

# --- v7.2: the open account: ssh play@host, no ssh password, the game asks who you are --------------
if [[ -n $guest ]]; then
  # its login shell: it can only open the game (whatever command ssh asks for - only --hd/--ascii/--name count)
  cat > /usr/local/bin/shellmmorpg-guest <<GUEST
#!/usr/bin/env bash
# the login shell of the open ssh account '$guest' (shellmmorpg, deploy/install.sh): nothing but the game
set -f
args=(--ask-name)
w=(\${SSH_ORIGINAL_COMMAND:-})
for (( i = 0; i < \${#w[@]}; i++ )); do
  case \${w[i]} in
    --hd|--ascii) args+=("\${w[i]}") ;;
    --name) [[ \${w[i+1]} =~ ^[A-Za-z0-9_-]{1,12}\$ ]] && args+=(--name "\${w[i+1]}"); i=\$(( i + 1 )) ;;
  esac
done
[[ -t 0 && -t 1 ]] || { echo "shellmmorpg needs a terminal: ssh -t \$(id -un)@this-host"; exit 1; }
exec /opt/shellmmorpg/shellmmorpg.sh --join $port "\${args[@]}"
GUEST
  chmod 755 /usr/local/bin/shellmmorpg-guest
  if ! id "$guest" >/dev/null 2>&1; then
    useradd --system --home-dir /var/lib/shellmmorpg-guest --no-create-home --shell /usr/local/bin/shellmmorpg-guest "$guest"
  elif [[ $(getent passwd "$guest" | cut -d: -f7) != /usr/local/bin/shellmmorpg-guest ]]; then
    echo "user '$guest' already exists (and is not ours) - it never becomes an open account; pick another name with --guest NAME"; exit 1
  fi
  install -d -o root -g root -m 755 /var/lib/shellmmorpg-guest     # (owned by root: no ~/.ssh, nothing to write)
  passwd -d "$guest" >/dev/null                                    # an empty password: ssh lets everybody in ...
  conf=/etc/ssh/sshd_config.d/shellmmorpg.conf
  rules="# shellmmorpg (deploy/install.sh): the open account - no password, nothing but the game
Match User $guest
    PermitEmptyPasswords yes
    PasswordAuthentication yes
    KbdInteractiveAuthentication yes
    AuthenticationMethods any
    ForceCommand /usr/local/bin/shellmmorpg-guest
    PermitTTY yes
    DisableForwarding yes
    PermitTunnel no
    PermitUserRC no
    MaxSessions 1"
  if [[ -d /etc/ssh/sshd_config.d ]] && grep -qiE '^\s*Include\s+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config 2>/dev/null; then
    printf '%s\n' "$rules" > "$conf"
    if sshd -t 2>/dev/null || /usr/sbin/sshd -t; then
      systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null || service ssh reload 2>/dev/null ||
        echo "reload sshd yourself so it reads $conf"
      echo "open account: ssh $guest@this-host  (sshd rules in $conf)"
    else
      rm -f "$conf"; echo "sshd did not accept the rules - nothing changed in sshd, see docs/SERVER.md"; exit 1
    fi
  else
    echo "add this to the END of /etc/ssh/sshd_config, then reload sshd:"; echo; printf '%s\n\n' "$rules"
  fi
  # ... which only works if PAM accepts empty passwords (nullok - the default on Debian, Ubuntu, Arch, Fedora)
  grep -rqs nullok /etc/pam.d/ || echo "warning: no 'nullok' in /etc/pam.d - PAM may refuse the empty password (see docs/SERVER.md)"
  echo "players: ssh $guest@this-host     (or ./shellmmorpg.sh --ssh $guest@this-host)"
fi
echo "players with an ssh login of their own: ssh -t user@this-host shellmmorpg-play"
