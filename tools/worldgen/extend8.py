#!/usr/bin/env python3
"""v8.0: grow the 480x200 world of v4.0-7.2 to 600x200 - four new lands for levels 40-50, east of
everything (x 480-599), from the south up:
   the Shroudmarch      (y 150-199, levels 40-42)  mist, void-touched bog, dead trees, chasms
   the Gilded Expanse   (y 100-149, levels 42-45)  golden dunes, mesas, the ruins of a sun empire
   the Rimewastes       (y  50- 99, levels 45-47)  glaciers, frozen lakes, black pines
   the Aether Reach     (y   0- 49, levels 47-50)  storm heights and crystal spires above the sky gaps
No new tiles. The old east border (x 479) becomes a ridge with two passes: from Dawnspire (Starfall
Crater) into the Shroudmarch, and from Wyrmrest Keep (Dragonspine) into the Gilded Expanse. The new
lands are joined by one road from the south to the north."""
import os, random, math, sys
from collections import deque
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'world.txt')
random.seed(8080)
old = [list(r) for r in open(os.path.join(HERE, 'world_v40.txt')).read().split('\n') if r]
OW, OH = len(old[0]), len(old)
W, H = 600, 200
X0 = OW                                              # 480: where the new lands begin
g = [['^'] * W for _ in range(H)]
for y in range(OH):
    for x in range(OW):
        g[y][x] = old[y][x]

def setc(x, y, c):
    if 0 <= x < W and 0 <= y < H: g[y][x] = c
def get(x, y): return g[y][x] if 0 <= x < W and 0 <= y < H else '^'

def mknoise(cell, seed):
    rnd = random.Random(seed)
    gw, gh = W // cell + 3, H // cell + 3
    pts = [[rnd.random() for _ in range(gw)] for _ in range(gh)]
    def n(x, y):
        fx, fy = x / cell, y / cell; ix, iy = int(fx), int(fy); tx, ty = fx - ix, fy - iy
        tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
        P = lambda yy, xx: pts[yy % gh][xx % gw]
        a = P(iy, ix) * (1 - tx) + P(iy, ix + 1) * tx; b = P(iy + 1, ix) * (1 - tx) + P(iy + 1, ix + 1) * tx
        return a * (1 - ty) + b * ty
    return n
n1 = mknoise(7, 81); n2 = mknoise(3, 82); n3 = mknoise(11, 83); n4 = mknoise(5, 84)
def noise(x, y): return 0.6 * n1(x, y) + 0.4 * n2(x, y)
def ellipse(cx, cy, rx, ry, inner, outer=None, jag=0.0):
    for y in range(cy - ry - 2, cy + ry + 3):
        for x in range(cx - rx - 2, cx + rx + 3):
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + jag * (n2(x + 7, y + 7) - 0.5)
            if d < 0.6: setc(x, y, inner)
            elif d < 1.0 and outer: setc(x, y, outer)
def ridge(x0, x1, y0, y1, p=0.85):
    for y in range(y0, y1):
        for x in range(x0, x1):
            if random.random() < p: setc(x, y, '^')

# ---- the Shroudmarch (y 150-199): mist over a void-touched bog, dead trees, chasms ----------------------
for y in range(150, H - 1):
    for x in range(X0, W - 1):
        v = noise(x + 2100, y + 300)
        c = '%'
        if v > 0.55: c = 'E'
        if v < 0.26: c = 'B'
        if n2(x + 31, y + 7) > 0.74 or random.random() < 0.04: c = 'y'      # dead autumn trees
        if n3(x + 3, y + 51) > 0.78: c = 'G'                                # chasms into the void
        g[y][x] = c
for (cx, cy, rx, ry) in [(500, 160, 6, 3), (572, 168, 7, 3), (512, 190, 5, 2), (560, 192, 4, 2)]:
    ellipse(cx, cy, rx, ry, '~', '%', 0.3)

# ---- the Gilded Expanse (y 100-149): golden dunes, mesas, cactus, the ruins of a sun empire -------------
for y in range(100, 150):
    for x in range(X0, W - 1):
        v = noise(x + 2400, y + 700)
        c = 'S'
        if v > 0.58: c = 's'
        if v < 0.30: c = 'D'
        if n2(x + 17, y + 23) > 0.77: c = 'V'
        if random.random() < 0.025 and c in 'Ss': c = 'Y'
        g[y][x] = c
