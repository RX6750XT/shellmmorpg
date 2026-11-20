import random, math
random.seed(1337)
W,H=160,64
g=[['.']*W for _ in range(H)]
def setc(x,y,c):
    if 0<=x<W and 0<=y<H: g[y][x]=c
def get(x,y): return g[y][x] if 0<=x<W and 0<=y<H else '^'
# value noise
def mknoise(cell):
    gw,gh=W//cell+3,H//cell+3
    pts=[[random.random() for _ in range(gw)] for _ in range(gh)]
    def n(x,y):
        fx,fy=x/cell,y/cell; ix,iy=int(fx),int(fy); tx,ty=fx-ix,fy-iy
        tx=tx*tx*(3-2*tx); ty=ty*ty*(3-2*ty)
        P=lambda yy,xx: pts[yy%gh][xx%gw]
        a=P(iy,ix)*(1-tx)+P(iy,ix+1)*tx; b=P(iy+1,ix)*(1-tx)+P(iy+1,ix+1)*tx
        return a*(1-ty)+b*ty
    return n
n1=mknoise(6); n2=mknoise(3); n3=mknoise(10)
def noise(x,y): return 0.6*n1(x,y)+0.4*n2(x,y)
# meadow base variation
for y in range(H):
    for x in range(W):
        v=noise(x,y)
        g[y][x]= '"' if v>0.68 else (',' if v>0.52 else '.')
        if random.random()<0.015: g[y][x]='*'
# forest NW (soft edge)
for y in range(H):
    for x in range(W):
        edge = (x<66 and y<27) 
        d = max(0,(x-58))/10 + max(0,(y-20))/8
        if x<70 and y<30:
            dens = 0.62 - d*0.35
            if noise(x+300,y)<dens and random.random()<0.85: g[y][x]='T'
# scattered trees in meadows
for _ in range(260):
    x,y=random.randrange(W),random.randrange(H)
    if g[y][x] in '.,"': g[y][x]='T'
# mountains NE: ridges with valleys
for y in range(H):
    for x in range(W):
        if x>100 and y<24:
            d=max(0,106-x)/6+max(0,y-17)/5
            v=n3(x+50,y+50)*0.55+n2(x+7,y+3)*0.45 - d*0.25
            if v>0.53: g[y][x]='^'
            elif v<0.30 and random.random()<0.3: g[y][x]='T'
# foothills rocks
for _ in range(70):
    x,y=random.randrange(100,158),random.randrange(22,38)
    if random.random()<0.5: g[y][x]='^'
# swamp SE
for y in range(40,H):
    for x in range(104,W):
        v=noise(x+500,y+500)
        if v>0.5: g[y][x]='%'
        elif v<0.28: g[y][x]='~'
        elif random.random()<0.06: g[y][x]='T'
# lake SW
cx,cy,rx,ry=32,47,17,7.5
for y in range(H):
    for x in range(W):
        d=((x-cx)/rx)**2+((y-cy)/ry)**2
        if d<1.0+0.25*(n2(x+90,y+90)-0.5): g[y][x]='~'
# river from top into lake (meander)
x=50.0
for y in range(0,60):
    x+= math.sin(y/5.0)*0.9
    xi=int(x)
    if y>36 and get(xi-1,y)=='~': break
    for dx in (0,1): setc(xi+dx,y,'~')
    if y>36: x-=1.2
# border mountains
for y in range(H):
    for x in range(W):
        if x<1 or y<1 or x>=W-1 or y>=H-1: g[y][x]='^'
        elif (x<2 or y<2 or x>=W-2 or y>=H-2) and random.random()<0.6: g[y][x]='^'
# roads
def road(points):
    for (x1,y1),(x2,y2) in zip(points,points[1:]):
        x,y=x1,y1
        while (x,y)!=(x2,y2):
            c=get(x,y)
            if c=='~': setc(x,y,'=')
            elif c!='=': setc(x,y,':')
            if x!=x2: x+= 1 if x2>x else -1
            elif y!=y2: y+= 1 if y2>y else -1
        setc(x2,y2,':' if get(x2,y2)!='~' else '=')
