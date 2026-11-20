#!/usr/bin/env python3
"""v6.2: real clients in a pty against a real server: create a hero, quit, come back, wrong password,
nothing is written on the player's computer, old local heroes move to the server."""
import fcntl, os, pty, random, re, select, shutil, signal, socket, struct, subprocess, sys, tempfile, termios, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.environ.get('GAME', os.path.join(ROOT, 'shellmmorpg.sh'))
PASS = FAIL = 0


def check(desc, cond, extra=''):
    global PASS, FAIL
    if cond: PASS += 1
    else: FAIL += 1; print(f'  FAIL [test_login] {desc} {extra}')


class Client:
    def __init__(self, port, name, home, pw, extra_env=None):
        self.m, s = pty.openpty()
        fcntl.ioctl(s, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
        env = dict(os.environ, SHELLMMO_DIR=home, TERM='xterm-256color', SHELLMMO_PASS=pw, **(extra_env or {}))
        self.err = open(os.path.join(home, f'{name}.stderr'), 'w+')
        self.p = subprocess.Popen(['bash', GAME, '--join', f'127.0.0.1:{port}', '--name', name], stdin=s, stdout=s,
                                  stderr=self.err, env=env, start_new_session=True)
        self.buf = b''

    def pump(self, secs):
        end = time.time() + secs
        while time.time() < end:
            if select.select([self.m], [], [], 0.05)[0]:
                try: self.buf += os.read(self.m, 65536)
                except OSError: break

    def text(self):
        return re.sub(rb'\x1b\[[0-9;?]*[a-zA-Z]', b'', self.buf).decode('utf8', 'replace')

    def key(self, k): os.write(self.m, k.encode())

    def stop(self):
        try: os.killpg(self.p.pid, signal.SIGTERM)
        except OSError: pass
        try: self.p.wait(timeout=8)
        except subprocess.TimeoutExpired: os.killpg(self.p.pid, signal.SIGKILL)
        self.pump(0.3)

    def errors(self):
        self.err.seek(0); return [l for l in self.err.read().splitlines() if re.search(r'line \d+:|syntax error|unbound', l)]


def main():
    port = random.randint(20000, 40000)
    base = tempfile.mkdtemp(prefix='shellmmo_login_')
    for d in ('srv', 'home1', 'home2', 'home3'): os.mkdir(f'{base}/{d}')
    env = dict(os.environ, SHELLMMO_DIR=f'{base}/srv', SHELLMMO_WB_DELAY='9999999')
    env.pop('SHELLMMO_OPEN', None)
    srv = subprocess.Popen(['bash', GAME, '--server', str(port)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    try:
        for _ in range(100):
            time.sleep(0.1)
            try: socket.create_connection(('127.0.0.1', port), timeout=1).close(); break
            except OSError: pass
        time.sleep(1.5)
        # a new hero: Cleric (4), default symbol and color
        c = Client(port, 'tess', f'{base}/home1', 'secret1')
        c.pump(3); c.key('4'); c.pump(0.7); c.key('\r'); c.pump(0.7); c.key('\r'); c.pump(2.5)
        check('a new hero enters the world', 'online' in c.text())
        for _ in range(8): c.key('d'); c.pump(0.15)
        c.stop()
        check('the hero is saved on the server', os.path.isfile(f'{base}/srv/chars/tess.char'))
        check('nothing is saved on the player\'s computer', not [f for f in os.listdir(f'{base}/home1') if f.endswith('.char')], str(os.listdir(f'{base}/home1')))
        check('no bash errors in the client', not c.errors(), str(c.errors()[:2]))
        # coming back (from another computer)
        c2 = Client(port, 'tess', f'{base}/home2', 'secret1')
        c2.pump(5)
        check('the hero is loaded: welcome back', 'Welcome back' in c2.text())
        check('...as a Cleric', 'Cleric' in c2.text())
        # v6.3: logging in from a third computer takes the hero over, the second session ends without saving
        c2b = Client(port, 'tess', f'{base}/home3', 'secret1')
        c2b.pump(5); c2.pump(2)
        check('a new login takes the hero over', 'Welcome back' in c2b.text())
        check('...the old session ends', c2.p.poll() is not None and 'somewhere else' in c2.text(), c2.text()[-200:])
        c2b.stop()
        # wrong password
        c3 = Client(port, 'tess', f'{base}/home3', 'wrongpw')
        c3.pump(3); c3.stop()
        c3.err.seek(0); e3 = c3.err.read()
        check('a wrong password is refused', 'refused' in e3 and c3.p.returncode not in (None, 0), e3[-200:])
        # an old local hero moves to the server
        shutil.copy(f'{base}/srv/chars/tess.char', f'{base}/home3/oldie.char')
        c4 = Client(port, 'oldie', f'{base}/home3', 'secret1')
        c4.pump(5); c4.stop()
        check('an old local hero moves to the server', os.path.isfile(f'{base}/srv/chars/oldie.char') and not os.path.exists(f'{base}/home3/oldie.char')
              and os.path.exists(f'{base}/home3/oldie.char.moved-to-server'))
    finally:
        os.killpg(srv.pid, signal.SIGTERM)
        shutil.rmtree(base, ignore_errors=True)
    print(f'{"test_login":<14} {PASS:4d} passed  {FAIL} failed')
    sys.exit(1 if FAIL else 0)


main()
