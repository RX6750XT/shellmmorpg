# ---------------------------------------------------------------------------
#  Module 04m - v8.0 client (loaded last): what the content of Beyond the Edge
#  needs once the sprites and screens exist - icons of the new tiers and
#  materials, the flavor of the new tiers, the hero's new counters (save/load),
#  the drops of Aurelion and Frostmaw, dungeon clears at the edge, and the
#  achievements of 8.0.
# ---------------------------------------------------------------------------
MAT_E[13]=🪐 MAT_E[14]=🔥 MAT_E[15]=🌟                       # Mythforged Primordial Ascendant
TIER_FL[13]="Its metal remembers the shape of the old myths."
TIER_FL[14]="Older than the world. It was here before the edge."
TIER_FL[15]="It shines with the first light of a horizon made whole."
MAT_I[M80]=⚫ MAT_I[M80+1]=🟡 MAT_I[M80+2]=💠 MAT_I[M80+3]=🥀 MAT_I[M80+4]=🌼 MAT_I[M80+5]=🧊 MAT_I[M80+6]=🌸
MAT_I[M80+7]=🐍 MAT_I[M80+8]=🐠 MAT_I[M80+9]=🐟

RAID2K=0 EDGEK=0
V80_VARS=(RAID2K EDGEK)
v80_reset() { RAID2K=0 EDGEK=0; }
v80_load_kv() {  # key value: the lines nobody before knows
  case $1 in
    RAID2K|EDGEK) [[ $2 =~ ^[0-9]{1,9}$ ]] && printf -v "$1" '%d' "$(( 10#$2 ))" ;;
  esac
}
v80_save() { local k; for k in "${V80_VARS[@]}"; do echo "$k=${!k}"; done; }

v80_kill() {  # monster type I helped to kill (from dly_kill)
  if (( $1 == RD2_AUR )); then
    RAID2K=$(( RAID2K + 1 )); dly_ev raid2; valor_add 120 "the Sundered Sky"
    (( RANDOM % 100 < 8 )) && mount_give 12
  fi
  (( $1 == W_FROST && RANDOM % 100 < 8 )) && mount_give 10
  return 0
}
v80_dclear() {  # dungeon type I just cleared
  (( D_REQ[$1] >= 40 )) && dly_ev edge
  (( $1 == D80 + 4 )) && EDGEK=$(( EDGEK + 1 ))
  ach_check
}

ach_ok80() {  # achievements of 8.0 (index ACH80 and up)
  local s e
  case $(( $1 - ACH80 )) in
    0) (( LVL >= 50 )) ;;
    1) (( STORY >= NST )) ;;
    2) (( RAID2K >= 1 )) ;; 3) (( RAID2K >= 10 )) ;;
    4) (( EDGEK >= 1 )) ;;
    5) (( ${#WAYS} >= ${#WAYSTONES[@]} )) && [[ ${WAYS//1/} == "" ]] ;;
    6) (( ROOM_T >= 5 )) ;;
    7) for e in "$EQW" "$EQA" "$EQO" "$EQH" "$EQJ"; do [[ -n $e ]] || return 1; item_stats "$e"; (( IT >= MAXTIER )) || return 1; done ;;
    8) (( ${REP[FAC80]:-0} >= REP_RANK[4] )) ;;
    9) s=${CLOG:C80}; [[ -n $s && ${s//1/} == "" ]] ;;
    *) return 1 ;;
  esac
}
