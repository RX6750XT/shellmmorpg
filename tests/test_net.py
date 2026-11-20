#!/usr/bin/env python3
"""Integration test: a real dedicated server, driven by protocol bots.

Starts `shellmmorpg.sh --server PORT` (python3 hub unless SHELLMMO_HUB says
otherwise), connects bots over TCP and checks the world server end to end:
world sync, combat + loot, dungeon instances, parties, anti-spoofing and
robustness against garbage input.
"""
import os, random, re, shutil, signal, socket, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.environ.get('GAME', os.path.join(ROOT, 'shellmmorpg.sh'))
HUB = os.environ.get('SHELLMMO_HUB', 'python3')
PASS = FAIL = 0


def check(desc, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
    else:
        FAIL += 1
        print(f'  FAIL [test_net/{HUB}] {desc} {extra}')


class Bot:
    def __init__(self, port, pid, name):
        self.id, self.name = pid, name
        self.s = socket.create_connection(('127.0.0.1', port), timeout=5)
        self.s.settimeout(0.1)
        self.buf = b''
        self.lines = []

    def send(self, *fields):
        self.s.sendall(('SM1|' + '|'.join(str(f) for f in fields) + '\n').encode())

    def pump(self, secs=0.3):
        end = time.time() + secs
        while time.time() < end:
            try:
                d = self.s.recv(65536)
                if not d:
                    break
                self.buf += d
            except socket.timeout:
                pass
            except OSError:
                break
        *done, self.buf = self.buf.split(b'\n')
        new = [l.decode('utf-8', 'replace') for l in done]
        self.lines += new
        return new

    def wait(self, pattern, secs=6):
        """pump until a line matching the regex arrives (searches what came before, too)"""
        rx = re.compile(pattern)
        end = time.time() + secs
        seen = 0
        while True:
            for l in self.lines[seen:]:
                m = rx.search(l)
                if m:
                    return m
            seen = len(self.lines)
            if time.time() > end:
                return None
            self.pump(0.2)

    def hello(self, cls=0, lvl=5, x=80, y=34, mp='W'):
        self.send('HELLO', self.id, self.name, cls, lvl)
        self.pos(cls, lvl, mp, x, y)

    def pos(self, cls=0, lvl=5, mp='W', x=80, y=34):
        self.send('POS', self.id, self.name, cls, lvl, mp, x, y, 100, 100, 0, '@', 1, '', '', '')

    def close(self):
        try:
            self.s.close()
        except OSError:
            pass


def main():
    port = random.randint(20000, 40000)
    data = tempfile.mkdtemp(prefix='shellmmo_net_')
    env = dict(os.environ, SHELLMMO_DIR=data, SHELLMMO_HUB=HUB, SHELLMMO_WB_DELAY='9999999')
    srv = subprocess.Popen(['bash', GAME, '--server', str(port)], env=env, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, start_new_session=True)
    try:
        for _ in range(100):
            time.sleep(0.1)
            try:
                socket.create_connection(('127.0.0.1', port), timeout=1).close()
                break
            except OSError:
                pass
        time.sleep(1.5)                       # the world server spawns its monsters
        run(port)
    finally:
        os.killpg(srv.pid, signal.SIGTERM)
        try:
            out = srv.communicate(timeout=5)[0].decode('utf-8', 'replace')
        except subprocess.TimeoutExpired:
            os.killpg(srv.pid, signal.SIGKILL); out = ''
        errs = [l for l in out.splitlines() if re.search(r'line \d+:|syntax error|command not found|unbound', l)]
        check('server log has no bash errors', not errs, '\n    ' + '\n    '.join(errs[:5]))
        shutil.rmtree(data, ignore_errors=True)
    print(f'{"test_net/" + HUB:<14} {PASS:4d} passed  {FAIL} failed')
    sys.exit(1 if FAIL else 0)


def run(port):
    a = Bot(port, 'aaaaaa', 'alice')
    b = Bot(port, 'bbbbbb', 'bob')
    a.hello(); b.hello(cls=3)

    # --- the world comes in on join --------------------------------------------------
    check('clock arrives', a.wait(r'^SM1\|CLOCK\|srv\|\d+$') is not None)
    check('world monsters arrive', a.wait(r'^SM1\|MON\|srv\|W\|') is not None)
    a.pump(1.5)
    mons = {}
    for l in a.lines:
        f = l.split('|')
        if len(f) >= 10 and f[1] == 'MON' and f[3] == 'W':
            mons[int(f[4])] = (int(f[5]), int(f[6]), int(f[7]), int(f[8]))
    check('hundreds of monsters are synced', len(mons) > 300, f'(got {len(mons)})')

    # --- combat: kill a weak monster, get the reward ------------------------------------
    rats = [m for m, (t, x, y, hp) in mons.items() if t in (0, 1) and hp <= 40]
    check('there are rats and slimes to hunt', bool(rats))
    if rats:
        m = rats[0]
        t, x, y, hp = mons[m]
        a.pos(x=x, y=y + 1)
        for _ in range(3):
            a.send('HIT', a.id, 'W', m, 200, 0)
            a.pump(0.2)
        check('the monster dies', a.wait(rf'^SM1\|MDIE\|srv\|W\|{m}\|alice') is not None)
        check('the killer gets XP and gold', a.wait(r'^SM1\|REW\|srv\|aaaaaa\|\d+\|\d+\|') is not None)
        a.send('HIT', a.id, 'W', m, 200, 0)          # hitting a corpse does nothing
        a.pump(0.3)

    # --- monster AI: wolves notice you, walk over and bite ------------------------------
    wolves = [m for m, (t, x, y, hp) in mons.items() if t == 2]
    check('there are wolves', bool(wolves))
    if wolves:
        m = wolves[0]
        t, x, y, hp = mons[m]
        a.lines.clear()
        a.pos(x=x + 2, y=y)
        bit = None
        end = time.time() + 12
        while bit is None and time.time() < end:
            a.pos(x=x + 2, y=y)                      # stand still, keep the server fed with positions
            bit = a.wait(rf'^SM1\|MATK\|srv\|W\|{m}\|aaaaaa\|\d+', 1)
        check('an aggressive monster attacks', bit is not None)
        check('monsters move around players', any(l.startswith('SM1|MMOV|srv|W|') for l in a.lines))

    # --- anti-spoofing (python3 and socat hubs) -------------------------------------------
    b.lines.clear()
    a.send('ANN', 'srv', 'HACKED')                   # pretend to be the server
    a.send('CHAT', 'bbbbbb', 'bob', 'impersonated')  # pretend to be someone else
    a.send('CHAT', 'aaaaaa', 'alice', 'legit')
    b.pump(1.0)
    if HUB in ('python3', 'socat'):
        check('nobody can speak as the server', not any('HACKED' in l for l in b.lines))
        check('nobody can speak as another player', not any('impersonated' in l for l in b.lines))
    check('normal chat gets through', any('legit' in l for l in b.lines))

    # --- garbage does not take the server down ---------------------------------------------
    junk = ['', 'hello', 'SM1', 'SM1|', 'SM1|||||', 'SM1|HIT|aaaaaa|W|08|5|0', 'SM1|HIT|aaaaaa|W|1+1|5|0',
            'SM1|HIT|aaaaaa|W|a[$(touch /tmp/shellmmo_pwned)]|5|0', 'SM1|POS|aaaaaa|x|9|999|W|1|1|1|1|0',
            'SM1|DREQ|aaaaaa|99', 'SM1|DREQ|aaaaaa|$(id)', 'SM1|QADD|aaaaaa|K.1.1.0.1.1;ls',
            'SM1|SYNC|aaaaaa|../../etc', 'SM1|' + 'A' * 3000, '\xff\xfe garbage \x00', 'SM1|INV|aaaaaa|x|' + 'b' * 500]
    for j in junk:
        a.s.sendall((j + '\n').encode('utf-8', 'replace'))
    a.pump(0.5)
    check('injection attempts stay inert', not os.path.exists('/tmp/shellmmo_pwned'))
    a.lines.clear()
    a.send('SYNC', a.id, 'W')
    check('the server still answers after the garbage', a.wait(r'^SM1\|MON\|srv\|W\|', 8) is not None)

    # --- a solo dungeon -----------------------------------------------------------------------
    a.lines.clear()
    a.send('DREQ', a.id, 0)
    m = a.wait(r'^SM1\|DSTART\|srv\|(D\d+)\|0\|(\d+)\|(\d+)\|aaaaaa\|0\|0\|0$')
    check('a dungeon instance opens', m is not None)
    if m:
        inst = m.group(1)
        check('its monsters are sent', a.wait(rf'^SM1\|MON\|srv\|{inst}\|') is not None)
        a.pos(mp=inst, x=5, y=5)
        a.lines.clear(); time.sleep(1.6)
        a.send('DREQ', a.id, 0)                      # walking in again resumes the same instance
        check('re-entering resumes the instance', a.wait(rf'^SM1\|DSTART\|srv\|{inst}\|') is not None)

    # --- a party -------------------------------------------------------------------------------
    a.pos(); b.lines.clear(); a.lines.clear()
    a.send('INV', a.id, 'alice', 'bob')
    check('the invite arrives', b.wait(r'^SM1\|PINV\|srv\|bbbbbb\|alice$') is not None)
    b.send('PACC', b.id)
    m = a.wait(r'^SM1\|PARTY\|srv\|(p\d+)\|aaaaaa\|([a-f0-9,]+)$')
    check('the party forms', m is not None and 'bbbbbb' in (m.group(2) if m else ''))
    a.send('QADD', a.id, 'K.0.3.0.50.20')
    check('the leader takes a party quest', a.wait(r'^SM1\|PQUEST\|srv\|p\d+\|K\.0\.3\.0\.50\.20$') is not None)
    b.send('PLEAVE', b.id)
    check('leaving dissolves a party of two', a.wait(r'^SM1\|PARTY\|srv\|p\d+\|\|$') is not None)

    # --- leaving ----------------------------------------------------------------------------------
    b.send('BYE', b.id); b.close()
    a.close()


if __name__ == '__main__':
    main()
