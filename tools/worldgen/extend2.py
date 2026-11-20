#!/usr/bin/env python3
"""v2.0: grow the 240x100 world to 360x150 - five new regions with towns, roads and dungeons.
New tiles:  K crystal ground  C crystal spire (blocks)  J jungle ground  W jungle tree / palm (blocks)
            D red badland ground  V mesa rock (blocks)  E void ground  G void chasm (blocks)"""
import os, random, math, sys
from collections import deque
HERE = os.path.dirname(os.path.abspath(__file__))
OUT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, 'world.txt')
random.seed(2027)
old = [list(r) for r in open(os.path.join(HERE, 'world_v18.txt')).read().split('\n') if r]
OW, OH = len(old[0]), len(old)
W, H = 360, 150
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
n1 = mknoise(7, 11); n2 = mknoise(3, 12); n3 = mknoise(11, 13); n4 = mknoise(5, 14)
def noise(x, y): return 0.6 * n1(x, y) + 0.4 * n2(x, y)

# ---- Crystal Highlands (x 240-359, y 0-49) ------------------------------------------
for y in range(1, 50):
    for x in range(240, W - 1):
        v = noise(x, y + 900)
        c = 'K'
        if v < 0.30: c = 'N'                       # snow patches
        if n2(x + 31, y + 7) > 0.74: c = 'C'       # crystal spires
        if n3(x + 5, y + 50) > 0.72: c = '^'
        g[y][x] = c
for (cx, cy, rx, ry) in [(262, 40, 7, 3), (330, 30, 6, 3), (318, 8, 5, 2)]:   # frozen lakes with open water
    for y in range(cy - ry - 1, cy + ry + 2):
        for x in range(cx - rx - 1, cx + rx + 2):
            d = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
            if d < 0.55: setc(x, y, '~')
            elif d < 1.0: setc(x, y, 'I')

# ---- Emerald Jungle (x 240-359, y 52-99) -----------------------------------------------
for y in range(50, 100):
    for x in range(240, W - 1):
        v = noise(x + 400, y)
        c = 'J'
        if v > 0.63 or random.random() < 0.06: c = 'W'
        elif v < 0.27: c = '%'
        if n3(x + 70, y + 70) > 0.78: c = '^'
        if random.random() < 0.02 and c == 'J': c = '*'
        g[y][x] = c
rx = 322.0                                         # a jungle river from the north to the south-east
for y in range(52, 100):
    rx += math.sin(y / 6.0) * 1.1
    for dx in (0, 1, 2): setc(int(rx) + dx, y, '~')
for y in range(49, 52):                            # ridge between highlands and jungle
    for x in range(240, W):
        if random.random() < 0.85: g[y][x] = '^'

# ---- Sapphire Isles (x 0-119, y 100-149) + the southern sea ---------------------------------
for y in range(100, H - 1):
    for x in range(1, 120):
        g[y][x] = '~'
islands = [(58, 121, 18, 9), (22, 138, 11, 7), (92, 112, 13, 7), (96, 138, 12, 7), (30, 108, 9, 4), (66, 142, 9, 4)]
for (cx, cy, irx, iry) in islands:
    for y in range(cy - iry - 3, cy + iry + 4):
        for x in range(cx - irx - 3, cx + irx + 4):
            if not (1 <= x < 120 and 96 <= y < H - 1): continue
            d = ((x - cx) / irx) ** 2 + ((y - cy) / iry) ** 2 + 0.35 * (n2(x + 3, y + 3) - 0.5)
            if d < 0.55:
                c = 'J' if noise(x + 600, y) > 0.42 else 's'
                if random.random() < 0.10: c = 'W'
                if n3(x + 9, y + 9) > 0.80: c = '^'
                g[y][x] = c
            elif d < 1.0:
                g[y][x] = 'S' if random.random() < 0.93 else 'W'

