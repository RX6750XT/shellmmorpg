#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Update a server that deploy/install.sh set up (run as root, from the repo).
#    sudo deploy/update.sh [--no-pull] [--yes]
#      --no-pull  do not git pull - install what is checked out right now
#      --yes      do not ask before restarting (players online get kicked)
#
#  Pulls the repo, backs up the heroes, then runs install.sh again with the
#  port and open account the server already uses - that copies the new game
#  to /opt/shellmmorpg and restarts the shellmmorpg service. Without the
#  restart the old world server keeps running the old version.
# ---------------------------------------------------------------------------
set -e
[[ $EUID == 0 ]] || { echo "run as root (sudo $0)"; exit 1; }
cd "$(dirname "$0")/.."
pull=1 yes=0
for a in "$@"; do
  case $a in
    --no-pull) pull=0 ;;
    --yes|-y)  yes=1 ;;
    *)         echo "usage: $0 [--no-pull] [--yes]"; exit 1 ;;
  esac
done

ver() { [[ -f $1 ]] && sed -n 's/^VERSION="\(.*\)"$/\1/p' "$1" | head -n 1; }
old=$(ver /opt/shellmmorpg/shellmmorpg.sh)
[[ -n $old ]] || { echo "no server in /opt/shellmmorpg - install one first: sudo deploy/install.sh"; exit 1; }

# --- 1. the new version ---------------------------------------------------
if (( pull )); then
  owner=$(stat -c %U .)                     # pull as the repo's owner (keeps .git owned by them, uses their keys)
  if [[ $owner != root ]]; then sudo -u "$owner" git pull --ff-only
  else git pull --ff-only; fi
fi
[[ -f shellmmorpg.sh ]] || ./build.sh
new=$(ver shellmmorpg.sh)
bash -n shellmmorpg.sh || { echo "shellmmorpg.sh does not parse - nothing changed"; exit 1; }
echo "installed: v$old   ->   repo: v$new"

# --- 2. what the server uses now (so install.sh keeps it) -----------------
port=$(sed -n 's/.*--join \([0-9]\+\).*/\1/p' /usr/local/bin/shellmmorpg-play 2>/dev/null | head -n 1)
[[ $port =~ ^[0-9]+$ ]] || port=4747
guest=$(getent passwd | awk -F: '$7 == "/usr/local/bin/shellmmorpg-guest" { print $1; exit }')
args=("$port")
if [[ -n $guest ]]; then args+=(--guest "$guest"); else args+=(--no-guest); fi
echo "port $port, open account: ${guest:-none}"

# --- 3. players online? ----------------------------------------------------
online=$(pgrep -u shellmmo -fc -- 'shellmmorpg.sh --session' 2>/dev/null || true)
if (( ${online:-0} > 0 && ! yes )); then
  read -rp "$online player game(s) running - the restart disconnects them. Go on? [y/N] " r
  [[ $r == [yY]* ]] || { echo "nothing changed"; exit 0; }
fi

# --- 4. back up the heroes -------------------------------------------------
data=/var/lib/shellmmorpg
if [[ -d $data/chars ]]; then
  install -d -m 700 "$data/backups"
  b="$data/backups/chars-v$old-$(date +%Y%m%d-%H%M%S).tar.gz"
  tar -czf "$b" -C "$data" chars $( [[ -f $data/admins ]] && echo admins )
  chown -R shellmmo: "$data/backups"
  echo "heroes backed up: $b"
fi

# --- 5. install + restart ---------------------------------------------------
deploy/install.sh "${args[@]}"

# --- 6. check ---------------------------------------------------------------
now=$(ver /opt/shellmmorpg/shellmmorpg.sh)
[[ $now == "$new" ]] || { echo "error: /opt/shellmmorpg has v$now, expected v$new"; exit 1; }
if command -v systemctl >/dev/null 2>&1 && systemctl is-enabled shellmmorpg >/dev/null 2>&1; then
  sleep 2
  systemctl is-active --quiet shellmmorpg || { echo "error: the service did not come up - journalctl -u shellmmorpg -n 50"; exit 1; }
  journalctl -u shellmmorpg --since "-1min" --no-pager 2>/dev/null | grep -o "world server v[0-9.]*" | tail -n 1
fi
echo "done: v$now is live"
