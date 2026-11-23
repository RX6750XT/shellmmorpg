#!/usr/bin/env bash
# v8.0: Beyond the Edge - level 50, the 600x200 world and its four new lands, the towns and the Horizon
# Watch, gear tiers 13-15, materials and recipes, the second raid (Aurelion), mounts 9-13, the Skyward
# Manor, act III of the story, collectables, achievements, and old heroes in the new world.
source "$(dirname "$0")/lib.sh"
stub_client
load_world

# --- the level cap and the gear ------------------------------------------------------------------------------------
eq "the cap is level 50" "$MAXLVL" 50
eq "three more tiers" "$MAXTIER/${TIER_Q[13]}/${TIER_Q[15]}" "15/Mythforged/Ascendant"
for t in 13 14 15; do
  [[ -n ${MAT_E[t]} && -n ${TIER_FL[t]} ]] || fail "tier $t has no icon or flavor"
  check "tier $t gear is valid" valid_item "A.3.$t.2.r3__"
done
base_stats 45; b45=$BH; base_stats 40; b40=$BH; base_stats 50; b50=$BH
gt "creatures grow between 40 and 50" "$b45" "$b40"; gt "...up to 50" "$b50" "$b45"
new_hero 0 49; XP=0; gain_xp 99999999; eq "a hero reaches 50" "$LVL" 50
gt "...and the rest is paragon" "$PARA" 0
new_hero 4 50; bad=0; for (( i = 0; i < 300; i++ )); do
  roll_item "$AR_GOLEM" aaaaaa; [[ -z $ITEM || $ITEM == [HM] ]] && continue; valid_item "$ITEM" || { bad=1; fail "loot '$ITEM'"; }
done; eq "level 50 creatures drop valid loot" "$bad" 0
t=0; for (( i = 0; i < 200; i++ )); do roll_item "$AR_GOLEM" aaaaaa; [[ $ITEM =~ ^[WAOHJ]\.[0-9]+\.15\. ]] && t=1; done
eq "...of tier 15" "$t" 1
CRAFT=forge; craft_build; n=0; for i in "${!RC_ID[@]}"; do [[ ${RC_ID[i]} == W.*.1[345] ]] && n=$(( n + 1 )); done
eq "the forge makes tiers 13, 14 and 15" "$n" 3
for i in "${!RC_ID[@]}"; do [[ ${RC_ID[i]} == W.*.15 ]] && t15=$i; done
MATS[M80+2]=50 MATS[M80+1]=50 GOLD=999999 INV=() BAGS=30; craft_do "$t15" >/dev/null
[[ ${INV[0]} =~ ^W\.[0-9]+\.15\.[1-3]$ ]] && ok || fail "an Ascendant weapon from aetherium: '${INV[0]}'"
for (( u = U80; u < NUQ; u++ )); do check "unique $u (${U_NAME[u]}) is valid" valid_item "U.$u"; done
ge "25 new uniques" $(( NUQ - U80 )) 25

# --- the world ---------------------------------------------------------------------------------------------------
eq "the world is 600x200" "${MAPW[W]}x${MAPH[W]}" 600x200
for p in "Shroudmarch:540:190" "Gilded Expanse:500:105" "Rimewastes:560:55" "Aether Reach:560:5"; do
  IFS=: read -r n x y <<< "$p"; region_of "$x" "$y" nosafe; eq "$x,$y is in the $n" "$RNAME" "$n"
done
for (( i = 0; i < 4; i++ )); do
  region_of $(( T8_X[i] + 10 )) $(( T8_Y[i] + 6 )); eq "${T8_NAME[i]} is a town" "$RNAME" "${T8_NAME[i]}"
  in_safe_xy $(( T8_X[i] + 10 )) $(( T8_Y[i] + 6 )) && ok || fail "${T8_NAME[i]} is not safe"
  w=-1; for j in "${!WAYSTONES[@]}"; do [[ ${WAYSTONES[j]%% *} == "${T8_NAME[i]}" ]] && w=$j; done
  a=(${WAYSTONES[w]}); tile W "${a[1]}" "${a[2]}"; eq "${T8_NAME[i]} has a waystone" "$T" Z
  eq "${T8_NAME[i]} belongs to the Horizon Watch" "${TOWN_FAC[${T8_NAME[i]}]}" "$FAC80"
