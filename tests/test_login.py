#!/usr/bin/env python3
"""v6.2/v7.0: real players in a pty, joining a real server: the game runs on the server, the player's
terminal only sends keys. Create a hero (typing the password into the game on the server), quit, come back,
a takeover, wrong passwords, nothing on the player's computer, resizing the window."""
import fcntl, os, pty, random, re, select, shutil, signal, socket, struct, subprocess, sys, tempfile, termios, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.environ.get('GAME', os.path.join(ROOT, 'shellmmorpg.sh'))
PASS = FAIL = 0


def check(desc, cond, extra=''):
    global PASS, FAIL
    if cond: PASS += 1
    else: FAIL += 1; print(f'  FAIL [test_login] {desc} {extra}')


class Client:
    def __init__(self, port, name, home, extra_env=None):
        self.m, self.s = pty.openpty(); s = self.s
        fcntl.ioctl(s, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
        env = dict(os.environ, SHELLMMO_DIR=home, TERM='xterm-256color', **(extra_env or {}))
        env.pop('SHELLMMO_PASS', None)
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

    def wait(self, text, secs=8):
        end = time.time() + secs
        while time.time() < end and text not in self.text():
            self.pump(0.2)
        return text in self.text()

    def login(self, pw, new=False):
        ok = self.wait('Password for')
        self.key(pw + '\r')
        if new:
            ok = self.wait('Repeat the password') and ok
            self.key(pw + '\r')
        return ok

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
        # a new hero: the password is asked by the game on the server; Cleric (4), default symbol and color
        open(f'{base}/home1/tess.char', 'w').write('version=2\nCLS=1\nLVL=40\nGOLD=99999999\n')   # (a 6.x hero file: ignored now)
        c = Client(port, 'tess', f'{base}/home1')
        check('the game on the server asks for the password', c.login('secret1', new=True))
        c.pump(1); c.key('4'); c.pump(0.7); c.key('\r'); c.pump(0.7); c.key('\r'); c.pump(2.5)
        check('a new hero enters the world', 'online' in c.text())
        check('...a new one, not the file on the player\'s computer', 'Cleric' in c.text())
        for _ in range(8): c.key('d'); c.pump(0.15)
        fcntl.ioctl(c.s, termios.TIOCSWINSZ, struct.pack('HHHH', 32, 104, 0, 0)); os.killpg(c.p.pid, signal.SIGWINCH)
        c.buf = b''; c.pump(2.5)
        rows = [int(r) for r in re.findall(rb'\x1b\[(\d+);\d+H', c.buf)]
        check('a smaller window: the game on the server redraws at the new size', len(c.buf) > 3000 and rows and max(rows) <= 32, str(max(rows or [0])))
        c.key('\r'); c.pump(0.5); c.key('Q'); c.pump(0.5); c.key('y'); c.pump(6)
        check('Q quits the game on the server, the terminal closes', c.p.poll() is not None)
        check('the hero is saved on the server', os.path.isfile(f'{base}/srv/chars/tess.char'))
        check('nothing is written on the player\'s computer', sorted(os.listdir(f'{base}/home1')) == ['tess.char', 'tess.stderr'], str(os.listdir(f'{base}/home1')))
        check('no bash errors on the screen', not re.search(r'line \d+:|syntax error|unbound', c.text()))
        # coming back (from another computer)
        c2 = Client(port, 'tess', f'{base}/home2')
        c2.login('secret1'); c2.pump(4)
        check('the hero is loaded: welcome back', 'Welcome back' in c2.text())
        check('...as a Cleric', 'Cleric' in c2.text())
        # v6.3: logging in from a third computer takes the hero over, the second session ends without saving
        c2b = Client(port, 'tess', f'{base}/home3')
        c2b.login('secret1'); c2b.pump(4); c2.pump(3)
        check('a new login takes the hero over', 'Welcome back' in c2b.text())
        check('...the old session ends', c2.p.poll() is not None and 'somewhere else' in c2.text(), c2.text()[-200:])
        c2b.stop()
        # wrong password, three times
        c3 = Client(port, 'tess', f'{base}/home3')
        for pw in ('wrongpw1', 'wrongpw2', 'wrongpw3'):
            c3.login(pw); c3.buf = c3.buf.replace(b'Password for', b'(asked)'); c3.pump(1.2)
        c3.pump(3)
        check('wrong passwords are refused, the session ends', 'refused' in c3.text() and c3.p.poll() is not None, c3.text()[-200:])
        # an old hero file on the server's own disk is not handed to whoever logs in with that name
        shutil.copy(f'{base}/srv/chars/tess.char', f'{base}/srv/oldie.char')
        c4 = Client(port, 'oldie', f'{base}/home3')
        c4.login('secret1', new=True); c4.pump(2)
        check('a stranger does not get the host\'s old local hero', 'Choose your class' in c4.text() and not os.path.exists(f'{base}/srv/oldie.char.moved-to-server'))
        c4.stop()
        # only over ssh: --join to another machine is refused with a hint, --bind is gone
        r = subprocess.run(['bash', GAME, '--join', '192.168.1.20:4747'], capture_output=True, text=True, timeout=10)
        check('--join to another machine: use ssh', r.returncode != 0 and '--ssh user@192.168.1.20' in r.stderr, r.stderr)
        r = subprocess.run(['bash', GAME, '--server', '4747', '--bind', '0.0.0.0'], capture_output=True, text=True, timeout=10)
        check('--bind is gone', r.returncode != 0 and 'ssh' in r.stderr, r.stderr)
        # not a terminal client: the gate says so
        g = socket.create_connection(('127.0.0.1', port), timeout=3); g.sendall(b'SM1|HELLO|abcdef|x|0|1\n')
        time.sleep(0.5); check('an old 6.x client is told to update', g.recv(4096).startswith(b'SMT1|NO|'))
        g.close()
    finally:
        os.killpg(srv.pid, signal.SIGTERM)
        shutil.rmtree(base, ignore_errors=True)
    print(f'{"test_login":<14} {PASS:4d} passed  {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
