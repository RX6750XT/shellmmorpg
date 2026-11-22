# ---------------------------------------------------------------------------
#  Module 02 - network: a hub relays every line to every connection; the
#  python3 and socat hubs also bind each connection to one sender id and let
#  only the world server (secret token) speak as "srv".
#  Line protocol: SM1|TYPE|from|fields...   (see docs/PROTOCOL.md)
# ---------------------------------------------------------------------------
HUB_PID="" HUB_DIR="" HUB_TOOL="" WS_PID="" net_up=0 net_buf=""

read -r -d '' PY_HUB <<'PY'
# Relay hub with anti-spoofing: every connection is bound to the first sender
# id it uses, and only the world server (which proves itself with a secret
# token from the environment) may speak as "srv".
import asyncio, os, sys
TOKEN = os.environ.get("SHELLMMO_HUB_TOKEN", "").encode()
MAXBUF = 1 << 20
clients = set()
ids = {}          # writer -> bound sender id (b"srv" for the world server)
# --- interest management (v6.3): in the open world a player only gets the monsters near them -------
# The hub remembers every monster of W (from MON/MMOV/MHP) and where every player is (from their POS).
# Monster lines go to the players in range; a monster that comes into range (it walks in, or the
# player walks up to it) is sent as a full MON line; MDIE goes to everybody who knows the monster.
R_IN, R_OUT, BK = 50, 58, 16
mons = {}         # mid -> [type, x, y, hp, max, champ]
grid = {}         # (bx, by) -> set of mids
where = {}        # writer -> [map, x, y] (from the player's own POS)
near = {}         # writer -> mids in range (they get every update)
known = {}        # writer -> mids the player has heard of (they get MDIE)
MONT = (b"MON", b"MMOV", b"MHP", b"MDIE", b"MATK")
def mon_line(mid):
    t, x, y, hp, mx, ch = mons[mid]
    return b"SM1|MON|srv|W|%s|%s|%d|%d|%s|%s|%s\n" % (mid, t, x, y, hp, mx, ch)