# ---- Scorched Badlands (x 120-239, y 100-149) ---------------------------------------------
for y in range(100, H - 1):
    for x in range(120, 240):
        v = noise(x + 200, y + 300)
        c = 'D'
        if v < 0.32: c = 's'
        if n3(x + 33, y + 3) > 0.69: c = 'V'
        if n2(x + 90, y + 40) > 0.80: c = 'V'
        if random.random() < 0.012 and c == 'D': c = 'Y'
        g[y][x] = c
for y in range(128, H - 1):                        # a lava field in the south-east corner
    for x in range(196, 236):
        if n4(x, y) > 0.62: g[y][x] = 'L'

# ---- Void Rift (x 240-359, y 102-149) -------------------------------------------------
for y in range(100, H - 1):
    for x in range(240, W - 1):
        v = noise(x + 800, y + 800)
        c = 'E'
        if v > 0.68: c = 'G'
        if n2(x + 17, y + 71) > 0.78: c = 'C'
        if n3(x + 44, y + 21) > 0.76: c = '^'
        g[y][x] = c
for y in range(99, 102):                           # ridge between jungle and the rift
    for x in range(240, W):
        if random.random() < 0.85: g[y][x] = '^'
for y in range(100, H):                            # ridge between badlands and the rift
    for x in range(238, 242):
        if random.random() < 0.85: g[y][x] = '^'

# borders of the whole world
for x in range(W): g[0][x] = '^'; g[H - 1][x] = '^'
for y in range(H): g[y][0] = '^' if g[y][0] != '~' else '~'; g[y][W - 1] = '^'; g[y][W - 2] = '^' if random.random() < 0.6 else g[y][W - 2]
for y in range(100, H): g[y][0] = '^'

# ---- towns -------------------------------------------------------------------------------
def walls(x1, y1, x2, y2, floor='_', wall='#'):
    for y in range(y1, y2 + 1):
        for x in range(x1, x2 + 1):
            g[y][x] = wall if (y in (y1, y2) or x in (x1, x2)) else floor
TOWNS = {}
def town(name, x1, y1, x2, y2, gates, way, fire):
    walls(x1, y1, x2, y2)
    for (x, y) in gates: g[y][x] = '_'
    g[way[1]][way[0]] = 'Z'
    g[fire[1]][fire[0]] = 'F'
    TOWNS[name] = (x1, y1, x2, y2)
# Port Coral (Sapphire Isles)
town('Port Coral', 48, 115, 68, 126, [(58, 115), (57, 115), (59, 115), (48, 121), (68, 121), (58, 126)], (51, 117), (62, 123))
# Shardhaven (Crystal Highlands)
town('Shardhaven', 282, 16, 302, 28, [(292, 16), (291, 16), (293, 16), (282, 22), (302, 22), (292, 28), (291, 28), (293, 28)], (285, 18), (296, 25))
# Jadeleaf Village (Emerald Jungle)
town('Jadeleaf Village', 290, 66, 308, 78, [(299, 66), (298, 66), (300, 66), (290, 72), (308, 72), (299, 78), (298, 78), (300, 78)], (293, 68), (303, 75))
# Redrock Outpost (Scorched Badlands)
town('Redrock Outpost', 168, 110, 186, 122, [(177, 110), (176, 110), (178, 110), (168, 116), (186, 116), (177, 122)], (171, 112), (181, 119))
# Last Light Bastion (Void Rift)
town('Last Light Bastion', 268, 108, 288, 118, [(278, 108), (277, 108), (279, 108), (268, 113), (288, 113), (278, 118)], (271, 110), (283, 115))
# a little pond in Jadeleaf and torches/flowers
for (x, y) in [(294, 75), (295, 75), (294, 76), (295, 76)]: g[y][x] = '~'

# ---- dungeon entrances ----------------------------------------------------------------------
def ruin(x, y, ground):
    for dx in range(-2, 3): setc(x + dx, y - 1, '#')
    setc(x - 2, y, '#'); setc(x + 2, y, '#'); setc(x - 1, y, '_'); setc(x + 1, y, '_'); setc(x, y, '>')
    for dy in (1, 2, 3):
        for dx in (-1, 0, 1):
            if get(x + dx, y + dy) in '^TLRPYI~WCVG': setc(x + dx, y + dy, ground)