done
for (( t = NPC80; t < NPC80 + 28; t++ )); do
  [[ -n ${N_ROLE[$t]} ]] || continue
  for s in "${NPC_SPAWNS[@]}"; do a=($s); (( a[0] == t )) || continue; tile W "${a[1]}" "${a[2]}"; [[ $T == _ ]] || fail "${N_FULL[$t]} stands on '$T'"; done
done; ok
for z in "${ZONES[@]}"; do
  a=($z); (( a[0] >= SH_STALK )) || continue
  c=0; for (( y = a[2]; y <= a[4] && c == 0; y++ )); do for (( x = a[1]; x <= a[3]; x++ )); do m_walk W $x $y && { c=1; break; }; done; done
  (( c )) || fail "zone of ${M_NAME[a[0]]} has no walkable tile"
done; ok
for (( d = D80; d < NDT; d++ )); do tile W "${D_ENTX[d]}" "${D_ENTY[d]}"; eq "${D_NAME[d]} has an entrance" "$T" ">"; done
bad=0; for (( t = SH_STALK; t < NM; t++ )); do
  (( M_KIND[t] == 0 )) || continue
  [[ -n ${M_EL[t]} && -n ${M_WK[t]} && -n ${M_RS[t]} ]] || { bad=1; echo "  ${M_NAME[t]} has no element"; }
  [[ ${M_AB[t]} == -* ]] && { bad=1; echo "  ${M_NAME[t]}: ability '${M_AB[t]}'"; }
  dispw "${MEMO[t]}"; (( DW == 2 )) || { bad=1; echo "  ${M_NAME[t]}: sprite is $DW columns"; }
done; eq "every new creature has an element and a 2-column sprite" "$bad" 0
eq "the Rimeborn shaman heals" "${M_HEALR[RW_SHAMAN]}" 1
eq "a new rare is made of what its kind is made of" "${M_EL[$(( R80 + 4 ))]}" "${M_EL[RW_WOLF]}"
eq "the bosses summon" "${M_SUMM[B_STARW]}" 1
new_hero 0 46; QSRC=board; seen=0; for i in $(seq 40); do gen_offers; [[ " ${OFFERS[*]} " == *K.$RW_* ]] && seen=1
  for o in "${OFFERS[@]}"; do [[ $o == K.$RW_TROLL.* || $o == K.$RW_WOLF.* || $o == K.$GE_WURM.* || $o == K.$RW_WRAITH.* ]] && seen=1; done; done
eq "the quest board offers the new creatures" "$seen" 1

# --- an old hero in the bigger world ----------------------------------------------------------------------------
new_hero 0 10
EXPW=""; for (( i = 0; i < 1500; i++ )); do EXPW+=0; done
EXPW="1${EXPW:1}"; EXPW="${EXPW:0:59}1${EXPW:60}"; EXPW="${EXPW:0:60}1${EXPW:61}"   # (0,0) (59,0) (0,1) of the 60x25 chunks
init_explore
eq "explored map grows to 75x25 chunks" "${#EXPW}" 1875
eq "the old east edge stays explored" "${EXPW:59:1}" 1
eq "...and the second row" "${EXPW:75:1}" 1
eq "nothing new is explored" "${EXPW//0/}" 111
REP=(1 2 3 4 5 6 7 8); save_char; REP=(); load_char; eq "an old save gets the ninth faction" "${REP[*]}" "1 2 3 4 5 6 7 8 0"
MOUNTS=11111111; v45_fix; eq "an old stable gets five more stalls" "$MOUNTS" 1111111100000
new_hero 0 50; RAID2K=7 EDGEK=3; save_char; RAID2K=0 EDGEK=0; load_char; eq "the new counters survive save and load" "$RAID2K/$EDGEK" 7/3
new_char 0; eq "...and a new hero starts at zero" "$RAID2K/$EDGEK" 0/0

