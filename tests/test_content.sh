#!/usr/bin/env bash
# Content tables: every table has an entry per index, references point at real things.
source "$(dirname "$0")/lib.sh"
load_world

alen() { declare -n _a=$1; echo "${#_a[@]}"; }

# --- parallel tables have the same length -----------------------------------------
for v in M_NAME M_HP M_DMG M_ATK M_MOVE M_XP M_GOLD M_LVL M_AGGRO M_GLY M_COL M_KIND M_BOSS; do
  eq "monster table $v" "$(alen $v)" "$NM"
done
for v in D_NAME D_W D_H D_ROOMS D_POOL D_BOSS D_ELITE D_CHESTS D_FLOOR D_WALL D_WE D_REQ D_ENTX D_ENTY D_WHERE; do
  eq "dungeon table $v" "$(alen $v)" "$NDT"
done
for v in U_NAME U_SLOT U_KIND U_TIER U_BT U_FL; do eq "unique table $v" "$(alen $v)" "$NUQ"; done
for v in ALY_NAME ALY_SHORT ALY_G ALY_ROLE ALY_PCT ALY_RNG ALY_CD ALY_COST ALY_SELL ALY_DESC ALY_E; do
  eq "ally table $v" "$(alen $v)" "$NALY"
done
for v in ST_TITLE ST_LVL ST_OBJ ST_XP ST_GOLD ST_REW ST_TEXT ST_DONE; do eq "story table $v" "$(alen $v)" "$NST"; done
for v in C_NAME C_DESC C_HP0 C_HPL C_MP0 C_MPL C_DMG C_ARM CEMO DEFW ALTW DEFA DEFH DEFO; do eq "class table $v" "$(alen $v)" "$NCLS"; done
for v in S_NAME S_MP S_CD S_EL SKILL_E; do eq "skill table $v" "$(alen $v)" $(( NCLS * 3 )); done
for v in TL_NAME TL_FX; do eq "talent table $v" "$(alen $v)" $(( NCLS * 12 )); done
eq "talent trees" "$(alen TL_TREE)" $(( NCLS * 3 ))
for v in FAC_NAME FAC_E FAC_COL; do eq "faction table $v" "$(alen $v)" "$NFAC"; done
for v in CHP_NAME CHP_DESC CHP_COL CHP_E; do eq "champion table $v" "$(alen $v)" "$NCHP"; done
for v in D_NAME D_REQ D_POOL D_BOSS D_ELITE D_ENTX D_ENTY D_WHERE D_WALL D_FLOOR D_WE D_W D_H D_ROOMS D_CHESTS; do
  eq "dungeon table $v" "$(alen $v)" "$NDT"