for (cx, cy, rx, ry) in [(566, 108, 5, 2), (498, 140, 4, 2)]:              # two oases
    ellipse(cx, cy, rx + 3, ry + 2, 'J')
    ellipse(cx, cy, rx, ry, '~', 'W')
for i in range(34):                                  # broken colonnades of the sun kings
    cx, cy = random.randint(486, 594), random.randint(103, 146)
    for dx in range(0, 5, 2):
        if get(cx + dx, cy) in 'SsD': setc(cx + dx, cy, '#')

# ---- the Rimewastes (y 50-99): glaciers, frozen lakes, black pines ---------------------------------------
for y in range(50, 100):
    for x in range(X0, W - 1):
        v = noise(x + 2700, y + 1100)
        c = 'N'
        if v > 0.60: c = 'n'
        if v < 0.28: c = 'I'
        if n2(x + 5, y + 19) > 0.72 or random.random() < 0.03: c = 'P'
        if n3(x + 44, y + 2) > 0.76: c = '^'
        g[y][x] = c
for (cx, cy, rx, ry) in [(500, 58, 7, 3), (580, 62, 6, 3), (556, 92, 8, 3), (494, 90, 4, 2)]:
    ellipse(cx, cy, rx, ry, '~', 'I', 0.3)

# ---- the Aether Reach (y 0-49): storm heights and crystal spires above the sky gaps ---------------------
for y in range(1, 50):
    for x in range(X0, W - 1):
        v = noise(x + 3000, y + 1500)
        c = 'H'
        if v > 0.60: c = 'K'
        if v < 0.27: c = 'N'
        if n2(x + 9, y + 37) > 0.76: c = 'X'
        if random.random() < 0.035 and c == 'K': c = 'C'
        if n3(x + 21, y + 13) > 0.77: c = 'G'                               # the sky below the islands
        g[y][x] = c

# ---- ridges: the old east border and between the new lands ------------------------------------------------
ridge(X0 - 1, X0 + 2, 0, H, 0.97)
ridge(X0, W, 49, 51); ridge(X0, W, 99, 101); ridge(X0, W, 149, 151)
for x in range(W): g[0][x] = '^'; g[H - 1][x] = '^'
for y in range(H): g[y][W - 1] = '^'

# ---- towns (21x13, as in v4.0: waystone at +3+2, campfire at +14+9) ----------------------------------------
def walls(x1, y1, x2, y2, floor='_', wall='#'):
    for y in range(y1, y2 + 1):
        for x in range(x1, x2 + 1):
            g[y][x] = wall if (y in (y1, y2) or x in (x1, x2)) else floor
TOWNS = {}
def town(name, x1, y1, ground):
    x2, y2 = x1 + 20, y1 + 12
    for y in range(y1 - 3, y2 + 4):
        for x in range(x1 - 3, x2 + 4):
            setc(x, y, ground)
    walls(x1, y1, x2, y2)
    cx, cy = x1 + 10, y1 + 6
    for (x, y) in [(cx - 1, y1), (cx, y1), (cx + 1, y1), (x1, cy), (x2, cy), (cx - 1, y2), (cx, y2), (cx + 1, y2)]: g[y][x] = '_'
    g[y1 + 2][x1 + 3] = 'Z'
    g[y1 + 9][x1 + 14] = 'F'
    TOWNS[name] = (x1, y1, x2, y2)
town('Lanternfall', 520, 166, '%')
town('Sunhollow', 520, 116, 'S')
town('Rimeholt', 520, 68, 'N')
town('Zenith', 520, 18, 'H')
for (x, y) in [(536, 172), (537, 172), (536, 173), (537, 173)]: g[y][x] = '~'      # Lanternfall's lantern pool
for (x, y) in [(527, 121), (528, 121), (527, 122), (528, 122)]: g[y][x] = '~'      # Sunhollow's sun well

# ---- dungeon entrances --------------------------------------------------------------------------------------
def ruin(x, y, ground):
    for dx in range(-2, 3): setc(x + dx, y - 1, '#')
    setc(x - 2, y, '#'); setc(x + 2, y, '#'); setc(x - 1, y, '_'); setc(x + 1, y, '_'); setc(x, y, '>')
    for dy in (1, 2, 3):
        for dx in (-1, 0, 1):
            if get(x + dx, y + dy) in '^TLRPYI~WCVGyUX#': setc(x + dx, y + dy, ground)
