#!/usr/bin/env python3
"""v6.3: the world server dies under a host and a friend (real clients in a pty): the host restarts it,
both log in again by themselves, nothing is lost, no bash errors and no "Killed" notices on screen."""
import fcntl, os, pty, random, re, select, shutil, signal, struct, subprocess, sys, tempfile, termios, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
GAME = os.environ.get('GAME', os.path.join(ROOT, 'shellmmorpg.sh'))
PASS = FAIL = 0
def check(desc, cond, extra=''):
    global PASS, FAIL
    if cond: PASS += 1
    else: FAIL += 1; print(f'  FAIL [test_restart] {desc} {extra}')

base = tempfile.mkdtemp(prefix='shellmmo_restart_')
port = random.randint(20000, 40000)
def client(args, home, name):
    m, s = pty.openpty(); fcntl.ioctl(s, termios.TIOCSWINSZ, struct.pack('HHHH', 40, 120, 0, 0))
    os.makedirs(f'{base}/{home}', exist_ok=True)
    env = dict(os.environ, SHELLMMO_DIR=f'{base}/{home}', SHELLMMO_PASS='abcd1234', TERM='xterm-256color', SHELLMMO_HUB='python3')
    env.pop('SHELLMMO_OPEN', None)
    p = subprocess.Popen(['bash', GAME] + args + ['--name', name], stdin=s, stdout=s, stderr=open(f'{base}/{name}.err', 'w'),
                         env=env, start_new_session=True)
    return [p, m, b'', name]
cl = []
def pump(t):
    end = time.time() + t
    while time.time() < end:
        for c in cl:
            if select.select([c[1]], [], [], 0.02)[0]:
                try: c[2] += os.read(c[1], 65536)
                except OSError: pass
def create(c):
    for k in ('4', '\r', '\r'): os.write(c[1], k.encode()); pump(0.6)
    pump(2)
txt = lambda c: re.sub(rb'\x1b\[[0-9;?]*[a-zA-Z]', b'', c[2]).decode('utf8', 'replace')
try:
    cl.append(client(['--port', str(port)], 'host', 'hosty')); pump(5); create(cl[0])
    cl.append(client(['--join', f'127.0.0.1:{port}'], 'friend', 'buddy')); pump(4); create(cl[1]); pump(3)
    check('two players online', '2 online' in txt(cl[1]))
    ws = subprocess.run(['pgrep', '-f', f'world-server {port}'], capture_output=True, text=True).stdout.split()
    check('the world server runs', len(ws) == 1, str(ws))
    for p in ws: os.kill(int(p), signal.SIGKILL)
    for c in cl: c[2] = b''
    pump(20)
    log = open(f'{base}/host/server.log').read()
    check('the host restarted the world server', log.count('world server v') == 2)
    check('...and both logged in again by themselves', 'login: hosty' in log and 'login: buddy' in log, log[-300:])
    for c in cl:
        t = txt(c)
        check(f'{c[3]} is still playing', c[0].poll() is None)
        on = re.findall(r'(\d) online', t); check(f'{c[3]} sees both players again', on and on[-1] == '2', str(on[-5:]))
        check(f'no "Killed" notice on {c[3]}\'s screen', 'Killed' not in t)
    for c in cl: os.killpg(c[0].pid, signal.SIGTERM)
    time.sleep(3)
    check('both heroes are saved on the host', sorted(f for f in os.listdir(f'{base}/host/chars') if f.endswith('.char')) == ['buddy.char', 'hosty.char'])
    for c in cl:
        errs = [l for l in open(f'{base}/{c[3]}.err').read().splitlines() if re.search(r'line \d+:|syntax error|unbound', l)]
        check(f'no bash errors ({c[3]})', not errs, str(errs[:2]))
finally:
    for c in cl:
        try: os.killpg(c[0].pid, signal.SIGKILL)
        except OSError: pass
    subprocess.run(['pkill', '-f', f'world-server {port}'])
    shutil.rmtree(base, ignore_errors=True)
print(f'{"test_restart":<14} {PASS:4d} passed  {FAIL} failed')
sys.exit(1 if FAIL else 0)
