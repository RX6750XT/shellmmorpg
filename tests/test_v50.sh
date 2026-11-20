#!/usr/bin/env bash
# v5.0: housing (rooms at the inn: renting, rent, furniture, displays, the room chest, Well Rested,
# visits, the guestbook) and collectables (80 in six sets: drops, finds, the story, the book).
source "$(dirname "$0")/lib.sh"
stub_client

# --- the data ---------------------------------------------------------------------------------------------
ge "80 collectables or more" "$NCOL" 80
ge "six sets or more" "$NCS" 6
for a in CL_NAME CL_E CL_G CL_SET CL_RR CL_REF CL_FL CL_VAL CL_SRC; do declare -n tb=$a; eq "$a has an entry per collectable" "${#tb[@]}" "$NCOL"; unset -n tb; done
bad=0; for (( i = 0; i < NCOL; i++ )); do
  valid_item "C.$i" || bad=1
  dispw "${CL_E[i]}"; (( DW == 2 )) || { bad=1; echo "  ${CL_NAME[i]}: sprite is $DW columns"; }
  valid_sym "${CL_G[i]}" || { bad=1; echo "  ${CL_NAME[i]}: bad ASCII glyph"; }
  item_name "C.$i" 0; [[ $INAME == "${CL_NAME[i]}" && -n $ICOL ]] || bad=1
  (( ${#CL_FL[i]} > 10 && ${#CL_NAME[i]} <= 31 )) || { bad=1; echo "  ${CL_NAME[i]}: name too long or no flavor"; }
done; eq "every collectable is a valid item with a 2-column sprite, a glyph, a name and a story" "$bad" 0
for c in C.$NCOL C.08 C.-1 C. C.1.2 'C.1!x'; do if valid_item "$c"; then fail "$c is no collectable"; else ok; fi; done
for (( d = 0; d < NDT; d++ )); do [[ -n ${COL_BOSS[${D_BOSS[d]}]} ]] || fail "no trophy for ${M_NAME[${D_BOSS[d]}]}"; done; ok
for w in "${WB_LIST[@]}"; do [[ -n ${COL_BOSS[$w]} ]] || fail "no trophy for ${M_NAME[w]}"; done; ok
for r in "${REGIONS[@]}"; do a=($r); [[ ${a[5]} == safe ]] && continue; [[ -n ${COL_CUR[${a[4]//_/ }]} ]] || fail "no curio for ${a[4]}"; done; ok
n=0; for (( s = 0; s < NCS; s++ )); do for i in ${COL_SETL[s]}; do (( CL_SET[i] == s )) || fail "set list $s"; n=$(( n + 1 )); done; done; eq "every collectable is in its set list" "$n" "$NCOL"
ge "45 achievements or more" "$NACH" 45
# the rooms: rectangles, one door, the right number of displays, every piece of furniture reachable
for (( t = 1; t <= NROOM; t++ )); do
  room_build H1 "$t"
  w=${MAPW[H1]} h=${MAPH[H1]} bad=0 doors=0
  for (( y = 0; y < h; y++ )); do (( ${#MAPROW[H1:$y]} == w )) || bad=1; r=${MAPROW[H1:$y]//[^<]/}; doors=$(( doors + ${#r} )); done
  eq "room $t is a rectangle" "$bad" 0
  eq "room $t has one door" "$doors" 1
  eq "room $t: displays" "$RM_NS" "${ROOM_NDSP[t]}"
  check "room $t: you start on the floor" p_walk H1 "$RM_SX" "$RM_SY"
  declare -A seen=(["$RM_SX,$RM_SY"]=1); q=("$RM_SX,$RM_SY")
  while (( ${#q[@]} )); do
    c=${q[0]}; q=("${q[@]:1}"); x=${c%,*} y=${c#*,}
    for dd in "1 0" "-1 0" "0 1" "0 -1"; do
      set -- $dd; nx=$(( x + $1 )) ny=$(( y + $2 ))
      [[ -n ${seen[$nx,$ny]} ]] && continue
      p_walk H1 "$nx" "$ny" && [[ ${MAPROW[H1:$ny]:nx:1} == _ ]] || continue
      seen["$nx,$ny"]=1; q+=("$nx,$ny")
    done
  done
  bad=0
  for f in "${RM_F[@]}"; do
    a=($f); r=0
    for dd in "1 0" "-1 0" "0 1" "0 -1"; do set -- $dd; [[ -n ${seen[$(( a[1] + $1 )),$(( a[2] + $2 ))]} ]] && r=1; done
    (( r )) || { bad=1; echo "  room $t: ${a[0]} at ${a[1]},${a[2]} can't be reached"; }
  done
  eq "room $t: every piece of furniture can be reached" "$bad" 0
  k=""; for f in "${RM_F[@]}"; do k+=${f:0:1}; done
  for need in B C K G; do [[ $k == *$need* ]] || fail "room $t has no $need"; done; ok
  unset seen
done

# --- renting ------------------------------------------------------------------------------------------------
new_hero 2 4; GOLD=100000
room_rent 1 >/dev/null; eq "level 4 is too young for a room" "$ROOM_T" 0
LVL=5; GOLD=100; room_rent 1 >/dev/null; eq "...and you need the gold" "$ROOM_T" 0
GOLD=1000; room_rent 1; eq "the Attic Room" "$ROOM_T/$GOLD" "1/700"
eq "four displays, all empty" "${ROOMD[*]}" "- - - -"
rent_week; eq "the first week is paid" "$ROOM_PAID" "$RWK"
room_rent 3 >/dev/null; eq "the Grand Suite is for level 25" "$ROOM_T" 1
LVL=15; GOLD=2000; room_rent 2 >/dev/null; eq "moving up pays the difference (2200)" "$ROOM_T" 1
GOLD=2200; room_rent 2 >/dev/null; eq "...the Guest Room" "$ROOM_T/$GOLD/${#ROOMD[@]}" "2/0/8"
room_rent 1 >/dev/null; eq "nobody moves down" "$ROOM_T" 2
ach_check; eq "achievement: Homeowner" "${ACHS:ACH50:1}" 1
ROOM_PAID=$(( RWK - 1 )) GOLD=0 BANKG=0
if room_pay >/dev/null; then fail "no gold, no room"; else ok; fi
BANKG=1000; room_pay; eq "the rent comes out of the vault" "$BANKG/$ROOM_PAID" "700/$RWK"
ROOM_PAID=$(( RWK - 3 )) GOLD=500; room_pay; eq "only this week is charged, from the purse first" "$GOLD/$BANKG" "200/700"

# --- inside: the map, the furniture -----------------------------------------------------------------------------
PX=88 PY=32 CUR_MAP=W; room_home
room_map "$MY_ID"; eq "you are in your room" "$CUR_MAP" "$RMAP"
eq "the map name is H + the id" "$RMAP" "H$(( 16#$MY_ID ))"
eq "you came from the inn" "$WX,$WY" "88,32"
check "it is your room" room_mine
send_pos; [[ ${SENT[-1]} == *"|$RMAP|"* || ${SENT[-1]} == *" $RMAP "* ]] && ok || fail "POS carries the room: ${SENT[-1]}"
for f in "${!RM_F[@]}"; do a=(${RM_F[f]}); [[ ${a[0]} == B ]] && bed=$f; [[ ${a[0]} == C ]] && chest=$f; [[ ${a[0]} == D && ${a[3]} == 0 ]] && d0=$f; [[ ${a[0]} == G ]] && gb=$f; done
a=(${RM_F[bed]}); PX=$(( a[1] + 1 )) PY=${a[2]}; next_move=0; try_move -1 0
eq "furniture blocks your way" "$PX" $(( a[1] + 1 ))
gt "the bed makes you Well Rested" "$REST_UNTIL" "$NOW"
eq "...+15% in a Guest Room" "$REST_PCT" 15
XP=0; LVL=15; calc_stats; reward 100 0 "" 0; eq "Well Rested: 115 XP instead of 100" "$XP" 115
REST_UNTIL=0; XP=0; reward 100 0 "" 0; eq "...and 100 without" "$XP" 100
a=(${RM_F[d0]}); PX=$(( a[1] + 1 )) PY=${a[2]}; p_walk "$CUR_MAP" "$PX" "$PY" || PX=$(( a[1] - 1 ))
next_move=0; UI=""; try_move $(( a[1] - PX )) 0; eq "walking into a display opens it" "$UI/$DSP_I" "dsp/0"
UI=""; LOGS=(); a=(${RM_F[$(( ${#RM_F[@]} - 1 ))]}); RM_AT_K=${RM_AT[${a[1]},${a[2]}]}; room_use "$RM_AT_K"; [[ -n $UI || ${#LOGS[@]} -gt 0 ]] && ok || fail "every piece of furniture does something"

# --- displays and the chest ------------------------------------------------------------------------------------------
CH=${COL_CUR[Greenfield Meadows]}; eq "the chicken" "${CL_NAME[CH]}" "A Very Lost Chicken"
INV=(C.$CH W.0.9.3 U.2 C.20); BAGS=10
dsp_put 0 0; eq "the chicken goes on display 1" "${ROOMD[0]}/${#INV[@]}" "C.$CH/3"
eq "...and you see it there" "${RM_DSP[0]}" C.$CH
[[ ${GLYH[h$d0]} == *🐔* ]] && ok || fail "the display shows the chicken: ${GLYH[h$d0]}"
TW2=0; room_glyphs; [[ ${GLY[h$d0]} == *c ]] && ok || fail "ASCII: the chicken is a c"
TW2=1; dsp_put 0 0; eq "a sword replaces it - the chicken goes back into your bags" "${ROOMD[0]}" W.0.9.3
[[ " ${INV[*]} " == *" C.$CH "* ]] && ok || fail "the chicken is back: ${INV[*]}"
dsp_put 1 0; dsp_put 2 0; room_shown; eq "three things on display" "$RSH" 3
BAGS=${#INV[@]}; dsp_take 1 >/dev/null; eq "bags full: it stays on display" "$RSH" 3; BAGS=10
dsp_take 1; room_shown; eq "taken back" "$RSH" 2
room_chest; eq "the chest opens the bank screen on the room tab" "$UI/$BK_TAB" "bank/2"
bk_store; eq "...the room chest holds 35 (Guest Room)" "$ST/$SCAP" "ROOMC/35"
n=${#INV[@]}; BK_SIDE=0 BK_CUR=(0 0); bk_transfer; eq "into the room chest" "${#ROOMC[@]}/$(( ${#INV[@]} + 1 ))" "1/$n"
MATS[3]=7; bk_mats in; eq "materials into the room chest" "${ROOMM[3]}/${MATS[3]}" "7/0"
GOLD=50; bk_gold dep 10 >/dev/null; eq "no gold in the room chest" "$GOLD" 50
BK_TAB=2; bank_open; eq "a banker never opens the room chest" "$BK_TAB" 0
UI=""

# --- save and load -------------------------------------------------------------------------------------------------------
GUESTS="mira:20000 bob:19999" CLOG=$(printf '1%.0s' $(seq 10)); v50_fix
REST_UNTIL=$(( NOW + 60000 )) REST_PCT=15 ROOM_DOOR=2
want="$ROOM_T|$ROOM_PAID|$ROOM_DOOR|${ROOMD[*]}|${ROOMC[*]}|${ROOMM[3]}|${CLOG:0:12}|$GUESTS|$REST_UNTIL|$REST_PCT"
save_char; ROOM_T=0 ROOMD=() ROOMC=() ROOMM=() CLOG="" GUESTS="" REST_UNTIL=0 REST_PCT=0 ROOM_DOOR=0 ROOM_PAID=0
load_char
eq "the room survives save and load" "$ROOM_T|$ROOM_PAID|$ROOM_DOOR|${ROOMD[*]}|${ROOMC[*]}|${ROOMM[3]}|${CLOG:0:12}|$GUESTS|$REST_UNTIL|$REST_PCT" "$want"
eq "...and you wake up at the inn" "$WX,$WY" "88,32"
cp "$CHAR_FILE" "$T_TMP/good.char"
echo "ROOM_T=9" >> "$CHAR_FILE"; load_char
eq "a hostile save: no room number 9" "$ROOM_T" 0
eq "...nothing to display without a room" "${#ROOMD[@]}" 0
cp "$T_TMP/good.char" "$CHAR_FILE"
cat >> "$CHAR_FILE" <<'EOF'
ROOM_T=4
ROOMD=C.999 $(rm -rf /) W.0.9.3 - U.999
ROOMC=C.3 a[$(touch /tmp/pwn)] C.500
CLOG=12x
GUESTS=a:1 $(boom):2
ROOM_PAID=-5
REST_UNTIL=99999999999999999
EOF
load_char
eq "...bad display entries become empty ones (garbage splits into words)" "${ROOMD[*]:0:5}" "- - - - W.0.9.3"
eq "...the Hero's Hall has 20" "${#ROOMD[@]}" 20
eq "...the chest keeps valid items only" "${ROOMC[*]}" "C.3"
eq "...the collection log stays sane" "${#CLOG}" "$NCOL"
[[ $GUESTS != *'$('* ]] && ok || fail "the guestbook kept garbage"
[[ -e /tmp/pwn ]] && fail "a save file ran code" || ok

# --- collectables: finding them ---------------------------------------------------------------------------------------------
new_hero 0 30; BAGS=10 INV=() ROOM_T=0 CLOG=""; v50_fix
col_give 5; eq "a collectable goes into your bags" "${INV[*]}" "C.5"
check "...and into your collection" col_has 5
[[ " ${LOGS[*]} " == *"New for your collection"* ]] && ok || fail "the first one is news"
INV=(W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0)
ROOM_T=1; v50_fix; col_give 6; eq "bags full: it goes to the room chest" "${ROOMC[*]}" "C.6"
ROOMC=(C.1 C.1 C.1 C.1 C.1 C.1 C.1 C.1 C.1 C.1 C.1 C.1 C.1 C.1 C.1 C.1 C.1 C.1 C.1 C.1); col_give 7
eq "no room anywhere: it squeezes into your bags" "${INV[10]}" C.7
INV=() ROOMC=() CLOG=""; v50_fix
boss=${D_BOSS[2]}; for i in $(seq 40); do col_kill "$boss" 0; done
check "the Ancient Dragon drops its trophy" col_has "${COL_BOSS[$boss]}"
INV=(); for i in $(seq 200); do col_kill "$boss" 0; done; n=0; for c in "${INV[@]}"; do [[ $c == "C.${COL_BOSS[$boss]}" ]] && n=$(( n + 1 )); done
gt "...again and again, but not every time" "$n" 5; le "...not every time" "$n" 80
INV=() CLOG=""; v50_fix; CUR_MAP=W PX=30 PY=10; region_of "$PX" "$PY" nosafe; cur=${COL_CUR[$RNAME]}
eq "we are in the Whisperwood" "$RNAME" Whisperwood
for i in $(seq 3000); do col_kill 2 0; col_has "$cur" && break; done
check "a wolf of the Whisperwood carries the Whispering Acorn" col_has "$cur"
INV=(); CUR_MAP=D3; for i in $(seq 3000); do col_kill 2 0; done; eq "no curios in dungeons" "${#INV[@]}" 0; CUR_MAP=W
PX=$SPAWN_X PY=$SPAWN_Y; for i in $(seq 3000); do col_kill 2 0; done; eq "...or in towns" "${#INV[@]}" 0
INV=() CLOG=""; v50_fix; for i in $(seq 2000); do col_find 3; done; n=0; for c in "${INV[@]}"; do [[ ${CL_SET[${c#C.}]} == 3 ]] && n=$(( n + 1 )); done
gt "fishing pulls up angler's treasures" "$n" 20; eq "...and only those" "$n" "${#INV[@]}"
BAGS=999; INV=(); for i in $(seq 30000); do col_pick 3; INV+=("C.$CP"); done
n0=0 n3=0; for c in "${INV[@]}"; do (( CL_RR[${c#C.}] == 0 )) && n0=$(( n0 + 1 )); (( CL_RR[${c#C.}] == 3 )) && n3=$(( n3 + 1 )); done
gt "the old boot is much more common than a black pearl" "$n0" $(( n3 * 3 )); BAGS=10
INV=() CLOG=""; v50_fix; STORY=25; col_story; eq "an old hero gets the relics of chapters 6 to 24 at once" "${#INV[@]}" 4
STORY=42; col_story; eq "...all seven at the end" "${#INV[@]}" 7
col_count; eq "eleven sets... no: seven relics found" "${CLSD[5]}/${CLST[5]}" "7/7"
ach_check; eq "achievement: Keeper of Tales" "${ACHS:$(( ACH50 + 10 )):1}" 1
CLOG=""; v50_fix; INV=(C.40); BANK=(C.41); col_scan; check "what you hold counts as found" col_has 40; check "...the vault too" col_has 41
CLOG=$(printf '1%.0s' $(seq $NCOL)); ach_check; eq "Master Collector" "${ACHS:$(( ACH50 + 4 )):1}" 1
ach_title $(( ACH50 + 4 )); eq "...the Collector" "$ATT" "the Collector"
# a kill hands trophies through the network message, too
INV=() CLOG=""; v50_fix; for i in $(seq 60); do cli_srv REW abc123 10 5 "" "${WB_LIST[0]}" 0; done
check "REW from the server: the Elder Treant leaves its heartwood" col_has "${COL_BOSS[${WB_LIST[0]}]}"

# --- collectables: bags, shops, the inventory -------------------------------------------------------------------------------
new_hero 0 30; INV=(C.5 C.5 C.5! C.6 W.0.5.0 C.9); ROOMD=(C.9 - - -) ROOM_T=1 BAGS=10
col_dupes; eq "duplicates: two unlocked chickens and the displayed scarab" "${#DUP[@]}" 3
SHOP=general TALK_T=20; GOLD=0; shop_key c; eq "the shop buys the duplicates" "${INV[*]}" "C.5! C.6 W.0.5.0"
eq "...for their worth" "$GOLD" $(( CL_VAL[5] * 2 + CL_VAL[9] ))
GOLD=0; shop_key s; eq "sell everything keeps collectables" "${INV[*]}" "C.5! C.6"
junk_value; eq "collectables are never junk" "$JUNK" 0
if inv_equip 1 quiet; then fail "you can't wear a collectable"; else ok; fi
eq "...it stays in the bags" "${INV[1]}" C.6
INV=(W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0 W.0.1.0); add_item C.12
eq "a gifted collectable is never auto-sold" "${INV[10]}" C.12
INV=(C.3 W.0.1.0 B.2); SORT_M=0; sort_items INV; eq "collectables sort last" "${INV[2]}" C.3
INV_TAB=0; CDW=40; inv_card_col C.5; gt "a collectable has its own card" "${#CD_C[@]}" 6

# --- visiting ---------------------------------------------------------------------------------------------------------------------
new_hero 0 30; LVL=30 ROOM_T=3; v50_fix; ROOMD[0]=C.$CH ROOMD[3]=U.2; ROOM_DOOR=1; GOLD=0; rent_week; ROOM_PAID=$RWK
cli_line "SM1|POS|bbbbbb|bob|1|30|W|81|34|50|50|0|@|0|-1|0|0|-"
SENT=(); cli_line "SM1|RREQ|bbbbbb|bob|abc123"; [[ ${SENT[-1]} == "RNO abc123 tester bbbbbb party" ]] && ok || fail "a stranger at a party-only door: ${SENT[-1]}"
SENT=(); cli_line "SM1|RASK|bbbbbb|bob"; eq "...and no answer to asking around" "${#SENT[@]}" 0
PARTY_IDS=(abc123 bbbbbb); NOW=$(( NOW + 1100 )); SENT=(); cli_line "SM1|RASK|bbbbbb|bob"; [[ ${SENT[-1]} == "RHAS abc123 tester bbbbbb 3 2 "* ]] && ok || fail "a party member hears of the room: ${SENT[-1]}"
NOW=$(( NOW + 1100 )); SENT=(); cli_line "SM1|RREQ|bbbbbb|bob|abc123"; [[ ${SENT[-1]} == "ROOM abc123 tester bbbbbb 3 "*" C.$CH,-,-,U.2,"* ]] && ok || fail "...and is let in: ${SENT[-1]}"
ROOM_DOOR=0; NOW=$(( NOW + 1100 )); SENT=(); cli_line "SM1|RREQ|bbbbbb|bob|abc123"; [[ ${SENT[-1]} == *" locked" ]] && ok || fail "a locked door: ${SENT[-1]}"
ROOM_DOOR=2 PARTY_IDS=(); NOW=$(( NOW + 1100 )); SENT=(); cli_line "SM1|RREQ|bbbbbb|bob|abc123"; [[ ${SENT[-1]} == "ROOM "* ]] && ok || fail "an open door lets anybody in"
SENT=(); cli_line "SM1|RREQ|bbbbbb|bob|cccccc"; eq "requests for other owners are none of my business" "${#SENT[@]}" 0
NOW=$(( NOW + 1500 )); SENT=(); for i in 1 2 3 4 5; do cli_line "SM1|RASK|bbbbbb|bob"; done; eq "asking again and again: one answer a second" "${#SENT[@]}" 1
# the guestbook: only people in my room can sign
GUESTS=""; cli_line "SM1|RSIGN|bbbbbb|bob|abc123"; eq "bob is not in my room: no signature" "$GUESTS" ""
room_map abc123; cli_line "SM1|POS|bbbbbb|bob|1|30|$RMAP|5|5|50|50|0|@|0|-1|0|0|-"; eq "others can stand in a room" "${OP_MAP[bbbbbb]}" "$RMAP"
NOW=$(( NOW + 1100 )); cli_line "SM1|RSIGN|bbbbbb|bob|abc123"; [[ $GUESTS == bob:* ]] && ok || fail "bob signs: $GUESTS"
NOW=$(( NOW + 1100 )); cli_line "SM1|RSIGN|bbbbbb|bob|abc123"; set -- $GUESTS; eq "everybody signs once" "$#" 1
for g in ann cid dot eve fay gus hal ivy jon kim lou max ned; do guest_add "$g"; done; set -- $GUESTS
eq "twelve signatures at most" "$#" 12; eq "...newest first" "${1%%:*}" ned
ach_check; eq "achievement: Good Company" "${ACHS:$(( ACH50 + 12 )):1}" 1
# the owner changes something while bob is inside: everybody inside hears of it
SENT=(); dsp_put 1 0 2>/dev/null; INV=(C.8); dsp_put 1 0; [[ " ${SENT[*]} " == *"ROOM abc123 tester * 3 "* ]] && ok || fail "visitors see the change: ${SENT[*]}"
# --- the other side: I visit bob ---
new_hero 0 30; LOGS=(); CUR_MAP=W PX=88 PY=32
OP_NAME=() OP_MAP=(); cli_line "SM1|POS|bbbbbb|bob|1|30|W|88|33|50|50|0|@|0|-1|0|0|-"
visit_ask; [[ ${SENT[-1]} == "RASK abc123 tester" ]] && ok || fail "asking around"
cli_line "SM1|RHAS|bbbbbb|bob|abc123|2|5|33"; visit_list; eq "bob answers" "${VIS_L[*]}" bbbbbb
cli_line "SM1|RHAS|bbbbbb|bob|abc123|9|5|33"; eq "...a room size that doesn't exist is ignored" "${VIS_INFO[bbbbbb]}" "2 5 33"
cli_line "SM1|ROOM|bbbbbb|bob|abc123|2|33|C.5,-,-"; eq "a room nobody asked for is ignored" "$CUR_MAP" W
visit_go bbbbbb; [[ ${SENT[-1]} == "RREQ abc123 tester bbbbbb" ]] && ok || fail "knocking"
cli_line "SM1|ROOM|bbbbbb|bob|abc123|2|33|C.$CH,-,-,U.2,a[\$(x)],-,-,-,C.7,C.7"
room_map bbbbbb; eq "bob lets me in" "$CUR_MAP" "$RMAP"
eq "...his displays" "${RM_DSP[*]}" "C.$CH - - U.2 - - - -"
check "...it is not my room" eval '! room_mine'
for f in "${!RM_F[@]}"; do a=(${RM_F[f]}); [[ ${a[0]} == B ]] && bed=$f; [[ ${a[0]} == C ]] && chest=$f; [[ ${a[0]} == G ]] && gb=$f; [[ ${a[0]} == D && ${a[3]} == 0 ]] && d0=$f; done
REST_UNTIL=0; room_use "$bed"; eq "a guest can't sleep in bob's bed" "$REST_UNTIL" 0
UI=""; room_use "$chest"; eq "...or open his chest" "$UI" ""
LOGS=(); room_use "$d0"; [[ ${LOGS[-1]} == *"A Very Lost Chicken"* ]] && ok || fail "looking at a display: ${LOGS[-1]}"
SENT=(); room_use "$gb"; [[ ${SENT[-1]} == "RSIGN abc123 tester bbbbbb" ]] && ok || fail "signing bob's guestbook"
SENT=(); room_use "$gb"; eq "...once per visit" "${#SENT[@]}" 0
cli_line "SM1|ROOM|bbbbbb|bob|*|2|34|-,C.9,-,-,-,-,-,-"; eq "bob changes a display" "${RM_DSP[1]}" C.9
r3=${ROOM_LAY[3]%%/*}; cli_line "SM1|ROOM|bbbbbb|bob|*|3|34|-,C.9"; eq "bob moves up: the room grows around me" "${MAPW[$RMAP]}" "${#r3}"
cli_line "SM1|ROOM|cccccc|eve|*|0|0|"; eq "somebody else can't close bob's door" "$CUR_MAP" "$RMAP"
cli_line "SM1|ROOM|bbbbbb|bob|*|0|0|"; eq "bob locks his door: out I go" "$CUR_MAP" W
eq "...back at the inn" "$PX,$PY" "88,32"
visit_go bbbbbb; cli_line "SM1|ROOM|bbbbbb|bob|abc123|2|33|-"; room_map bbbbbb; eq "in again" "$CUR_MAP" "$RMAP"
unset "OP_NAME[bbbbbb]"; v50_tick; eq "bob leaves the world: so do his guests" "$CUR_MAP" W
visit_go bbbbbb 2>/dev/null; cli_line "SM1|POS|bbbbbb|bob|1|30|W|88|33|50|50|0|@|0|-1|0|0|-"; visit_go bbbbbb
cli_line "SM1|RNO|bbbbbb|bob|abc123|party"; [[ ${LOGS[-1]} == *"party"* ]] && ok || fail "a closed door says why"
# the door out
ROOM_T=1; v50_fix; rent_week; ROOM_PAID=$RWK; room_home; next_move=0
PY=$RM_SY PX=$RM_SX; try_move 0 1; eq "the door leads back down" "$CUR_MAP" W
[[ ${LOGS[-1]} == *taproom* ]] && ok || fail "down to the taproom: ${LOGS[-1]}"
eq "...and the room's furniture is gone" "${#RM_F[@]}" 0

# --- the server: players in rooms ----------------------------------------------------------------------------------------------------
slog() { :; }
srv_line "SM1|POS|dddddd|dora|0|20|H12303291|5|5|100|100|0|@|0"; eq "the server knows who is in a room" "${SP_MAP[dddddd]}" H12303291
srv_line "SM1|POS|dddddd|dora|0|20|H1230329100|5|5|100|100|0|@|0"; eq "...and ignores nonsense" "${SP_MAP[dddddd]}" H12303291
srv_line "SM1|POS|dddddd|dora|0|20|Hx|5|5|100|100|0|@|0"; eq "...of any kind" "${SP_MAP[dddddd]}" H12303291

# --- the innkeeper -----------------------------------------------------------------------------------------------------------------------
new_hero 0 30; cm_set 990 23 89 32 900 900; talk_open 990; talk_key 9; eq "[9] at an innkeeper: the rooms" "$UI" inn
UI=talk; cm_set 991 21 89 33 900 900; talk_open 991; talk_key 9; eq "...not at a smith" "$UI" talk
WANTED_UNTIL=$(( NOW + 9999 )); talk_open 990; talk_key 9; eq "...and not for murderers" "$UI" talk; WANTED_UNTIL=0
UI=inn GOLD=500; inn_key 2; eq "[2] rents the Attic Room" "$ROOM_T" 1
inn_key d; eq "[d] changes the door" "$ROOM_DOOR" 2
CUR_MAP=W PX=88 PY=32; inn_key 1; room_map "$MY_ID"; eq "[1] goes up" "$CUR_MAP" "$RMAP"
room_leave; UI=inn; inn_key v; eq "[v] asks who has a room" "$UI" visit

t_end
