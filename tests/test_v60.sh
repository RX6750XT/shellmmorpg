#!/usr/bin/env bash
# v6.0: more of everything - the new creatures, rares, dungeons, world bosses, townsfolk, questlines,
# uniques, weapon kinds, materials and recipes, the hunter's trophies, the achievements of 6.0.
source "$(dirname "$0")/lib.sh"
stub_client

# --- creatures: every one has a home, an element, a sprite -----------------------------------------------------
n=0; for e in "${X60_EL[@]}"; do n=$(( n + 1 )); done; ge "52 new creatures with elements" "$n" 52
bad=0; for (( t = 0; t < NM; t++ )); do
  (( M_KIND[t] == 0 )) || continue
  [[ -n ${M_EL[t]} && -n ${M_WK[t]} && -n ${M_RS[t]} ]] || { bad=1; echo "  ${M_NAME[t]} has no element"; }
  dispw "${MEMO[t]}"; (( DW == 2 )) || { bad=1; echo "  ${M_NAME[t]}: sprite is $DW columns"; }
done; eq "every hostile creature has an element and a 2-column sprite" "$bad" 0
eq "the Lake Snapper is frost" "${M_EL[L_SNAP]}/${M_WK[L_SNAP]}" "2/1"
eq "...the Marsh Hag casts from afar" "${M_RNG[M_HAG]}" 5
eq "...the Cinder Fiend burns" "${M_AB[A_FIEND]}" burn
eq "...the Thornhog bleeds you (no '-' leaks into the ability)" "${M_AB[G_HOG]}" bleed
eq "...the Meadow Beetle has no ability" "${M_AB[G_BEETLE]}" ""
eq "a new rare is made of what its kind is made of" "${M_EL[$(( R60 + 7 ))]}" "${M_EL[D_DJINN]}"
eq "the old rares keep theirs (Grimfang bleeds)" "${M_AB[${RARE_T[0]}]}" bleed
load_world
for z in "${ZONES[@]}"; do
  a=($z); (( a[0] >= G_HOG )) || continue
  c=0; for (( y = a[2]; y <= a[4] && c == 0; y++ )); do for (( x = a[1]; x <= a[3]; x++ )); do m_walk W $x $y && { c=1; break; }; done; done
  (( c )) || fail "zone of ${M_NAME[a[0]]} has no walkable tile"
done; ok
for t in $G_HOG $Z_BEHEM $D_DJINN; do [[ " ${WORLD_TYPES[*]} " == *" $t "* ]] || fail "${M_NAME[t]} is not in the world"; done; ok
new_hero 0 24; QSRC=board; seen=0; for i in $(seq 40); do gen_offers; [[ " ${OFFERS[*]} " == *K.$J_PANTH.* || " ${OFFERS[*]} " == *K.$C_BEETLE.* || " ${OFFERS[*]} " == *K.$J_TOAD.* ]] && seen=1; done
eq "the quest board offers the new creatures" "$seen" 1
ge "46 rare elites" "$NRARE" 46

# --- the four dungeons ----------------------------------------------------------------------------------------------
ge "23 dungeons (more since 8.0)" "$NDT" 23
for (( d = D60; d < NDT; d++ )); do
  tile W "${D_ENTX[d]}" "${D_ENTY[d]}"; eq "${D_NAME[d]} has an entrance" "$T" ">"
  [[ -n ${N_FULL[${D_BOSS[d]}]:-} ]] && fail "a boss is no townsperson"
  [[ -n ${COL_BOSS[${D_BOSS[d]}]} ]] || fail "${D_NAME[d]}: no trophy for its boss"
done
eq "the levels fill the gaps" "${D_REQ[*]:D60:4}" "2 8 16 26"
new_hero 0 2; PX=${D_ENTX[D60]} PY=$(( D_ENTY[D60] + 1 )); SENT=(); dreq_until=0; next_move=0; try_move 0 -1
[[ " ${SENT[*]} " == *"DREQ $MY_ID $D60"* ]] && ok || fail "a level 2 hero may enter the Old Mill: ${SENT[*]}"

