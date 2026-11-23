#!/usr/bin/env bash
# v4.5: professions and gems to level 40, paragon, mythic dungeons, the raid, invasions, valor,
# mounts, dailies and weeklies, achievements and titles.
source "$(dirname "$0")/lib.sh"
stub_client

# --- professions up to 40 -----------------------------------------------------------------------------
new_hero 0 40
ge "54 materials or more" "$NMAT" 54
for k in 0 1 2 3; do n=0; for i in ${MAT_GRP[k]}; do (( MAT_PK[i] == k )) || fail "material $i in group $k"; n=$(( n + 1 )); done; ge "group $k has materials" "$n" 6; done
n=0; for i in ${MAT_GRP[3]}; do gem_kq "$i" || fail "$i is no gem"; n=$(( n + 1 )); done; eq "24 gems" "$n" 24
for g in 0 1 2 3 4 5; do for q in 1 2 3 4; do gem_mat "$g" "$q"; gem_kq "$GM"; [[ "$GKI.$GQI" == "$g.$q" ]] || fail "gem $g.$q -> $GM -> $GKI.$GQI"; done; done; ok
PROF_LV=(29 29 29) PROF_XP=(0 0 0); for i in $(seq 400); do prof_gain 1 500 >/dev/null; done; eq "mining goes to the cap ($PROF_MAX since 8.0)" "${PROF_LV[1]}" "$PROF_MAX"
for t in "${NODE_T[@]}"; do [[ -n ${NODE_MAT[$t]} && -n ${NODE_PK[$t]} ]] || fail "node $t"; done; ge "16 kinds of nodes or more" "${#NODE_T[@]}" 16
PROF_LV=(40 40 40); m=0; CM_T=(); cm_set 960 $(( N45 + 1 )) $(( PX + 1 )) "$PY" 3 3
GATH_MID=""; gather_start 960; GATH_END=0; MATS[M45+1]=0; gather_tick
gt "a starmetal vein gives starmetal" "${MATS[M45+1]}" 0
CRAFT=cook; craft_build; bad=0; for id in "${RC_ID[@]}"; do x=${id#c}; gem_kq "$x" && bad=1; done; eq "no more cooking gems" "$bad" 0
CRAFT=forge; craft_build; t12=-1; for i in "${!RC_ID[@]}"; do [[ ${RC_ID[i]} == W.*.12 ]] && t12=$i; done
ge "the forge makes tier 12" "$t12" 0
MATS[M45]=50 MATS[M45+1]=50 GOLD=999999 INV=() BAGS=30; craft_do "$t12" >/dev/null
check "a forged Godforged weapon is valid" valid_item "${INV[0]}"
CRAFT=alch; craft_build; g=-1; for i in "${!RC_ID[@]}"; do [[ ${RC_ID[i]} == grand ]] && { g=$i; break; }; done   # (8.0 has a second recipe)
MATS[M45+2]=9 MATS[M45+3]=9 EL_STR=0 EL_IRON=0 EL_SWIFT=0; craft_do "$g" >/dev/null; eq "the grand elixir" "$EL_STR$EL_IRON$EL_SWIFT" 111
n=0; for e in ${FISHW[sea]}; do [[ ${e%%:*} == $(( M45 + 7 )) ]] && n=1; done; eq "the Starfish of Ys bites in the sea" "$n" 1
check "perfect gems in sockets are valid" valid_item W.0.12.3.r4e4a4
EQW=W.${DEFW[0]}.12.2; calc_stats; a=$CRIT; EQW=W.${DEFW[0]}.12.2.e4e4; calc_stats; eq "two perfect emeralds: +18 crit" $(( CRIT - a )) 18
gem_mat 2 3; MATS[GM]=3; GOLD=9999 JW_TAB=1; jewel_key i; gem_mat 2 4; eq "three flawless emeralds make a perfect one" "${MATS[GM]}" 1
eq "...an achievement" "$GEMP" 1

# --- paragon --------------------------------------------------------------------------------------------
new_hero 3 "$MAXLVL"
para_points; eq "13 paragon points at level 50 (talents are full at 36)" "$PFREE" 13
XP=0; gain_xp 130000 >/dev/null; eq "130k XP after 50: two paragon levels" "$PARA" 2
para_points; eq "15 points" "$PFREE" 15
a=$ATK; para_learn 0 >/dev/null; para_learn 0 >/dev/null; gt "Might hits harder" "$ATK" "$a"
h=$MAXHP; para_learn 1 >/dev/null; gt "Vitality gives health" "$MAXHP" "$h"
PARA_P="50 0 0 0 0 0"; PARA=99; if para_learn 0 2>/dev/null >/dev/null; then fail "Might stops at 50"; else ok; fi
PARA_P="2 1 0 0 0 0" PARA=2; save_char; PARA=0 PARA_P=""; load_char; eq "paragon survives save and load" "$PARA/$PARA_P" "2/2 1 0 0 0 0"
GOLD=999999; tal_reset; eq "the innkeeper resets paragon points too" "$PARA_P" "0 0 0 0 0 0"
XPNEXT=1; calc_stats; para_next "$PARA"; eq "the XP bar shows the next paragon level" "$XPNEXT" "$PNX"

# --- mythic dungeons (server) ----------------------------------------------------------------------------
send() { SENT+=("$*"); return 0; }; slog() { :; }
NOW=5000000; WH_LAST=$(( NOW / 150 - 1 ))
SP_NAME[aaaaaa]=alice SP_MAP[aaaaaa]=W SP_DEAD[aaaaaa]=0 SP_LVL[aaaaaa]=$MAXLVL SP_CLS[aaaaaa]=0
SP_X[aaaaaa]=${D_ENTX[2]} SP_Y[aaaaaa]=${D_ENTY[2]}
SENT=(); DREQ_T=(); srv_dreq aaaaaa 2 0; n=${SOLO_INST[aaaaaa]}
for m in ${IN_MONS[$n]}; do (( MT[m] == D_BOSS[2] )) && nb=$m; done; nhp=${MMAX[nb]}
close_instance "$n"
SENT=(); DREQ_T=(); srv_dreq aaaaaa 2 10; map=${SOLO_INST[aaaaaa]}
eq "a mythic +10 instance" "${IN_MYTH[$map]}" 10
[[ " ${SENT[*]} " == *"DSTART srv $map 2 "*" aaaaaa 10 ${IN_LIM[$map]} 0"* ]] && ok || fail "DSTART carries the key and the clock: ${SENT[*]}"
for m in ${IN_MONS[$map]}; do (( MT[m] == D_BOSS[2] )) && boss=$m; done
gt "the boss of a level 6 dungeon is much stronger on mythic" "${MMAX[boss]}" $(( nhp * 10 ))
gt "...and hits harder" "${MDS[boss]}" 400
ch=0 cnt=0; for m in ${IN_MONS[$map]}; do (( M_BOSS[MT[m]] == 0 && M_KIND[MT[m]] == 0 )) || continue; cnt=$(( cnt + 1 )); (( ${MCH[m]:--1} >= 0 )) && ch=$(( ch + 1 )); done
gt "this week's champion affix is everywhere" "$ch" 0
SP_MAP[aaaaaa]=$map SP_X[aaaaaa]=$(( MX[boss] + 1 )) SP_Y[aaaaaa]=${MY[boss]}
PLIST=(); PLIST[$map]=" aaaaaa"; SENT=(); MCH[boss]=-1; mon_attack "$boss" aaaaaa
x=""; for s in "${SENT[@]}"; do [[ $s == "MATK srv $map $boss aaaaaa "* ]] && { x=${s#MATK srv $map $boss aaaaaa }; x=${x%% *}; }; done
gt "mythic bosses hit like level $MYTH_LVL" "${x:-0}" "${M_DMG[D_BOSS[2]]}"
srv_line "SM1|POS|aaaaaa|alice|0|$MAXLVL|$map|${SP_X[aaaaaa]}|${SP_Y[aaaaaa]}|0|100|1|@|0"; t0=${IN_T0[$map]}
eq "dying costs the group 5 seconds" "$t0" $(( NOW - 5000 ))
SP_DEAD[aaaaaa]=0
IN_T0[$map]=$(( NOW - IN_LIM[map] / 3 )); SENT=(); MHP[boss]=1; srv_hit aaaaaa "$map" "$boss" 500 0
md=""; for s in "${SENT[@]}"; do [[ $s == "MDONE srv aaaaaa 10 "* ]] && md=$s; done
[[ $md == "MDONE srv aaaaaa 10 2 "* ]] && ok || fail "a fast clear raises the key by 2: $md"
n=0; for s in "${SENT[@]}"; do [[ $s =~ ^LOOT\ srv\ aaaaaa\ i:([WAOHJ]\.[0-9]+\.15\.[23]\..+)$ ]] && valid_item "${BASH_REMATCH[1]}" && n=1; done
eq "the mythic boss pays epic+ tier 15 gear" "$n" 1
KEYLV=10 MYBEST=0 VALOR=0; myth_done 10 2 200 80 >/dev/null; eq "client: the key rises" "$KEYLV/$MYBEST" 12/10
myth_done 12 0 900 40 >/dev/null; eq "client: too slow, the key stays" "$KEYLV/$MYBEST" 12/10
ge "client: valor" "$VALOR" 120
close_instance "$map"

# --- the raid -------------------------------------------------------------------------------------------------
SP_MAP[aaaaaa]=W SP_X[aaaaaa]=${D_ENTX[RAID_DT]} SP_Y[aaaaaa]=${D_ENTY[RAID_DT]}
SENT=(); DREQ_T=(); srv_dreq aaaaaa "$RAID_DT" 5; map=${SOLO_INST[aaaaaa]}
eq "no mythic raid" "${IN_MYTH[$map]}" 0
for m in ${IN_MONS[$map]}; do (( MT[m] == RD_NYX )) && nyx=$m; done
check "Nyxara waits on her throne" test -n "$nyx"
SP_MAP[aaaaaa]=$map SP_X[aaaaaa]=$(( MX[nyx] + 1 )) SP_Y[aaaaaa]=${MY[nyx]}; PLIST=(); PLIST[$map]=" aaaaaa"
MATKN[nyx]=2; SENT=(); AOE_Q=(); mon_attack "$nyx" aaaaaa
eq "her third blow is a meteor on everyone" "${#AOE_Q[@]}" 1
NOW=$(( NOW + 2000 )); SENT=(); aoe_tick
n=0; for s in "${SENT[@]}"; do [[ $s == "MATK srv $map $nyx aaaaaa "* ]] && n=1; done; eq "standing in it hurts" "$n" 1
MATKN[nyx]=2; mon_attack "$nyx" aaaaaa; SP_X[aaaaaa]=$(( SP_X[aaaaaa] + 4 )); NOW=$(( NOW + 2000 )); SENT=(); aoe_tick
n=0; for s in "${SENT[@]}"; do [[ $s == MATK* ]] && n=1; done; eq "stepping out of it doesn't" "$n" 0
MHP[nyx]=$(( MMAX[nyx] * 6 / 10 )); h=${MHP[nyx]}; srv_hit aaaaaa "$map" "$nyx" 100 0
eq "at 2/3 she calls her guards" "${MPH[nyx]}" 1
h=${MHP[nyx]}; srv_hit aaaaaa "$map" "$nyx" 1000 0; eq "...and hides behind her shield" $(( h - MHP[nyx] )) 200
MHP[nyx]=$(( MMAX[nyx] / 4 )) MPH[nyx]=2 MATKN[nyx]=4; AOE_Q=(); mon_attack "$nyx" aaaaaa
a=(${AOE_Q[0]}); eq "phase 3: the total eclipse covers 4 tiles around her" "${a[4]}" 4
SENT=(); MHP[nyx]=1; srv_hit aaaaaa "$map" "$nyx" 500 0
n=0; for s in "${SENT[@]}"; do [[ $s =~ ^LOOT\ srv\ aaaaaa\ i:([WAOHJ]\.[0-9]+\.12\.3\.______)$ ]] && valid_item "${BASH_REMATCH[1]}" && n=1; done
eq "everyone gets a three-socket legendary" "$n" 1
close_instance "$map"

# --- invasions -----------------------------------------------------------------------------------------------
SP_MAP[aaaaaa]=W SP_X[aaaaaa]=80 SP_Y[aaaaaa]=34; inv_towns
ge "every town but Hearthmoor can be invaded" "${#INV_T[@]}" 16
SENT=(); INV_TOWN=-1; inv_start
eq "the first wave" "$INV_WAVE" 1
n=0; for m in $INV_MONS; do n=$(( n + 1 )); in_safe_xy "${MX[m]}" "${MY[m]}" && fail "an invader spawned inside the walls"; done; ge "eight invaders" "$n" 7
for w in 1 2 3; do for m in $INV_MONS; do MHP[m]=1; srv_hit aaaaaa W "$m" 9999 0; done; SENT=(); inv_second; done
n=0; for s in "${SENT[@]}"; do [[ $s == "EVREW srv aaaaaa 25 "* ]] && n=1; done; eq "the defender is paid after three waves" "$n" 1
eq "the invasion is over" "$INV_TOWN" -1
VALOR=0 INVK=0; cli_srv EVREW "$MY_ID" 25 1000 500; eq "client: valor for the defence" "$VALOR/$INVK" 25/1
INV_TOWN=-1; inv_start; INV_END=$NOW; SENT=(); inv_second; eq "too slow: the town falls" "$INV_TOWN" -1

# --- valor, mounts --------------------------------------------------------------------------------------------
new_hero 1 "$MAXLVL"; INV=() BAGS=30 VALOR=99999
for i in 0 1 2 3 4 5 6; do valor_buy "$i" >/dev/null; done
bad=0; for c in "${INV[@]}"; do valid_item "${c%!}" || bad=1; [[ $c =~ \.15\. ]] || bad=1; done
eq "valor buys Ascendant gear" "${#INV[@]}/$bad" 6/0
valor_buy 7 >/dev/null; check "valor buys the Storm Gryphon" mount_has 4
MOUNTS=00000000 GOLD=100; mount_buy 0 >/dev/null; if mount_has 0; then fail "a horse costs 1500"; else ok; fi
GOLD=99999; mount_buy 0 >/dev/null; check "Hilda sells a horse" mount_has 0
REP[2]=0; mount_buy 2 >/dev/null; if mount_has 2; then fail "the camel is for the Honored of Kadar"; else ok; fi
REP[2]=5000; mount_buy 2 >/dev/null; check "...like this one" mount_has 2
MNT_CUR=0 last_hurt=0 last_att=0 RIDING=0; mount_toggle >/dev/null; eq "mounted" "$RIDING" 1
PX=100 PY=50; next_move=0; try_move 1 0; d1=$(( next_move - NOW ))
RIDING=0 PX=100 PY=50; next_move=0; try_move 1 0; d0=$(( next_move - NOW )); gt "faster on horseback" "$d0" "$d1"; RIDING=1
RIDING=1; DODGE=0 BLOCK=0; take_damage 5 Wolf "" 0 "" >/dev/null; eq "a hit throws you off" "$RIDING" 0
CUR_MAP=D3; mount_toggle >/dev/null; eq "no horses in dungeons" "$RIDING" 0; CUR_MAP=W
OP_CLS[bbbbbb]=1; cli_line "SM1|POS|bbbbbb|bob|1|30|W|81|34|50|50|0|@|0|-1|0|0|4"; eq "others see your mount" "${OP_MNT[bbbbbb]}" 4
[[ ${GLYH[pbbbbbb]} == *🦅* ]] && ok || fail "...in HD"
cli_line "SM1|POS|bbbbbb|bob|1|30|W|81|34|50|50|0|@|0|-1|0|0|-"; eq "...and when you get off" "${OP_MNT[bbbbbb]:-none}" none

# --- dailies and weeklies --------------------------------------------------------------------------------------
new_hero 0 35; DAILY="" WEEKLY=""; dly_fix
eq "three dailies" "${#DLY_CUR[@]}" 3; eq "two weeklies" "${#WKY_CUR[@]}" 2
week_now; [[ ${DAILY%% *} == "$DAYN" ]] && ok || fail "the dailies are today's"
k=${DLY_CUR[0]%%:*}; need=${DLY_CUR[0]#*:}; need=${need%%:*}; VALOR=0
for (( i = 0; i < need; i++ )); do dly_ev "$k" >/dev/null; done
a=($DAILY); [[ ${a[1]} == *":$need:1" ]] && ok || fail "daily done: $DAILY"
ge "dailies pay valor" "$VALOR" 30
save_char; s=$DAILY; DAILY=""; load_char; eq "dailies survive save and load" "$DAILY" "$s"
DAILY="1 0:0:0 0:0:0 0:0:0"; dly_fix; [[ ${DAILY%% *} == "$DAYN" ]] && ok || fail "a new day, new dailies"

# --- achievements ---------------------------------------------------------------------------------------------
new_hero 0 40; ACHS="" TITLE=-1; v45_fix; ach_check >/dev/null
eq "level 20, 30, 40" "${ACHS:0:3}" 111
title_next >/dev/null; my_title; eq "a title" "$TTL" "the Veteran"
title_next >/dev/null; my_title; eq "the next one" "$TTL" "the Legend"
save_char; ACHS="" TITLE=-1; load_char; eq "achievements survive save and load" "${ACHS:0:3}/$TITLE" 111/2

# --- LOOT i: and the mythic gate ---------------------------------------------------------------------------------
INV=() BAGS=10; cli_srv LOOT "$MY_ID" "i:W.3.12.3.______"; eq "a reward item arrives" "${INV[0]}" W.3.12.3.______
cli_srv LOOT "$MY_ID" 'i:W.3.$(id)'; cli_srv LOOT "$MY_ID" "i:U.99"; eq "...garbage does not" "${#INV[@]}" 1
LVL=$MAXLVL; UI=""; CUR_MAP=W PX=${D_ENTX[5]} PY=${D_ENTY[5]}; dungeon_enter; eq "at the level cap the gate asks first" "$UI" dgate
SENT=(); dreq_until=0; DG_K=5 KEYLV=5; dgate_key 2; eq "...and sends the key level" "${SENT[*]}" "DREQ $MY_ID 5 5"

t_end
