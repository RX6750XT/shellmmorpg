#!/usr/bin/env python3
"""v6.2: heroes live on the server. A real dedicated server (login required), once per hub:
login, new heroes, saving in chunks, loading, wrong passwords and the lock-out, one session per hero,
privacy of hero data (python3 and socat hubs), bad saves, nobody plays without a login."""
import os, random, shutil, signal, socket, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_net as T
T.NAME = 'test_acct'
from test_net import Bot, check

US = '\x1f'
HERO = 'version=2\nCLS=3\nLVL=7\nGOLD=123\nSYM=;\nINV=W.0.3.0 W.1.2.1\nQLS=' + '1' * 40


def login(bot, pw, keep=''):
    bot.send(*(['ALOAD', bot.id, bot.name, pw] + ([keep] if keep else [])))


def answer(bot, secs=4):
    """the next private answer (earlier ones are consumed)"""
    import re
    rx = re.compile(rf'^SM1\|AR{bot.id}\|srv\|(\w+)(?:\|(.*))?$')
    end = time.time() + secs
    while True:
        for i, l in enumerate(bot.lines):
            m = rx.match(l)
            if m:
                del bot.lines[:i + 1]
                return m.group(1), m.group(2) or ''
        if time.time() > end:
            return None, ''
        bot.pump(0.2)


def save(bot, text, size=1400):
    t = text.replace('\n', US)
    parts = [t[i:i + size] for i in range(0, len(t), size)] or ['']
    for n, c in enumerate(parts, 1):
        bot.send('ASAVE', bot.id, n, len(parts), c)


def load_text(bot):
    """collect the DATA chunks that follow a login"""
    k, rest = answer(bot)
    if k != 'DATA':
        return k, None
    n, total, chunk = rest.split('|', 2)
    txt = chunk
    while int(n) < int(total):
        k, rest = answer(bot)
        n, total, chunk = rest.split('|', 2)
        txt += chunk
    return k, txt.replace(US, '\n')


def run(port):
    a = Bot(port, '151add', 'alice')
    spy = Bot(port, '9e1715', 'spy')
    spy.send('HELLO', spy.id, 'spy', 0, 1)                  # (not logged in: the hub binds the id)
    time.sleep(0.3)

    # --- nobody plays without a login ------------------------------------------------------------------
    spy.hello(); spy.pump(1.0)
    check('without a login the server ignores HELLO/POS', not any('|CLOCK|' in l or '|MON|' in l for l in spy.lines))

    # --- a new hero ----------------------------------------------------------------------------------
    login(a, 'sekret123')
    check('a free name: NONE', answer(a)[0] == 'NONE')
    save(a, HERO + 'X' * 4000)                               # several chunks
    check('the first save is acknowledged', answer(a)[0] == 'ACK')
    a.hello()
    check('after the login the world comes in', a.wait(r'^SM1\|CLOCK\|srv\|\d+$') is not None)
    spy.pump(0.5)
    check('hero data and passwords never reach other players',
          not any(('ALOAD' in l or 'ASAVE' in l or f'|AR{a.id}|' in l or 'sekret123' in l) for l in spy.lines))

    # --- a hero with another name than the login is ignored ------------------------------------------------
    b = Bot(port, 'abc123', 'bob')
    login(b, 'bobpass1')
    check('bob is new too', answer(b)[0] == 'NONE')
    b.send('HELLO', b.id, 'alice', 0, 1)
    b.send('POS', b.id, 'alice', 0, 1, 'W', 80, 34, 100, 100, 0, '@', 1, '', '', '')
    b.pump(1.0)                                      # (checked in the server log at the end)

    # --- bad saves ----------------------------------------------------------------------------------------
    save(b, 'not a hero at all')
    check('garbage is refused (BAD)', answer(b)[0] == 'BAD')
    save(b, 'version=2\nCLS=1\nx=$(touch /tmp/pwned)\n')
    check('a line that is not KEY=value is refused', answer(b)[0] == 'BAD')
    save(b, 'version=2\nCLS=1\nLVL=1')
    check('a good small save works', answer(b)[0] == 'ACK')

    # --- logging in again --------------------------------------------------------------------------------
    a.send('BYE', a.id); a.close(); time.sleep(0.4)
    a2 = Bot(port, 'a2a2a2', 'alice')
    login(a2, 'wrong')
    k, rest = answer(a2)
    check('a wrong password is refused', k == 'DENY' and rest.startswith('PASS'), f'({k} {rest})')
    time.sleep(0.8)
    login(a2, 'sekret123')
    k, txt = load_text(a2)
    check('the hero comes back: DATA', k == 'DATA')
    check('...exactly as saved (newlines, ;, 4000 extra characters)', txt is not None and txt.startswith(HERO) and txt.rstrip('\n').endswith('X' * 4000), repr((txt or '')[:60]))

    # --- one session per hero: the right password takes it over (v6.3) ------------------------------------
    a2.hello(); time.sleep(0.8)
    a3 = Bot(port, 'a3a3a3', 'alice')
    login(a3, 'wrongpw')
    check('a wrong password does not take a hero over', answer(a3)[0] == 'DENY' and answer(a2, 1)[0] is None)
    time.sleep(0.8); login(a3, 'sekret123')
    k, txt = load_text(a3)
    check('the right password takes the hero over', k == 'DATA')
    k, rest = answer(a2)
    check('...and the old session is told (DENY KICK)', k == 'DENY' and rest.startswith('KICK'), f'({k} {rest})')
    save(a2, HERO)
    check('...and cannot save any more', answer(a2, 1.5)[0] in (None, 'AUTH'))
    a3b = Bot(port, 'a4a4a4', 'alice')
    login(a3b, 'sekret123', 'keep')
    check('a reconnect ("keep") never kicks anybody', answer(a3b)[0] == 'DENY' and answer(a3, 1)[0] is None)

    # --- lock-out after five wrong passwords -----------------------------------------------------------------
    c = Bot(port, 'c0ffee', 'carol')
    login(c, 'carolpw1'); answer(c); save(c, 'version=2\nCLS=0'); answer(c)
    c.send('BYE', c.id); time.sleep(0.3)
    d = Bot(port, 'd00d00', 'carol')
    res = []
    for i in range(6):
        time.sleep(0.8); login(d, 'nope%d' % i); res.append(answer(d)[1][:4])
    check('five wrong passwords lock the hero', res[-1] == 'LOCK', str(res))
    time.sleep(0.8); login(d, 'carolpw1')
    check('...even for the right password', answer(d)[0] == 'DENY')

    # --- reconnect without loading -----------------------------------------------------------------------------
    e = Bot(port, 'e1e1e1', 'erin')
    login(e, 'erinpw12'); answer(e); save(e, 'version=2\nCLS=2\nLVL=3'); answer(e)
    e.close(); time.sleep(0.5)
    e2 = Bot(port, 'e2e2e2', 'erin')
    time.sleep(8.5)                                          # the crashed session is stale by now
    login(e2, 'erinpw12', 'keep')
    check('login with "keep" answers OK, no data', answer(e2)[0] == 'OK')

    for x in (a2, a3, a3b, b, spy, d, e2): x.close()


