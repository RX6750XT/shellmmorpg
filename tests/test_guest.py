#!/usr/bin/env python3
"""v7.2: the shared, open ssh account (--ask-name): everybody comes in as the same unix user, the game on the
server asks for the hero's name and password. A new name leads to a new hero (after a yes), a known name logs in,
a wrong password or a 'no' goes back to the name, the case of a name is fixed, the guest login shell only passes
--hd/--ascii/--name on."""
import fcntl, os, pty, random, re, select, shutil, signal, socket, struct, subprocess, sys, tempfile, termios, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.environ.get('GAME', os.path.join(ROOT, 'shellmmorpg.sh'))
PASS = FAIL = 0


def check(desc, cond, extra=''):
    global PASS, FAIL
    if cond: PASS += 1
    else: FAIL += 1; print(f'  FAIL [test_guest] {desc} {extra}')


class Client:
    def __init__(self, port, home, args=(), argv=None):
        self.m, s = pty.openpty()
        fcntl.ioctl(s, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
        env = dict(os.environ, SHELLMMO_DIR=home, TERM='xterm-256color', USER='play')
        env.pop('SHELLMMO_PASS', None)
        self.p = subprocess.Popen(argv or ['bash', GAME, '--join', str(port), '--ask-name', *args], stdin=s, stdout=s,
                                  stderr=s, env=env, start_new_session=True)
        os.close(s)
        self.buf = b''

    def pump(self, secs):
        end = time.time() + secs
        while time.time() < end:
            if select.select([self.m], [], [], 0.05)[0]:
                try: self.buf += os.read(self.m, 65536)
                except OSError: break

    def text(self): return re.sub(rb'\x1b\[[0-9;?]*[a-zA-Z]', b'', self.buf).decode('utf8', 'replace')

    def key(self, k): os.write(self.m, k.encode())

    def wait(self, text, secs=8):
        end = time.time() + secs
        while time.time() < end and self.text().count(text) <= self.seen.get(text, 0):
            self.pump(0.2)
        n = self.text().count(text); ok = n > self.seen.get(text, 0); self.seen[text] = n
        return ok
    seen = None

    def answer(self, prompt, k):
        ok = self.wait(prompt); self.key(k + '\r'); return ok

    def stop(self):
        try: os.killpg(self.p.pid, signal.SIGTERM)
        except OSError: pass
        try: self.p.wait(timeout=8)
        except subprocess.TimeoutExpired: os.killpg(self.p.pid, signal.SIGKILL)


def client(*a, **k):
    c = Client(*a, **k); c.seen = {}; return c


def main():
    port = random.randint(20000, 40000)
    base = tempfile.mkdtemp(prefix='shellmmo_guest_')
    for d in ('srv', 'home'): os.mkdir(f'{base}/{d}')
    env = dict(os.environ, SHELLMMO_DIR=f'{base}/srv', SHELLMMO_WB_DELAY='9999999')
    srv = subprocess.Popen(['bash', GAME, '--server', str(port)], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    NAME, PW = 'Hero name', 'Password for'
    try:
        for _ in range(100):
            time.sleep(0.1)
            try: socket.create_connection(('127.0.0.1', port), timeout=1).close(); break
            except OSError: pass
        time.sleep(1.5)
        home = f'{base}/home'
        # ron has never played: a new name -> "create?" -> no goes back to the name; yes -> password twice -> classes
        c = client(port, home)
        check('the game asks for the hero name first', c.answer(NAME, 'ron'), c.text()[-300:])
        check('an unknown name asks for a password', c.answer(PW, 'ronpw1'))
        check('...then asks before it makes a new hero', c.answer('Create ron? [y/n]', 'n'))
        check('"no" goes back to the name', c.answer(NAME, 'r o n!'), c.text()[-300:])
        check('a bad name is refused and asked again', c.wait('Names are 1-12') and c.answer(NAME, 'ron'))
        c.answer(PW, 'ronpw1'); c.answer('Create ron? [y/n]', 'y')
        check('a new hero: repeat the password', c.answer('Repeat the password', 'ronpw1'))
        check('...and the class choice comes', c.wait('Choose your class'), c.text()[-300:])
        c.key('2'); c.pump(0.7); c.key('\r'); c.pump(0.7); c.key('\r'); c.pump(2.5)
        check('ron enters the world', 'online' in c.text())
        c.key('\r'); c.pump(0.3); c.key('Q'); c.pump(0.5); c.key('y'); c.pump(5)
        check('ron is saved on the server', os.path.isfile(f'{base}/srv/chars/ron.char'))
        check('nothing on the account\'s disk', os.listdir(home) == [], str(os.listdir(home)))
        # sid has played before (here: ron comes back): name, password, in - no "create"
        c = client(port, home)
        c.answer(NAME, 'ron')
        c.answer(PW, 'wrongpw')
        check('a wrong password is asked again', c.wait('Wrong password') and c.answer(PW, 'ronpw1'))
        c.pump(4)
        check('a known hero logs in: welcome back', 'Welcome back' in c.text() and 'Create' not in c.text(), c.text()[-300:])
        c.stop()
        # three wrong passwords: back to the name instead of a closed session
        c = client(port, home)
        c.answer(NAME, 'ron')
        for pw in ('bad1pw', 'bad2pw', 'bad3pw'): c.answer(PW, pw); c.pump(0.9)
        check('three wrong passwords go back to the name', c.wait(NAME) and c.p.poll() is None, c.text()[-300:])
        c.stop()
        # the case of the name is the hero's: RON -> ron
        c = client(port, home)
        c.answer(NAME, 'RON'); c.answer(PW, 'ronpw1'); c.pump(4)
        check('RON logs in as ron', 'Welcome back' in c.text(), c.text()[-300:])
        c.stop()
        # --name preselects the name (./shellmmorpg.sh --ssh play@host --name ron)
        c = client(port, home, ('--name', 'ron'))
        check('--name: straight to the password', c.answer(PW, 'ronpw1') and NAME not in c.text())
        c.pump(4); check('...and in', 'Welcome back' in c.text()); c.stop()
        # the gate: "?" and "?name" are fine, junk is not
        for hs, good in ((b'SMT1|?|120|40|-\n', True), (b'SMT1|?ron|120|40|hd\n', True), (b'SMT1|??|120|40|-\n', False),
                         (b'SMT1|?a;b|120|40|-\n', False)):
            g = socket.create_connection(('127.0.0.1', port), timeout=3); g.sendall(hs); time.sleep(0.4)
            check(f'gate handshake {hs!r}', g.recv(4096).startswith(b'SMT1|OK') == good); g.close()
        # the guest login shell (made by deploy/install.sh): only --hd/--ascii/--name get through
        src = open(os.path.join(ROOT, 'deploy', 'install.sh')).read()
        body = re.search(r"<<GUEST\n(.*?)\nGUEST\n", src, re.S).group(1)
        body = body.replace('\\$', '$').replace('$port', str(port)).replace('/opt/shellmmorpg/shellmmorpg.sh', GAME)
        body = body.replace("'$guest'", 'play').replace('exec ', 'echo ARGS: ', 1)
        open(f'{base}/guest.sh', 'w').write(body)
        r = subprocess.run(['bash', f'{base}/guest.sh', '-c', 'ignored'], capture_output=True, text=True, timeout=10,
                           env=dict(os.environ, SSH_ORIGINAL_COMMAND='shellmmorpg-play --hd --name ron; rm -rf / $(id) --port 1 --name a*b'))
        check('the guest shell needs a terminal', 'needs a terminal' in r.stdout, r.stdout + r.stderr)
        c = client(port, home, argv=['bash', f'{base}/guest.sh', '-c', 'x'])
        os.environ.pop('SSH_ORIGINAL_COMMAND', None)
        c.pump(1)
        check('the guest shell runs only --join --ask-name', f'ARGS: {GAME} --join {port} --ask-name' in c.text(), c.text())
        c = Client(port, home, argv=['env', 'SSH_ORIGINAL_COMMAND=x --hd --name ron;id --port 1 --name a*b --ascii', 'bash', f'{base}/guest.sh'])
        c.pump(1)
        check('...plus --hd/--ascii/--name, nothing else', f'--join {port} --ask-name --hd --ascii\r' in c.text(), c.text())
    finally:
        os.killpg(srv.pid, signal.SIGTERM)
        shutil.rmtree(base, ignore_errors=True)
    print(f'{"test_guest":<14} {PASS:4d} passed  {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
