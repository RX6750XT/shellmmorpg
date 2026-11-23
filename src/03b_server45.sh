# ---------------------------------------------------------------------------
#  Module 03b - v4.5 world server: mythic dungeons (scaling, affixes, the clock,
#  rewards), the raid boss Nyxara, invasions, delayed area attacks, loot that
#  is handed out directly (LOOT i:<code>).
# ---------------------------------------------------------------------------

inst_mon() {  # map type x y party-scale mythic-level: a monster of an instance
  local map=$1 t=$2 sc=$5 mk=${6:-0} md=100
  if (( mk )); then
    myth_scale "$t" "$mk" "$sc"; sc=$MSC md=$MDSC
  fi
  spawn_mon "$map" "$t" "$3" "$4" -1 "$sc"
  MDS[MID]=$md
  if (( mk >= 4 && M_BOSS[t] == 0 && M_KIND[t] == 0 && RANDOM % 3 == 0 )); then   # this week's champion affix
    myth_afx; MCH[MID]=$MB
  fi
}

myth_scale() {  # type key-level party-scale -> MSC (health, xp, gold %) MDSC (damage %)
  local t=$1 k=$2 h d
  base_stats "${M_LVL[t]}"; h=$BH d=$BD
  base_stats "$MYTH_LVL"
  MSC=$(( $3 * BH / h * (100 + 12 * k) / 100 )) MDSC=$(( 100 * BD / d * (100 + 6 * k) / 100 ))
  myth_afx
  if (( MA == 0 && M_BOSS[t] == 0 )); then MSC=$(( MSC * 130 / 100 )) MDSC=$(( MDSC * 115 / 100 ))       # fortified
  elif (( MA == 1 && M_BOSS[t] )); then MSC=$(( MSC * 140 / 100 )) MDSC=$(( MDSC * 120 / 100 )); fi     # tyrannical
}

myth_bolster() {  # mid that just died: its friends nearby grow stronger
  local m=$1 map=${MMAP[$1]} o
  for o in ${IN_MONS[$map]}; do
    (( MALIVE[o] && M_BOSS[MT[o]] == 0 && M_KIND[MT[o]] == 0 )) || continue
    cheb $(( MX[o] - MX[m] )) $(( MY[o] - MY[m] )); (( D <= 6 )) || continue
    MHP[o]=$(( MHP[o] + MMAX[o] / 5 )); (( MHP[o] > MMAX[o] )) && MHP[o]=${MMAX[o]}
    MDS[o]=$(( ${MDS[o]:-100} + 15 ))
    send MHP srv "$map" "$o" "${MHP[o]}" ""
  done
}

srv_loot() {  # player slot tier rarity sockets -> sends LOOT i:<code> (gear for the player's class)
  local p=$1 s=$2 r
  [[ $s == "?" ]] && { r=$(( RANDOM % 100 )); if (( r < 34 )); then s=W; elif (( r < 56 )); then s=A; elif (( r < 72 )); then s=H; elif (( r < 86 )); then s=O; else s=J; fi; }
  kind_pick "$s" "${SP_CLS[$p]:-0}"
  ITEM="$s.$KP.$3.$4"
  (( $5 > 0 )) && { ITEM+=.; for (( r = 0; r < $5; r++ )); do ITEM+=__; done; }
  send LOOT srv "$p" "i:$ITEM"
}

