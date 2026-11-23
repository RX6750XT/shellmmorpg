#!/usr/bin/env bash
# v3.0: talents, gems and sockets, elements and status effects, quests 2.0,
# questlines with choices, reputation, quartermasters, champions and the new AI.
source "$(dirname "$0")/lib.sh"
stub_client

# --- talents -----------------------------------------------------------------------------------
new_hero 0 20
tal_points; eq "19 points at level 20" "$TFREE" 19
if tal_can 1; then fail "row 2 needs 3 points in the tree first"; else ok; fi
tal_learn 0; tal_learn 0; tal_learn 0
check "row 2 opens after 3 points" tal_can 1
tal_learn 0; tal_learn 0
if tal_can 0; then fail "rank 5 is the maximum"; else ok; fi
eq "talent string" "$TAL" 500000000000
h=$MAXHP; tal_learn 8; tal_learn 8; tal_learn 8
gt "Toughness raises max HP" "$MAXHP" "$h"
for i in 1 1 1 2 2 2; do tal_learn "$i" >/dev/null; done
tal_learn 3; check "a capstone after 10 points in the tree" has_cap bleed0
tal_points; eq "points left" "$TFREE" 4
for i in 4 4 4 4; do tal_learn "$i"; done
if tal_learn 5 2>/dev/null; then fail "no points left"; else ok; fi
save_char; TAL=000000000000; load_char; eq "talents survive save and load" "$TAL" 533140003000
GOLD=100000; tal_reset; eq "an innkeeper makes you forget" "$TAL" 000000000000
for (( c = 0; c < NCLS; c++ )); do              # every class: every talent has a description
  CLS=$c; for (( i = 0; i < 12; i++ )); do tal_desc "$i"; [[ -n $TD ]] || fail "class $c talent $i has no description"; done
done; ok