# --- world bosses -----------------------------------------------------------------------------------------------------
ge "20 world bosses" "${#WB_LIST[@]}" 20
eq "...each with a place" "${#WB_RECT[@]}" "${#WB_LIST[@]}"; eq "...and helpers" "${#WB_ADDS[@]}" "${#WB_LIST[@]}"
send() { SENT+=("$*"); return 0; }; slog() { :; }
SP_NAME=() SP_LVL=(); SP_NAME[aaaaaa]=al SP_LVL[aaaaaa]=4 SP_MAP[aaaaaa]=W SP_X[aaaaaa]=80 SP_Y[aaaaaa]=35
picks=" "; for i in $(seq 30); do WB_MID=""; wb_spawn; picks+="${MT[WB_MID]} "; [[ -n $WB_MID ]] && close_wb_t=$WB_MID; done
[[ $picks == *" $W_GRUMB "* ]] && ok || fail "a level 4 hero meets Old Grumblegut: $picks"
for t in $picks; do (( M_LVL[t] <= 8 )) || { fail "${M_NAME[t]} (level ${M_LVL[t]}) is far too strong for level 4"; break; }; done; ok

# --- townsfolk and questlines --------------------------------------------------------------------------------------------
ge "27 questlines" "$NQL" 27
for (( q = 19; q < NQL; q++ )); do
  t=${QL_NPC[q]}
  [[ ${N_ROLE[$t]} == questgiver ]] || fail "${QL_NAME[q]}: giver is no questgiver"
  ql_for_npc "$t" && (( QLN == q )) || fail "${N_FULL[$t]} offers ${QL_NAME[q]}"
  [[ -n ${N_QK[$t]} ]] || fail "${N_FULL[$t]} has no kill quests"
  for (( s = QL_S0[q]; s < QL_S0[q] + QL_N[q]; s++ )); do
    qobj_parse "${QS_OBJ[s]}"
    case $OT in
      E) (( OA < NSPOT )) || fail "${QL_NAME[q]}: scouting spot $OA"
         ok2=0; for (( dy = -3; dy <= 3; dy++ )); do for (( dx = -3; dx <= 3; dx++ )); do p_walk W $(( SPT_X[OA] + dx )) $(( SPT_Y[OA] + dy )) && ok2=1; done; done
         (( ok2 )) || fail "${SPT_NAME[OA]} can't be reached" ;;
      B) (( M_BOSS[OA] == 2 )) || fail "${QL_NAME[q]}: bounty on a non-rare" ;;
      D) (( OA < NDT )) || fail "${QL_NAME[q]}: dungeon $OA" ;;
      T) [[ -n ${N_FULL[$OA]} ]] || fail "${QL_NAME[q]}: nobody to talk to" ;;
    esac
  done
  r=${QS_CHR[$(( QL_S0[q] + QL_N[q] - 1 ))]}; [[ $r == uq:* ]] || fail "${QL_NAME[q]} ends without a unique to choose"
done; ok
for p in "${NPC_SPAWNS[@]}"; do a=($p); (( a[0] >= NPC60 && a[0] < NPC60 + 8 )) || continue; p_walk W "${a[1]}" "${a[2]}" || fail "${N_FULL[${a[0]}]} stands in a wall"; done; ok
new_hero 0 30; cm_set 990 $Q_PELL 298 17 900 900; talk_open 990; QSRC=$Q_PELL; gen_offers
[[ " ${OFFERS[*]} " == *K.$C_BEETLE.* || " ${OFFERS[*]} " == *K.$C_PRISM.* ]] && ok || fail "Gemcutter Pell has work: ${OFFERS[*]}"

