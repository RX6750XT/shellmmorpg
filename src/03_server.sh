# ---------------------------------------------------------------------------
#  Module 03 - world server: authoritative for monsters, NPCs, loot, parties,
#  party quests, the wanted list, weather, the clock and dungeon instances.
#  Clients own their character. Monsters think in a timer wheel (ai_tick).
# ---------------------------------------------------------------------------
declare -A SP_NAME=() SP_MAP=() SP_X=() SP_Y=() SP_LVL=() SP_DEAD=() SP_SEEN=() SP_PARTY=() SP_WANTED=() SP_CLS=()
declare -A OCC=() AL=() RS=() PT_LEADER=() PT_MEMBERS=() PT_INST=() PT_QUESTS=() INV_FROM=() PLIST=()
declare -A IN_TYPE=() IN_SEED=() IN_PARTY=() IN_EMPTY=() IN_SCALE=() IN_DONE=() IN_MONS=() SOLO_INST=() DREQ_T=() SYNC_T=() SYNC_PEND=()
MX=() MY=() MT=() MHP=() MMAX=() MMAP=() MALIVE=() MHX=() MHY=() MNEXT=() MFRZ=() MAGG=()
MRESP=() MZONE=() MATKN=() MSCALE=() MWR=() MCON=() MPH=()
NMON=0 NPARTY=0 NINST=0 WB_MID=-1 WB_NEXT=0 WB_GONE=0 WB_PING=0 WBS_AT=0 WBS_M=-1 WBS_X=0 WBS_Y=0 WBS_D=0
SRV_CLK0=0 NIGHT=0 WS_T=() WS_E=() WS_N=()
declare -A GATH_T=()

slog() { printf '[%(%H:%M:%S)T] %s\n' -1 "$*"; }

mon_state() { send MON srv "${MMAP[$1]}" "$1" "${MT[$1]}" "${MX[$1]}" "${MY[$1]}" "${MHP[$1]}" "${MMAX[$1]}" $(( ${MCH[$1]:--1} + 1 )); }

champ_roll() {  # mid: now and then a monster is a champion (MCH = affix, -1 = none): more HP, XP, loot
  local m=$1 t=${MT[$1]} p=4
  MCH[m]=-1 MMAX[m]=$(( M_HP[t] * MSCALE[m] / 100 ))
  (( M_KIND[t] == 0 && M_BOSS[t] == 0 && MZONE[m] != -2 && MZONE[m] != -4 )) || return
  [[ ${MMAP[m]} == D* ]] && p=8
  (( RANDOM % 100 < p )) || return
  MCH[m]=$(( RANDOM % NCHP ))
  MMAX[m]=$(( MMAX[m] * (MCH[m] == 6 ? 3 : 2) ))
}

in_safe() { [[ $1 == W ]] && in_safe_xy "$2" "$3"; }

spawn_mon() {  # map type x y zone scale [wander] -> MID
  local m=$NMON
  NMON=$(( NMON + 1 ))
  MMAP[m]=$1 MT[m]=$2 MX[m]=$3 MY[m]=$4 MHX[m]=$3 MHY[m]=$4 MZONE[m]=$5 MSCALE[m]=$6 MWR[m]=${7:-3}
  MMAX[m]=$(( M_HP[$2] * $6 / 100 )); champ_roll "$m"; MHP[m]=${MMAX[m]}
  MALIVE[m]=1 MNEXT[m]=0 MFRZ[m]=0 MAGG[m]="" MATKN[m]=0 MRESP[m]=0 MCON[m]="" MPH[m]=0 MHEALT[m]=0
  if (( M_KIND[$2] >= 3 )); then MNEXT[m]=4000000000000   # resource nodes and chests never think
  else wake "$m"; fi
  OCC["$1:$3:$4"]=$m; AL[$m]=1
  [[ $1 == W ]] || IN_MONS[$1]+=" $m"                      # instance monsters are freed with their dungeon
  MID=$m
}