def mon_put(mid, x, y):
    old = mons.get(mid)
    if old:
        grid.get((old[1] // BK, old[2] // BK), set()).discard(mid)
    grid.setdefault((x // BK, y // BK), set()).add(mid)
def around(x, y, r):
    out = []
    for bx in range((x - r) // BK, (x + r) // BK + 1):
        for by in range((y - r) // BK, (y + r) // BK + 1):
            for mid in grid.get((bx, by), ()):
                m = mons[mid]
                if abs(m[1] - x) <= r and abs(m[2] - y) <= r:
                    out.append(mid)
    return out
def player_moved(c, f):
    """f = POS fields after the type: id name cls lvl map x y ..."""
    try:
        mp, x, y = f[4], int(f[5]), int(f[6])
    except (IndexError, ValueError):
        return []
    old = where.get(c)
    where[c] = [mp, x, y]
    if old is None or old[0] != mp:
        near[c] = set(); known[c] = set()
    if mp != b"W":
        return []
    nr = near[c]
    keep = {m for m in nr if m in mons and abs(mons[m][1] - x) <= R_OUT and abs(mons[m][2] - y) <= R_OUT}
    new = [m for m in around(x, y, R_IN) if m not in keep]
    keep.update(new); near[c] = keep; known[c].update(new)
    return [mon_line(m) for m in new]
def monster_dest(typ, f, line, dest):
    """f = fields after the type: srv map mid ...; returns [(writer, line)]"""
    if len(f) < 3:
        return [(c, line) for c in dest]
    mp, mid = f[1], f[2]
    full = None
    if mp == b"W":
        try:
            if typ == b"MON" and len(f) >= 8:
                x, y = int(f[4]), int(f[5]); mon_put(mid, x, y); mons[mid] = [f[3], x, y, f[6], f[7], f[8] if len(f) > 8 else b"0"]
                full = line
            elif typ == b"MMOV" and len(f) >= 5:
                x, y = int(f[3]), int(f[4])
                if len(f) >= 9:
                    mon_put(mid, x, y); mons[mid] = [f[5], x, y, f[6], f[7], f[8]]
                elif mid in mons:
                    mon_put(mid, x, y); mons[mid][1:3] = [x, y]
            elif typ == b"MHP" and mid in mons and len(f) >= 4:
                mons[mid][3] = f[3]
        except ValueError:
            pass
    out = []
    for c in dest:
        w = where.get(c)
        if w is None or ids.get(c) == b"srv" or mp != b"W":     # (instances are small: everybody gets them)
            out.append((c, line)); continue
        if w[0] != mp:
            continue
        nr, kn = near[c], known[c]
        if typ == b"MDIE":
            if mid in kn:
                out.append((c, line)); kn.discard(mid); nr.discard(mid)
            continue
        if typ == b"MATK" and len(f) >= 4 and f[3] == ids.get(c):
            out.append((c, line)); continue
        m = mons.get(mid)
        if m is None:
            out.append((c, line)); continue
        dx, dy = abs(m[1] - w[1]), abs(m[2] - w[2])
        if mid in nr:
            if dx <= R_OUT and dy <= R_OUT:
                out.append((c, line))
            else:
                nr.discard(mid)
        elif dx <= R_IN and dy <= R_IN and typ in (b"MON", b"MMOV"):
            nr.add(mid); kn.add(mid)
            out.append((c, full or mon_line(mid)))
    if typ == b"MDIE" and mp == b"W" and mid in mons:
        m = mons.pop(mid); grid.get((m[1] // BK, m[2] // BK), set()).discard(mid)
    return out
async def handle(reader, writer):
    clients.add(writer)
    me = None
    try:
        while True:
            try:
                line = await reader.readline()
            except (ValueError, asyncio.LimitOverrunError):
                break
            if not line:
                break
            if len(line) > 2048 or not line.endswith(b"\n"):
                continue
            p = line[:-1].split(b"|", 3)
            if len(p) < 3 or p[0] != b"SM1":
                continue
            frm = p[2]
            if p[1] == b"AUTH":
                if TOKEN and frm == b"srv" and len(p) == 4 and p[3] == TOKEN:
                    me = b"srv"
                continue
            if me is None and frm != b"srv":
                me = frm
            if frm != me:
                continue
            ids[writer] = me
            # private lines: ALOAD/ASAVE (hero data, passwords) and ADM (admin commands) go to the world server only,
            # AR<id> (the server's answer) to that one player only
            typ = p[1]
            if typ in (b"ALOAD", b"ASAVE", b"ADM"):
                if me == b"srv":
                    continue
                dest = [c for c in clients if ids.get(c) == b"srv"]
            elif typ[:2] == b"AR" and len(typ) == 8:
                if me != b"srv":
                    continue
                dest = [c for c in clients if ids.get(c) == typ[2:]]
            else:
                dest = list(clients)
            if me == b"srv" and typ in MONT:
                sends = monster_dest(typ, line[:-1].split(b"|")[2:], line, dest)
            else:
                sends = [(c, line) for c in dest]
                if typ == b"POS" and me != b"srv":
                    sends += [(writer, l) for l in player_moved(writer, line[:-1].split(b"|")[2:])]
            for c, l in sends:
                try:
                    if c.transport.get_write_buffer_size() > MAXBUF:
                        raise ConnectionError("client too slow")
                    c.write(l)
                except Exception:
                    clients.discard(c)
                    c.close()
    except Exception:
        pass
    finally:
        clients.discard(writer)
        ids.pop(writer, None)
        for d in (where, near, known):
            d.pop(writer, None)
        try:
            writer.close()
        except Exception:
            pass
async def watchdog(pid):          # the game that started this hub is gone (kill -9): do not stay behind
    while True:
        await asyncio.sleep(2)
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            os._exit(0)
        except Exception:
            pass
async def main():
    if len(sys.argv) > 3 and sys.argv[3].isdigit():
        asyncio.get_running_loop().create_task(watchdog(int(sys.argv[3])))
    server = await asyncio.start_server(handle, (sys.argv[2] if len(sys.argv) > 2 else None) or None, int(sys.argv[1]))
    async with server:
        await server.serve_forever()
try:
    asyncio.run(main())
except KeyboardInterrupt:
    pass
PY

pick_hub_tool() {  # python3 and socat hubs enforce sender ids; the ncat broker relays blindly
  if [[ $SHELLMMO_HUB =~ ^(ncat|python3|socat)$ ]] && command -v "$SHELLMMO_HUB" >/dev/null 2>&1; then HUB_TOOL=$SHELLMMO_HUB
  elif command -v python3 >/dev/null 2>&1; then HUB_TOOL=python3
  elif command -v socat >/dev/null 2>&1; then HUB_TOOL=socat
  elif command -v ncat >/dev/null 2>&1; then HUB_TOOL=ncat
  elif command -v nc >/dev/null 2>&1 && nc --version 2>&1 | grep -qi ncat; then HUB_TOOL=nc
  else return 1; fi
  if [[ $HUB_TOOL == @(python3|socat) && -z $SHELLMMO_HUB_TOKEN ]]; then
    local t=""
    [[ -r /dev/urandom ]] && t=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null)
    t=${t//[^0-9a-f]/}
    (( ${#t} >= 16 )) || printf -v t '%04x%04x%04x%04x' $RANDOM $RANDOM $RANDOM $RANDOM
    export SHELLMMO_HUB_TOKEN=$t
  fi
}

alive() { [[ -n $1 ]] && kill -0 "$1" 2>/dev/null; }

start_hub() {
  local run=() i
  command -v setsid >/dev/null 2>&1 && run=(setsid)
  case $HUB_TOOL in
    ncat|nc) "${run[@]}" "$HUB_TOOL" --broker -l ${NET_BIND:+"$NET_BIND"} "$NET_PORT" </dev/null >/dev/null 2>&1 & ;;
    python3) "${run[@]}" python3 -I -c "$PY_HUB" "$NET_PORT" "$NET_BIND" "$$" </dev/null >/dev/null 2>&1 & ;;
    socat)
      [[ -n $HUB_DIR ]] || HUB_DIR=$(mktemp -d)
      : > "$HUB_DIR/log"
      "${run[@]}" socat "TCP-LISTEN:$NET_PORT,reuseaddr,fork${NET_BIND:+,bind=$NET_BIND}" "EXEC:bash $SELF --hub-handler $HUB_DIR/log" \
        </dev/null >/dev/null 2>&1 & ;;
  esac
  HUB_PID=$!
  disown "$HUB_PID" 2>/dev/null
  for (( i = 0; i < 30; i++ )); do
    sleep 0.1
    alive "$HUB_PID" || return 1
    (exec 3<>"/dev/tcp/${NET_BIND:-127.0.0.1}/$NET_PORT") 2>/dev/null && return 0
  done
  return 1
}

start_world_server() {
  local run=()
  command -v setsid >/dev/null 2>&1 && run=(setsid)
  mkdir -p "$DATA_DIR"
  SHELLMMO_ADMIN_NAME=$MY_NAME "${run[@]}" bash "$SELF" --world-server "$NET_PORT" </dev/null >>"$DATA_DIR/server.log" 2>&1 &
  WS_PID=$!
  disown "$WS_PID" 2>/dev/null           # (no "Killed" notice from bash on top of the game if it dies)
}

kill_tree() {
  [[ -n $1 ]] || return
  kill -TERM -- "-$1" 2>/dev/null
  pkill -TERM -P "$1" 2>/dev/null
  kill -TERM "$1" 2>/dev/null
}

stop_all() {
  kill_tree "$WS_PID"; WS_PID=""
  kill_tree "$HUB_PID"; HUB_PID=""
  [[ -n $HUB_DIR ]] && rm -rf "$HUB_DIR"
}

net_connect() {
  timeout 2 bash -c 'exec 3<>"/dev/tcp/$0/$1"' "$NET_HOST" "$NET_PORT" 2>/dev/null || return 1
  { exec 7<>"/dev/tcp/$NET_HOST/$NET_PORT"; } 2>/dev/null || return 1
  net_up=1 net_buf=""
  # the world server proves to the hub that it may speak as "srv"
  [[ $MODE == @(world|server) && -n $SHELLMMO_HUB_TOKEN ]] && send AUTH srv "$SHELLMMO_HUB_TOKEN"
  return 0
}

send() {   # TYPE fields... (joined with |)
  (( net_up )) || return 1
  local IFS='|'
  printf 'SM1|%s\n' "$*" >&7 2>/dev/null && return 0
  net_lost
  return 1
}

# read up to $1 complete lines, calling on_line for each
net_poll() {
  local line rc n=0 max=${1:-200}
  while (( net_up && n < max )) && read -t 0 -u 7 2>/dev/null; do
    IFS= read -r -t 0.02 -u 7 line; rc=$?
    if (( rc == 0 )); then on_line "$net_buf$line"; net_buf=""
    elif (( rc > 128 )); then net_buf+=$line; break
    else net_lost; return; fi
    n=$(( n + 1 ))
  done
  (( ${#net_buf} > 4096 )) && net_buf=""
}