done
for (( t = 0; t < NM; t++ )); do (( M_KIND[t] == 0 )) && [[ -z ${MEMO[t]} ]] && fail "creature $t (${M_NAME[t]}) has no HD sprite"; done
for (( c = 0; c < NCLS; c++ )); do                 # every class starts with gear it can wear
  for s in W:DEFW A:DEFA H:DEFH O:DEFO; do
    k=${s%%:*} v=${s#*:}; eval "d=\${$v[c]}"; slot_kinds "$k"
    [[ ${KCLS[d]} == *$c* ]] || fail "class $c (${C_NAME[c]}) cannot use its $v (${KCLS[d]})"
  done
done
for v in MAT_NAME MAT_I MAT_VAL MAT_RARE; do eq "material table $v" "$(alen $v)" "$NMAT"; done
for v in BAG_NAME BAG_SZ BAG_PRICE BAG_E BAG_RR BAG_FL BAG_M; do eq "bag table $v" "$(alen $v)" 6; done
for v in WB_LIST WB_RECT WB_ADDS; do eq "world boss table $v" "$(alen $v)" "${#WB_LIST[@]}"; done
eq "tier names" "$(alen TIER_Q)" $(( MAXTIER + 1 ))
eq "tier textures" "$(alen MAT_E)" $(( MAXTIER + 1 ))
eq "tier flavour" "$(alen TIER_FL)" $(( MAXTIER + 1 ))

# --- monsters ------------------------------------------------------------------------
for (( t = 0; t < NM; t++ )); do
  [[ -n ${M_NAME[t]} ]] || fail "monster $t has no name"
  isnum "${M_HP[t]}" && (( M_HP[t] > 0 )) || fail "monster $t (${M_NAME[t]}) HP '${M_HP[t]}'"
  [[ ${M_KIND[t]} == [0-4] ]] || fail "monster $t kind '${M_KIND[t]}'"
  [[ ${M_BOSS[t]} == [0-2] ]] || fail "monster $t boss flag '${M_BOSS[t]}'"
  if (( M_KIND[t] == 1 || M_KIND[t] == 2 )) && (( t >= 19 )) && [[ -z ${N_FULL[$t]} && -z ${N_ROLE[$t]} ]]; then
    [[ ${M_NAME[t]} == *Guard* || ${M_NAME[t]} == *Villager* ]] || fail "NPC $t (${M_NAME[t]}) has no role"
  fi
done
ok

# --- dungeons --------------------------------------------------------------------------
for (( d = 0; d < NDT; d++ )); do
  b=${D_BOSS[d]} e=${D_ELITE[d]}
  (( b < NM && M_BOSS[b] == 1 )) || fail "dungeon $d (${D_NAME[d]}) boss $b is not a boss"
  (( e < NM && M_BOSS[e] == 2 )) || fail "dungeon $d (${D_NAME[d]}) elite $e is not an elite"
  for m in ${D_POOL[d]}; do (( m < NM && M_KIND[m] == 0 )) || fail "dungeon $d pool has non-hostile $m"; done
  tile W "${D_ENTX[d]}" "${D_ENTY[d]}"
  [[ $T == '>' ]] || fail "dungeon $d entrance at ${D_ENTX[d]},${D_ENTY[d]} is '$T', not '>'"
done
ok

# --- uniques and their drop table --------------------------------------------------------
for (( u = 0; u < NUQ; u++ )); do
  [[ ${U_SLOT[u]} == [WAOHJ] ]] || fail "unique $u slot '${U_SLOT[u]}'"
  [[ ${U_TIER[u]} =~ ^([1-9]|1[0-2])$ ]] || fail "unique $u tier '${U_TIER[u]}'"
  check "unique U.$u is a valid item" valid_item "U.$u"
done
for d in "${U_DROP[@]}"; do
  [[ $d =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]] || { fail "U_DROP entry '$d'"; continue; }
  (( BASH_REMATCH[1] < NM && BASH_REMATCH[2] < NUQ )) || fail "U_DROP '$d' points nowhere"
done

# --- story ---------------------------------------------------------------------------------
for (( s = 0; s < NST; s++ )); do
  o=${ST_OBJ[s]}
  [[ $o =~ ^([KDTL])\.([0-9]+)(\.([0-9]+))?$ ]] || { fail "story $s objective '$o'"; continue; }
  case ${BASH_REMATCH[1]} in
    K) (( BASH_REMATCH[2] < NM )) || fail "story $s kills unknown monster" ;;
    D) (( BASH_REMATCH[2] < NDT )) || fail "story $s clears unknown dungeon" ;;
    T) [[ -n ${N_FULL[${BASH_REMATCH[2]}]} ]] || fail "story $s talks to unknown NPC ${BASH_REMATCH[2]}" ;;
  esac
  (( s == 0 )) || le "story $s level order" "${ST_LVL[s-1]}" "${ST_LVL[s]}"
done

# --- NPCs, spawns, safe zones, waystones --------------------------------------------------
for n in "${NPC_SPAWNS[@]}"; do
  a=($n)
  (( a[0] < NM )) || fail "NPC spawn of unknown type ${a[0]}"
  p_walk W "${a[1]}" "${a[2]}" || fail "NPC ${M_NAME[a[0]]} stands on '$T' at ${a[1]},${a[2]}"
done
for w in "${WAYSTONES[@]}"; do
  a=($w)
  tile W "${a[1]}" "${a[2]}"; eq "waystone ${a[0]} tile" "$T" Z
done
for z in "${ZONES[@]}"; do
  a=($z)
  (( a[0] < NM )) || fail "zone spawns unknown monster ${a[0]}"
  (( a[1] <= a[3] && a[2] <= a[4] && a[3] < MAPW[W] && a[4] < MAPH[W] )) || fail "zone rect '$z'"
done
for q in "${!N_QK[@]}"; do
  for m in ${N_QK[$q]}; do (( m < NM )) || fail "quest giver $q offers unknown monster $m"; done
done
for q in "${!N_QT[@]}"; do [[ -n ${N_FULL[${N_QT[$q]}]} ]] || fail "courier target ${N_QT[$q]} of $q unknown"; done
ok

# --- the world map ---------------------------------------------------------------------
eq "world width" "${MAPW[W]}" 480
eq "world height" "${MAPH[W]}" 200
bad=0
for (( y = 0; y < MAPH[W]; y++ )); do
  (( ${#MAPROW[W:$y]} == MAPW[W] )) || { bad=1; fail "world row $y is ${#MAPROW[W:$y]} wide"; }
done
(( bad )) || ok
bad=$(world_data | LC_ALL=C grep -c '[^ .,"*T~^#_:=%><SsNnIAQOFYPRZbcfghijlortuvwxzKCJWDVEGLadekpqyMUHXB]')
eq "world tiles are all known" "$bad" 0
check "spawn point is walkable" p_walk W "$SPAWN_X" "$SPAWN_Y"
if command -v python3 >/dev/null; then       # every dungeon entrance and waystone can be reached on foot
  check "world map reachability (tools/worldgen/check_world.py)" eval 'python3 "$T_ROOT/tools/worldgen/check_world.py" "$T_ROOT/world.txt" >/dev/null'
fi

t_end