# --- the Horizon Watch -----------------------------------------------------------------------------------------
eq "nine factions" "$NFAC" 9
wares_build "$Q_YSOLDE"; eq "Ysolde's wares are the Horizon Watch's" "$WR_F" "$FAC80"
[[ " ${WR_CODE[*]} " == *" U.${FAC_UQX[$FAC80]} "* ]] && ok || fail "the Watch sells its own unique: ${WR_CODE[*]}"
wares_build "$Q_HOLLOW"; [[ " ${WR_CODE[*]} " == *" U.$(( FAC_UQ0 + 6 )) "* ]] && ok || fail "the Wildwatch keeps its unique: ${WR_CODE[*]}"

# --- mounts -----------------------------------------------------------------------------------------------------
eq "thirteen mounts" "$NMNT" 13
for (( i = 0; i < NMNT; i++ )); do dispw "${MNT_E[i]}"; (( DW == 2 )) || fail "${MNT_NAME[i]}: ${DW} columns"; done; ok
new_hero 0 42; MOUNTS=""; v45_fix; GOLD=99999; TALK_T=$Q_LANT; for (( t = NPC80; t < NPC80 + 7; t++ )); do [[ ${N_ROLE[$t]} == stable ]] && TALK_T=$t; done
eq "Wren keeps a stable" "${N_ROLE[$TALK_T]}" stable
STABLE_SRC=talk; stable_key 9; check "the 9th key buys the Mist Stalker" mount_has 8
stable_key a; eq "the 10th (a) needs the Watch's favor" "$(mount_has 9 && echo y || echo n)" n
REP[FAC80]=5000; stable_key a; check "...and then it is yours" mount_has 9
STABLE_SRC=keys; stable_key a; eq "[a] picks it to ride" "$MNT_CUR" 9
stable_key d; eq "[d] does not pick what you do not own" "$MNT_CUR" 9
new_hero 0 50; MOUNTS=""; v45_fix; VALOR=5000; valor_buy 9 >/dev/null; check "valor buys the Aurora Unicorn" mount_has 11
MOUNTS=""; v45_fix; for i in $(seq 400); do v80_kill "$W_FROST"; done; check "Frostmaw leaves a mammoth behind" mount_has 10

