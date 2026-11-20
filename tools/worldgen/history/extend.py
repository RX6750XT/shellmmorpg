import random, math
from collections import deque
random.seed(2026)
import os, sys
HERE=os.path.dirname(os.path.abspath(__file__))
OUT=sys.argv[1] if len(sys.argv)>1 else os.path.join(HERE,'world_v18.txt')
old=[list(r) for r in open(os.path.join(HERE,'world_v11.txt')).read().split('\n') if r]
OW,OH=len(old[0]),len(old)
W,H=240,100
g=[['^']*W for _ in range(H)]
for y in range(OH):
    for x in range(OW): g[y][x]=old[y][x]
def setc(x,y,c):
    if 0<=x<W and 0<=y<H: g[y][x]=c
def get(x,y): return g[y][x] if 0<=x<W and 0<=y<H else '^'
def mknoise(cell,seed):
    rnd=random.Random(seed)
    gw,gh=W//cell+3,H//cell+3
    pts=[[rnd.random() for _ in range(gw)] for _ in range(gh)]
    def n(x,y):
        fx,fy=x/cell,y/cell; ix,iy=int(fx),int(fy); tx,ty=fx-ix,fy-iy
        tx=tx*tx*(3-2*tx); ty=ty*ty*(3-2*ty)
        P=lambda yy,xx: pts[yy%gh][xx%gw]
        a=P(iy,ix)*(1-tx)+P(iy,ix+1)*tx; b=P(iy+1,ix)*(1-tx)+P(iy+1,ix+1)*tx
        return a*(1-ty)+b*ty
    return n
n1=mknoise(7,1); n2=mknoise(3,2); n3=mknoise(11,3)
def noise(x,y): return 0.6*n1(x,y)+0.4*n2(x,y)
# ---- south: coast (west) + Sunscorch Desert (east) -------------------------
for y in range(64,H):
    for x in range(0,160):
        coast = 72 + 3*math.sin(x/7.0) + max(0,(8-x))*0.6
        if x < 62:
            if y > coast+3: g[y][x]='~'
            elif y > coast-4: g[y][x]='S' if random.random()<0.9 else 's'
            else: g[y][x]=random.choice('.,,"') if noise(x,y)>0.45 else ('T' if random.random()<0.08 else 's')
        else:
            v=noise(x+40,y)
            c='S' if v<0.55 else 's'
            if random.random()<0.025: c='Y'
            if n3(x,y)>0.72: c='^'
            g[y][x]=c
    for x in range(0,160):
        if y>=98 or (x<1): g[y][x]='^' if g[y][x]!='~' else '~'
for x in range(W): g[H-1][x]='^'
# blend the old southern mountain border: open a few gaps with sand
for x in range(58,160):
    for y in (62,63):
        if random.random()<0.25: g[y][x]='s'
# ---- east north: Frostfang Tundra -----------------------------------------
for y in range(0,49):
    for x in range(160,W):
        v=noise(x,y+300)
        c='N' if v<0.5 else 'n'
        if n2(x+9,y+9)>0.7 and random.random()<0.8: c='P'
        if n3(x+77,y)>0.74: c='^'
        g[y][x]=c
cx,cy=212,34
for y in range(0,49):
    for x in range(160,W):
        if ((x-cx)/12)**2+((y-cy)/5)**2<1: g[y][x]='I'
# ---- east south: Ashen Wastes ---------------------------------------------
for y in range(49,99):
    for x in range(160,W):
        v=noise(x+200,y+100)
        c='A'
        if v>0.66: c='L'
        elif n2(x+3,y+5)>0.75: c='R'
        elif n3(x+11,y+31)>0.73: c='^'
        g[y][x]=c
for y in range(46,52):
    for x in range(160,W):
        if random.random()<0.65: g[y][x]='^'
for y in range(H):
    for x in (W-1,W-2):
        g[y][x]='^'
for x in range(W):
    g[0][x]='^'
# ---- hubs ---------------------------------------------------------------------
def walls(x1,y1,x2,y2,floor='_',wall='#'):
    for y in range(y1,y2+1):
        for x in range(x1,x2+1):
            g[y][x]=wall if (y in (y1,y2) or x in (x1,x2)) else floor
# Oasis of Kadar (desert hub)
walls(100,76,124,88)
for (x,y) in [(112,76),(111,76),(113,76),(100,82),(124,82),(112,88)]: g[y][x]='_'
for y in range(80,85):
    for x in range(108,117):
        if ((x-112)/4.2)**2+((y-82)/2.2)**2<1: g[y][x]='~'
