#!/usr/bin/env bash
# Rendering: every screen, both graphics modes, three terminal sizes.
# Each frame must render without a bash error and (checked by vt.py) stay
# inside the terminal without breaking the map frame.
source "$(dirname "$0")/lib.sh"
stub_client
T_ROWS=40 T_COLS=120
stty() { echo "$T_ROWS $T_COLS"; }
init_explore; init_lights
HAVE_PY=0; command -v python3 >/dev/null && HAVE_PY=1
NF=0

frame() {  # label: render one full frame, check stderr + layout
  local f=$T_TMP/f$NF err=$T_TMP/e$NF
  NF=$(( NF + 1 ))
  NEED_FULL=1 MAP_DIRTY=1 next_mapdraw=0
  render > "$f" 2> "$err"
  if [[ -s $err ]]; then fail "$1 ($GFX ${T_COLS}x$T_ROWS): $(head -c 300 "$err")"; else ok; fi
  if (( HAVE_PY )); then
    if python3 "$T_ROOT/tests/vt.py" "$f" "$T_ROWS" "$T_COLS" "$MW" "$VH" > "$err.vt"; then ok
    else fail "$1 ($GFX ${T_COLS}x$T_ROWS): $(head -n 3 "$err.vt")"; fi
  fi
  rm -f "$f" "$err" "$err.vt"
}

setup_world() {
  new_hero 7 26; GOLD=98765 EQW=W.19.8.3 EQA=A.0.8.2 EQO=O.5.7.1 EQH=H.1.6.0 EQJ=U.7
  INV=(W.0.9.3 U.1 B.5 A.1.4.1! H.2.3.0 J.1.9.2 O.0.2.0 W.6.5.1 W.3.1.0 B.0)
  BAGEQ=(4 2 -); bag_cap; BANK=(U.2 W.1.7.3) BANKG=5000
  MATS=(); for (( i = 0; i < NMAT; i++ )); do MATS[i]=$(( i * 7 % 50 )); done
  POT_H=12 POT_M=4 POT_GH=2 EL_STR=1 SCROLL=3 STORY=6 ALLIES=11111111
  QUESTS=(K.5.10.3.100.50 D.2.1.0.500.300 T.25.1.0.80.40)
  WAYS=1111111111 SEEN=; for (( i = 0; i < NM; i++ )); do SEEN+=1; done
  CUR_MAP=W PX=80 PY=34
  CM_T=() CM_X=() CM_Y=() CM_HP=() CM_MAX=() CM_POS=()
  cm_set 900 2 83 34 20 34; cm_set 901 19 78 33 900 900; cm_set 902 $NPC1 82 30 900 900
  cm_set 903 $BANK0 84 36 900 900; cm_set 904 $(( WB0 )) 90 38 9000 9000
  OP_NAME[beefed]=Mira OP_MAP[beefed]=W OP_X[beefed]=79 OP_Y[beefed]=36 OP_CLS[beefed]=3 OP_LVL[beefed]=24
  OP_HP[beefed]=50 OP_MAX[beefed]=300 OP_DEAD[beefed]=0 OP_SEEN[beefed]=$NOW OP_SYM[beefed]=M OP_COL[beefed]=3
  OP_SAY[beefed]="hello there, this is a rather long chat bubble to test wrapping" OP_SAYT[beefed]=$(( NOW + 99999 ))
  player_glyph beefed M 3 0
  MY_PARTY=p1 PARTY_LEADER=$MY_ID PARTY_IDS=("$MY_ID" beefed)
  TARGET=900
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do logm "log line $i with some text"; chatm "Mira: chat $i"; done
  explore_here; ALLY=0; aly_place
}