TX1,TY1,TX2,TY2=66,28,94,40   # town walls
TCX,TCY=80,34
road([(TCX,TY1),(TCX,16),(60,16),(60,10),(40,10)])          # north road -> crypt (crosses river)
road([(TX2,TCY),(112,TCY),(126,TCY),(126,50),(134,50)])     # east road -> warrens
road([(112,TCY),(112,26),(124,26),(124,14),(140,14),(140,8)])  # NE pass -> dragon lair
road([(TX1,TCY),(56,TCY),(56,38)])                           # west road -> lake shore
road([(TCX,TY2),(TCX,58)])                                   # south road
# widen roads a bit near town? keep 1 wide
# town
for y in range(TY1,TY2+1):
    for x in range(TX1,TX2+1):
        if y in (TY1,TY2) or x in (TX1,TX2): g[y][x]='#'
        else: g[y][x]='_'
for (x,y) in [(TCX,TY1),(TCX,TY2),(TX1,TCY),(TX2,TCY),(TCX-1,TY1),(TCX+1,TY1),(TCX-1,TY2),(TCX+1,TY2),(TX1,TCY-1),(TX1,TCY+1),(TX2,TCY-1),(TX2,TCY+1)]:
    g[y][x]='_'
def house(x1,y1,x2,y2,door,npc):
    for y in range(y1,y2+1):
        for x in range(x1,x2+1):
            g[y][x]='#' if (y in (y1,y2) or x in (x1,x2)) else '_'
    dx,dy=door; g[dy][dx]='_'
    nx,ny,c=npc; g[ny][nx]=c
house(69,30,75,33,(72,33),(72,31,'S'))       # shop (door south)
house(85,30,91,33,(88,33),(88,31,'I'))       # inn
house(69,36,75,39,(72,36),(72,38,'H'))       # house (decor) 'H' = resident? make plain
g[38][72]='_'
house(85,36,91,39,(88,36),(88,38,'_'))
g[TCY][TCX]='O'   # fountain
g[TCY-2][TCX+3]='Q'  # quest board
# flowers in town plaza corners
for (x,y) in [(77,31),(83,31),(77,37),(83,37)]: g[y][x]='*'
# dungeon entrances with ruins
def ruin(x,y):
    for dx in range(-2,3):
        setc(x+dx,y-1,'#')
    setc(x-2,y,'#'); setc(x+2,y,'#')
    setc(x-1,y,'_'); setc(x+1,y,'_')
    setc(x,y,'>')
ENT=[(0,40,10),(1,134,50),(2,140,8)]
for d,x,y in ENT:
    ruin(x,y)
    setc(x,y+1,':')
# make sure area around entrances walkable
for d,x,y in ENT:
    for dy in (1,2):
        for dx in (-1,0,1):
            if get(x+dx,y+dy) in 'T^~%': setc(x+dx,y+dy,'.')
# connectivity check
from collections import deque
WALK=set('.,":=_*%><')
def bfs(sx,sy):
    seen={(sx,sy)}; q=deque([(sx,sy)])
    while q:
        x,y=q.popleft()
        for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
            nx,ny=x+dx,y+dy
            if (nx,ny) not in seen and 0<=nx<W and 0<=ny<H and g[ny][nx] in WALK:
                seen.add((nx,ny)); q.append((nx,ny))
    return seen
g[TCY][TCX]='_'; R=bfs(TCX,TCY+1); g[TCY][TCX]='O'
import sys
for d,x,y in ENT: print('entrance',d,(x,y),'reachable',(x,y) in R, file=sys.stderr)
# fill unreachable walkable pockets with trees/rocks so monsters never spawn there
for y in range(H):
    for x in range(W):
        if g[y][x] in WALK and (x,y) not in R and g[y][x] not in '><':
            g[y][x] = '^' if (x>100 and y<24) else 'T'
tot=sum(1 for y in range(H) for x in range(W) if g[y][x] in WALK)
print('walkable',tot,'of',W*H, file=sys.stderr)
ZONES=[('rat',70,18,100,26),('meadowW',52,26,64,44),('meadowE',96,26,104,44),('meadowS',64,43,100,60),('lake',10,36,52,60),
       ('forest',4,4,68,28),('swamp',106,40,156,60),('foot',100,24,156,38),('peaks',104,3,156,23)]
for n,x1,y1,x2,y2 in ZONES:
    c=sum(1 for y in range(y1,y2+1) for x in range(x1,x2+1) if g[y][x] in WALK and not (66<=x<=94 and 28<=y<=40))
    print('zone',n,c,file=sys.stderr)
rows=[''.join(r) for r in g]
import os, sys
OUT=sys.argv[1] if len(sys.argv)>1 else os.path.join(os.path.dirname(os.path.abspath(__file__)),'world_v1.txt')
open(OUT,'w').write('\n'.join(rows)+'\n')
for r in rows: print(r)