myth_finish() {  # map: the boss of a mythic dungeon is dead
  local map=$1 k=${IN_MYTH[$1]} el=$(( NOW - ${IN_T0[$1]} )) lim=${IN_LIM[$1]} up=0 val p r n=0 names=""
  (( el <= lim )) && up=1; (( el <= lim * 6 / 10 )) && up=2
  val=$(( 20 + 6 * k )); (( up )) && val=$(( val * 3 / 2 ))
  for p in "${!SP_NAME[@]}"; do
    [[ ${SP_MAP[$p]} == "$map" ]] || continue
    n=$(( n + 1 )); names+="${SP_NAME[$p]}, "
    send MDONE srv "$p" "$k" "$up" $(( el / 1000 )) "$val"
    r=2; (( RANDOM % 100 < 5 + 2 * k )) && r=3
    tier_for "$MYTH_LVL"; srv_loot "$p" "?" "$TF" "$r" $(( r == 3 ? 3 : 1 + RANDOM % 2 ))     # v8.0: the gear of the level cap
    (( RANDOM % 100 < 10 + 3 * k )) && { gem_mat $(( RANDOM % 6 )) 4; send LOOT srv "$p" "g$GM"; }
  done
  if (( up )); then send ANN srv "${names%, } completed ${D_NAME[${IN_TYPE[$map]}]} on Mythic +$k in time!"
  else send ANN srv "${names%, } completed ${D_NAME[${IN_TYPE[$map]}]} on Mythic +$k (too slow)."; fi
}

# --- the raid boss -----------------------------------------------------------------------------------------------
raid_adds_alive() {  # boss mid -> 0 if one of her guards still lives
  local o
  for o in ${IN_MONS[${MMAP[$1]}]}; do (( MALIVE[o] && ${MADD[o]:--1} == $1 )) && return 0; done
  return 1
}
aoe_add() {  # map x y radius delay dmg element mid: marked ground, then the blow
  local c="" i j
  for (( j = -$4; j <= $4; j++ )); do for (( i = -$4; i <= $4; i++ )); do c+="$(( $2 + i )),$(( $3 + j )) "; done; done
  send FX srv "$1" warn "$c"
  AOE_Q+=("$(( NOW + $5 )) $1 $2 $3 $4 $6 $7 $8")
}
aoe_tick() {
  local i a q c j k
  for i in "${!AOE_Q[@]}"; do
    a=(${AOE_Q[i]})
    (( NOW >= a[0] )) || continue
    unset "AOE_Q[i]"
    c=""; for (( j = -a[4]; j <= a[4]; j++ )); do for (( k = -a[4]; k <= a[4]; k++ )); do c+="$(( a[2] + k )),$(( a[3] + j )) "; done; done
    send FX srv "${a[1]}" fire "$c"
    for q in ${PLIST[${a[1]}]}; do
      cheb $(( ${SP_X[$q]} - a[2] )) $(( ${SP_Y[$q]} - a[3] ))
      (( D <= a[4] )) && send MATK srv "${a[1]}" "${a[7]}" "$q" "${a[5]}" "${a[6]}" ""
    done
  done
  AOE_Q=("${AOE_Q[@]}")
}
raid_attack() {  # boss target damage: Nyxara's three phases
  local m=$1 t=${MT[$1]} map=${MMAP[$1]} dmg=$3 q n=0
  (( NOW - ${IN_T0[$map]:-$NOW} > 480000 )) && dmg=$(( dmg * 2 ))       # 8 minutes: the eclipse devours everything
  MATKN[m]=$(( MATKN[m] + 1 ))
  if (( MHP[m] * 3 < MMAX[m] && MATKN[m] % 5 == 0 )); then                # phase 3: total eclipse - run!
    send BOSS srv "$map" "${M_NAME[t]}: TOTAL ECLIPSE! Get away from her!" "${MX[m]}" "${MY[m]}"
    aoe_add "$map" "${MX[m]}" "${MY[m]}" 4 2200 $(( dmg * 35 / 10 )) 4 "$m"; return
  fi
  if (( MATKN[m] % 3 == 0 )); then                                        # eclipse meteors on everyone
    send BOSS srv "$map" "${M_NAME[t]} calls down the dark stars - move!" "${MX[m]}" "${MY[m]}"
    for q in ${PLIST[$map]}; do
      (( n++ < 5 )) || break
      aoe_add "$map" "${SP_X[$q]}" "${SP_Y[$q]}" 1 1800 $(( dmg * 22 / 10 )) 6 "$m"
    done
    return
  fi
  mon_hit "$m" "$2" "$dmg"
}
raid_finish() {  # map: the raid boss is dead (v8.0: raid 1 Nyxara, raid 2 Aurelion)
  local map=$1 p names="" r=${D_RAID[${IN_TYPE[$1]}]:-1} tier=12 uq
  uq=("${RAID_UQ[@]}"); (( r == 2 )) && { uq=("${RAID2_UQ[@]}"); tier=$MAXTIER; }
  for p in "${!SP_NAME[@]}"; do
    [[ ${SP_MAP[$p]} == "$map" ]] || continue
    names+="${SP_NAME[$p]}, "
    srv_loot "$p" "?" "$tier" 3 3
    (( RANDOM % 100 < 40 )) && send LOOT srv "$p" "i:U.${uq[RANDOM % ${#uq[@]}]}"
    (( RANDOM % 2 )) && { gem_mat $(( RANDOM % 6 )) 4; send LOOT srv "$p" "g$GM"; }
  done
  send ANN srv "${names%, } brought down ${RAID_NAME[r]}! ${RAID_ANN[r]}"
}
raid2_attack() {  # boss target damage: Aurelion, the Sundered Sun - flares, the sundering, the supernova
  local m=$1 t=${MT[$1]} map=${MMAP[$1]} dmg=$3 q n=0
  (( NOW - ${IN_T0[$map]:-$NOW} > 600000 )) && dmg=$(( dmg * 2 ))       # 10 minutes: the sun burns everything
  MATKN[m]=$(( MATKN[m] + 1 ))
  if (( MHP[m] * 4 < MMAX[m] && MATKN[m] % 6 == 0 )); then                # below a quarter: supernova - get far away
    send BOSS srv "$map" "${M_NAME[t]}: SUPERNOVA! Run, as far as you can!" "${MX[m]}" "${MY[m]}"
    aoe_add "$map" "${MX[m]}" "${MY[m]}" 6 3000 $(( dmg * 5 )) 1 "$m"; return
  fi
  if (( MHP[m] * 2 < MMAX[m] && MATKN[m] % 4 == 0 )); then                # below half: the sundering - a cross of fire
    send BOSS srv "$map" "${M_NAME[t]} sunders the sky - stand between the beams!" "${MX[m]}" "${MY[m]}"
    for q in -4 -2 2 4; do
      aoe_add "$map" "${MX[m]}" $(( MY[m] + q )) 1 2200 $(( dmg * 3 )) 1 "$m"
      aoe_add "$map" $(( MX[m] + q )) "${MY[m]}" 1 2200 $(( dmg * 3 )) 1 "$m"
    done
    return
  fi
  if (( MATKN[m] % 3 == 0 )); then                                        # solar flares under everyone
    send BOSS srv "$map" "${M_NAME[t]} calls down solar flares - move!" "${MX[m]}" "${MY[m]}"
    for q in ${PLIST[$map]}; do
      (( n++ < 6 )) || break
      aoe_add "$map" "${SP_X[$q]}" "${SP_Y[$q]}" 1 1700 $(( dmg * 2 )) 5 "$m"
    done
    return
  fi
  mon_hit "$m" "$2" "$dmg"
}