# --- uniques and weapon kinds ---------------------------------------------------------------------------------------------
ge "66 uniques" "$NUQ" 66
for (( u = U60; u < NUQ; u++ )); do valid_item "U.$u" || fail "U.$u"; item_name "U.$u" 0; [[ $INAME == "${U_NAME[u]}" ]] || fail "unique $u name"; done; ok
for u in "${U_DROP[@]}"; do a=(${u//:/ }); (( a[1] >= U60 )) && (( M_BOSS[a[0]] == 1 )) || continue; n=$(( n + 1 )); done
item_stats U.$(( U60 + 7 )); eq "the Cinderdeep Lantern lights the way" "$IBT" light; gt "...a little" "$IBV" 0
check "a hand cannon is valid gear" valid_item W.30.5.2
check "...a runestone too" valid_item W.31.12.3.__
can_use W.30.5.2 4 && ok || fail "rogues use hand cannons"; can_use W.30.5.2 0 && fail "warriors don't" || ok
can_use W.31.5.2 8 && ok || fail "druids use runestones"

# --- materials, nodes, recipes ---------------------------------------------------------------------------------------------
ge "60 materials" "$NMAT" 60
for a in MAT_NAME MAT_VAL MAT_RARE MAT_PK MAT_I; do declare -n tb=$a; eq "$a has an entry per material" "${#tb[@]}" "$NMAT"; unset -n tb; done
for k in $M60 $(( M60 + 1 )); do mat_prof "$k"; eq "${MAT_NAME[k]} is mined" "$MP_K" 1; done
for k in $(( M60 + 2 )) $(( M60 + 3 )); do mat_prof "$k"; eq "${MAT_NAME[k]} is picked" "$MP_K" 2; done
for k in $(( M60 + 4 )) $(( M60 + 5 )); do mat_prof "$k"; eq "${MAT_NAME[k]} is fished" "$MP_K" 0; done
new_hero 0 30; PROF_LV=(30 30 30); CM_T=(); cm_set 960 $N60 $(( PX + 1 )) "$PY" 3 3
GATH_MID=""; gather_start 960; GATH_END=0; MATS[M60]=0; gather_tick; gt "a cobalt vein gives cobalt" "${MATS[M60]}" 0
CRAFT=forge; craft_build; t8=-1; for i in "${!RC_ID[@]}"; do [[ ${RC_ID[i]} == W.*.8 && " ${RC_NEED[i]} " == *" $M60:"* ]] && t8=$i; done
ge "the forge makes tier 8 from cobalt" "$t8" 0
MATS[M60]=10 MATS[5]=5 GOLD=99999 INV=() BAGS=30; craft_do "$t8" >/dev/null; check "...a valid weapon" valid_item "${INV[0]}"
CRAFT=alch; craft_build; g=-1; for i in "${!RC_ID[@]}"; do [[ ${RC_ID[i]} == gh3 && " ${RC_NEED[i]} " == *" $(( M60 + 2 )):"* ]] && g=$i; done
MATS[M60+2]=5 MATS[6]=5 POT_GH=0; craft_do "$g" >/dev/null; eq "sungrass brews greater health potions" "$POT_GH" 3
bad=0; for (( k = 0; k < NMAT; k++ )); do
  mat_uses "$k"; (( ${#MU[@]} )) || { bad=1; echo "  ${MAT_NAME[k]}: no use"; }
  mat_prof "$k"; (( MP_K == 1 || MP_K == 2 )) && [[ ${MU[*]} == *Cooking* ]] && { bad=1; echo "  ${MAT_NAME[k]} is no fish: ${MU[*]}"; }
done; eq "every material says what it is for (ore is not cooked any more)" "$bad" 0
mat_uses $M45; [[ ${MU[*]} == *Forge* ]] && ok || fail "titanite is for the forge: ${MU[*]}"
n=0; for e in ${FISHW[sea]}; do [[ ${e%%:*} == $(( M60 + 4 )) ]] && n=1; done; eq "the Reef Snapper bites in the sea" "$n" 1

# --- collectables of 6.0 ------------------------------------------------------------------------------------------------------
col_count; eq "a hunter's trophy for every rare elite" "${CLST[6]}" "$NRARE"
eq "...trophies for the new dungeon bosses too" "${CLST[0]}" "$NDT"
eq "...and for every world boss" "${CLST[1]}" "${#WB_LIST[@]}"
i=${COL_BOSS[${RARE_T[0]}]}; eq "Grimfang's trophy" "${CL_NAME[i]}" "Grimfang's Trophy"
[[ ${CL_E[i]} == "${MEMO[${RARE_T[0]}]}" ]] && ok || fail "the trophy looks like its owner"
eq "...Captain Saltbones' trophy" "${CL_NAME[${COL_BOSS[$(( R4 + 2 ))]}]}" "Captain Saltbones' Trophy"
new_hero 0 30; INV=() CLOG=""; v50_fix; for i in $(seq 40); do col_kill "${RARE_T[5]}" 0; done
check "a rare leaves its trophy" col_has "${COL_BOSS[${RARE_T[5]}]}"
valid_item "C.$(( NCOL - 1 ))" && ok || fail "the last collectable is valid"
INV=("C.$(( NCOL - 1 ))"); save_char; INV=(); load_char; eq "three-digit collectables survive save and load" "${INV[*]}" "C.$(( NCOL - 1 ))"

# --- achievements of 6.0 ----------------------------------------------------------------------------------------------------------
ge "50 achievements" "$NACH" 50
new_hero 0 30; RAREK=50; ach_check; eq "Big Game Hunter" "${ACHS:ACH60:1}" 1
CLOG=$(printf '1%.0s' $(seq 100)); ach_check; eq "Hoarder" "${ACHS:$(( ACH60 + 2 )):1}" 1
DCLR=250; ach_check; eq "Dungeon Lord" "${ACHS:$(( ACH60 + 4 )):1}" 1
QLS=$(printf 'x%.0s' $(seq 25))00; ach_check; eq "Pathfinder" "${ACHS:$(( ACH60 + 3 )):1}" 1
ach_title $(( ACH60 + 1 )); eq "...the Huntmaster" "$ATT" "the Huntmaster"

t_end