# --- the Skyward Manor ----------------------------------------------------------------------------------------------
eq "five rooms" "$NROOM" 5
IFS=/ read -ra r <<< "${ROOM_LAY[5]}"; w=${#r[0]}; bad=0; for l in "${r[@]}"; do (( ${#l} == w )) || bad=1; done
eq "the manor is a rectangle" "$bad" 0
ge "...with the most displays" "${ROOM_NDSP[5]}" $(( ROOM_NDSP[4] + 1 ))
new_hero 0 44; GOLD=999999; room_rent 5 >/dev/null; eq "level 44 is too young for a manor" "$ROOM_T" 0
LVL=45; room_rent 5 >/dev/null; eq "level 45 moves in" "$ROOM_T" 5
UI=inn; ROOM_T=4; inn_key 6 >/dev/null; eq "[6] at the inn rents the manor" "$ROOM_T" 5
room_build H1 5; ge "the manor map is built" "${MAPH[H1]}" 10

# --- the second raid -----------------------------------------------------------------------------------------------
send() { SENT+=("$*"); return 0; }; slog() { :; }
NOW=9000000; WH_LAST=$(( NOW / 150 - 1 ))
eq "the Sundered Sky is a raid" "${D_RAID[$RAID2_DT]}" 2
eq "...and the Eclipse Throne still is" "${D_RAID[$RAID_DT]}" 1
SP_NAME[aaaaaa]=alice SP_MAP[aaaaaa]=W SP_DEAD[aaaaaa]=0 SP_LVL[aaaaaa]=50 SP_CLS[aaaaaa]=0
SP_X[aaaaaa]=${D_ENTX[RAID2_DT]} SP_Y[aaaaaa]=${D_ENTY[RAID2_DT]}
SENT=(); DREQ_T=(); srv_dreq aaaaaa "$RAID2_DT" 5; map=${SOLO_INST[aaaaaa]}
eq "no mythic raid" "${IN_MYTH[$map]}" 0
eq "raids scale harder per hero" "${IN_SCALE[$map]}" 100
aur=""; for m in ${IN_MONS[$map]}; do (( MT[m] == RD2_AUR )) && aur=$m; done
check "Aurelion waits" test -n "$aur"
SP_MAP[aaaaaa]=$map SP_X[aaaaaa]=$(( MX[aur] + 1 )) SP_Y[aaaaaa]=${MY[aur]}; PLIST=(); PLIST[$map]=" aaaaaa"
MATKN[aur]=2; SENT=(); AOE_Q=(); mon_attack "$aur" aaaaaa
eq "his third blow is a solar flare under everyone" "${#AOE_Q[@]}" 1
NOW=$(( NOW + 2000 )); SENT=(); aoe_tick
n=0; for s in "${SENT[@]}"; do [[ $s == "MATK srv $map $aur aaaaaa "* ]] && n=1; done; eq "standing in it hurts" "$n" 1
MATKN[aur]=0; SENT=(); AOE_Q=(); mon_attack "$aur" aaaaaa
n=0; for s in "${SENT[@]}"; do [[ $s == "MATK srv $map $aur aaaaaa "* ]] && n=1; done; eq "the first blow is a plain one" "$n" 1
MHP[aur]=$(( MMAX[aur] * 6 / 10 )); srv_hit aaaaaa "$map" "$aur" 100 0
eq "at 2/3 he calls his wardens" "${MPH[aur]}" 1
n=0; for s in "${SENT[@]}"; do [[ $s == "BOSS srv $map ${M_NAME[RD2_AUR]} wraps himself in sunfire"* ]] && n=1; done; eq "...and says so" "$n" 1
h=${MHP[aur]}; srv_hit aaaaaa "$map" "$aur" 1000 0; eq "...and the sunfire shields him" $(( h - MHP[aur] )) 200
MHP[aur]=$(( MMAX[aur] * 4 / 10 )) MATKN[aur]=3; AOE_Q=(); mon_attack "$aur" aaaaaa
eq "below half: the sundering, a cross of eight beams" "${#AOE_Q[@]}" 8
MHP[aur]=$(( MMAX[aur] / 5 )) MATKN[aur]=5; AOE_Q=(); mon_attack "$aur" aaaaaa
a=(${AOE_Q[0]}); eq "below a quarter: the supernova covers 6 tiles" "${a[4]}" 6
SENT=(); MHP[aur]=1; srv_hit aaaaaa "$map" "$aur" 500 0
n=0; for s in "${SENT[@]}"; do [[ $s =~ ^LOOT\ srv\ aaaaaa\ i:([WAOHJ]\.[0-9]+\.15\.3\.______)$ ]] && valid_item "${BASH_REMATCH[1]}" && n=1; done
eq "everyone gets a three-socket Ascendant legendary" "$n" 1
n=0; for s in "${SENT[@]}"; do [[ $s == "ANN srv alice brought down Aurelion, the Sundered Sun!"* ]] && n=1; done; eq "the world hears of it" "$n" 1
n=0; for i in $(seq 60); do SENT=(); raid_finish "$map"; for s in "${SENT[@]}"; do [[ $s =~ i:U\.([0-9]+)$ ]] && { [[ " ${RAID2_UQ[*]} " == *" ${BASH_REMATCH[1]} "* ]] || fail "wrong raid unique ${BASH_REMATCH[1]}"; n=1; }; done; done
eq "...and sometimes one of Aurelion's uniques" "$n" 1
close_instance "$map"
stub_client
new_hero 0 50; RAID2K=0 VALOR=0 ACHS="" TITLE=-1; v45_fix; DAILY="" WEEKLY=""; dly_fix
dly_kill "$RD2_AUR"; eq "client: Aurelion counts" "$RAID2K" 1; ge "...and pays valor" "$VALOR" 120
ach_check >/dev/null; eq "achievement: Sunbreaker" "${ACHS:$(( ACH80 + 2 )):1}" 1
UI=""; CUR_MAP=W PX=${D_ENTX[RAID2_DT]} PY=${D_ENTY[RAID2_DT]}; dungeon_enter; eq "the raid gate asks first" "$UI" dgate
SENT=(); dreq_until=0; DG_K=5 KEYLV=5; dgate_key 2; eq "...and has no mythic" "${#SENT[@]}" 0

# --- dailies and weeklies ---------------------------------------------------------------------------------------------
new_hero 0 35; DAILY="" WEEKLY=""; dly_fix; dly_tasks
for d in "${DLY_CUR[@]}"; do [[ $d == edge* ]] && fail "a level 35 hero gets the edge daily"; done
for d in "${WKY_CUR[@]}"; do [[ $d == raid2* ]] && fail "a level 35 hero gets the Aurelion weekly"; done; ok
new_hero 0 45; EDGEK=0; v80_dclear "$(( D80 + 4 ))"; eq "the World's Edge counts" "$EDGEK" 1

# --- the story, act III -------------------------------------------------------------------------------------------
eq "55 chapters" "$NST" 55
for (( s = ST80; s < NST; s++ )); do
  st_obj "$s"
  case $SO_K in T) [[ -n ${N_FULL[$SO_A]} ]] || fail "chapter $s: nobody to talk to" ;; D) (( SO_A < NDT )) || fail "chapter $s: no dungeon" ;;
    K) [[ " ${WORLD_TYPES[*]} " == *" $SO_A "* ]] || fail "chapter $s: ${M_NAME[SO_A]} is not in the world" ;; esac
  [[ -n ${ST_TEXT[s]} && -n ${ST_DONE[s]} ]] || fail "chapter $s has no text"
