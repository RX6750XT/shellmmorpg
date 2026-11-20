#!/usr/bin/env python3
"""v4.0: grow the 360x150 world of v2.0-3.0 to 480x200 - seven new lands for levels 30-40.
East (x 360-479): Stormreach Peaks, Gloomcap Hollows, Dragonspine.  South (y 150-199): the Sunken
Kingdom, Duskwood, the Bonefields, Starfall Crater. New tiles:
   q autumn leaves (walk)   y autumn tree (blocks)    M mycelium (walk)   U giant mushroom (blocks)
   H storm heights (walk)   X thunder crag (blocks)   B bone field (walk)"""
import os, random, math, sys
from collections import deque
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'world.txt')
random.seed(4040)
old = [list(r) for r in open(os.path.join(HERE, 'world_v20.txt')).read().split('\n') if r]
OW, OH = len(old[0]), len(old)
W, H = 480, 200
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
n1 = mknoise(7, 41); n2 = mknoise(3, 42); n3 = mknoise(11, 43); n4 = mknoise(5, 44)
def noise(x, y): return 0.6 * n1(x, y) + 0.4 * n2(x, y)
def ellipse(cx, cy, rx, ry, inner, outer=None, jag=0.0):
    for y in range(cy - ry - 2, cy + ry + 3):
        for x in range(cx - rx - 2, cx + rx + 3):
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 + jag * (n2(x + 7, y + 7) - 0.5)
            if d < 0.6: setc(x, y, inner)
            elif d < 1.0 and outer: setc(x, y, outer)
def ridge_rows(y0, y1, x0, x1, p=0.85):
    for y in range(y0, y1):
        for x in range(x0, x1):
            if random.random() < p: g[y][x] = '^'
def ridge_cols(x0, x1, y0, y1, p=0.85):
    for y in range(y0, y1):
        for x in range(x0, x1):
            if random.random() < p: g[y][x] = '^'

# ---- Stormreach Peaks (x 360-479, y 0-49): wind-scoured heights, thunder crags, snow -------------
for y in range(1, 50):
    for x in range(360, W - 1):
        v = noise(x, y + 1200)
        c = 'H'
        if v < 0.30: c = 'N'
        if n2(x + 13, y + 5) > 0.73: c = 'X'
        if n3(x + 9, y + 61) > 0.74: c = '^'
        g[y][x] = c
for (cx, cy, rx, ry) in [(386, 40, 6, 3), (452, 30, 7, 3)]:
    ellipse(cx, cy, rx, ry, '~', 'I')

# ---- Gloomcap Hollows (x 360-479, y 50-99): giant mushrooms on mycelium, dark pools -------------
for y in range(50, 100):
    for x in range(360, W - 1):
        v = noise(x + 500, y + 200)
        c = 'M'
        if v > 0.62 or random.random() < 0.05: c = 'U'
        elif v < 0.27: c = '%'
        if n3(x + 31, y + 17) > 0.79: c = '^'
        g[y][x] = c
for (cx, cy, rx, ry) in [(380, 60, 5, 3), (448, 86, 6, 3), (396, 92, 4, 2)]:
    ellipse(cx, cy, rx, ry, '~', '%')

# ---- Dragonspine (x 360-479, y 100-149): black rock, ash, lava rivers ------------------------------
for y in range(100, 150):
    for x in range(360, W - 1):
        v = noise(x + 900, y + 400)
        c = 'A'
        if v < 0.30: c = 'D'
        if n2(x + 51, y + 3) > 0.74: c = 'R'
        if n3(x + 8, y + 88) > 0.73: c = 'V'
        g[y][x] = c
lx = 455.0                                          # a lava river from the north-east
for y in range(100, 148):
    lx += math.sin(y / 5.0) * 1.3 - 0.35
    for dx in (0, 1): setc(int(lx) + dx, y, 'L')
for y in range(132, 148):
    for x in range(366, 400):
        if n4(x, y) > 0.64: g[y][x] = 'L'

