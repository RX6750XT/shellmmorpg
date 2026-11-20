#!/usr/bin/env python3
"""Minimal terminal emulator for the render tests.

Usage: vt.py FRAME_FILE ROWS COLS MW VH      check one frame
       vt.py --cells FRAME_FILE ROWS COLS     print every cell with its colors (for diffs)
Replays the escape sequences of one rendered frame (no auto-wrap, like the
game sets with ESC[?7l) and checks that
  * nothing was written past the right edge of the terminal,
  * the map frame (box drawing) is intact on both sides,
  * no raw escape garbage ended up on screen.
Prints problems and exits 1 if there are any.
"""
import re, sys, unicodedata

ZW = set('‍️︎')

def width(ch):
    if ch in ZW or unicodedata.combining(ch):
        return 0
    return 2 if unicodedata.east_asian_width(ch) in 'WF' else 1

def run(path, rows, cols, mw, vh):
    data = open(path, 'rb').read().decode('utf-8', 'replace')
    scr = [[' '] * cols for _ in range(rows)]
    r = c = 0
    problems = []
    over = 0
    over_rows = {}
    for tok in re.split(r'(\x1b\[[0-9;?]*[A-Za-z]|\n|\r)', data):
        if not tok:
            continue
        if tok == '\n':
            r = min(r + 1, rows - 1); continue
        if tok == '\r':
            c = 0; continue
        if tok.startswith('\x1b['):
            m = re.match(r'\x1b\[(\d*);?(\d*)H$', tok)
            if m:
                r = int(m.group(1) or 1) - 1; c = int(m.group(2) or 1) - 1
            elif tok == '\x1b[2J':
                scr = [[' '] * cols for _ in range(rows)]
            continue
        for ch in tok:
            w = width(ch)
            if w == 0:
                continue
            if ch == '\x1b' or (ord(ch) < 32):
                problems.append(f'control character {ord(ch)} at row {r + 1}')
                continue
            if c + w > cols:
                over += 1
                over_rows.setdefault(r, '')
                over_rows[r] += ch
            elif 0 <= r < rows:
                scr[r][c] = ch
                if w == 2:
                    scr[r][c + 1] = ''
            c += w
    if over:
        rr = sorted(over_rows)
        problems.append(f'{over} cells written past column {cols} (rows {[x + 1 for x in rr[:5]]}, e.g. {over_rows[rr[0]][:40]!r})')
    # the map frame: rows 3..vh+2 have a border at column 1 and column mw+2
    if mw + 2 <= cols:
        for y in range(2, vh + 2):
            if scr[y][0] != '│':
                problems.append(f'left frame broken at row {y + 1}: {scr[y][0]!r}')
                break
        for y in range(2, vh + 2):
            if scr[y][mw + 1] != '│':
                line = ''.join(scr[y][max(0, mw - 6):mw + 4])
                problems.append(f'right frame broken at row {y + 1}: ...{line}...')
                break
        if scr[1][0] != '╭' or scr[vh + 2][0] != '╰':
            problems.append('frame corners missing')
    for p in problems[:6]:
        print(f'{path}: {p}')
    return 1 if problems else 0

def sgr(state, params):
    """apply one SGR sequence to (fg, bg, bold, blink, rev)"""
    fg, bg, bold, blink, rev = state
    p = [int(x) if x else 0 for x in params.split(';')] if params else [0]
    i = 0
    while i < len(p):
        v = p[i]
        if v == 0: fg, bg, bold, blink, rev = None, None, 0, 0, 0
        elif v == 1: bold = 1
        elif v == 2: bold = 2
        elif v == 22: bold = 0
        elif v == 5: blink = 1
        elif v == 7: rev = 1
        elif v in (38, 48) and i + 2 < len(p) and p[i + 1] == 5:
            if v == 38: fg = p[i + 2]
            else: bg = p[i + 2]
            i += 2
        elif 30 <= v <= 37 or 90 <= v <= 97: fg = v
        elif 40 <= v <= 47 or 100 <= v <= 107: bg = v
        elif v == 39: fg = None
        elif v == 49: bg = None
        i += 1
    return (fg, bg, bold, blink, rev)

def cells(path, rows, cols):
    data = open(path, 'rb').read().decode('utf-8', 'replace')
    scr = [[(' ', None)] * cols for _ in range(rows)]
    r = c = 0
    st = (None, None, 0, 0, 0)
    for tok in re.split(r'(\x1b\[[0-9;?]*[A-Za-z]|\n|\r)', data):
        if not tok: continue
        if tok.startswith('\x1b['):
            m = re.match(r'\x1b\[(\d*);?(\d*)H$', tok)
            if m: r = int(m.group(1) or 1) - 1; c = int(m.group(2) or 1) - 1
            elif tok.endswith('m'): st = sgr(st, tok[2:-1])
            elif tok == '\x1b[2J': scr = [[(' ', None)] * cols for _ in range(rows)]
            elif tok == '\x1b[K':
                for x in range(c, cols):
                    if 0 <= r < rows: scr[r][x] = (' ', st[1])
            continue
        if tok in '\r\n': continue
        for ch in tok:
            w = width(ch)
            if w == 0: continue
            if 0 <= r < rows and c + w <= cols:
                # a space only shows its background
                scr[r][c] = (ch, (st[1],) if ch == ' ' else st)
                if w == 2: scr[r][c + 1] = ('', None)
            c += w
    return scr

if __name__ == '__main__':
    if sys.argv[1] == '--cells':
        f, rows, cols = sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
        for y, line in enumerate(cells(f, rows, cols)):
            for x, (ch, a) in enumerate(line):
                if ch: print(y, x, ch, a)
        sys.exit(0)
    f, rows, cols, mw, vh = sys.argv[1], *map(int, sys.argv[2:6])
    sys.exit(run(f, rows, cols, mw, vh))
