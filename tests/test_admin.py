#!/usr/bin/env python3
"""v6.4: admin tools. A real dedicated server (logins on), once per hub: the server decides who is an
admin (the admins file, read for every command), tells the client privately (AR<id> ADMIN), refuses
commands from everybody else, carries out world commands itself and sends hero effects privately
(AR<id> ADM ...); grant/revoke from inside the game; nobody can fake an admin effect."""
import os, random, re, shutil, signal, socket, subprocess, sys, tempfile, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_net as T
from test_net import Bot, check
from test_acct import login, answer, save
T.NAME = 'test_admin'

HERO = 'version=2\nCLS=0\nLVL=5'


def enter(bot, pw, x=100, y=40):
    login(bot, pw)
    if private(bot, 'NONE') is not None:
        save(bot, HERO); private(bot, 'ACK')
    bot.hello(x=x, y=y)
    bot.xy = (x, y)
    bot.pump(0.5)


BOTS = []


def adm(bot, cmd, args=''):
    """send an admin command; everything the bots got before it is dropped, so answers are matched to it"""
    for b in BOTS:                       # (and a POS: the server forgets heroes that say nothing for 15 s)
        b.pos(x=b.xy[0], y=b.xy[1]); b.pump(0.05); b.lines.clear()
    bot.send('ADM', bot.id, cmd, args)
    time.sleep(0.2)


def private(bot, kind, secs=3):
    """the oldest AR<id> line of this kind (ADMIN, ADM, ACK ...) not taken yet, as its fields"""
    rx = re.compile(rf'^SM1\|AR{bot.id}\|srv\|{kind}(?:\|(.*))?$')
    end = time.time() + secs
    while True:
        for i, l in enumerate(bot.lines):
            m = rx.match(l)
            if m:
                del bot.lines[i]
                return (m.group(1) or '').split('|')
        if time.time() > end:
            return None
        bot.pump(0.2)


