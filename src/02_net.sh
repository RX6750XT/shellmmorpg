# ---------------------------------------------------------------------------
#  Module 02 - network (v7.0: the game runs on the server).
#  One python3 process is both
#   - the gate (127.0.0.1:port - players come in over ssh): every player who connects gets a terminal
#     (a pty) with a game session of their own (--session) running on the
#     server; the player's computer only sends keys and shows the screen
#     (term_main in 02b_term.sh). Nothing the player sends is more than a key.
#   - the hub (127.0.0.1, port + 1): relays every line to every connection.
#     A connection must prove first that the server started it (AUTH with a
#     secret token from the environment): the world server speaks as "srv",
#     the sessions as their player id. Nobody else can talk to the hub.
#  Line protocol: SM1|TYPE|from|fields...   (see docs/PROTOCOL.md)
# ---------------------------------------------------------------------------
HUB_PID="" HUB_TOOL="" WS_PID="" net_up=0 net_buf=""

read -r -d '' PY_HUB <<'PY'
# The gate and the hub (v7.0). Hub: a connection is bound to the id it proves with AUTH - the world
# server ("srv", SHELLMMO_HUB_TOKEN) or a game session the gate started (its player id,
# SHELLMMO_SESS_TOKEN); everything from a connection that did not prove itself is dropped.
# Gate: SMT1|name|cols|rows|gfx, then a pty with "bash GAME --session" for that player; bytes go
# both ways, an in-band ESC ] 5379 ; rows ; cols BEL resizes the terminal.
import asyncio, fcntl, os, re, signal, struct, subprocess, sys, termios
TOKEN = os.environ.get("SHELLMMO_HUB_TOKEN", "").encode()
STOKEN = os.environ.get("SHELLMMO_SESS_TOKEN", "").encode()
MAXBUF = 1 << 20
MAXSESS = int(os.environ.get("SHELLMMO_MAX_PLAYERS", "32") or 32)
sessions = set()
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
                if me is None and len(p) == 4:
                    if TOKEN and frm == b"srv" and p[3] == TOKEN:
                        me = b"srv"
                    elif STOKEN and p[3] == STOKEN and re.fullmatch(rb"[0-9a-f]{6}", frm):
                        me = frm
                    if me is not None:
                        ids[writer] = me
                continue
            if me is None or frm != me:
                continue
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
                dest = [c for c in clients if c in ids]     # (only connections that proved themselves hear anything)
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
RESIZE = re.compile(rb"\x1b\]5379;(\d{1,3});(\d{1,3})\x07")
ENV_KEEP = ("PATH", "HOME", "LANG", "LC_ALL", "LC_CTYPE", "SHELLMMO_DIR", "SHELLMMO_SESS_TOKEN", "SHELLMMO_HUB_PORT",
            "SHELLMMO_WB_DELAY", "SHELLMMO_CLOCK", "SHELLMMO_WEATHER_DELAY")
def winsz(fd, rows, cols):
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack("HHHH", max(10, min(rows, 300)), max(20, min(cols, 500)), 0, 0))
def ctty():
    os.setsid()
    fcntl.ioctl(0, termios.TIOCSCTTY, 0)