done; ok
[[ ${ST_DONE[41]} != *"THE END."* ]] && ok || fail "act II does not end the story any more"
eq "act II's achievement stays at chapter 42" "$(STORY=42; ach_ok 8 && echo y)" y
new_hero 0 40; STORY=$ST80 STORY_P=0; check "act III starts at level 40" story_active

# --- collectables and achievements ----------------------------------------------------------------------------------
for (( i = C80; i < NCOL; i++ )); do
  dispw "${CL_E[i]}"; (( DW == 2 )) || fail "${CL_NAME[i]}: ${DW} columns"
  [[ ${#CL_G[i]} == 1 && ${CL_G[i]} == [[:graph:]] ]] || fail "${CL_NAME[i]}: glyph '${CL_G[i]}'"
done; ok
for r in Shroudmarch "Gilded Expanse" Rimewastes "Aether Reach"; do [[ -n ${COL_CUR[$r]} ]] || fail "no curio for the $r"; done; ok
for b in $B_ABBESS $B_RAMAHET $B_SKADI $B_STARW $B_OBLIV $RD2_AUR; do [[ -n ${COL_BOSS[$b]} ]] || fail "no trophy for ${M_NAME[b]}"; done; ok
new_hero 0 50; ACHS="" TITLE=-1; v45_fix; ach_check >/dev/null; eq "achievement: Ascended" "${ACHS:ACH80:1}" 1
WAYS=""; for (( i = 0; i < ${#WAYSTONES[@]}; i++ )); do WAYS+=1; done; ach_check >/dev/null; eq "achievement: Waywise" "${ACHS:$(( ACH80 + 5 )):1}" 1
ach_ok $(( ACH80 + 7 )) && fail "Ascendant Arms without the arms" || ok
EQW=W.0.15.2 EQA=A.3.15.2 EQO=O.0.15.2 EQH=H.2.15.2 EQJ=J.0.15.2; check "...and with them" ach_ok $(( ACH80 + 7 ))
CLOG=${CLOG:0:C80}; while (( ${#CLOG} < NCOL )); do CLOG+=1; done; check "achievement: Curator of the Edge" ach_ok $(( ACH80 + 9 ))
for (( i = ACH80; i < NACH; i++ )); do [[ ${ACH[i]} =~ ^[^:]+:[^:]+:[^:]*$ ]] || fail "achievement $i: '${ACH[i]}'"; done; ok

t_end