for (x,y) in [(107,80),(117,84),(107,84),(117,80)]: g[y][x]='T'
g[78][103]='Z'                      # waystone
# Frosthold (tundra hub)
walls(192,16,212,26,floor='_',wall='#')
for (x,y) in [(202,16),(201,16),(203,16),(202,26),(192,21),(212,21)]: g[y][x]='_'
g[21][202]='F'                      # hearth fire
g[18][195]='Z'
# Ser Kael's camp (ashen wastes)
walls(186,58,198,66)
for (x,y) in [(192,58),(191,58),(193,58),(186,62)]: g[y][x]='_'
g[62][194]='F'; g[60][188]='Z'
# old hubs get waystones
g[35][77]='Z'; g[36][118]='Z'
# ---- dungeon entrances ----------------------------------------------------------
def ruin(x,y):
    for dx in range(-2,3): setc(x+dx,y-1,'#')
    setc(x-2,y,'#'); setc(x+2,y,'#'); setc(x-1,y,'_'); setc(x+1,y,'_'); setc(x,y,'>')
    for dy in (1,2):
        for dx in (-1,0,1):
            if get(x+dx,y+dy) in '^TLRPYI~': setc(x+dx,y+dy,'.' if y<64 or x<160 else get(x+dx,y+dy))
NEW_ENT=[(3,142,94),(4,228,8),(5,226,90)]
for d,x,y in NEW_ENT: ruin(x,y)
# ---- roads ----------------------------------------------------------------------
def road(points, ch=':'):
    for (x1,y1),(x2,y2) in zip(points,points[1:]):
        x,y=x1,y1
        while True:
            c=get(x,y)
            if c in '~I': setc(x,y,'=')
            elif c=='L': setc(x,y,'=')
            elif c not in '>_=' and c!='Z': setc(x,y,ch)
            if (x,y)==(x2,y2): break
            if x!=x2: x+= 1 if x2>x else -1
            elif y!=y2: y+= 1 if y2>y else -1
road([(80,58),(80,70),(112,70),(112,76)])                    # Greenfield -> Oasis
road([(112,88),(112,93),(142,93),(142,95)])                  # Oasis -> Sunken Tomb
road([(80,66),(40,66),(30,70)])                              # -> coast
for x in range(24,31): setc(x,75,'=')                         # fishing pier
road([(140,14),(150,14),(150,12),(175,12),(202,12),(202,16)])  # peaks -> Frosthold
road([(202,26),(202,30),(226,30),(228,10)])                  # Frosthold -> Ice Caverns
road([(134,51),(150,51),(150,56),(170,56),(192,56),(192,58)])  # swamp -> Kael's camp
road([(202,30),(202,45),(196,52),(196,56)])                  # tundra <-> ashen
road([(192,66),(192,80),(226,80),(226,89)])                  # camp -> Infernal Gate
# v1.3 campfires (cooking + light at night)
setc(84,38,'F'); setc(106,86,'F')
# keep dungeon entrance fronts open
for d,x,y in NEW_ENT:
    for dy in (1,2):
        if get(x,y+dy) not in ':=': setc(x,y+dy,':')
# ---- reachability -----------------------------------------------------------------
WALK=set('.,":=_*%><SsNnIA')
def bfs(sx,sy):
    seen={(sx,sy)}; q=deque([(sx,sy)])
    while q:
        x,y=q.popleft()
        for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
            nx,ny=x+dx,y+dy
            if (nx,ny) not in seen and 0<=nx<W and 0<=ny<H and g[ny][nx] in WALK:
                seen.add((nx,ny)); q.append((nx,ny))
    return seen
R=bfs(80,35)
import sys
checks={'tomb':(142,94),'caverns':(228,8),'gate':(226,90),'oasis':(112,82-3),'frosthold':(202,20),'kael':(192,62),
        'coast':(30,68),'crypt':(40,10),'lair':(140,8),'warrens':(134,50)}
for k,(x,y) in checks.items(): print(f'{k:10s} {g[y][x]!r} reachable={(x,y) in R}', file=sys.stderr)
for y in range(H):
    for x in range(W):
        if g[y][x] in WALK and (x,y) not in R and g[y][x] not in '><':
            g[y][x] = {'S':'Y','s':'Y','N':'P','n':'P','A':'R','I':'P'}.get(g[y][x],'T') if (x>=160 or y>=64) else g[y][x]
tot=sum(1 for y in range(H) for x in range(W) if g[y][x] in WALK)
print('walkable', tot, file=sys.stderr)
open(OUT,'w').write('\n'.join(''.join(r) for r in g)+'\n')