#        dungeon      x    y  ground
NEW_ENT = [(23, 584, 184, '%'),   # Shroud Abbey
           (24, 584, 134, 'S'),   # Tomb of the Sun Kings
           (25, 584, 84, 'N'),    # the Hall of Endless Winter
           (26, 584, 10, 'H'),    # the Starwright's Observatory
           (27, 584, 38, 'K'),    # the World's Edge
           (28, 500, 8, 'H')]     # raid: the Sundered Sky
for d, x, y, gr in NEW_ENT: ruin(x, y, gr)

# ---- roads ----------------------------------------------------------------------------------------------------
def road(points, ch=':'):
    for (x1, y1), (x2, y2) in zip(points, points[1:]):
        x, y = x1, y1
        while True:
            c = get(x, y)
            if c in '~IGL': setc(x, y, '=')
            elif c not in '>_=Z#F': setc(x, y, ch)
            elif c == '#': setc(x, y, '_')
            if (x, y) == (x2, y2): break
            if x != x2: x += 1 if x2 > x else -1
            elif y != y2: y += 1 if y2 > y else -1
def to_ent(gx, gy, ex, ey):                          # from a town gate to the front of a dungeon, around its walls
    road([(gx, gy), (ex - 4, gy), (ex - 4, ey + 3), (ex, ey + 3), (ex, ey + 1)])
# the two passes: Dawnspire -> the Shroudmarch -> Lanternfall; Wyrmrest Keep -> the Gilded Expanse -> Sunhollow
road([(440, 160), (476, 160), (476, 172), (520, 172)])
road([(460, 122), (520, 122)])
# the long road north: Lanternfall -> Sunhollow -> Rimeholt -> Zenith
road([(530, 166), (530, 128)])
road([(530, 116), (530, 80)])
road([(530, 68), (530, 30)])
# from every town's east gate to its dungeon
to_ent(540, 172, 584, 184)
to_ent(540, 122, 584, 134)
to_ent(540, 74, 584, 84)
road([(540, 24), (560, 24), (560, 14), (584, 14), (584, 11)])
road([(560, 24), (560, 42), (584, 42), (584, 39)])
road([(530, 18), (530, 12), (500, 12), (500, 9)])                    # Zenith's north gate -> the Sundered Sky
for d, x, y, gr in NEW_ENT:                          # keep dungeon fronts open
    for dy in (1, 2):
        if get(x, y + dy) not in ':=': setc(x, y + dy, ':')

# ---- reachability ---------------------------------------------------------------------------------------------
WALK = set('.,":=_*%><SsNnIAKJDEqMHB')
def bfs(sx, sy):
    seen = {(sx, sy)}; q = deque([(sx, sy)])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if (nx, ny) not in seen and 0 <= nx < W and 0 <= ny < H and g[ny][nx] in WALK:
                seen.add((nx, ny)); q.append((nx, ny))
    return seen
R = bfs(80, 35)
checks = {f'dungeon {d}': (x, y) for d, x, y, gr in NEW_ENT}
for k, (x1, y1, x2, y2) in TOWNS.items(): checks[k] = (x1 + 10, y1 + 6)
bad = 0
for k, (x, y) in checks.items():
    ok = (x, y) in R
    bad += not ok
    print(f'{k:14s} {g[y][x]!r} reachable={ok}', file=sys.stderr)
FILL = {'S': 'V', 's': 'V', 'N': 'P', 'n': 'P', 'I': '^', 'K': 'C', 'J': 'W', 'D': 'V', 'E': 'G',
        'H': 'X', 'B': 'y', '%': 'y'}
for y in range(H):
    for x in range(X0 - 1, W):
        if g[y][x] in WALK and (x, y) not in R and g[y][x] not in '><':
            g[y][x] = FILL.get(g[y][x], '^')
tot = sum(1 for y in range(H) for x in range(W) if g[y][x] in WALK)
print('walkable', tot, 'bad', bad, file=sys.stderr)
for k, v in TOWNS.items(): print('town', k, v, file=sys.stderr)
open(OUT, 'w').write('\n'.join(''.join(r) for r in g) + '\n')
sys.exit(1 if bad else 0)