def main():
    port = random.randint(20000, 40000)
    data = tempfile.mkdtemp(prefix='shellmmo_acct_')
    env = dict(os.environ, SHELLMMO_DIR=data, SHELLMMO_SESS_TOKEN=T.TOKEN, SHELLMMO_WB_DELAY='9999999')
    env.pop('SHELLMMO_OPEN', None)
    srv = subprocess.Popen(['bash', T.GAME, '--server', str(port)], env=env, stdout=subprocess.PIPE,
                           stderr=subprocess.STDOUT, start_new_session=True)
    try:
        for _ in range(100):
            time.sleep(0.1)
            try:
                socket.create_connection(('127.0.0.1', port), timeout=1).close(); break
            except OSError:
                pass
        time.sleep(1.5)
        run(port)
        check('the hero is a file on the server', os.path.isfile(os.path.join(data, 'chars', 'alice.char')))
        check('...and the password is not stored in the clear',
              'sekret123' not in open(os.path.join(data, 'chars', 'alice.pw')).read())
    finally:
        os.killpg(srv.pid, signal.SIGTERM)
        try:
            out = srv.communicate(timeout=5)[0].decode('utf-8', 'replace')
        except subprocess.TimeoutExpired:
            os.killpg(srv.pid, signal.SIGKILL); out = ''
        import re
        errs = [l for l in out.splitlines() if re.search(r'line \d+:|syntax error|command not found|unbound', l)]
        check('server log has no bash errors', not errs, '\n    ' + '\n    '.join(errs[:5]))
        check('a hero cannot enter the world under another name', '+ alice (abc123)' not in out and 'joined' in out)
        check('no password in the server log', 'sekret123' not in out and 'carolpw1' not in out)
        shutil.rmtree(data, ignore_errors=True)
    print(f'{"test_acct":<14} {T.PASS:4d} passed  {T.FAIL} failed')
    sys.exit(1 if T.FAIL else 0)


if __name__ == '__main__':
    main()