# --- invasions: now and then the Horde marches on a town ------------------------------------------------------------
inv_towns() {  # -> INV_T: "x y questgiver" of every town that has someone to give quests
  local t w a
  INV_T=()
  for t in "${!N_ROLE[@]}"; do
    [[ -n ${N_QK[$t]} && -n ${N_HOME[$t]} ]] || continue
    for w in "${WAYSTONES[@]}"; do a=($w); [[ ${a[0]//_/ } == "${N_HOME[$t]}" ]] && { INV_T+=("${a[1]} ${a[2]} $t"); break; }; done
  done
}
inv_second() {  # once a second
  local n=0 p m alive=0
  if (( INV_TOWN < 0 )); then
    (( INV_NEXT )) || INV_NEXT=$(( NOW + ${SHELLMMO_INV_DELAY:-2400000} + RANDOM % 900000 ))
    (( NOW >= INV_NEXT )) || return
    for p in "${!SP_NAME[@]}"; do [[ ${SP_MAP[$p]} == W ]] && n=$(( n + 1 )); done
    (( n )) || { INV_NEXT=$(( NOW + 120000 )); return; }
    inv_start; return
  fi
  for m in $INV_MONS; do (( MALIVE[m] )) && alive=$(( alive + 1 )); done
  if (( NOW >= INV_END )); then
    for m in $INV_MONS; do (( MALIVE[m] )) && { MALIVE[m]=0; unset "AL[$m]" "OCC[W:${MX[m]}:${MY[m]}]"; send MDIE srv W "$m" "-"; }; done
    send ANN srv "The Horde has sacked ${N_HOME[${INV_Q}]}... it will be rebuilt, but nobody is paid for a defeat."
    inv_end; return
  fi
  (( alive )) && return
  if (( INV_WAVE < 3 )); then INV_WAVE=$(( INV_WAVE + 1 )); inv_wave; return; fi
  inv_win
}
inv_start() {
  local a
  (( ${#INV_T[@]} )) || inv_towns
  (( ${#INV_T[@]} )) || { INV_NEXT=$(( NOW + 600000 )); return; }
  INV_TOWN=$(( RANDOM % ${#INV_T[@]} )); a=(${INV_T[INV_TOWN]})
  INV_X=${a[0]} INV_Y=${a[1]} INV_Q=${a[2]} INV_WAVE=1 INV_END=$(( NOW + 720000 )) INV_MONS="" INV_PART=()
  send ANN srv "THE HORDE MARCHES ON ${N_HOME[$INV_Q]^^}! Defend the town - three waves, twelve minutes."
  inv_wave
}
inv_wave() {  # spawns the next wave around the town
  local k=(${N_QK[$INV_Q]}) n i tries t
  case $INV_WAVE in 1) n=8 ;; 2) n=10 ;; *) n=4 ;; esac
  INV_MONS=""
  for (( i = 0; i < n + (INV_WAVE == 3); i++ )); do
    t=${k[RANDOM % ${#k[@]}]}
    (( INV_WAVE == 3 && i == n )) && t=${D_ELITE[${N_QD[$INV_Q]:-0}]}
    for (( tries = 0; tries < 25; tries++ )); do
      free_tile $(( INV_X - 16 )) $(( INV_Y - 12 )) $(( INV_X + 16 )) $(( INV_Y + 12 )) W || continue
      in_safe_xy "$SX" "$SY" || break
    done
    (( tries < 25 )) || continue
    spawn_mon W "$t" "$SX" "$SY" -4 $(( INV_WAVE == 3 && i == n ? 300 : 120 )) 6
    MEV[MID]=1; INV_MONS+=" $MID"
    (( INV_WAVE == 2 && i < 3 )) && { MCH[MID]=$(( RANDOM % NCHP )); MMAX[MID]=$(( MMAX[MID] * 2 )) MHP[MID]=${MMAX[MID]}; }
    mon_state "$MID"
  done
  case $INV_WAVE in
    1) send ANN srv "The first wave reaches ${N_HOME[$INV_Q]}!" ;;
    2) send ANN srv "A second wave, with champions, storms ${N_HOME[$INV_Q]}!" ;;
    3) send ANN srv "The warlord of the Horde himself attacks ${N_HOME[$INV_Q]}!" ;;
  esac
}
inv_win() {
  local p l
  for p in "${!INV_PART[@]}"; do
    [[ -n ${SP_NAME[$p]} ]] || continue
    l=${SP_LVL[$p]:-1}
    send EVREW srv "$p" 25 $(( 40 * l * l + 400 )) $(( 30 * l + 200 ))
    tier_for "$l"; srv_loot "$p" "?" "$TF" 2 1
  done
  send ANN srv "${N_HOME[$INV_Q]} is saved! The defenders are paid in valor."
  inv_end
}
inv_end() { INV_TOWN=-1 INV_WAVE=0 INV_MONS="" INV_NEXT=$(( NOW + ${SHELLMMO_INV_DELAY:-2400000} + RANDOM % 900000 )); }
