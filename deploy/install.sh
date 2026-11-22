#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Install a shellmmorpg server that players reach over ssh (run as root).
#    sudo deploy/install.sh [PORT]        default port 4747, listens on 127.0.0.1 only
#  Players log in with their own ssh account and run:   shellmmorpg-play
#  or, from their machine:                              ./shellmmorpg.sh --ssh user@host
# ---------------------------------------------------------------------------
set -e
[[ $EUID == 0 ]] || { echo "run as root (sudo $0)"; exit 1; }
cd "$(dirname "$0")/.."
[[ -f shellmmorpg.sh ]] || ./build.sh
command -v python3 >/dev/null 2>&1 || { echo "the server needs python3 (the gate runs every player's game in a terminal of its own)"; exit 1; }
port=${1:-4747}
[[ $port =~ ^[0-9]+$ ]] || { echo "bad port"; exit 1; }
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
  systemctl enable --now shellmmorpg.service
  echo "server running: systemctl status shellmmorpg"
else
  echo "no systemd: start it yourself:  sudo -u shellmmo /opt/shellmmorpg/shellmmorpg.sh --server $port"
fi
echo "players: ssh -t user@this-host shellmmorpg-play     (or ./shellmmorpg.sh --ssh user@this-host)"