# ---- the Sunken Kingdom (x 0-119, y 150-199): drowned ruins on scattered islands -------------------
for y in range(150, H - 1):
    for x in range(1, 120):
        g[y][x] = '~'
islands = [(60, 172, 20, 10), (22, 188, 13, 7), (100, 160, 11, 6), (96, 189, 12, 6), (28, 158, 9, 4), (80, 176, 6, 3)]
for (cx, cy, irx, iry) in islands:
    for y in range(cy - iry - 3, cy + iry + 4):
        for x in range(cx - irx - 3, cx + irx + 4):
            if not (1 <= x < 120 and 150 <= y < H - 1): continue
            d = ((x - cx) / irx) ** 2 + ((y - cy) / iry) ** 2 + 0.35 * (n2(x + 3, y + 3) - 0.5)
            if d < 0.55:
                c = 'J' if noise(x + 700, y) > 0.45 else 'S'
                if random.random() < 0.08: c = 'W'
                if n3(x + 5, y + 5) > 0.82: c = '^'
                g[y][x] = c
            elif d < 1.0:
                g[y][x] = 'S' if random.random() < 0.92 else 's'
for (rx_, ry_) in [(44, 166), (76, 180), (16, 184), (104, 158), (92, 192), (66, 160)]:   # drowned ruins
    for dy in range(-1, 2):
        for dx in range(-1, 2):
            if (dx, dy) != (0, 0) and random.random() < 0.75 and get(rx_ + dx, ry_ + dy) in 'SJs': setc(rx_ + dx, ry_ + dy, '#')

# ---- Duskwood (x 120-239, y 150-199): an autumn forest that never sees the sun ---------------------
for y in range(150, H - 1):
    for x in range(120, 240):
        v = noise(x + 300, y + 600)
        c = 'q'
        if v > 0.60 or random.random() < 0.07: c = 'y'
        elif v < 0.25: c = '%'
        if n2(x + 3, y + 40) > 0.80: c = 'T'
        if random.random() < 0.015 and c == 'q': c = '*'
        if n3(x + 70, y + 9) > 0.80: c = '^'
        g[y][x] = c
for x in range(120, 126):                           # a beach where the forest meets the sea
    for y in range(150, H - 1):
        if g[y][x] != '^' and (x < 123 or random.random() < 0.5): g[y][x] = 'S'
for (cx, cy, rx, ry) in [(206, 160, 6, 3), (150, 176, 4, 2), (220, 190, 5, 3)]:
    ellipse(cx, cy, rx, ry, '~', '%')

# ---- the Bonefields (x 240-359, y 150-199): ash and bones of an old war, open graves ---------------
for y in range(150, H - 1):
    for x in range(240, 360):
        v = noise(x + 1100, y + 100)
        c = 'B'
        if v < 0.30: c = 'A'
        if n2(x + 21, y + 13) > 0.76: c = 'R'
        if n3(x + 14, y + 33) > 0.77: c = 'G'
        g[y][x] = c
for i in range(26):                                 # crypts and broken walls
    cx, cy = random.randint(246, 352), random.randint(154, 195)
    for dx in range(-1, 2):
        if get(cx + dx, cy) in 'BA': setc(cx + dx, cy, '#')

# ---- Starfall Crater (x 360-479, y 150-199): where the star came down --------------------------------
CX, CY = 420, 178
for y in range(150, H - 1):
    for x in range(360, W - 1):
        r = math.hypot((x - CX) / 1.6, y - CY) + 3 * (n2(x, y) - 0.5)
        if r > 27: c = 'H' if n1(x, y) > 0.35 else 'N'
        elif r > 23: c = 'X' if random.random() < 0.7 else 'H'
        elif r > 4: c = 'K' if noise(x + 50, y + 50) > 0.40 else 'E'
        else: c = 'G'
        if 4 < r <= 23 and random.random() < 0.06: c = 'C'
        g[y][x] = c