async def gate(reader, writer):
    """one player: a terminal with a game session of their own, on this machine"""
    loop = asyncio.get_running_loop()
    master = proc = None
    try:
        try:
            hs = await asyncio.wait_for(reader.readline(), 15)
        except Exception:
            return
        m = re.fullmatch(rb"SMT1\|([A-Za-z0-9_-]{1,12})\|(\d{1,3})\|(\d{1,3})\|(hd|ascii|-)\r?\n", hs)
        if not m:
            writer.write(b"SMT1|NO|This is a shellmmorpg 7 server - play over ssh (./shellmmorpg.sh --ssh user@host).\n"); return
        if len(sessions) >= MAXSESS:
            writer.write(b"SMT1|NO|The server is full.\n"); return
        name, rows, cols, gfx = m.group(1).decode(), int(m.group(3)), int(m.group(2)), m.group(4).decode()
        env = {k: os.environ[k] for k in ENV_KEEP if k in os.environ}
        env.update(TERM="xterm-256color", SHELLMMO_NAME=name)
        if gfx != "-":
            env["SHELLMMO_GFX"] = gfx
        master, slave = os.openpty()
        winsz(master, rows, cols)
        proc = subprocess.Popen(["bash", GAME, "--session"], stdin=slave, stdout=slave, stderr=slave, env=env,
                                cwd=os.environ.get("SHELLMMO_DIR") or "/", preexec_fn=ctty, close_fds=True)
        os.close(slave)
        os.set_blocking(master, False)
        sessions.add(proc)
        writer.write(b"SMT1|OK\n")
        done = asyncio.Event()
        def from_game():
            try:
                d = os.read(master, 65536)
            except BlockingIOError:
                return
            except OSError:
                d = b""
            if not d:
                loop.remove_reader(master); done.set(); return
            if not writer.is_closing():
                if writer.transport.get_write_buffer_size() > 4 * MAXBUF:
                    done.set(); return              # the player does not read: give up
                writer.write(d)
        loop.add_reader(master, from_game)
        async def from_player():
            while True:
                d = await reader.read(4096)
                if not d:
                    break
                for r in RESIZE.finditer(d):
                    winsz(master, int(r.group(1)), int(r.group(2)))
                d = RESIZE.sub(b"", d)
                if d:
                    try:
                        os.write(master, d)
                    except OSError:
                        pass                        # (the game is busy: a key is lost, never the server)
            done.set()
        async def game_alive():                     # (a child of the game may keep the pty open after it quit)
            while proc.poll() is None:
                await asyncio.sleep(0.3)
            await asyncio.sleep(0.3)
            from_game()
            done.set()
        t = loop.create_task(from_player())
        w = loop.create_task(game_alive())
        await done.wait()
        t.cancel(); w.cancel()
    except Exception:
        pass
    finally:
        if proc is not None:
            if proc.poll() is None:                 # the player is gone: the game saves and quits
                for sig in (signal.SIGHUP, signal.SIGCONT):
                    try:
                        os.killpg(proc.pid, sig)
                    except OSError:
                        pass
            for _ in range(80):
                if proc.poll() is not None:
                    break
                try:
                    while os.read(master, 65536):   # keep draining, a full pty would block its goodbye
                        pass
                except OSError:
                    pass
                await asyncio.sleep(0.1)
            try:
                os.killpg(proc.pid, signal.SIGKILL)         # the game and whatever it left behind
            except OSError:
                pass
            proc.wait()
            sessions.discard(proc)
        if master is not None:
            try:
                loop.remove_reader(master)
            except Exception:
                pass
            os.close(master)
        try:
            writer.close()
        except Exception:
            pass
GAME = ""
async def main():
    global GAME
    hub_port, gate_port, _, parent, GAME = sys.argv[1:6]
    if parent.isdigit():
        asyncio.get_running_loop().create_task(watchdog(int(parent)))
    hub = await asyncio.start_server(handle, "127.0.0.1", int(hub_port))
    gt = await asyncio.start_server(gate, "127.0.0.1", int(gate_port))   # players come in over ssh, never over the network
    async with hub, gt:
        await asyncio.gather(hub.serve_forever(), gt.serve_forever())
try:
    asyncio.run(main())
except KeyboardInterrupt:
    pass
PY

new_token() {  # -> TOK (32 hex digits)
  local t=""
  [[ -r /dev/urandom ]] && t=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null)
  t=${t//[^0-9a-f]/}
  (( ${#t} >= 16 )) || printf -v t '%04x%04x%04x%04x%04x%04x' $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM $RANDOM
  TOK=$t
}

pick_hub_tool() {  # v7.0: the gate needs ptys - python3 only
  command -v python3 >/dev/null 2>&1 || return 1
  HUB_TOOL=python3
  [[ -n $SHELLMMO_HUB_TOKEN ]] || { new_token; export SHELLMMO_HUB_TOKEN=$TOK; }
  [[ -n $SHELLMMO_SESS_TOKEN ]] || { new_token; export SHELLMMO_SESS_TOKEN=$TOK; }
  export SHELLMMO_HUB_PORT=$HUB_PORT
}

alive() { [[ -n $1 ]] && kill -0 "$1" 2>/dev/null; }

start_hub() {
  local run=() i
  command -v setsid >/dev/null 2>&1 && run=(setsid)
  "${run[@]}" python3 -I -c "$PY_HUB" "$HUB_PORT" "$NET_PORT" 127.0.0.1 "$$" "$SELF" </dev/null >/dev/null 2>&1 &
  HUB_PID=$!
  disown "$HUB_PID" 2>/dev/null
  for (( i = 0; i < 30; i++ )); do
    sleep 0.1
    alive "$HUB_PID" || return 1
    (exec 3<>"/dev/tcp/127.0.0.1/$HUB_PORT") 2>/dev/null && return 0
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
}

net_connect() {  # to the hub - always on this machine (v7.0)
  timeout 2 bash -c 'exec 3<>"/dev/tcp/127.0.0.1/$0"' "$HUB_PORT" 2>/dev/null || return 1
  { exec 7<>"/dev/tcp/127.0.0.1/$HUB_PORT"; } 2>/dev/null || return 1
  net_up=1 net_buf=""
  # prove to the hub that the server started us: the world server speaks as "srv", a game session as its player
  if [[ $MODE == @(world|server) ]]; then send AUTH srv "$SHELLMMO_HUB_TOKEN"
  else send AUTH "$MY_ID" "$SHELLMMO_SESS_TOKEN"; fi
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
