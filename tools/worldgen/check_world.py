#!/usr/bin/env python3
"""Check a world map: size, known tiles, and that everything is reachable on foot.

Usage: check_world.py [world.txt]        (default: the world.txt of the project)

From the spawn point (read from src/01_core.sh) it walks every tile a player
can walk on and reports dungeon entrances ('>'), waystones ('Z', reached from
a neighbour) and walkable tiles that cannot be reached. Exit code 1 on problems.
"""
import os, re, sys
from collections import deque

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
WALK = set('.,"*:=_%<>SsNnIAKJDEqMHB')            # p_walk() in src/01_core.sh
KNOWN = set(' .,"*T~^#_:=%><SsNnIAQOFYPRZbcfghijlortuvwxzKCJWDVEGLadekpqyMUHXB')

def main():
    path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'world.txt')
    rows = [r for r in open(path, encoding='utf-8').read().split('\n') if r]
    w, h = len(rows[0]), len(rows)
    problems = []
    for y, r in enumerate(rows):
        if len(r) != w:
            problems.append(f'row {y} is {len(r)} wide, not {w}')
        bad = set(r) - KNOWN
        if bad:
            problems.append(f'row {y} has unknown tiles {sorted(bad)}')
    core = open(os.path.join(ROOT, 'src', '01_core.sh'), encoding='utf-8').read()
    m = re.search(r'SPAWN_X=(\d+) SPAWN_Y=(\d+)', core)
    sx, sy = (int(m.group(1)), int(m.group(2))) if m else (w // 2, h // 2)
    tile = lambda x, y: rows[y][x] if 0 <= y < h and 0 <= x < len(rows[y]) else '^'
    if tile(sx, sy) not in WALK:
        problems.append(f'spawn {sx},{sy} is on {tile(sx, sy)!r}')
    seen = {(sx, sy)}
    q = deque([(sx, sy)])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (x + dx, y + dy)
            if n not in seen and tile(*n) in WALK:
                seen.add(n); q.append(n)
    walk = [(x, y) for y in range(h) for x in range(w) if tile(x, y) in WALK]
    ents = [(x, y) for (x, y) in walk if tile(x, y) == '>']
    ways = [(x, y) for y in range(h) for x in range(w) if tile(x, y) == 'Z']
    for e in ents:
        if e not in seen:
            problems.append(f'dungeon entrance at {e} cannot be reached')
    for (x, y) in ways:
        if not any((x + dx, y + dy) in seen for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
            problems.append(f'waystone at {(x, y)} cannot be reached')
    lost = len(walk) - len(seen)
    print(f'world {w}x{h}: {len(walk)} walkable tiles, {len(seen)} reachable from the spawn '
          f'({lost} in closed pockets), {len(ents)} dungeon entrances, {len(ways)} waystones')
    for p in problems[:20]:
        print('  PROBLEM:', p)
    sys.exit(1 if problems else 0)

if __name__ == '__main__':
    main()
