#!/usr/bin/env bash
# v4.0: the 480x200 world and its seven new lands, levels up to 40 and gear tiers 10-12, the druid
# and the monk, eight factions, twelve allies, ten champion affixes, old saves in the bigger world.
source "$(dirname "$0")/lib.sh"
stub_client

# --- the world ------------------------------------------------------------------------------------------
eq "the world is 480 wide" "${MAPW[W]}" 480
eq "and 200 high" "${MAPH[W]}" 200
for r in Duskwood Sunken_Kingdom Stormreach_Peaks Gloomcap_Hollows Dragonspine Bonefields Starfall_Crater; do
  n=0; for g in "${REGIONS[@]}"; do [[ $g == *" $r "* ]] && n=1; done; eq "region $r exists" "$n" 1
done
for (( i = 0; i < ${#T4_NAME[@]}; i++ )); do
  x=$(( T4_X[i] + 10 )) y=$(( T4_Y[i] + 6 ))
  region_of "$x" "$y"; eq "${T4_NAME[i]} is a safe town" "$RNAME" "${T4_NAME[i]}"
  check "${T4_NAME[i]} is a safe zone" in_safe_xy "$x" "$y"
  fac_at "$x" "$y"; ge "${T4_NAME[i]} belongs to a faction" "$FA" 0
done
region_of 200 190; eq "south of Redrock lies the Duskwood" "$RNAME" "Duskwood"
fac_at 420 180; eq "the crater belongs to the Dawnguard" "$FA" 7
for (( d = 11; d < 18; d++ )); do                 # (the v4.0 dungeons: 6.0 adds some for lower levels)
  tile W "${D_ENTX[d]}" "${D_ENTY[d]}"; eq "${D_NAME[d]} has an entrance" "$T" ">"
  ge "${D_NAME[d]} is for level 30+" "${D_REQ[d]}" 30
done
for (( s = SP4; s < NSPOT; s++ )); do check "scouting spot ${SPT_NAME[s]} is walkable" p_walk W "${SPT_X[s]}" "${SPT_Y[s]}"; done
for c in q M H B; do T=$c; [[ $T == [.,\":=_*%SsNnIAKJDEqMHB] ]] && ok || fail "tile $c is walkable"; done
for c in y U X; do T=$c; [[ $T == [\#T^QOFYPRZCWVyUX] ]] && ok || fail "tile $c blocks arrows"; done
for c in y U X; do T=$c; [[ $T == [.,\":=_*%SsNnIAKJDEqMHB] ]] && fail "tile $c is not walkable" || ok; done

# --- old saves in the bigger world ---------------------------------------------------------------------
new_hero 0 10
EXPW=""; for (( i = 0; i < 855; i++ )); do EXPW+=0; done
EXPW="1${EXPW:1}"; EXPW="${EXPW:0:44}1${EXPW:45}"; EXPW="${EXPW:0:45}1${EXPW:46}"   # (0,0) (44,0) (0,1) of the 45x19 chunks
init_explore
eq "explored map grows to 60x25 chunks" "${#EXPW}" 1500
eq "the north-west corner stays explored" "${EXPW:0:1}" 1
eq "the old east edge stays explored" "${EXPW:44:1}" 1
eq "...and the second row" "${EXPW:60:1}" 1
eq "nothing new is explored" "${EXPW//0/}" 111
REP=(10 20 30 40 50 60); save_char; REP=(); load_char
eq "a 3.0 save loads with eight factions" "${REP[*]}" "10 20 30 40 50 60 0 0"
REP=(-50 0 0 0 0 0 7 007); save_char; REP=(); load_char; eq "negative and padded reputation" "${REP[0]} ${REP[7]}" "-50 7"

# --- levels and tiers ---------------------------------------------------------------------------------------
for p in 1:1 23:8 24:9 29:9 30:10 33:10 34:11 37:11 38:12 40:12 50:12; do tier_for "${p%%:*}"; eq "tier at level ${p%%:*}" "$TF" "${p#*:}"; done
check "tier 12 gear is valid" valid_item W.0.12.3
check "socketed tier 11 gear is valid" valid_item A.3.11.2.r3__
if valid_item W.0.13.0; then fail "tier 13 does not exist"; else ok; fi
new_hero 0 39; XP=0; gain_xp 99999999; eq "the cap is level 40" "$LVL" 40
TAL=533153315331; tal_points; eq "36 talent points fill every tree" "$TFREE" 0
TAL=000000000000; tal_points; eq "39 points at level 40, but only 36 to spend" "$TFREE" 36
bad=0; for (( i = 0; i < 300; i++ )); do
  roll_item "$B_AZOTH" aaaaaa; [[ -z $ITEM || $ITEM == [HM] ]] && continue; valid_item "$ITEM" || { bad=1; fail "loot '$ITEM'"; }
done; eq "the last boss drops valid loot" "$bad" 0
SP_CLS[aaaaaa]=9; t=0; for (( i = 0; i < 200; i++ )); do roll_item "$SF_SERAPH" aaaaaa; [[ $ITEM =~ ^[WAOHJ]\.[0-9]+\.12\. ]] && t=1; done
eq "level 40 creatures drop tier 12" "$t" 1
TALK_T=$(( NPC4 + 1 )); SHOP=smith; shop_build smith; n=0; for c in "${SH_ID[@]}"; do [[ $c =~ ^[WA]\.[0-9]+\.1[0-2]\. ]] && n=1; done
eq "smiths sell tier 10+ at level 40" "$n" 1
for (( u = 26; u < NUQ; u++ )); do check "unique $u (${U_NAME[u]}) is valid" valid_item "U.$u"; done
n=0; for d in "${U_DROP[@]}"; do [[ $d == "$B_AZOTH:"* ]] && n=1; done; eq "Azoth carries a unique" "$n" 1

# --- the druid and the monk ------------------------------------------------------------------------------
for c in 8 9; do
  new_hero "$c" 30
  item_stats "$EQW"; check "${C_NAME[c]} can use the starting weapon" test "${ICLS//[^$c]/}" == "$c"
  gt "${C_NAME[c]} hits for something" "$ATK" 20
  for k in 0 1 2; do
    s=$(( c * 3 + k ))
    CM_T=() CM_X=() CM_Y=() CM_HP=() CM_MAX=() CM_POS=()
    cm_set 950 "$DW_WOLF" $(( PX + 1 )) "$PY" 9999 9999; cm_set 951 "$DW_WOLF" $(( PX + 2 )) "$PY" 9999 9999
    FDX=1 FDY=0 SKCD=(0 0 0) MP=$MAXMP HP=$(( MAXHP / 2 )) SENT=() LOGS=()
    err=$( { cast "$k"; } 2>&1 >/dev/null ); [[ -z $err ]] && ok || fail "${S_NAME[s]}: $err"
    cast "$k" 2>/dev/null                            # (once more, for the effects - the first ran in a subshell)
    hit=0; for x in "${SENT[@]}"; do [[ $x == HIT* ]] && hit=1; done
    case $s in
      26|29) gt "${S_NAME[s]} heals" "$HP" $(( MAXHP / 2 )) ;;
      *)     eq "${S_NAME[s]} hits" "$hit" 1 ;;
    esac
    lt=$(( SKCD[k] > NOW )); eq "${S_NAME[s]} goes on cooldown" "$lt" 1
  done
  TAL=000000000000; for i in 0 0 0 0 0 1 1 1 2 2 3; do tal_learn "$i" >/dev/null; done
  tal_desc 3; [[ -n $TD ]] && ok || fail "${C_NAME[c]} capstone has no text"
  check "${C_NAME[c]} reaches the first capstone" has_cap "${TL_FX[c * 12 + 3]#cap:}"
done
PS_UNTIL[0]=$(( NOW + 9000 )); CLS=9; MP=999 SKCD=(0 0 0); cast 2; eq "Inner Peace cleanses" "${PS_UNTIL[0]}" 0

# --- factions, allies, champions ------------------------------------------------------------------------------
new_hero 0 35; REP=(0 0 0 0 0 0 0 0)
rep_add 7 5000; rep_rank 7; eq "honored with the Dawnguard" "$RR" 2
rep_add 9 500; eq "no ninth faction" "${REP[9]:-none}" none
TALK_T=$Q_DAWN; wares_build "$TALK_T"; eq "Lumen's quartermaster serves the Dawnguard" "$WR_F" 7
eq "...and sells their unique" "${WR_CODE[3]}" "U.$(( FAC_UQ0 + 7 ))"
ALLIES=111111111111 ALLY=-1; aly_key 0; eq "[0] calls the tenth ally" "$ALLY" 9
aly_key -; eq "[-] the eleventh" "$ALLY" 10
aly_key =; eq "[=] the twelfth" "$ALLY" 11
send() { SENT+=("$*"); return 0; }; slog() { :; }
SP_NAME[aaaaaa]=alice SP_MAP[aaaaaa]=W SP_DEAD[aaaaaa]=0 SP_LVL[aaaaaa]=35 SP_CLS[aaaaaa]=8
MMAP[999]=W MT[999]=$DS_KIN MHP[999]=100 MMAX[999]=100
for c in 7:stun 8:weaken; do
  MCH[999]=${c%%:*} SENT=(); for i in $(seq 80); do mon_hit 999 aaaaaa 10; done
  e=0; for x in "${SENT[@]}"; do [[ $x == *" ${c#*:}" ]] && e=1; done; eq "${CHP_NAME[${c%%:*}]} champions ${c#*:}" "$e" 1
done
cli_srv MON W 777 "$DW_WOLF" 1 1 50 50 10; eq "the client knows the tenth affix" "${CM_CH[777]}" 10
cli_srv MON W 778 "$DW_WOLF" 1 1 50 50 11; eq "...but not an eleventh" "${CM_CH[778]}" 0

# --- the new lands are alive ----------------------------------------------------------------------------------
NOW=5000000; WH_LAST=$(( NOW / 150 - 1 )); spawn_world
declare -A seen=()
for m in "${!AL[@]}"; do [[ ${MMAP[m]} == W ]] && seen[${MT[m]}]=1; done
for t in $DW_WOLF $SK_NAGA $ST_HARPY $GC_SPIDER $DS_KIN $BF_COLOS $SF_SERAPH $X_GOOSE $X_VWRAITH; do
  eq "${M_NAME[t]} roams the world" "${seen[$t]:-0}" 1
done
n=0; for t in "${RARE_T[@]}"; do (( ${seen[$t]:-0} )) && n=$(( n + 1 )); done; eq "every rare elite is out there" "$n" "$NRARE"
for m in "${!AL[@]}"; do [[ ${MMAP[m]} == W ]] || continue; m_walk W "${MX[m]}" "${MY[m]}" || fail "${M_NAME[MT[m]]} spawned in a wall at ${MX[m]},${MY[m]}"; done; ok

t_end