NEW_ENT = [(6, 22, 140, 'S'), (7, 342, 10, 'K'), (8, 346, 92, 'J'), (9, 226, 142, 'D'), (10, 340, 140, 'E')]
for d, x, y, gr in NEW_ENT: ruin(x, y, gr)

# ---- roads -----------------------------------------------------------------------------------
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
# Saltwind Coast pier -> long bridge south -> Port Coral
road([(27, 76), (27, 108), (40, 108), (40, 112), (58, 112), (58, 115)])
road([(48, 121), (34, 121), (34, 134), (22, 134), (22, 137)])            # -> Coral Grotto island
road([(68, 121), (80, 121), (80, 112), (92, 112)])                         # -> east island
road([(58, 126), (58, 134), (66, 134), (66, 142)])                         # -> south islet
road([(80, 121), (80, 138), (96, 138)])                                     # -> south-east island
# Sunscorch Desert -> Scorched Badlands -> Redrock Outpost
road([(128, 93), (128, 104), (177, 104), (177, 110)])
road([(177, 122), (177, 132), (210, 132), (226, 132), (226, 139)])         # -> Obsidian Forge
# Redrock -> Void Rift -> Last Light Bastion
road([(186, 116), (232, 116), (232, 124), (252, 124), (252, 113), (268, 113)])
road([(288, 113), (330, 113), (330, 136), (340, 136), (340, 139)])         # -> Throne of the Void
# Frostfang Tundra -> Crystal Highlands -> Shardhaven
road([(226, 30), (262, 30), (262, 22), (282, 22)])
road([(302, 22), (342, 22), (342, 13)])                                     # -> Crystal Depths
# Ashen Wastes -> Emerald Jungle -> Jadeleaf Village
road([(226, 80), (260, 80), (260, 72), (290, 72)])
road([(308, 72), (346, 72), (346, 95)])                                     # -> Temple of the Jade Serpent
# Shardhaven <-> Jadeleaf, Jadeleaf <-> Last Light
road([(292, 28), (292, 40), (299, 40), (299, 66)])
road([(299, 78), (299, 100), (278, 100), (278, 108)])
# keep dungeon fronts open
for d, x, y, gr in NEW_ENT:
    for dy in (1, 2):
        if get(x, y + dy) not in ':=': setc(x, y + dy, ':')

# ---- reachability --------------------------------------------------------------------------
WALK = set('.,":=_*%><SsNnIAKJDE')
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
checks = {'grotto': (22, 140), 'depths': (342, 10), 'temple': (346, 92), 'forge': (226, 142), 'throne': (340, 140),
          'coral': (58, 120), 'shard': (292, 22), 'jade': (299, 72), 'redrock': (177, 116), 'lastlight': (278, 113),
          'tomb': (142, 94), 'caverns': (228, 8), 'gate': (226, 90), 'oasis': (112, 79), 'crypt': (40, 10)}
bad = 0
for k, (x, y) in checks.items():
    ok = (x, y) in R
    bad += not ok
    print(f'{k:10s} {g[y][x]!r} reachable={ok}', file=sys.stderr)
FILL = {'S': 'W', 's': 'W', 'N': 'P', 'n': 'P', 'A': 'R', 'I': 'P', 'K': 'C', 'J': 'W', 'D': 'V', 'E': 'G'}
for y in range(H):
    for x in range(W):
        if g[y][x] in WALK and (x, y) not in R and g[y][x] not in '><':
            if x >= 240 or y >= 100:
                g[y][x] = FILL.get(g[y][x], 'W')
tot = sum(1 for y in range(H) for x in range(W) if g[y][x] in WALK)
print('walkable', tot, 'bad', bad, file=sys.stderr)
for k, v in TOWNS.items(): print('town', k, v, file=sys.stderr)
open(OUT, 'w').write('\n'.join(''.join(r) for r in g) + '\n')