# ---- ridges between the lands, and the old border ----------------------------------------------------
ridge_rows(49, 51, 360, W)          # Stormreach | Gloomcap
ridge_rows(99, 101, 360, W)         # Gloomcap | Dragonspine
ridge_rows(149, 151, 360, W)        # Dragonspine | Starfall
ridge_rows(149, 151, 120, 360)      # old south border | Duskwood, Bonefields
ridge_cols(238, 242, 150, H)        # Duskwood | Bonefields
ridge_cols(358, 362, 150, H)        # Bonefields | Starfall
for x in range(W): g[0][x] = '^'; g[H - 1][x] = '^'
for y in range(H): g[y][W - 1] = '^'; g[y][0] = '^' if y >= 100 else g[y][0]

# ---- towns -------------------------------------------------------------------------------------------
def walls(x1, y1, x2, y2, floor='_', wall='#'):
    for y in range(y1, y2 + 1):
        for x in range(x1, x2 + 1):
            g[y][x] = wall if (y in (y1, y2) or x in (x1, x2)) else floor
TOWNS = {}
def town(name, x1, y1, ground):
    x2, y2 = x1 + 20, y1 + 12
    for y in range(y1 - 3, y2 + 4):                  # a clearing around the walls
        for x in range(x1 - 3, x2 + 4):
            if get(x, y) not in '~' or ground == 'S': setc(x, y, ground)
    walls(x1, y1, x2, y2)
    cx, cy = x1 + 10, y1 + 6
    for (x, y) in [(cx - 1, y1), (cx, y1), (cx + 1, y1), (x1, cy), (x2, cy), (cx - 1, y2), (cx, y2), (cx + 1, y2)]: g[y][x] = '_'
    g[y1 + 2][x1 + 3] = 'Z'
    g[y1 + 9][x1 + 14] = 'F'
    TOWNS[name] = (x1, y1, x2, y2)
town('Hollowmere', 168, 166, 'q')
town('Tidewatch', 50, 166, 'S')
town('Skyhold', 410, 18, 'H')
town('Sporeholm', 410, 68, 'M')
town('Wyrmrest Keep', 410, 116, 'A')
town('Gravewatch', 290, 166, 'B')
town('Dawnspire', 366, 154, 'H')
for (x, y) in [(184, 176), (185, 176), (184, 177), (185, 177)]: g[y][x] = '~'      # Hollowmere's well-pond

# ---- dungeon entrances -------------------------------------------------------------------------------
def ruin(x, y, ground):
    for dx in range(-2, 3): setc(x + dx, y - 1, '#')
    setc(x - 2, y, '#'); setc(x + 2, y, '#'); setc(x - 1, y, '_'); setc(x + 1, y, '_'); setc(x, y, '>')
    for dy in (1, 2, 3):
        for dx in (-1, 0, 1):
            if get(x + dx, y + dy) in '^TLRPYI~WCVGyUX#': setc(x + dx, y + dy, ground)
NEW_ENT = [(11, 140, 190, 'q'), (12, 22, 190, 'S'), (13, 468, 8, 'H'), (14, 468, 92, 'M'),
           (15, 468, 140, 'A'), (16, 252, 192, 'B'), (17, 424, 182, 'K'),
           (18, 456, 166, 'H')]                    # v4.5: the raid, the Eclipse Throne, on the crater's east rim
for d, x, y, gr in NEW_ENT: ruin(x, y, gr)

# ---- roads -------------------------------------------------------------------------------------------
def road(points, ch=':'):
    for (x1, y1), (x2, y2) in zip(points, points[1:]):
        x, y = x1, y1
        while True:
            c = get(x, y)
            if c in '~IGL': setc(x, y, '=')
            elif c not in '>_=Z#': setc(x, y, ch)
            elif c == '#': setc(x, y, '_')
            if (x, y) == (x2, y2): break
            if x != x2: x += 1 if x2 > x else -1
            elif y != y2: y += 1 if y2 > y else -1