# --- gems and sockets ---------------------------------------------------------------------------
new_hero 1 20
for (( k = 0; k < ${#WK_NAME[@]}; k++ )); do [[ ${WK_CLS[k]} == *1* ]] && { mk=$k; break; }; done
c=W.3.6.2.____
sock_info "$c"; eq "two empty sockets" "$SN/$SF" 2/0
sock_set "$c" 1 e3; eq "set a gem" "$CODE2" W.3.6.2.__e3
check "a socketed code is valid" valid_item "$CODE2"
sock_add "$CODE2"; eq "add a socket" "$CODE2" W.3.6.2.__e3__
sock_add W.3.6.2!; eq "socket on a locked item" "$CODE2" W.3.6.2.__!
sock_set W.3.6.2.r1__! 0 s2; eq "set keeps the lock" "$CODE2" W.3.6.2.s2__!
sock_cost W.3.6.0.__; eq "commons take one socket" "$SKC" 0
sock_cost W.3.6.3.____; gt "legendaries take a third" "$SKC" 0
sock_cost U.3; eq "uniques take none" "$SKC" 0
EQW=W.$mk.6.2; calc_stats; a=$CRIT
EQW=W.$mk.6.2.e3e3; calc_stats; eq "two flawless emeralds: +12 crit" $(( CRIT - a )) 12
EQW=W.$mk.6.2.a3__; calc_stats; b=$MAXHP; EQW=W.$mk.6.2; calc_stats; gt "amethyst: more HP" "$b" "$MAXHP"
EQW=W.3.6.2; calc_stats; a=$CRIT; EQW=W.3.6.2.e3e3; calc_stats; eq "gems in gear you can't use do nothing" "$CRIT" "$a"
# the jeweler, as a player would use it
INV=(W.3.6.2.____ A.0.6.1); TALK_MID=905; cm_set 905 21 81 34 900 900; TALK_T=21
gem_mat 0 2; MATS[GM]=1; GOLD=0
jewel_open; jw_list; JW_CUR=-1; for i in "${!JWL[@]}"; do [[ ${JWL[i]} == I:0 ]] && JW_CUR=$i; done
jewel_key $'\r'; jewel_key 1; jewel_key a
eq "the jeweler sets a polished ruby" "${INV[0]}" W.3.6.2.r2__
eq "the gem is used up" "${MATS[GM]}" 0
gem_mat 4 1; MATS[GM]=3; GOLD=500; JW_TAB=1; jewel_key m
gem_mat 4 2; eq "three chipped amethysts make a polished one" "${MATS[GM]}" 1

# --- elements, damage, status effects ------------------------------------------------------------
new_hero 1 20; CRIT=0
el_mult 37 1; eq "ice elementals are weak to fire" "$EM" 150
el_mult 37 2; eq "ice elementals resist frost" "$EM" 50
el_mult 0 1; eq "rats don't care" "$EM" 100
hits() {  # type element -> AVG damage over 40 hits
  local i s=0 n=0 x
  for (( i = 0; i < 40; i++ )); do
    cm_set 950 "$1" $(( PX + 1 )) "$PY" 99999 99999; SENT=(); DEAL_EL=$2 CASTK=-1; deal 950 100 0 q
    x=${SENT[0]}; x=${x#HIT * * 950 }; s=$(( s + ${x%% *} )); n=$(( n + 1 ))
  done
  AVG=$(( s / n ))
}
hits 37 1; w=$AVG; hits 37 0; p=$AVG; hits 37 2; r=$AVG
gt "fire hurts an ice elemental more" "$w" "$p"; gt "frost hurts it less" "$p" "$r"
DODGE=0 BLOCK=0 RES=0 BARRIER=0; HP=$MAXHP
take_damage 100 Test "" 0 ""; a=$(( MAXHP - HP )); HP=$MAXHP
RES=50; take_damage 100 Test "" 1 ""; b=$(( MAXHP - HP )); HP=$MAXHP
gt "resistance protects from fire" "$a" "$b"
RES=0; DODGE=100; take_damage 500 Test "" 0 ""; eq "a dodge takes no damage" "$HP" "$MAXHP"; DODGE=0
BARRIER=1000; take_damage 100 Test "" 0 ""; eq "a barrier absorbs" "$HP" "$MAXHP"; BARRIER=0
RES=0; take_damage 50 Spider "" 3 poison; check "poisoned" test "${PS_UNTIL[0]}" -gt "$NOW"
h=$HP; pst_tick; gt "poison hurts every second" "$h" "$HP"
POT_H=1; use_item h; eq "a health potion cures poison" "${PS_UNTIL[0]}" 0
pst_apply stun 10; x=$PX; try_move 1 0; eq "stunned: no step" "$PX" "$x"
SKCD=(0 0 0); MP=999; m=$MP; cast 0; eq "stunned: no spell" "$MP" "$m"
PS_UNTIL[4]=0; pst_apply stun 10; eq "stuns can't be chained" "${PS_UNTIL[4]}" 0
new_hero 0 30; TAL=000000000000
for i in 8 8 8 8 8 9 9 9 10 10 10 11; do tal_learn "$i" >/dev/null; done
check "Last Stand learned" has_cap laststand
HP=5; DODGE=0 BLOCK=0 BARRIER=0; take_damage 9999 Ogre "" 0 ""
eq "Last Stand: still standing" "$HP/$DEAD" 1/0
immune_until=0; take_damage 9999 Ogre "" 0 ""; eq "...but only once" "$DEAD" 1

# --- quests 2.0 -------------------------------------------------------------------------------------
new_hero 0 14; init_where
for r in 1 2 3 4 5; do QSRC=board; gen_offers; for q in "${OFFERS[@]}"; do check "offer '$q' is valid" valid_quest "$q"; done; done
QUESTS=(C.29.3.0.100.50); g=$GOLD
for i in $(seq 40); do qev_kill 29; [[ ${#QUESTS[@]} == 0 ]] && break; done
eq "collect quest done" "${#QUESTS[@]}" 0; gt "it paid" "$GOLD" "$g"
QUESTS=(B.$(( RARE0 + 6 )).1.0.500.100); qev_kill $(( RARE0 + 6 )); eq "bounty done" "${#QUESTS[@]}" 0
QUESTS=(E.12.1.0.100.10); PX=${SPT_X[12]} PY=${SPT_Y[12]}; ql_explore; eq "scouting done" "${#QUESTS[@]}" 0
QUESTS=(G.6.4.0.100.10); MATS[6]=3; qev_board; eq "not enough herbs yet" "${#QUESTS[@]}" 1
MATS[6]=5; qev_board; eq "delivery done" "${#QUESTS[@]}/${MATS[6]}" 0/1
REP=(0 0 0 0 0 0); QUESTS=(K.29.1.0.10.10); reward 1 0 "" 29; gt "a desert quest helps Kadar" "${REP[2]}" 0

# --- every questline, start to finish ------------------------------------------------------------------
new_hero 3 30; init_where; REP=(0 0 0 0 0 0); QLS=""; QLP=(); QLC=""; ql_fix; INV=() BAGS=40
for (( l = 0; l < NQL; l++ )); do
  (( LVL < QL_LVL[l] )) && LVL=${QL_LVL[l]}                  # (8.0: questlines up to level 48)
  TALK_T=${QL_NPC[l]}; UI=talk; ql_key
  eq "${QL_NAME[l]} starts" "${QLS:l:1}" 1
  for (( s = 0; s < QL_N[l]; s++ )); do
    ql_step "$l"; qobj_parse "${QS_OBJ[QST]}"
    case $OT in
      K|B) for (( i = 0; i < ON; i++ )); do qev_kill "$OA"; done ;;
      C)   for (( i = 0; i < 60 && QLP[l] < ON; i++ )); do qev_kill "$OA"; done ;;
      G)   MATS[OA]=$(( MATS[OA] + ON )) ;;
      E)   PX=${SPT_X[OA]} PY=${SPT_Y[OA]}; ql_explore ;;
      D)   qev_dungeon "$OA" ;;
    esac
    if [[ $OT == T ]]; then ql_talk "$OA"
    else check "${QL_NAME[l]} step $(( s + 1 )) ($OT) is ready" ql_ready "$l"; TALK_T=${QL_NPC[l]}; ql_key; fi
    if [[ $UI == qchoice ]]; then ql_choose $( (( l % 2 )) && echo b || echo a ); fi
  done
  eq "${QL_NAME[l]} is done" "${QLS:l:1}" x
done
n=0; for (( l = 0; l < NQL; l++ )); do [[ ${QLC:l:1} != - ]] && n=$(( n + 1 )); done
ge "choices were made" "$n" 7
for f in 0 1 2 3 4 5; do gt "${FAC_NAME[f]} reputation" "${REP[f]}" 0; done
bad=0; for c in "${INV[@]}"; do valid_item "${c%!}" || bad=1; done; eq "questline rewards are valid items" "$bad" 0
save_char; s=$QLS; QLS=""; load_char; eq "questlines survive save and load" "$QLS" "$s"

# --- reputation, shops, quartermasters -------------------------------------------------------------------
REP=(0 0 0 0 0 0); rep_rank 0; eq "neutral" "$RR" 0
rep_add 0 5000; rep_rank 0; eq "honored" "$RR" 2
TALK_T=20; SHOP=general; shop_build general; p1=${SH_PRICE[0]}
REP[0]=0; shop_build general; p0=${SH_PRICE[0]}
gt "honored customers pay less" "$p0" "$p1"
REP[0]=16000 GOLD=999999 INV=() BAGS=20; TALK_T=$NPC1
for i in 0 1 2 3 4; do wares_buy "$i"; done
eq "the quartermaster sold everything" "${#INV[@]}" 4
bad=0; for c in "${INV[@]}"; do valid_item "${c%!}" || bad=1; done; eq "quartermaster items are valid" "$bad" 0
REP[0]=0; INV=(); wares_buy 3; eq "uniques only for the Revered" "${#INV[@]}" 0

# --- the world server: champions, rares, abilities, ranged attacks, healers, summons ---------------------
send() { SENT+=("$*"); return 0; }; slog() { :; }
NOW=5000000; WH_LAST=$(( NOW / 150 - 1 )); spawn_world
ch=0 rare=0
for m in "${!AL[@]}"; do (( ${MCH[m]:--1} >= 0 )) && ch=$(( ch + 1 )); (( M_BOSS[MT[m]] == 2 )) && rare=$(( rare + 1 )); done
ge "some champions roam the world" "$ch" 1
eq "every rare elite is out there" "$rare" "$NRARE"
for m in "${!AL[@]}"; do (( ${MCH[m]:--1} >= 0 )) && { cm=$m; break; }; done
SENT=(); mon_state "$cm"; [[ ${SENT[0]} == "MON srv W $cm "*" $(( MCH[cm] + 1 ))" ]] && ok || fail "MON carries the champion affix: ${SENT[0]}"
bad=0; for (( i = 0; i < 300; i++ )); do roll_item 30 bbbbbb "" 1; [[ -z $ITEM || $ITEM == [HM] ]] && continue; valid_item "$ITEM" || { bad=1; fail "loot '$ITEM'"; }; done
eq "champion loot is valid" "$bad" 0
SP_NAME[aaaaaa]=alice SP_MAP[aaaaaa]=W SP_DEAD[aaaaaa]=0 SP_LVL[aaaaaa]=20 SP_CLS[aaaaaa]=0
for m in "${!AL[@]}"; do [[ ${M_AB[MT[m]]} == poison && ${MMAP[m]} == W ]] && (( M_KIND[MT[m]] == 0 )) && { pm=$m; break; }; done
SENT=(); for i in $(seq 60); do mon_hit "$pm" aaaaaa 10; done
eff=0; for x in "${SENT[@]}"; do [[ $x == "MATK srv W $pm aaaaaa 10 ${M_EL[MT[pm]]} poison" ]] && eff=1; done
eq "poisonous monsters poison" "$eff" 1
for m in "${!AL[@]}"; do (( M_RNG[MT[m]] && M_KIND[MT[m]] == 0 )) && [[ ${MMAP[m]} == W ]] && { rm=$m; break; }; done
for dx in 3 -3 0; do for dy in 0 3 -3; do
  x=$(( MX[rm] + dx )) y=$(( MY[rm] + dy )); m_walk W "$x" "$y" && los W "${MX[rm]}" "${MY[rm]}" "$x" "$y" && { tx=$x ty=$y; break 2; }
done; done
SP_X[aaaaaa]=$tx SP_Y[aaaaaa]=$ty; MAGG[rm]=aaaaaa; MFRZ[rm]=0; SENT=(); NOW=$(( NOW + 100000 )); mon_think "$rm"
[[ " ${SENT[*]} " == *"MATK srv W $rm aaaaaa"* ]] && ok || fail "a ranged monster (${M_NAME[MT[rm]]}) shoots from 3 tiles: ${SENT[*]:0:3}"
SP_DEAD[aaaaaa]=1
DREQ_T=(); SOLO_INST=(); SP_DEAD[aaaaaa]=0; SP_X[aaaaaa]=${D_ENTX[1]} SP_Y[aaaaaa]=${D_ENTY[1]}; srv_dreq aaaaaa 1
map=${SOLO_INST[aaaaaa]}; for m in ${IN_MONS[$map]}; do (( MT[m] == D_BOSS[1] )) && boss=$m; done
n=${#IN_MONS[$map]}; MHP[boss]=$(( MMAX[boss] / 2 )); SENT=(); srv_hit aaaaaa "$map" "$boss" 1 0
gt "the boss calls for help at half health" "${#IN_MONS[$map]}" "$n"
for m in ${IN_MONS[$map]}; do (( M_HEALR[MT[m]] )) && { hm=$m; break; }; done
if [[ -n $hm ]]; then
  for m in ${IN_MONS[$map]}; do [[ $m != "$hm" ]] && (( M_KIND[MT[m]] == 0 )) && { cheb $(( MX[m] - MX[hm] )) $(( MY[m] - MY[hm] )); (( D <= 5 )) && { wm=$m; break; }; }; done
  if [[ -n $wm ]]; then MHP[wm]=1; MHEALT[hm]=0; mon_healer "$hm"; gt "a shaman heals its friends" "${MHP[wm]}" 1; fi
fi
SENT=(); for i in $(seq 40); do gem_drop $(( RARE0 + 3 )) aaaaaa 0; done
n=0; for x in "${SENT[@]}"; do [[ $x =~ ^LOOT\ srv\ aaaaaa\ g([0-9]+)$ ]] && (( BASH_REMATCH[1] >= GEM0 && BASH_REMATCH[1] < NMAT )) && n=$(( n + 1 )); done
ge "rares drop gems" "$n" 10
MATS[GEM0]=0; cli_srv LOOT "$MY_ID" "g$GEM0"; eq "the client takes the gem" "${MATS[GEM0]}" 1
cli_srv LOOT "$MY_ID" 'g$(id)'; cli_srv LOOT "$MY_ID" "g999"; ok

t_end