def run(port, data):
    boss = Bot(port, 'ad0001', 'Boss')
    pleb = Bot(port, 'b00b00', 'pleb')
    BOTS[:] = [boss, pleb]
    enter(boss, 'bosspass')
    enter(pleb, 'plebpass', 130, 40)
    check('nobody is an admin to begin with (no ADMIN line)', private(boss, 'ADMIN', 1) is None and private(pleb, 'ADMIN', 1) is None)

    adm(pleb, 'gold', '5000'); adm(pleb, 'ann', 'hacked')
    check('a player who is not an admin is refused', private(pleb, 'ADM') == ['say', 'You are not an admin.'])
    pleb.pump(0.5)
    check('...and nothing happens', not any('hacked' in l for l in pleb.lines) and not any('|ADM|gold' in l for l in pleb.lines))

    # --- the server's list makes an admin (written by --admin add, read for every command) ----------------------
    r = subprocess.run(['bash', T.GAME, '--admin', 'add', 'boss'], env=dict(os.environ, SHELLMMO_DIR=data),
                       capture_output=True, text=True)
    check('--admin add writes the list', r.returncode == 0 and 'now an admin' in r.stdout, r.stdout + r.stderr)
    adm(boss, 'who')
    m = private(boss, 'ADM')
    check('an admin from the list: commands work at once', m and m[0] == 'say' and 'pleb' in m[1] and 'Boss' in m[1], str(m))
    check('...who shows the map and position', m and 'W 130,40' in m[1], str(m))

    # --- hero effects go privately to the hero ----------------------------------------------------------------------
    adm(boss, 'gold', '777')
    check('gold for yourself', private(boss, 'ADM') == ['gold', '777'])
    adm(boss, 'level', '30 pleb')
    check('level for somebody else: the target gets it', private(pleb, 'ADM') == ['level', '30'])
    adm(boss, 'level', '99')
    check('levels are checked', (private(boss, 'ADM') or [''])[0] == 'say')
    adm(boss, 'item', 'W.6.12.3 pleb')
    check('an item', private(pleb, 'ADM') == ['item', 'W.6.12.3'])
    adm(boss, 'item', 'a[$(touch /tmp/pwned_adm)]')
    check('a bad item code is refused', (private(boss, 'ADM') or [''])[1].startswith('Not an item'))
    adm(boss, 'god')
    check('god mode on', private(boss, 'ADM') == ['god', '1'])
    adm(boss, 'god')
    check('...and off again', private(boss, 'ADM') == ['god', '0'])
    adm(boss, 'tp', '130 50')
    m = private(boss, 'ADM')
    check('teleport to a walkable spot', m and m[0] == 'tp' and m[1] == 'W', str(m))
    adm(boss, 'summon', 'pleb')
    m = private(pleb, 'ADM')
    check('summon moves the other hero next to the admin', m and m[0] == 'tp' and abs(int(m[2]) - 100) <= 6, str(m))
    pleb.lines.clear(); boss.pump(0.3)
    check('other players never see admin effects', not any(f'|AR{boss.id}|' in l for l in pleb.lines))

    # --- world commands ---------------------------------------------------------------------------------------------
    boss.lines.clear()
    adm(boss, 'spawn', 'wolf 3')
    check('spawn: creatures appear next to the admin', boss.wait(r'^SM1\|MON\|srv\|W\|\d+\|2\|', 4) is not None)
    check('...and the admin is told', (private(boss, 'ADM') or ['', ''])[1].startswith('Spawned 3 x Wolf'))
    time.sleep(0.3); boss.lines.clear()
    adm(boss, 'kill', '6')
    check('kill: the monsters around die', boss.wait(r'^SM1\|MDIE\|srv\|W\|\d+\|Boss$', 4) is not None)
    adm(boss, 'time', '22:30')
    m = boss.wait(r'^SM1\|CLOCK\|srv\|(\d+)$', 4)
    check('time: the clock jumps', m and abs(int(m.group(1)) // 800 - (22 * 60 + 30)) <= 2, m and m.group(1))
    adm(boss, 'weather', 'Silverlake storm')
    check('weather', boss.wait(r'^SM1\|WEATHER\|srv\|1\|storm\|180$', 4) is not None)
    adm(boss, 'ann', 'Hello all')
    check('announcements reach everybody', pleb.wait(r'^SM1\|ANN\|srv\|\[Boss\] Hello all$', 4) is not None)

    # --- grant and revoke from inside the game ----------------------------------------------------------------------
    adm(boss, 'grant', 'pleb')
    check('grant: the hero is told at once', private(pleb, 'ADMIN') == ['1'])
    adm(pleb, 'heal')
    check('...and can use the tools', private(pleb, 'ADM') == ['heal'])
    check('...and it is in the file', 'pleb' in open(os.path.join(data, 'admins')).read())
    adm(boss, 'revoke', 'pleb')
    check('revoke: told at once', private(pleb, 'ADMIN') == ['0'])
    adm(pleb, 'heal')
    check('...and refused again', private(pleb, 'ADM') == ['say', 'You are not an admin.'])

    # --- nobody fakes the server ---------------------------------------------------------------------------------------
    pleb.send(f'AR{pleb.id}', 'srv', 'ADM', 'gold', '999999')
    pleb.send(f'AR{pleb.id}', pleb.id, 'ADM', 'gold', '999999')
    time.sleep(0.4); pleb.lines.clear(); pleb.pump(0.5)
    check('a player cannot send itself admin effects', not any('999999' in l for l in pleb.lines))

    adm(boss, 'kick', 'pleb')
    k, rest = answer(pleb)
    check('kick: the hero is sent out (DENY KICK)', k == 'DENY' and rest.startswith('KICK'), f'{k} {rest}')

    # --- the file changes count at once (no restart) -----------------------------------------------------------------
    subprocess.run(['bash', T.GAME, '--admin', 'remove', 'Boss'], env=dict(os.environ, SHELLMMO_DIR=data), capture_output=True)
    adm(boss, 'who')
    check('--admin remove: refused from the next command on', private(boss, 'ADM') == ['say', 'You are not an admin.'])
    for b in (boss, pleb): b.close()


def main():
    port = random.randint(20000, 40000)
    data = tempfile.mkdtemp(prefix='shellmmo_adm_')
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
        run(port, data)
    finally:
        os.killpg(srv.pid, signal.SIGTERM)
        try:
            out = srv.communicate(timeout=5)[0].decode('utf-8', 'replace')
        except subprocess.TimeoutExpired:
            os.killpg(srv.pid, signal.SIGKILL); out = ''
        errs = [l for l in out.splitlines() if re.search(r'line \d+:|syntax error|command not found|unbound', l)]
        check('server log has no bash errors', not errs, '\n    ' + '\n    '.join(errs[:5]))
        check('admin commands are in the server log', 'admin Boss: gold 777' in out)
        check('no code from a command ran', not os.path.exists('/tmp/pwned_adm'))
        shutil.rmtree(data, ignore_errors=True)
    print(f'{"test_admin":<14} {T.PASS:4d} passed  {T.FAIL} failed')
    sys.exit(1 if T.FAIL else 0)


if __name__ == '__main__':
    main()