# Redrock Outpost -> Duskwood -> Hollowmere; Hollowmere -> the long bridge west -> Tidewatch
road([(177, 132), (178, 132), (178, 166)])
road([(168, 172), (70, 172)])
road([(178, 178), (178, 194), (140, 194), (140, 192)])                     # -> Witchroot Barrow
# Port Coral's south islet -> Tidewatch; Tidewatch -> the Drowned Cathedral
road([(66, 142), (66, 160), (60, 160), (60, 166)])
road([(50, 172), (34, 172), (34, 194), (22, 194), (22, 192)])
road([(100, 172), (100, 160)]); road([(96, 172), (96, 189)]); road([(60, 160), (28, 160)]); road([(80, 172), (80, 176)])   # island bridges
# Last Light Bastion -> the Bonefields -> Gravewatch -> Necropolis; Gravewatch -> Dawnspire
road([(278, 118), (278, 150), (300, 150), (300, 166)])
road([(290, 172), (260, 172), (260, 196), (252, 196), (252, 194)])
road([(310, 172), (360, 172), (360, 160), (366, 160)])
# Crystal Highlands -> Stormreach -> Skyhold -> Thunderpeak Citadel
road([(342, 22), (400, 22), (400, 24), (410, 24)])
road([(430, 24), (468, 24), (468, 10)])
# Emerald Jungle -> Gloomcap -> Sporeholm -> Mycelium Heart; Skyhold <-> Sporeholm
road([(346, 72), (400, 72), (400, 74), (410, 74)])
road([(430, 74), (460, 74), (460, 96), (468, 96), (468, 94)])
road([(420, 30), (420, 68)])
# Void Rift -> Dragonspine -> Wyrmrest Keep -> Dragon's Roost; Sporeholm <-> Wyrmrest
road([(330, 113), (400, 113), (400, 122), (410, 122)])
road([(430, 122), (460, 122), (460, 144), (468, 144), (468, 142)])
road([(420, 80), (420, 116)])
# Wyrmrest -> Starfall Crater -> Dawnspire -> the Shattered Star
road([(420, 128), (420, 150), (376, 150), (376, 154)])
road([(386, 160), (440, 160), (440, 186), (424, 186), (424, 184)])
road([(440, 168), (456, 168)])                                               # -> the Eclipse Throne (v4.5)
for d, x, y, gr in NEW_ENT:                          # keep dungeon fronts open
    for dy in (1, 2):
        if get(x, y + dy) not in ':=': setc(x, y + dy, ':')

# ---- reachability ------------------------------------------------------------------------------------
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
checks = {'barrow': (140, 191), 'cathedral': (22, 191), 'citadel': (468, 9), 'heart': (468, 93), 'roost': (468, 141),
          'necropolis': (252, 193), 'star': (424, 183), 'throne': (456, 167)}
for k, (x1, y1, x2, y2) in TOWNS.items(): checks[k] = (x1 + 10, y1 + 6)
bad = 0
for k, (x, y) in checks.items():
    ok = (x, y) in R
    bad += not ok
    print(f'{k:14s} {g[y][x]!r} reachable={ok}', file=sys.stderr)
FILL = {'S': 'W', 's': 'W', 'N': '^', 'n': '^', 'A': 'R', 'I': '^', 'K': 'C', 'J': 'W', 'D': 'V', 'E': 'G',
        'q': 'y', 'M': 'U', 'H': 'X', 'B': 'R', '%': 'U'}
for y in range(H):
    for x in range(W):
        if g[y][x] in WALK and (x, y) not in R and g[y][x] not in '><':
            if x >= 360 or y >= 150:
                c = FILL.get(g[y][x], '^')
                if c == 'U' and x < 360: c = 'y'                   # swamp in Duskwood: trees, not mushrooms
                g[y][x] = c
tot = sum(1 for y in range(H) for x in range(W) if g[y][x] in WALK)
print('walkable', tot, 'bad', bad, file=sys.stderr)
for k, v in TOWNS.items(): print('town', k, v, file=sys.stderr)
open(OUT, 'w').write('\n'.join(''.join(r) for r in g) + '\n')