free_tile() {  # x1 y1 x2 y2 map [ore|herb] -> SX SY   (nodes: open ground, ore right next to a mountain)
  local i x y n=40 r a b
  [[ -n $6 ]] && n=300
  for (( i = 0; i < n; i++ )); do
    x=$(( $1 + RANDOM % ($3 - $1 + 1) )) y=$(( $2 + RANDOM % ($4 - $2 + 1) ))
    m_walk "$5" "$x" "$y" || continue
    in_safe "$5" "$x" "$y" && continue
    [[ -n ${OCC[$5:$x:$y]} ]] && continue
    if [[ -n $6 ]]; then                                 # never block roads, bridges or narrow passes
      [[ $T == [.,\"*%SsNnAKJDEqMHB] ]] || continue
      a=${MAPROW[$5:$(( y - 1 ))]:x-1:3}${MAPROW[$5:$y]:x-1:1}${MAPROW[$5:$y]:x+1:1}${MAPROW[$5:$(( y + 1 ))]:x-1:3}
      b=${a//[^.,\":=_*%SsNnIAKJDEqMHB]/}; (( ${#b} >= 5 )) || continue
      if [[ $6 == ore ]]; then
        r=${MAPROW[$5:$(( y - 1 ))]:x:1}${MAPROW[$5:$(( y + 1 ))]:x:1}${MAPROW[$5:$y]:x-1:1}${MAPROW[$5:$y]:x+1:1}
        [[ $r == *[\^RCV]* ]] || continue
      fi
    fi
    SX=$x SY=$y; return 0
  done
  return 1
}

zone_tile() {  # zone index -> SX SY
  local z=(${ZONES[$1]}) o=""
  if (( z[0] >= NODE0 && z[0] < NODE0 + 6 )); then o=ore; elif (( z[0] >= NODE0 && z[0] < NODE0 + 12 )); then o=herb; fi
  free_tile "${z[1]}" "${z[2]}" "${z[3]}" "${z[4]}" W "$o"
}

spawn_world() {
  local zi z c n
  for zi in "${!ZONES[@]}"; do
    z=(${ZONES[zi]})
    for (( c = 0; c < z[5]; c++ )); do
      zone_tile "$zi" && spawn_mon W "${z[0]}" "$SX" "$SY" "$zi" 100
    done
  done
  for n in "${NPC_SPAWNS[@]}"; do
    z=($n); spawn_mon W "${z[0]}" "${z[1]}" "${z[2]}" -3 100 "${z[3]}"
  done
  slog "spawned $NMON monsters and NPCs in the open world"
}

srv_sync() {  # map: resend every living monster of a map
  [[ $1 =~ ^(W|D[0-9]+)$ ]] || return
  local m
  for m in "${!AL[@]}"; do [[ ${MMAP[m]} == "$1" ]] && mon_state "$m"; done
}

sync_flush() {  # a full resync is ~500 lines to everyone: at most one per map per second
  local map
  for map in "${!SYNC_PEND[@]}"; do
    (( NOW - ${SYNC_T[$map]:-0} >= 1000 )) || continue
    unset "SYNC_PEND[$map]"; SYNC_T[$map]=$NOW
    srv_sync "$map"
  done
}

party_send() {
  local p=$1
  send PARTY srv "$p" "${PT_LEADER[$p]}" "${PT_MEMBERS[$p]// /,}"
  send PQUEST srv "$p" "${PT_QUESTS[$p]// /,}"
}

set_wanted() {  # id ms (0 clears) - only ever extends a running sentence
  local until=$(( NOW + $2 ))
  if (( $2 > 0 )); then
    [[ -z ${SP_WANTED[$1]} ]] && slog "${SP_NAME[$1]} is now wanted"
    (( until > ${SP_WANTED[$1]:-0} + 3000 )) || return
    SP_WANTED[$1]=$until
    send WANTED srv "$1" $(( $2 / 1000 ))
  elif [[ -n ${SP_WANTED[$1]} ]]; then
    unset "SP_WANTED[$1]"; send WANTED srv "$1" 0
  fi
}

srv_hello() {  # id name
  local p
  SP_NAME[$1]=${2//[^A-Za-z0-9_-]/} SP_SEEN[$1]=$NOW
  SP_MAP[$1]=${SP_MAP[$1]:-W} SP_X[$1]=${SP_X[$1]:-$SPAWN_X} SP_Y[$1]=${SP_Y[$1]:-$SPAWN_Y}
  SP_LVL[$1]=${SP_LVL[$1]:-1} SP_DEAD[$1]=0
  slog "+ ${SP_NAME[$1]} ($1) joined"
  SYNC_PEND[W]=1; sync_flush
  for p in "${!PT_LEADER[@]}"; do party_send "$p"; done
  for p in "${!SP_WANTED[@]}"; do send WANTED srv "$p" $(( (SP_WANTED[$p] - NOW) / 1000 )); done
  send CLOCK srv $(( (NOW - SRV_CLK0) % DAYLEN ))
  for p in "${!WS_T[@]}"; do [[ -n ${WS_T[p]} ]] && send WEATHER srv "$p" "${WS_T[p]}" $(( (WS_E[p] - NOW) / 1000 )); done
  if (( WB_MID >= 0 && MALIVE[WB_MID] )); then
    region_of "${MX[WB_MID]}" "${MY[WB_MID]}" nosafe
    send WBOSS srv "$WB_MID" "${MT[WB_MID]}" "${MX[WB_MID]}" "${MY[WB_MID]}"
    send INFO srv "$1" "World boss: ${M_NAME[${MT[WB_MID]}]} is roaming the $RNAME! Check your map [m]."
  fi
}

srv_drop() {
  acc_forget "$1"
  [[ -n ${SP_NAME[$1]} ]] || return
  slog "- ${SP_NAME[$1]} ($1) left"
  srv_pleave "$1"
  unset "SP_NAME[$1]" "SP_MAP[$1]" "SP_X[$1]" "SP_Y[$1]" "SP_LVL[$1]" "SP_DEAD[$1]" "SP_SEEN[$1]" "INV_FROM[$1]" "SP_WANTED[$1]" "GATH_T[$1]" "SP_CLS[$1]" "SOLO_INST[$1]" "DREQ_T[$1]"
}

roll_item() {  # type [player] [level] [champion] -> ITEM  (gear leans towards what the player's class can use)
  local t=$1 tier r rr k s u a
  ITEM=""
  tier_for "${3:-${M_LVL[t]}}"; tier=$TF
  r=$(( RANDOM % 100 ))
  if (( M_BOSS[t] == 1 )); then                         # bosses sometimes carry their unique
    for u in "${U_DROP[@]}"; do
      a=(${u//:/ })
      (( a[0] == t && RANDOM % 100 < a[2] )) && { ITEM="U.${a[1]}"; return; }
    done
  fi
  if (( M_KIND[t] == 4 )); then                          # treasure chests: always gear, often rare
    rr=$(( RANDOM % 100 )); if (( rr < 50 )); then rr=1; elif (( rr < 88 )); then rr=2; else rr=3; fi
  elif (( M_BOSS[t] )); then
    (( tier < MAXTIER )) && tier=$(( tier + 1 ))
    rr=$(( RANDOM % 100 )); if (( rr < 45 )); then rr=1; elif (( rr < 85 )); then rr=2; else rr=3; fi
  elif (( r < 12 + (M_KIND[t] ? 25 : 0) || ${4:-0} )); then
    rr=$(( RANDOM % 100 )); if (( rr < 70 )); then rr=0; elif (( rr < 93 )); then rr=1; elif (( rr < 99 )); then rr=2; else rr=3; fi
    (( ${4:-0} && rr < 3 )) && rr=$(( rr + 1 ))
  elif (( r < 24 )); then
    if (( RANDOM % 2 )); then ITEM=H; else ITEM=M; fi; return
  else
    return
  fi
  local wbt=0; [[ " ${WB_LIST[*]} " == *" $t "* ]] && wbt=1
  if (( RANDOM % 100 < (M_BOSS[t] ? (wbt ? 25 : 12) : 4) )); then   # v1.8: bags
    k=$(( RANDOM % 100 ))
    if (( M_BOSS[t] && wbt )); then if (( k < 50 )); then k=3; elif (( k < 85 )); then k=4; else k=5; fi
    elif (( M_BOSS[t] )); then if (( k < 55 )); then k=2; elif (( k < 90 )); then k=3; else k=4; fi
    elif (( k < 70 )); then k=0; else k=1; fi
    ITEM="B.$k"; return
  fi
  k=$(( RANDOM % 100 ))
  if (( k < 34 )); then s=W; elif (( k < 56 )); then s=A; elif (( k < 72 )); then s=H; elif (( k < 86 )); then s=O; else s=J; fi
  kind_pick "$s" "${SP_CLS[${2:-_}]}"
  ITEM="$s.$KP.$tier.$rr"
  k=$(( RANDOM % 100 ))                                  # v3.0: sockets for gems
  case $rr in
    0) (( k < 10 )) && ITEM+=".__" ;;
    1) (( k < 25 )) && ITEM+=".__" ;;
    2) if (( k < 15 )); then ITEM+=".____"; elif (( k < 45 )); then ITEM+=".__"; fi ;;
    3) if (( k < 20 )); then ITEM+=".______"; elif (( k < 60 )); then ITEM+=".____"; else ITEM+=".__"; fi ;;
  esac
}

gem_drop() {  # type player champion [level]: bosses, rares, champions and chests sometimes drop a gem
  local t=$1 l=${4:-${M_LVL[$1]}} c=0 g
  if (( M_KIND[t] == 4 )); then c=45; elif (( M_BOSS[t] == 1 )); then c=60; elif (( M_BOSS[t] == 2 )); then c=70
  elif (( $3 )); then c=35; else c=1; fi
  (( RANDOM % 100 < c )) || return
  g=1; (( l >= 12 )) && g=2; (( l >= 22 )) && g=3
  (( g > 1 && RANDOM % 3 == 0 )) && g=$(( g - 1 ))
  (( l >= 38 && RANDOM % 100 < (M_BOSS[t] == 1 ? 12 : 3) )) && g=4          # v4.5: perfect gems
  gem_mat $(( RANDOM % 6 )) "$g"
  send LOOT srv "$2" "g$GM"
}

boss_summon() {  # mid: a dungeon boss calls its minions
  local m=$1 t=${MT[$1]} map=${MMAP[$1]} i pool
  pool=(${D_POOL[${IN_TYPE[$map]:-0}]})
  for i in 1 2; do
    free_tile $(( MX[m] - 3 )) $(( MY[m] - 3 )) $(( MX[m] + 3 )) $(( MY[m] + 3 )) "$map" || continue
    spawn_mon "$map" "${pool[RANDOM % ${#pool[@]}]}" "$SX" "$SY" -1 "${MSCALE[m]}"; MAGG[MID]=${MAGG[m]}
    MDS[MID]=${MDS[m]:-100} MADD[MID]=$m
    mon_state "$MID"
  done
  if (( ${M_RAID[$t]:-0} )) && (( MPH[m] == 1 )); then
    send BOSS srv "$map" "${M_NAME[t]} ${RAID_SHIELD[${M_RAID[$t]}]}" "${MX[m]}" "${MY[m]}"
  else send BOSS srv "$map" "${M_NAME[t]} calls its servants!" "${MX[m]}" "${MY[m]}"; fi
}

los() {  # map x1 y1 x2 y2 -> 0 if nothing blocks the line; LCELLS = the cells in between
  local map=$1 x=$2 y=$3 tx=$4 ty=$5 dx dy sx sy err e2 n=0
  dx=$(( tx > x ? tx - x : x - tx )) dy=$(( ty > y ? ty - y : y - ty )); sx=$(( x < tx ? 1 : -1 )) sy=$(( y < ty ? 1 : -1 ))
  err=$(( dx - dy )) LCELLS=""
  while (( n++ < 20 )); do
    e2=$(( 2 * err ))
    (( e2 > -dy )) && { err=$(( err - dy )); x=$(( x + sx )); }
    (( e2 < dx )) && { err=$(( err + dx )); y=$(( y + sy )); }
    (( x == tx && y == ty )) && return 0
    blocks_shot "$map" "$x" "$y" && return 1
    LCELLS+="$x,$y "
  done
  return 1
}

mon_healer() {  # mid: heal the most wounded friend within 5 steps
  local m=$1 map=${MMAP[$1]} x y o best="" bp=100 p
  for (( y = MY[m] - 5; y <= MY[m] + 5; y++ )); do
    for (( x = MX[m] - 5; x <= MX[m] + 5; x++ )); do
      o=${OCC[$map:$x:$y]}; [[ -n $o ]] || continue
      (( M_KIND[MT[o]] == 0 && MHP[o] < MMAX[o] )) || continue
      p=$(( MHP[o] * 100 / MMAX[o] )); (( p < bp )) && { bp=$p; best=$o; }
    done
  done
  [[ -n $best ]] && (( bp < 80 )) || return 1
  MHP[best]=$(( MHP[best] + MMAX[best] / 4 )); (( MHP[best] > MMAX[best] )) && MHP[best]=${MMAX[best]}
  send MHP srv "$map" "$best" "${MHP[best]}" ""
  send FX srv "$map" holy "${MX[best]},${MY[best]}"
  MHEALT[m]=$(( NOW + 5000 ))
  return 0
}

pq_progress() {  # pid type|D.dtype  -> advance party quests, pay out finished ones
  local p=$1 q f out=() changed=0 m
  [[ -n ${PT_QUESTS[$p]} ]] || return
  for q in ${PT_QUESTS[$p]}; do
    IFS=. read -r -a f <<< "$q"
    if [[ ( ${f[0]} == K && $2 != [DT].* && ${f[1]} == "$2" ) || ( ${f[0]} == [DT] && $2 == "${f[0]}.${f[1]}" ) ]]; then
      f[3]=$(( f[3] + 1 )); changed=1
      if (( f[3] >= f[2] )); then
        send QDONE srv "$p" $(( f[4] * 125 / 100 )) $(( f[5] * 125 / 100 )) "${f[0]}.${f[1]}.${f[2]}.${f[2]}.${f[4]}.${f[5]}"
        slog "party $p finished quest $q"
        continue
      fi
      q="${f[0]}.${f[1]}.${f[2]}.${f[3]}.${f[4]}.${f[5]}"
    fi
    out+=("$q")
  done
  (( changed )) || return
  PT_QUESTS[$p]="${out[*]}"
  send PQUEST srv "$p" "${PT_QUESTS[$p]// /,}"
}

mon_die() {  # mid killer
  local m=$1 k=$2 t=${MT[$1]} map=${MMAP[$1]} rec=() p pid xp gold dt
  MALIVE[m]=0; unset "AL[$m]" "OCC[$map:${MX[m]}:${MY[m]}]"
  send MDIE srv "$map" "$m" "${SP_NAME[$k]}"
  if (( M_KIND[t] == 3 )); then MRESP[m]=$(( NOW + 45000 + RANDOM % 45000 )); RS[$m]=1; return; fi
  if (( MZONE[m] == -2 )); then wb_die "$m" "$k"; return; fi
  if (( M_KIND[t] == 4 )); then                          # a treasure chest: whoever opens it gets the lot
    dt=${IN_TYPE[$map]:-0}
    roll_item "$t" "$k" $(( D_REQ[dt] + 3 ))
    send REW srv "$k" $(( 20 * D_REQ[dt] + 20 )) $(( 40 * D_REQ[dt] + 30 + RANDOM % (20 * D_REQ[dt] + 20) )) "$ITEM" "$t"
    gem_drop "$t" "$k" 0 "${D_REQ[dt]}"
    return
  fi
  pid=${SP_PARTY[$k]}
  if [[ -n $pid ]]; then
    for p in ${PT_MEMBERS[$pid]}; do
      [[ ${SP_MAP[$p]} == "$map" ]] || continue
      if [[ $map == W ]]; then
        cheb $(( ${SP_X[$p]:-0} - MX[m] )) $(( ${SP_Y[$p]:-0} - MY[m] )); (( D <= 30 )) || continue
      fi
      rec+=("$p")
    done
  fi
  (( ${#rec[@]} )) || rec=("$k")
  xp=$(( M_XP[t] * MSCALE[m] / 100 )) gold=$(( M_GOLD[t] * MSCALE[m] / 100 ))
  local champ=$(( ${MCH[m]:--1} >= 0 ))
  (( champ )) && xp=$(( xp * 3 )) gold=$(( gold * 3 ))
  [[ $map == W ]] && (( NIGHT )) && [[ $UNDEAD == *" $t "* ]] && xp=$(( xp * 125 / 100 ))
  if (( ${#rec[@]} > 1 )); then xp=$(( xp * 80 / 100 )) gold=$(( gold * 60 / 100 + 1 )); fi
  local ml=""; (( ${IN_MYTH[$map]:-0} )) && ml=$MYTH_LVL
  for p in "${rec[@]}"; do
    roll_item "$t" "$p" "$ml" "$champ"
    send REW srv "$p" "$xp" "$gold" "$ITEM" "$t" "$champ"
    gem_drop "$t" "$p" "$champ" "$ml"
  done
  (( ${IN_MYTH[$map]:-0} >= 7 && ${IN_AFC[$map]:-0} == 0 && M_BOSS[t] == 0 )) && myth_bolster "$m"
  (( M_BOSS[t] == 2 && MZONE[m] >= 0 )) && send ANN srv "${SP_NAME[$k]} has slain the rare ${M_NAME[t]}!"
  [[ -n $pid ]] && pq_progress "$pid" "$t"
  if (( MZONE[m] >= 0 )); then
    MRESP[m]=$(( NOW + 20000 + RANDOM % 20000 )); RS[$m]=1
    (( M_BOSS[t] == 2 )) && MRESP[m]=$(( NOW + 240000 + RANDOM % 120000 ))    # rare elites take their time
  elif (( MZONE[m] == -3 )); then
    MRESP[m]=$(( NOW + 90000 )); RS[$m]=1
    set_wanted "$k" 180000
    send ANN srv "${SP_NAME[$k]} murdered ${N_FULL[$t]}! The guards of Hearthmoor are hunting ${SP_NAME[$k]}."
    slog "NPC $t killed by ${SP_NAME[$k]}"
  fi
  if (( M_BOSS[t] )) && [[ $map == D* && -n ${IN_TYPE[$map]} ]] && (( t == D_BOSS[${IN_TYPE[$map]}] )); then
    IN_DONE[$map]=1; dt=${IN_TYPE[$map]}
    send DCLEAR srv "$map" "${M_NAME[t]}"
    if (( ${IN_MYTH[$map]:-0} )); then myth_finish "$map"
    elif (( ${D_RAID[$dt]:-0} )); then raid_finish "$map"
    else send ANN srv "${SP_NAME[$k]}'s group cleared the ${D_NAME[dt]}!"; fi
    [[ -n ${IN_PARTY[$map]} && -n ${PT_LEADER[${IN_PARTY[$map]}]} ]] && pq_progress "${IN_PARTY[$map]}" "D.$dt"
    slog "instance $map cleared"
  fi
}

srv_hit() {  # from map mid dmg freeze
  local id=$1 map=$2 m=$3 dmg=$4 fr=$5 cap
  isnum "$m" && isnum "$dmg" && isnum "$fr" || return
  (( m < NMON && MALIVE[m] )) || return
  [[ ${MMAP[m]} == "$map" ]] || return
  if (( M_KIND[MT[m]] == 3 )); then                     # gathering a resource node
    (( NOW - ${GATH_T[$id]:-0} >= 800 )) || return
    GATH_T[$id]=$NOW MHP[m]=$(( MHP[m] - 1 ))
    if (( MHP[m] <= 0 )); then mon_die "$m" "$id"; else send MHP srv "$map" "$m" "${MHP[m]}" ""; fi
    return
  fi
  cap=$(( (${SP_LVL[$id]:-1} + 5) * 70 ))
  (( dmg > cap )) && dmg=$cap
  (( ${MCH[m]:--1} == 2 )) && dmg=$(( dmg * 60 / 100 ))   # armored champion
  (( ${MEV[m]:-0} )) && INV_PART[$id]=1                    # v4.5: a defender of the town
  if (( ${M_RAID[${MT[m]}]:-0} && MPH[m] == 1 )) && raid_adds_alive "$m"; then dmg=$(( dmg / 5 )); fi   # shielded
  MHP[m]=$(( MHP[m] - dmg ))
  if [[ -z ${MAGG[m]} ]] || (( RANDOM % 4 == 0 )); then MAGG[m]=$id; fi
  if (( M_KIND[MT[m]] == 1 || M_KIND[MT[m]] == 2 )); then
    MAGG[m]=$id
    set_wanted "$id" 120000
  fi
  if (( fr > 0 )); then
    (( fr > 4000 )) && fr=4000
    (( M_BOSS[MT[m]] )) && fr=$(( fr / 3 ))
    MFRZ[m]=$(( NOW + fr ))
  fi
  if (( MZONE[m] == -2 )); then
    [[ "${MCON[m]} " == *" $id "* ]] || MCON[m]+=" $id"
    if (( MHP[m] > 0 && MPH[m] < 2 && MHP[m] * 3 < MMAX[m] * (2 - MPH[m]) )); then MPH[m]=$(( MPH[m] + 1 )); wb_adds "$m"; fi
  elif (( M_SUMM[MT[m]] )) && [[ $map == D* ]]; then         # dungeon bosses call for help at 2/3 and 1/3
    if (( MHP[m] > 0 && MPH[m] < 2 && MHP[m] * 3 < MMAX[m] * (2 - MPH[m]) )); then MPH[m]=$(( MPH[m] + 1 )); boss_summon "$m"; fi
  fi
  if (( MHP[m] <= 0 )); then mon_die "$m" "$id"
  else send MHP srv "$map" "$m" "${MHP[m]}" "${SP_NAME[$id]}"; fi
}

player_at() {  # map x y -> 0 if a living player stands there
  local p
  for p in ${PLIST[$1]}; do (( ${SP_X[$p]} == $2 && ${SP_Y[$p]} == $3 )) && return 0; done
  return 1
}

mon_step() {  # mid tx ty
  local m=$1 x=${MX[$1]} y=${MY[$1]} map=${MMAP[$1]} dx dy sx sy c nx ny civ=${M_KIND[${MT[$1]}]} cand
  dx=$(( $2 - x )) dy=$(( $3 - y ))
  sx=$(( dx > 0 ? 1 : (dx < 0 ? -1 : 0) )) sy=$(( dy > 0 ? 1 : (dy < 0 ? -1 : 0) ))
  if (( (dx < 0 ? -dx : dx) >= (dy < 0 ? -dy : dy) )); then cand="$sx,0 0,$sy"; else cand="0,$sy $sx,0"; fi
  (( RANDOM % 3 == 0 )) && cand+=" 0,1 1,0 0,-1 -1,0"
  for c in $cand; do
    nx=$(( x + ${c%,*} )) ny=$(( y + ${c#*,} ))
    (( nx == x && ny == y )) && continue
    m_walk "$map" "$nx" "$ny" || continue
    (( civ == 0 )) && in_safe "$map" "$nx" "$ny" && continue
    [[ -n ${OCC[$map:$nx:$ny]} ]] && continue
    player_at "$map" "$nx" "$ny" && continue
    unset "OCC[$map:$x:$y]"; OCC["$map:$nx:$ny"]=$m
    MX[m]=$nx MY[m]=$ny
    send MMOV srv "$map" "$m" "$nx" "$ny" "${MT[m]}" "${MHP[m]}" "${MMAX[m]}" $(( ${MCH[m]:--1} + 1 ))   # v6.3: full state (interest management)
    return 0
  done
  return 1
}

mon_hit() {  # mid target dmg: MATK with the element and maybe a status effect (v3.0)
  local m=$1 t=${MT[$1]} ab=${M_AB[${MT[$1]}]} c=${MCH[$1]:--1} ch=22 eff=""
  case $c in 3) ab=burn ;; 4) ab=chill ;; 5) ab=poison ;; 7) ab=stun ;; 8) ab=weaken ;; esac   # v4.0: storming, cursed
  (( (c >= 3 && c <= 5) || c == 8 )) && ch=55; (( c == 7 )) && ch=25; (( M_BOSS[t] )) && ch=30
  [[ -n $ab ]] && (( RANDOM % 100 < ch )) && eff=$ab
  send MATK srv "${MMAP[m]}" "$m" "$2" "$3" "${M_EL[t]}" "$eff"
  if (( c == 0 && MHP[m] < MMAX[m] )); then                  # vampiric champion
    MHP[m]=$(( MHP[m] + $3 * 30 / 100 + 1 )); (( MHP[m] > MMAX[m] )) && MHP[m]=${MMAX[m]}
    send MHP srv "${MMAP[m]}" "$m" "${MHP[m]}" ""
  fi
  if [[ ${M_AB[t]} == drain ]]; then
    MHP[m]=$(( MHP[m] + $3 / 2 )); (( MHP[m] > MMAX[m] )) && MHP[m]=${MMAX[m]}
  fi
}

mon_attack() {  # mid target
  local m=$1 t=${MT[$1]} map=${MMAP[$1]} dmg q cells="" i j
  dmg=$(( M_DMG[t] * (85 + RANDOM % 31) / 100 ))
  (( ${MCH[m]:--1} >= 0 )) && dmg=$(( dmg * (MCH[m] == 6 ? 140 : 125) / 100 ))
  [[ $map == W ]] && (( NIGHT )) && [[ $UNDEAD == *" $t "* ]] && dmg=$(( dmg * 130 / 100 ))
  if [[ $map == D* ]]; then                                        # v4.5: mythic and raid
    dmg=$(( dmg * ${MDS[m]:-100} / 100 ))
    (( ${IN_MYTH[$map]:-0} >= 7 && ${IN_AFC[$map]:-0} == 1 && M_BOSS[t] == 0 && MHP[m] * 10 < MMAX[m] * 3 )) && dmg=$(( dmg * 150 / 100 ))
    if (( ${M_RAID[$t]:-0} == 2 )); then raid2_attack "$m" "$2" "$dmg"; return; fi   # v8.0: Aurelion
    if (( ${M_RAID[$t]:-0} )); then raid_attack "$m" "$2" "$dmg"; return; fi
  fi
  if (( MZONE[m] == -2 )); then
    MATKN[m]=$(( MATKN[m] + 1 ))
    if (( MATKN[m] % 3 == 0 && WBS_AT == 0 )); then     # telegraphed slam around the target
      WBS_X=${SP_X[$2]} WBS_Y=${SP_Y[$2]} WBS_M=$m WBS_D=$(( dmg * 2 )) WBS_AT=$(( NOW + 1400 ))
      for (( j = -2; j <= 2; j++ )); do for (( i = -2; i <= 2; i++ )); do cells+="$(( WBS_X + i )),$(( WBS_Y + j )) "; done; done
      send FX srv "$map" warn "$cells"
      send BOSS srv "$map" "${M_NAME[t]} raises its fists - get out of the marked area!" "$WBS_X" "$WBS_Y"
      return
    fi
    mon_hit "$m" "$2" "$dmg"; return
  fi
  if (( M_BOSS[t] )); then
    MATKN[m]=$(( MATKN[m] + 1 ))
    if (( MATKN[m] % 4 == 0 )); then
      for (( j = -2; j <= 2; j++ )); do for (( i = -2; i <= 2; i++ )); do cells+="$(( MX[m] + i )),$(( MY[m] + j )) "; done; done
      send FX srv "$map" fire "$cells"
      send BOSS srv "$map" "${M_NAME[t]} unleashes a devastating blast!"
      for q in ${PLIST[$map]}; do
        cheb $(( ${SP_X[$q]} - MX[m] )) $(( ${SP_Y[$q]} - MY[m] ))
        (( D <= 2 )) && send MATK srv "$map" "$m" "$q" $(( dmg * 80 / 100 )) "${M_EL[t]}" ""
      done
      return
    fi
  fi
  mon_hit "$m" "$2" "$dmg"
}

mon_think() {  # mid
  local m=$1 map=${MMAP[$1]} t=${MT[$1]} x=${MX[$1]} y=${MY[$1]} tgt="" best=999 p ag leash kind near=999 dx dy
  kind=${M_KIND[t]} ag=${M_AGGRO[t]}
  (( kind >= 3 )) && { MNEXT[m]=4000000000000; return; }
  p=${MAGG[m]}
  if [[ -n $p && ${SP_MAP[$p]} == "$map" && ${SP_DEAD[$p]:-1} == 0 ]] && { (( kind > 0 )) || [[ -z ${PSAFE[$p]} ]]; }; then
    cheb $(( ${SP_X[$p]} - x )) $(( ${SP_Y[$p]} - y )); (( D <= ag + 10 )) && { tgt=$p; best=$D; }
  fi
  if [[ -z $tgt ]]; then
    for p in ${PLIST[$map]}; do                        # (distance inlined: this loop is the server's hottest)
      (( dx = ${SP_X[$p]} - x, dx < 0 && (dx = -dx), dy = ${SP_Y[$p]} - y, dy < 0 && (dy = -dy), D = dx > dy ? dx : dy ))
      (( D < near )) && near=$D
      (( D <= ag && D < best )) || continue
      if (( kind == 0 )); then
        [[ -n ${PSAFE[$p]} ]] && continue
      elif (( kind == 2 )); then
        [[ -n ${SP_WANTED[$p]} ]] || continue          # guards only hunt outlaws
      else
        continue                                       # civilians only fight back
      fi
      best=$D tgt=$p
    done
    if [[ -z $tgt ]] && (( near > 28 && MHP[m] >= MMAX[m] )); then   # nobody near: sleep until someone could be
      near=$(( (near - 28) * 100 )); (( near < 1500 )) && near=1500; (( near > 15000 )) && near=15000
      MNEXT[m]=$(( NOW + near )); return
    fi
  fi
  leash=14; [[ $map == D* ]] && leash=40; (( MZONE[m] == -2 )) && leash=22
  (( kind == 1 )) && leash=8; (( kind == 2 )) && leash=30
  cheb $(( x - MHX[m] )) $(( y - MHY[m] ))
  (( D > leash )) && tgt=""
  if [[ -z $tgt ]]; then
    MAGG[m]=""
    if (( D > MWR[m] && D > 0 )); then
      mon_step "$m" "${MHX[m]}" "${MHY[m]}"
    elif (( MWR[m] > 0 && RANDOM % 3 == 0 )); then
      mon_step "$m" $(( MHX[m] + RANDOM % (2 * MWR[m] + 1) - MWR[m] )) $(( MHY[m] + RANDOM % (2 * MWR[m] + 1) - MWR[m] ))
    fi
    if (( MHP[m] < MMAX[m] )); then
      MHP[m]=$(( MHP[m] + MMAX[m] / 8 + 1 )); (( MHP[m] > MMAX[m] )) && MHP[m]=${MMAX[m]}
      send MHP srv "$map" "$m" "${MHP[m]}" ""
    fi
    MNEXT[m]=$(( NOW + 600 + RANDOM % 900 ))
    return
  fi
  MAGG[m]=$tgt
  if (( M_HEALR[t] && NOW >= MHEALT[m] )) && mon_healer "$m"; then MNEXT[m]=$(( NOW + M_ATK[t] )); return; fi
  dx=$(( ${SP_X[$tgt]} - x )) dy=$(( ${SP_Y[$tgt]} - y ))
  if (( (dx < 0 ? -dx : dx) + (dy < 0 ? -dy : dy) == 1 )); then   # orthogonal neighbours only
    mon_attack "$m" "$tgt"
    MNEXT[m]=$(( NOW + M_ATK[t] ))
    (( (MZONE[m] == -2 || M_BOSS[t] == 1) && MHP[m] * 4 < MMAX[m] )) && MNEXT[m]=$(( NOW + M_ATK[t] * 65 / 100 ))   # enraged
  else
    cheb "$dx" "$dy"
    if (( M_RNG[t] && D >= 2 && D <= M_RNG[t] )) && los "$map" "$x" "$y" "${SP_X[$tgt]}" "${SP_Y[$tgt]}"; then
      local fk=(slash fire frost poison bone holy sound)        # a bolt flies
      send FX srv "$map" "${fk[M_EL[t]]}" "$LCELLS${SP_X[$tgt]},${SP_Y[$tgt]}"
      mon_attack "$m" "$tgt"
      MNEXT[m]=$(( NOW + M_ATK[t] * 12 / 10 ))
    else
      mon_step "$m" "${SP_X[$tgt]}" "${SP_Y[$tgt]}"
      MNEXT[m]=$(( NOW + M_MOVE[t] ))
      (( ${MCH[m]:--1} == 9 )) && MNEXT[m]=$(( NOW + M_MOVE[t] * 55 / 100 ))       # swift champion
    fi
  fi
  (( ${MCH[m]:--1} == 1 )) && MNEXT[m]=$(( NOW + (MNEXT[m] - NOW) * 6 / 10 ))     # frenzied champion
}

ai_tick() {
  local id m
  local s cur=$(( NOW / 150 )) from list
  PLIST=() PSAFE=()
  for id in "${!SP_NAME[@]}"; do
    [[ ${SP_DEAD[$id]:-0} == 0 ]] || continue
    PLIST[${SP_MAP[$id]}]+=" $id"
    [[ ${SP_MAP[$id]} == W ]] && in_safe_xy "${SP_X[$id]}" "${SP_Y[$id]}" && PSAFE[$id]=1   # once per tick, not per monster
  done
  (( WH_LAST < 0 )) && WH_LAST=$(( cur - 1 ))
  from=$(( WH_LAST + 1 )); WH_LAST=$cur                  # from here on, wake-ups land in later slots
  for (( s = from; s <= cur; s++ )); do
    [[ -n ${WHEEL[s]} ]] || continue
    list=${WHEEL[s]}; unset "WHEEL[s]"
    for m in $list; do
      [[ -n ${AL[$m]} ]] && (( MSLOT[m] == s )) || continue     # dead, or woken again since
      if (( MNEXT[m] > NOW )); then wake "$m"; continue; fi    # due later in this slot: next one
      if [[ -z ${PLIST[${MMAP[m]}]} ]]; then MNEXT[m]=$(( NOW + 1500 )); wake "$m"; continue; fi
      if (( NOW < MFRZ[m] )); then MNEXT[m]=${MFRZ[m]}; wake "$m"; continue; fi
      mon_think "$m"
      (( MNEXT[m] < 4000000000000 )) && wake "$m"
    done
  done
  (( WBS_AT && NOW >= WBS_AT )) && wb_slam
  (( ${#AOE_Q[@]} )) && aoe_tick
}

# Monsters sleep in a timer wheel of 150 ms slots: a tick only touches the ones whose turn it is.
WHEEL=() WH_LAST=-1 MSLOT=()
declare -A PSAFE=()       # players standing in a town this tick
declare -A IN_MYTH=() IN_T0=() IN_LIM=() IN_AFC=() INV_PART=()   # v4.5: mythic level, start, limit, affix C of an instance
MDS=() MADD=() MEV=() AOE_Q=() INV_NEXT=0 INV_WAVE=0 INV_END=0 INV_MONS="" INV_TOWN=-1 INV_T=()
wake() {  # mid: schedule its next think at MNEXT (never into a slot that is already done)
  local s=$(( MNEXT[$1] / 150 ))
  (( s <= WH_LAST )) && s=$(( WH_LAST + 1 ))
  WHEEL[s]+=" $1"; MSLOT[$1]=$s
}
wake_check() {  # safety net: anything alive that fell out of the wheel goes back in
  local m
  for m in "${!AL[@]}"; do
    (( MNEXT[m] < NOW - 3000 && M_KIND[MT[m]] < 3 )) && { MNEXT[m]=$NOW; wake "$m"; }
  done
}

# --- world bosses -----------------------------------------------------------------
wb_slam() {
  local p cells="" i j m=$WBS_M
  WBS_AT=0
  (( m >= 0 && MALIVE[m] )) || return
  for (( j = -2; j <= 2; j++ )); do for (( i = -2; i <= 2; i++ )); do cells+="$(( WBS_X + i )),$(( WBS_Y + j )) "; done; done
  send FX srv W fire "$cells"
  for p in ${PLIST[W]}; do
    cheb $(( ${SP_X[$p]} - WBS_X )) $(( ${SP_Y[$p]} - WBS_Y ))
    (( D <= 2 )) && send MATK srv W "$m" "$p" "$WBS_D"
  done
}

wb_adds() {  # mid: the boss calls for help
  local m=$1 t=${MT[$1]} i a k=0 types
  for i in "${!WB_LIST[@]}"; do [[ ${WB_LIST[i]} == "$t" ]] && k=$i; done
  types=(${WB_ADDS[k]})
  for a in "${types[@]}"; do
    free_tile $(( MX[m] - 3 )) $(( MY[m] - 3 )) $(( MX[m] + 3 )) $(( MY[m] + 3 )) W || continue
    spawn_mon W "$a" "$SX" "$SY" -4 100 4; MAGG[MID]=${MAGG[m]}
    mon_state "$MID"
  done
  send BOSS srv W "${M_NAME[t]} calls for help - minions rush in!" "${MX[m]}" "${MY[m]}"
}

wb_spawn() {
  local id n=0 sum=0 mx=0 i t best="" bs=999 sc r a scale
  for id in "${!SP_NAME[@]}"; do n=$(( n + 1 )); sum=$(( sum + ${SP_LVL[$id]:-1} )); (( ${SP_LVL[$id]:-1} > mx )) && mx=${SP_LVL[$id]:-1}; done
  if (( n == 0 )); then WB_NEXT=$(( NOW + 60000 )); return; fi
  for i in "${!WB_LIST[@]}"; do
    t=${WB_LIST[i]}
    (( M_LVL[t] <= mx + 4 )) || continue
    sc=$(( M_LVL[t] - sum / n )); sc=$(( (sc < 0 ? -sc : sc) + RANDOM % 4 ))
    (( sc < bs )) && { bs=$sc; best=$i; }
  done
  [[ -n $best ]] || best=0
  t=${WB_LIST[best]} a=(${WB_RECT[best]})
  free_tile "${a[0]}" "${a[1]}" "${a[2]}" "${a[3]}" W || { WB_NEXT=$(( NOW + 20000 )); return; }
  scale=$(( 100 + 60 * (n - 1) )); (( scale > 400 )) && scale=400
  spawn_mon W "$t" "$SX" "$SY" -2 "$scale" 4; WB_MID=$MID
  WB_GONE=$(( NOW + 900000 )) WB_PING=0
  mon_state "$MID"
  region_of "$SX" "$SY" nosafe
  send ANN srv "The ground trembles... ${M_NAME[t]} (level ${M_LVL[t]}) has appeared in the $RNAME! Everyone who fights it shares the loot."
  slog "world boss ${M_NAME[t]} spawned at $SX,$SY (scale $scale%)"
}

wb_die() {  # mid killer: every contributor nearby gets full XP, gold and a boss item
  local m=$1 k=$2 t=${MT[$1]} p rec=()
  for p in ${MCON[m]}; do
    [[ -n ${SP_NAME[$p]} && ${SP_MAP[$p]} == W ]] || continue
    cheb $(( ${SP_X[$p]} - MX[m] )) $(( ${SP_Y[$p]} - MY[m] )); (( D <= 60 )) && rec+=("$p")
  done
  (( ${#rec[@]} )) || rec=("$k")
  for p in "${rec[@]}"; do
    roll_item "$t" "$p"
    send REW srv "$p" "${M_XP[t]}" "${M_GOLD[t]}" "$ITEM" "$t"
  done
  WB_NEXT=$(( NOW + 480000 )) WB_MID=-1
  send WBOSS srv -1 0 0 0
  send ANN srv "${M_NAME[t]} has been slain! ${SP_NAME[$k]} landed the final blow - ${#rec[@]} hero(es) share the spoils."
  slog "world boss ${M_NAME[t]} killed (${#rec[@]} contributors)"
}

wb_second() {
  if (( WB_MID < 0 || ! MALIVE[WB_MID] )); then
    (( WB_NEXT > 0 && NOW >= WB_NEXT )) && wb_spawn
    return
  fi
  local m=$WB_MID
  if (( NOW >= WB_GONE )); then
    MALIVE[m]=0; unset "AL[$m]" "OCC[W:${MX[m]}:${MY[m]}]"
    send MDIE srv W "$m" "-"; send WBOSS srv -1 0 0 0
    send ANN srv "${M_NAME[${MT[m]}]} grows tired of waiting and vanishes..."
    WB_MID=-1 WB_NEXT=$(( NOW + 300000 ))
    return
  fi
  if (( NOW >= WB_PING )); then WB_PING=$(( NOW + 4000 )); send WBOSS srv "$m" "${MT[m]}" "${MX[m]}" "${MY[m]}"; fi
}

# --- weather & clock ------------------------------------------------------------
weather_second() {
  local i k kinds
  for i in "${!WEA_REG[@]}"; do
    if [[ -n ${WS_T[i]} ]]; then
      (( NOW >= WS_E[i] )) || continue
      send WEATHER srv "$i" - 0
      WS_T[i]="" WS_N[i]=$(( NOW + 240000 + (RANDOM << 15 | RANDOM) % 360000 ))
    elif (( NOW >= ${WS_N[i]:-0} )); then
      kinds=(${WEA_KIND[i]}); k=${kinds[RANDOM % ${#kinds[@]}]}
      WS_T[i]=$k WS_E[i]=$(( NOW + 120000 + (RANDOM << 15 | RANDOM) % 120000 ))
      send WEATHER srv "$i" "$k" $(( (WS_E[i] - NOW) / 1000 ))
      slog "weather: $k over ${WEA_REG[i]}"
    fi
  done
}

clock_second() {
  local gm=$(( (NOW - SRV_CLK0) % DAYLEN / GMIN ))
  NIGHT=$(( gm >= 1260 || gm < 300 ))
  (( NOW >= ${CLK_NEXT:-0} )) && { CLK_NEXT=$(( NOW + 10000 )); send CLOCK srv $(( (NOW - SRV_CLK0) % DAYLEN )); }
}

srv_invite() {  # from targetname
  local from=$1 want=${2,,} id tid="" pid n
  for id in "${!SP_NAME[@]}"; do [[ ${SP_NAME[$id],,} == "$want" && $id != "$from" ]] && tid=$id; done
  if [[ -z $tid ]]; then send INFO srv "$from" "No player named '$2' is online."; return; fi
  pid=${SP_PARTY[$from]}
  if [[ -n $pid ]]; then
    if [[ ${PT_LEADER[$pid]} != "$from" ]]; then send INFO srv "$from" "Only the party leader can invite."; return; fi
    n=(${PT_MEMBERS[$pid]}); (( ${#n[@]} >= 4 )) && { send INFO srv "$from" "Your party is full (max 4)."; return; }
  fi
  if [[ -n ${SP_PARTY[$tid]} && ${SP_PARTY[$tid]} == "$pid" ]]; then send INFO srv "$from" "${SP_NAME[$tid]} is already in your party."; return; fi
  INV_FROM[$tid]=$from
  send PINV srv "$tid" "${SP_NAME[$from]}"
  send INFO srv "$from" "You invited ${SP_NAME[$tid]} to your party."
}

srv_accept() {
  local id=$1 from=${INV_FROM[$1]} pid n
  unset "INV_FROM[$id]"
  if [[ -z $from || -z ${SP_NAME[$from]} ]]; then send INFO srv "$id" "You have no pending party invite."; return; fi
  [[ -n ${SP_PARTY[$id]} ]] && srv_pleave "$id"
  pid=${SP_PARTY[$from]}
  if [[ -z $pid ]]; then
    NPARTY=$(( NPARTY + 1 )); pid="p$NPARTY"
    PT_LEADER[$pid]=$from PT_MEMBERS[$pid]=$from SP_PARTY[$from]=$pid PT_QUESTS[$pid]=""
  fi
  n=(${PT_MEMBERS[$pid]})
  if (( ${#n[@]} >= 4 )); then send INFO srv "$id" "That party is full."; return; fi
  PT_MEMBERS[$pid]+=" $id"; SP_PARTY[$id]=$pid
  party_send "$pid"
  slog "party $pid: ${PT_MEMBERS[$pid]}"
}

srv_pleave() {
  local id=$1 pid=${SP_PARTY[$1]} m rest=()
  [[ -n $pid ]] || return
  unset "SP_PARTY[$id]"
  for m in ${PT_MEMBERS[$pid]}; do [[ $m == "$id" ]] || rest+=("$m"); done
  if (( ${#rest[@]} <= 1 )); then
    for m in "${rest[@]}"; do unset "SP_PARTY[$m]"; done
    unset "PT_LEADER[$pid]" "PT_MEMBERS[$pid]" "PT_INST[$pid]" "PT_QUESTS[$pid]"
    send PARTY srv "$pid" "" ""
  else
    PT_MEMBERS[$pid]="${rest[*]}"
    [[ ${PT_LEADER[$pid]} == "$id" ]] && PT_LEADER[$pid]=${rest[0]}
    party_send "$pid"
  fi
}

srv_qadd() {  # from code  (party leader accepts a quest for the whole party)
  local id=$1 q=$2 pid=${SP_PARTY[$1]} n e
  [[ $q =~ ^[KDT]\.(0|[1-9][0-9]{0,2})\.([1-9][0-9]?)\.0\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$ ]] || return
  if [[ -z $pid ]]; then send INFO srv "$id" "You are not in a party."; return; fi
  if [[ ${PT_LEADER[$pid]} != "$id" ]]; then send INFO srv "$id" "Only the party leader can accept party quests."; return; fi
  n=(${PT_QUESTS[$pid]})
  (( ${#n[@]} >= 3 )) && { send INFO srv "$id" "Your party already has 3 quests."; return; }
  for e in "${n[@]}"; do [[ ${e%.*.*.*.*} == "${q%.*.*.*.*}" ]] && { send INFO srv "$id" "Your party already has that quest."; return; }; done
  PT_QUESTS[$pid]+=" $q"; PT_QUESTS[$pid]=${PT_QUESTS[$pid]# }
  send PQUEST srv "$pid" "${PT_QUESTS[$pid]// /,}"
  slog "party $pid accepted quest $q"
}

make_instance() {  # dtype pid mythic-level ids...
  local dt=$1 pid=$2 mk=${3:-0} map seed n scale pool i j a cnt csv
  shift 3
  NINST=$(( NINST + 1 )); map="D$NINST"
  seed=$(( ((RANDOM << 15) | RANDOM) & 0x7fffffff ))
  gen_dungeon "$map" "$dt" "$seed"
  n=$#; scale=$(( 100 + 70 * (n - 1) )); (( ${D_RAID[$dt]:-0} )) && scale=$(( 100 + 90 * (n - 1) ))
  IN_TYPE[$map]=$dt IN_SEED[$map]=$seed IN_PARTY[$map]=$pid IN_EMPTY[$map]=0 IN_SCALE[$map]=$scale IN_DONE[$map]=0
  IN_MYTH[$map]=$mk IN_T0[$map]=$NOW IN_LIM[$map]=0; myth_afx; IN_AFC[$map]=$MC
  (( mk )) && { myth_limit "$dt"; IN_LIM[$map]=$MYL; }
  if [[ -n $pid ]]; then PT_INST[$pid]=$map; else SOLO_INST[$1]=$map; fi
  pool=(${D_POOL[dt]})
  for (( i = 1; i < ${#DG_ROOMS[@]}; i++ )); do
    a=(${DG_ROOMS[i]})
    cnt=$(( 2 + RANDOM % 2 + (n > 2 ? 1 : 0) ))
    (( i == ${#DG_ROOMS[@]} - 1 )) && cnt=2
    for (( j = 0; j < cnt; j++ )); do
      free_tile "${a[0]}" "${a[1]}" $(( a[0] + a[2] - 1 )) $(( a[1] + a[3] - 1 )) "$map" || continue
      inst_mon "$map" "${pool[RANDOM % ${#pool[@]}]}" "$SX" "$SY" "$scale" "$mk"
    done
  done
  if (( ${#DG_ROOMS[@]} > 3 )); then                      # v2.0: an elite guards the middle of the dungeon
    a=(${DG_ROOMS[${#DG_ROOMS[@]} / 2]})
    free_tile "${a[0]}" "${a[1]}" $(( a[0] + a[2] - 1 )) $(( a[1] + a[3] - 1 )) "$map" && inst_mon "$map" "${D_ELITE[dt]}" "$SX" "$SY" "$scale" "$mk"
  fi
  for (( j = 0; j < ${D_CHESTS[dt]:-2}; j++ )); do        # ... and treasure chests hide in the side rooms
    i=$(( 1 + RANDOM % (${#DG_ROOMS[@]} - 2) )); a=(${DG_ROOMS[i]})
    free_tile "${a[0]}" "${a[1]}" $(( a[0] + a[2] - 1 )) $(( a[1] + a[3] - 1 )) "$map" && spawn_mon "$map" "$CHEST" "$SX" "$SY" -1 100 0
  done
  [[ -n ${OCC[$map:$DG_BX:$DG_BY]} ]] && unset "OCC[$map:$DG_BX:$DG_BY]"
  inst_mon "$map" "${D_BOSS[dt]}" "$DG_BX" "$DG_BY" "$scale" "$mk"
  csv="$*"; csv=${csv// /,}
  send DSTART srv "$map" "$dt" "$seed" "$scale" "$csv" "$mk" "${IN_LIM[$map]}" 0
  srv_sync "$map"
  slog "instance $map (${D_NAME[dt]}, seed $seed, scale $scale%) for: $csv"
}

srv_dreq() {  # from dtype [mythic level]
  local id=$1 dt=$2 mk=${3:-0} pid ex m ids=() far=0
  [[ $dt =~ ^(0|[1-9][0-9]?)$ ]] && (( dt < NDT )) || return
  [[ $mk =~ ^(0|[1-9][0-9]?)$ ]] && (( mk <= MYTH_MAX )) || mk=0          # (no "08": octal)
  (( mk && (mk < 2 || ${SP_LVL[$id]:-1} < MAXLVL || ${D_RAID[$dt]:-0}) )) && mk=0
  (( NOW - ${DREQ_T[$id]:-0} >= 1500 )) || return          # one request per 1.5 s per player
  DREQ_T[$id]=$NOW
  pid=${SP_PARTY[$id]}
  ex=${SOLO_INST[$id]}; [[ -n $pid ]] && ex=${PT_INST[$pid]}
  # re-entering resumes your running instance - unless its boss is already dead
  if [[ -n $ex && ${IN_TYPE[$ex]} == "$dt" && ${IN_DONE[$ex]} == 0 ]]; then
    send DSTART srv "$ex" "$dt" "${IN_SEED[$ex]}" "${IN_SCALE[$ex]}" "$id" "${IN_MYTH[$ex]:-0}" "${IN_LIM[$ex]:-0}" $(( NOW - ${IN_T0[$ex]:-$NOW} ))
    srv_sync "$ex"; return
  fi
  if (( ${#IN_TYPE[@]} >= ${SHELLMMO_MAX_INST:-40} )); then
    send INFO srv "$id" "The dungeons are overcrowded right now - try again in a minute."; return
  fi
  if [[ -n $pid ]]; then
    if [[ ${PT_LEADER[$pid]} != "$id" ]]; then
      send INFO srv "$id" "Only your party leader (${SP_NAME[${PT_LEADER[$pid]}]}) can open a new dungeon."; return
    fi
    for m in ${PT_MEMBERS[$pid]}; do
      [[ ${SP_MAP[$m]} == W && ${SP_DEAD[$m]:-0} == 0 ]] || { [[ $m != "$id" ]] && far=1; continue; }
      cheb $(( ${SP_X[$m]} - D_ENTX[dt] )) $(( ${SP_Y[$m]} - D_ENTY[dt] ))
      if (( D <= 20 )) || [[ $m == "$id" ]]; then ids+=("$m"); else far=1; fi
    done
  fi
  (( ${#ids[@]} )) || ids=("$id")
  make_instance "$dt" "$pid" "$mk" "${ids[@]}"
  (( far )) && send PINFO srv "$pid" "The party entered the ${D_NAME[dt]}. Walk into its entrance to join them."
}

close_instance() {
  local map=$1 m y p
  for m in ${IN_MONS[$map]}; do
    unset "AL[$m]" "RS[$m]" "OCC[$map:${MX[m]}:${MY[m]}]" "MX[m]" "MY[m]" "MT[m]" "MHP[m]" "MMAX[m]" "MMAP[m]" "MALIVE[m]" \
      "MHX[m]" "MHY[m]" "MNEXT[m]" "MFRZ[m]" "MAGG[m]" "MRESP[m]" "MZONE[m]" "MATKN[m]" "MSCALE[m]" "MWR[m]" "MCON[m]" "MPH[m]" "MSLOT[m]" "MCH[m]" "MHEALT[m]" \
      "MDS[m]" "MADD[m]"
  done
  for (( y = 0; y < ${MAPH[$map]:-0}; y++ )); do unset "MAPROW[$map:$y]"; done
  for p in "${!PT_INST[@]}"; do [[ ${PT_INST[$p]} == "$map" ]] && unset "PT_INST[$p]"; done
  for p in "${!SOLO_INST[@]}"; do [[ ${SOLO_INST[$p]} == "$map" ]] && unset "SOLO_INST[$p]"; done
  unset "IN_TYPE[$map]" "IN_SEED[$map]" "IN_PARTY[$map]" "IN_EMPTY[$map]" "IN_SCALE[$map]" "IN_DONE[$map]" "IN_MONS[$map]" "MAPW[$map]" "MAPH[$map]" \
    "IN_MYTH[$map]" "IN_T0[$map]" "IN_LIM[$map]" "IN_AFC[$map]"
  send DEND srv "$map"
  slog "instance $map closed"
}

srv_second() {
  local m id map cnt z
  for m in "${!RS[@]}"; do
    (( NOW >= MRESP[m] )) || continue
    if (( MZONE[m] == -3 )); then            # NPCs come back home
      [[ -n ${OCC[W:${MHX[m]}:${MHY[m]}]} ]] && continue
      SX=${MHX[m]} SY=${MHY[m]}
    else
      zone_tile "${MZONE[m]}" || continue
      MHX[m]=$SX MHY[m]=$SY
    fi
    unset "RS[$m]"
    champ_roll "$m"
    MX[m]=$SX MY[m]=$SY MHP[m]=${MMAX[m]} MALIVE[m]=1 MAGG[m]="" MNEXT[m]=0 MFRZ[m]=0
    (( M_BOSS[MT[m]] == 2 )) && { region_of "$SX" "$SY" nosafe; send ANN srv "Hunters whisper that ${M_NAME[MT[m]]} roams the $RNAME again."; }
    OCC["W:$SX:$SY"]=$m; AL[$m]=1
    (( M_KIND[MT[m]] < 3 )) && wake "$m"
    mon_state "$m"
    (( MZONE[m] == -3 )) && send ANN srv "${N_FULL[${MT[m]}]} is back in business."
  done
  for id in "${!SP_WANTED[@]}"; do (( NOW >= SP_WANTED[$id] )) && set_wanted "$id" 0; done
  for id in "${!SP_NAME[@]}"; do
    (( NOW - ${SP_SEEN[$id]:-0} > 15000 )) && srv_drop "$id"
  done
  for id in "${!ACC_NAME[@]}"; do               # logged in but never entered the world (or gone): forget after ten minutes
    [[ -z ${SP_NAME[$id]} ]] && (( NOW - ${ACC_SEEN[$id]:-0} > 600000 )) && acc_forget "$id"
  done
  for map in "${!IN_TYPE[@]}"; do
    cnt=0
    for id in "${!SP_NAME[@]}"; do [[ ${SP_MAP[$id]} == "$map" ]] && cnt=$(( cnt + 1 )); done
    if (( cnt > 0 )); then IN_EMPTY[$map]=0
    elif (( IN_EMPTY[$map] == 0 )); then IN_EMPTY[$map]=$NOW
    elif (( NOW - IN_EMPTY[$map] > 30000 )); then close_instance "$map"
    fi
  done
  wb_second; weather_second; clock_second; inv_second
  (( NOW / 1000 % 10 == 0 )) && wake_check
}

srv_line() {
  local line=$1 tag typ from a b c d e f g h i
  case $line in SM1\|*\|srv\|*) return ;; esac
  (( ${#line} <= 2048 )) || return
  IFS='|' read -r tag typ from a b c d e f g h i <<< "$line"
  [[ $tag == SM1 && $from =~ ^[0-9a-f]{6}$ ]] || return
  case $typ in                                        # v6.2: heroes live on the server
    ALOAD) srv_aload "$from" "$a" "$b" "$c"; return ;;
    ASAVE) srv_asave "$from" "$a" "$b" "$c"; return ;;
  esac
  if (( ACCT_ON )); then                              # nobody plays without logging in, and only as the hero they logged in as
    [[ -n ${ACC_NAME[$from]} ]] || { acc_nudge "$from"; return; }
    ACC_SEEN[$from]=$NOW
    case $typ in HELLO|POS) [[ ${a//[^A-Za-z0-9_-]/} == "${ACC_NAME[$from]}" ]] || return ;; esac
  fi
  case $typ in
    HELLO) srv_hello "$from" "$a" ;;
    POS)   # name cls lvl map x y hp maxhp dead sym col
      isnum "$c" && isnum "$e" && isnum "$f" && [[ $d =~ ^(W|D[0-9]+|H[0-9]{1,8})$ ]] || return   # v5.0: H = a room at the inn
      (( c <= 99 && e <= 999 && f <= 999 )) || return
      [[ -n ${SP_NAME[$from]} ]] || srv_hello "$from" "$a"
      SP_LVL[$from]=$c SP_MAP[$from]=$d SP_X[$from]=$e SP_Y[$from]=$f SP_SEEN[$from]=$NOW
      [[ $b =~ ^[0-9]$ ]] && (( b < NCLS )) && SP_CLS[$from]=$b
      if [[ ${i:0:1} == 1 ]]; then
        if [[ ${SP_DEAD[$from]} != 1 ]]; then
          set_wanted "$from" 0                                    # death pays for your crimes
          (( ${IN_MYTH[$d]:-0} )) && { IN_T0[$d]=$(( ${IN_T0[$d]} - 5000 )); send BOSS srv "$d" "${SP_NAME[$from]} has fallen - the clock loses 5 seconds!" 0 0; }
        fi
        SP_DEAD[$from]=1
      else SP_DEAD[$from]=0; fi ;;
    BYE)    srv_drop "$from" ;;
    HIT)    srv_hit "$from" "$a" "$b" "$c" "$d" ;;
    INV)    srv_invite "$from" "$b" ;;
    PACC)   srv_accept "$from" ;;
    PLEAVE) srv_pleave "$from" ;;
    QADD)   srv_qadd "$from" "$a" ;;
    QTALK)  isnum "$a" && [[ -n ${SP_PARTY[$from]} ]] && pq_progress "${SP_PARTY[$from]}" "T.$a" ;;
    DREQ)   srv_dreq "$from" "$a" "$b" ;;
    SYNC)   [[ $a =~ ^(W|D[0-9]+)$ ]] && { SYNC_PEND[$a]=1; sync_flush; } ;;
    ADM)    [[ $a =~ ^[a-z]{1,10}$ ]] || return                 # v6.4: admin tools (03d_admin.sh)
            local args=(); read -r -a args <<< "$b"; srv_adm "$from" "$a" "${args[@]:0:20}" ;;
  esac
}

server_main() {
  local line rc next_ai=0 next_sec=0 tries=0 i
  trap '' PIPE
  trap 'slog "world server stopping"; exit 0' INT TERM
  on_line() { srv_line "$1"; }
  net_lost() { net_up=0; exec 7>&- 2>/dev/null; slog "lost connection to the hub"; }
  load_world
  ACCT_ON=1; [[ $SHELLMMO_OPEN == 1 ]] && ACCT_ON=0       # SHELLMMO_OPEN=1: no logins (old tests)
  (( ACCT_ON )) && acc_init
  slog "shellmmorpg world server v$VERSION - map ${MAPW[W]}x${MAPH[W]} - port $NET_PORT"
  NET_HOST=127.0.0.1
  until net_connect; do
    tries=$(( tries + 1 )); (( tries > 50 )) && { slog "hub not reachable, giving up"; exit 1; }
    sleep 0.2
  done
  now_ms; WH_LAST=$(( NOW / 150 - 1 )); spawn_world; WB_NEXT=$(( NOW + ${SHELLMMO_WB_DELAY:-150000} ))
  SRV_CLK0=$(( NOW - ${SHELLMMO_CLOCK:-480} * GMIN ))      # the world wakes up at 08:00
  for i in "${!WEA_REG[@]}"; do WS_T[i]="" WS_N[i]=$(( NOW + ${SHELLMMO_WEATHER_DELAY:-30000} + (RANDOM << 15 | RANDOM) % 300000 )); done
  send ANN srv "World server online."
  while :; do
    if (( ! net_up )); then
      if [[ $MODE == server ]] && ! alive "$HUB_PID"; then         # v6.3: the dedicated server brings its hub back
        slog "the hub is gone - restarting it"; start_hub && slog "hub restarted"
      fi
      sleep 1; net_connect && { slog "reconnected"; tries=0; continue; }
      tries=$(( tries + 1 )); (( tries > 60 )) && exit 1
      continue
    fi
    IFS= read -r -t 0.04 -u 7 line; rc=$?
    now_ms
    if (( rc == 0 )); then on_line "$net_buf$line"; net_buf=""; net_poll 400
    elif (( rc > 128 )); then net_buf+=$line
    else net_lost; fi
    now_ms
    if (( NOW >= next_ai )); then next_ai=$(( NOW + 150 )); ai_tick; (( ${#SYNC_PEND[@]} )) && sync_flush; fi
    if (( NOW >= next_sec )); then next_sec=$(( NOW + 1000 )); srv_second; fi
  done
}