screens() {
  UI=""; frame "map view in town"
  PX=200 PY=100; explore_here; frame "map view in the wild"
  UI=inv; for t in 0 1 2 3; do INV_TAB=$t; INV_CUR=(1 1 1 0); frame "inventory tab $t"; done
  INV_TAB=0; INV_CUR=(3 1 1 0); frame "inventory with a unique selected"
  for r in general smith alchemist; do TALK_T=$NPC1 SHOP=$r UI=shop; shop_build "$r" 2>/dev/null; frame "shop $r"; done
  PX=80 PY=34; UI=""; talk_open 902; frame "talking to an NPC"
  talk_open 903; bank_open; for t in 0 1; do BK_TAB=$t; frame "bank tab $t"; done
  QSRC=board; gen_offers; UI=quest; frame "quest board"
  for u in qlog beasts chatlog way help prof allies allyshop talents; do UI=$u; frame "$u screen"; done; HELP_PG=1 UI=help; frame "help page 2"; HELP_PG=0
  for t in 1 2; do QLOG_TAB=$t UI=qlog; frame "quest log tab $t"; done; QLOG_TAB=0
  cm_set 905 21 81 34 900 900; talk_open 905; frame "talking to a smith"; jewel_open
  INV+=(W.0.5.2.r2__ A.1.6.3.______); MATS[GEM0]=4 MATS[$(( GEM0 + 4 ))]=2
  for st in 0 1 2; do JW_STEP=$st; frame "jeweler step $st"; done; JW_STEP=0 JW_TAB=1; frame "jeweler: combining gems"
  cm_set 906 $NPC1 83 33 900 900; talk_open 906; frame "talking to a questline giver"
  UI=wares; frame "faction quartermaster"
  QLS=${QLS:0:0}4${QLS:1}; QCH_L=0 UI=qchoice; frame "a questline choice"
  PS_UNTIL=($(( NOW + 3000 )) 0 $(( NOW + 2000 )) $(( NOW + 2000 )) 0 $(( NOW + 5000 ))); BARRIER=40; UI=""; frame "status effects in the panel"
  PS_UNTIL=(0 0 0 0 0 0) BARRIER=0
  CM_CH[900]=3; TARGET=900; frame "a champion as target"; CM_CH[900]=0
  for c in forge alch cook; do CRAFT=$c UI=craft; frame "crafting $c"; done
  story_complete 2>/dev/null; frame "story popup"
  UI=""; trade_open beefed; TR_MYI=(0 1); TR_THI=(U.3 W.0.9.3); TR_THG=500; frame "trading"
  UI=map; wm_open; frame "world map"; WM_Z=1; WM_CZ=""; frame "world map zoomed in"
  UI=""; CLK_OFF=$(( DAYLEN / 2 * 1 )); frame "night"
  gen_dungeon D9 3 12345; enter_instance D9 3 12345 2>/dev/null; UI=""; frame "inside a dungeon"
  leave_instance quiet
  # v4.0: the new lands (every new tile), a new dungeon, a druid and a monk, eight factions, twelve allies
  CLK_OFF=0
  for p in "178 160 Duskwood" "60 172 Tidewatch" "420 10 Stormreach" "420 60 Gloomcap" "440 130 Dragonspine" "300 185 Bonefields" "420 178 Starfall"; do
    set -- $p; PX=$1 PY=$2; explore_here; UI=""; frame "the $3"
  done
  CLK_OFF=$(( DAYLEN / 2 )); PX=420 PY=60; explore_here; frame "night in Gloomcap"; CLK_OFF=0
  gen_dungeon D17 17 777; enter_instance D17 17 777 2>/dev/null; UI=""; frame "inside the Shattered Star"; leave_instance quiet
  for d in $D60 $(( D60 + 3 )); do gen_dungeon D3$d "$d" 4242; enter_instance D3$d "$d" 4242 2>/dev/null; UI=""; frame "inside ${D_NAME[d]}"; leave_instance quiet; done   # v6.0
  CLS=8; calc_stats; PX=178 PY=172; UI=""; frame "a druid in Hollowmere"; UI=talents; frame "druid talents"
  CLS=9; calc_stats; UI=talents; frame "monk talents"; CLS=7; calc_stats
  REP=(100 2000 5000 9500 16000 -500 3000 12000); QLOG_TAB=2 UI=qlog; frame "eight factions"
  ALLIES=111111111111; UI=allies; frame "twelve allies"; ALLIES=11111111
  UI=map; wm_open; frame "the whole 480x200 world map"
  PX=80 PY=34
  # v4.5: paragon, the mythic gate, mounts, valor, achievements, dailies, the endgame help, the mythic clock
  LVL=40 PARA=12 PARA_P="5 4 3 0 0 0" TL_PAGE=1 UI=talents; frame "paragon"; TL_PAGE=0
  DG_D=17 DG_K=12 KEYLV=14 UI=dgate; frame "mythic gate +12"; DG_D=$RAID_DT; frame "the raid gate"
  MOUNTS=10001000 MNT_CUR=4 STABLE_SRC=keys UI=stable; frame "my mounts"
  TALK_T=$NPC45 STABLE_SRC=talk UI=stable; frame "Hilda's stable"
  VALOR=1234 UI=valor; frame "valor quartermaster"
  ACHS=$(printf '1%.0s' $(seq 12))00000000000000000000; TITLE=2 UI=ach; ACH_PG=0; frame "achievements 1"; ACH_PG=1; frame "achievements 2"
  QLOG_TAB=3 UI=qlog; frame "dailies"; QLOG_TAB=0
  HELP_PG=2 UI=help; frame "help page 3"; HELP_PG=0
  RIDING=1; UI=""; frame "riding the gryphon"; RIDING=0
  gen_dungeon D17 17 777; enter_instance D17 17 777 2>/dev/null; IN_MK=9 IN_LIM=600000 IN_T0=$(( NOW - 30000 )); UI=""
  frame "mythic +9 clock"; IN_T0=$(( NOW - 700000 )); frame "mythic over time"; IN_MK=0; leave_instance quiet
  # v5.0: every room (owner and guest), the inn, visiting, a display, the collection book, the guestbook, the room chest
  CUR_MAP=W PX=88 PY=32; rent_week; ROOM_PAID=$RWK
  for t in 1 2 3 4; do
    ROOM_T=$t; v50_fix; ROOMD[0]=C.40 ROOMD[1]=U.2 ROOMD[2]=W.0.12.3.r4__ ROOMD[3]=C.18
    room_home >/dev/null 2>&1; UI=""; frame "my room $t"; leave_instance quiet
  done
  room_go beefed 3 "C.5 - U.2 B.5 C.70"; VIS_OWNER=beefed RM_NCOL=33; UI=""; frame "visiting Mira's Grand Suite"
  CLK_OFF=$(( DAYLEN / 2 )); frame "a room at night"; CLK_OFF=0; leave_instance quiet
  TALK_T=23 UI=inn; frame "rooms at the inn"; ROOM_T=0; v50_fix; frame "rooms at the inn, no room yet"; ROOM_T=4; v50_fix
  VIS_INFO=([beefed]="3 5 40") UI=visit; frame "visiting: who is home"; VIS_INFO=() VIS_T=0; frame "visiting: nobody"
  ROOMD[0]=C.40 ROOMD[5]=U.2; room_home >/dev/null 2>&1
  INV+=(C.40 C.77); DSP_I=0 DSP_CUR=2 UI=dsp; frame "a display"; DSP_I=1 UI=dsp; frame "an empty display"
  CLOG=$(printf '10%.0s' $(seq 40)); for p in 0 1 2 3 4 5 6; do BOOK_PG=$p UI=book; frame "collection book page $p"; done
  GUESTS="Mira:20400 Bob:20390 Eve:20000"; UI=guest; frame "the guestbook"; GUESTS=""; frame "an empty guestbook"
  room_chest; ROOMC=(C.3 W.0.5.2 U.7); frame "the room chest"; UI=""; leave_instance quiet
  INV_TAB=0 INV_CUR=($(( 11 + ${#INV[@]} )) 1 1 0) UI=inv; frame "inventory: a collectable"
  HELP_PG=3 UI=help; frame "help page 4"; HELP_PG=0
  REST_UNTIL=$(( NOW + 600000 )) REST_PCT=25 UI=""; frame "well rested"; INV_TAB=1 UI=inv; frame "well rested in the inventory"; REST_UNTIL=0
  ROOM_T=0; v50_fix
  TITLE=-1 PARA=0 PARA_P="0 0 0 0 0 0" LVL=12; calc_stats
}

for g in ascii hd; do
  GFX=$g; set_gfx
  for size in "30 100" "40 120" "60 200"; do
    read -r T_ROWS T_COLS <<< "$size"
    layout; setup_world; screens
  done
done
# frames only send the lines that changed: the screen must still end up exactly like a full redraw
incremental() {  # label code...: full frame, change something, partial frame == full frame?
  local f=$T_TMP/inc a=$T_TMP/inc_a b=$T_TMP/inc_b
  NEED_FULL=1 MAP_DIRTY=1; render > "$f" 2>/dev/null
  eval "$2"
  MAP_DIRTY=1 next_mapdraw=0; render >> "$f" 2>/dev/null
  NEED_FULL=1 MAP_DIRTY=1; render > "$b" 2>/dev/null
  python3 "$T_ROOT/tests/vt.py" --cells "$f" "$T_ROWS" "$T_COLS" > "$a.c"
  python3 "$T_ROOT/tests/vt.py" --cells "$b" "$T_ROWS" "$T_COLS" > "$b.c"
  if cmp -s "$a.c" "$b.c"; then ok; else fail "incremental frame after $1 ($GFX): $(diff "$a.c" "$b.c" | head -4 | tr '\n' ' ')"; fi
}
if (( HAVE_PY )); then
  for g in ascii hd; do
    GFX=$g; set_gfx; T_ROWS=40 T_COLS=120; layout; setup_world; UI=""; NOW=2000000
    incremental "a step east" 'PX=$(( PX + 1 ))'
    incremental "a step south" 'PY=$(( PY + 1 ))'
    incremental "a monster moving" 'cm_move 900 $(( PX + 2 )) $(( PY + 1 ))'
    incremental "a new log line" 'logm "something happened"'
    incremental "losing HP" 'HP=$(( HP / 2 ))'
    incremental "closing the inventory" 'UI=inv; MAP_DIRTY=1; render >> "$f"; UI=""; NEED_FULL=1'
    incremental "dying" 'DEAD=1 dead_until=$(( NOW + 5000 ))'
    incremental "respawning" 'DEAD=0'
    incremental "time passing (water moves)" 'NOW=$(( NOW + 900 ))'
  done
fi

# terminals that are too small get a polite message, not a broken screen
T_ROWS=20 T_COLS=80; layout; out=$(render 2>&1); [[ $out == *"needs at least"* ]] && ok || fail "small terminal message"

t_end
