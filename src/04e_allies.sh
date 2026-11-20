# ---------------------------------------------------------------------------
#  Module 04e - allies (since v2.0): companions who follow you everywhere,
#  fight what you fight and patch you up. Everyone sees them next to you.
# ---------------------------------------------------------------------------
ALLIES="" ALLY=-1 AX=0 AY=0 ALY_MAP="" ALY_NEXT=0 ALY_HEALT=0 ALY_LAST=""
declare -A OP_ALY=() OP_AX=() OP_AY=()
ALY_E=(🤺 🧝 👼 🐺 🦉 🧞 🐲 💀 "${ALY_E_X[@]}")
ALY_KEYS="1234567890-="                          # the key that calls ally i
for (( i = 0; i < NALY; i++ )); do
  GLY[a$i]=$'\e[0;1;38;5;16;48;5;35m'"${ALY_G[i]}" GLYH[a$i]=$'\e[0;48;5;28m'"${ALY_E[i]}"
done

aly_fix() { while (( ${#ALLIES} < NALY )); do ALLIES+="0"; done; ALLIES=${ALLIES:0:NALY}; }
aly_has() { [[ ${ALLIES:$1:1} == 1 ]]; }
aly_unlock() {  # index -> calls it to your side unless someone is already there
  aly_fix
  ALLIES="${ALLIES:0:$1}1${ALLIES:$1+1}"
  (( ALLY < 0 )) && aly_summon "$1" quiet
  logm "${ALY_E[$1]} ${ALY_NAME[$1]} joins you! [y] calls or sends home your allies." "$K_ANN"
}

aly_place() {  # put the ally on a free tile next to me (after a teleport, a dungeon, a summon)
  local c x y
  ALY_MAP=$CUR_MAP AX=$PX AY=$PY
  for c in "$(( -FDX )),$(( -FDY ))" -1,0 1,0 0,1 0,-1 -1,1 1,1 -1,-1 1,-1; do
    x=$(( PX + ${c%,*} )) y=$(( PY + ${c#*,} ))
    (( x == PX && y == PY )) && continue
    p_walk "$CUR_MAP" "$x" "$y" || continue
    mon_at "$x" "$y" && continue
    AX=$x AY=$y; break
  done
  POS_DIRTY=1 MAP_DIRTY=1
}

aly_summon() {  # index [quiet]
  local i=$1
  aly_has "$i" || return
  ALLY=$i ALY_NEXT=$(( NOW + 600 )); aly_place
  [[ $2 == quiet ]] || logm "${ALY_E[i]} ${ALY_SHORT[i]} is at your side." "$K_GOOD"
}

aly_dismiss() {
  (( ALLY >= 0 )) || return
  logm "${ALY_SHORT[ALLY]} heads home for a rest." "$K_SYS"
  ALLY=-1 POS_DIRTY=1 MAP_DIRTY=1
}

aly_follow() {  # old-x old-y: called after every step I take
  (( ALLY >= 0 )) || return
  if [[ $ALY_MAP != "$CUR_MAP" ]]; then aly_place; return; fi
  cheb $(( AX - PX )) $(( AY - PY ))
  if (( D > 4 )); then aly_place
  elif (( D > 1 )); then AX=$1 AY=$2; fi
}

aly_target() {  # -> AT: what my ally should hit (my target, whoever hits me, foes right next to me)
  local m best=99
  AT=""
  for m in "$TARGET" "$ALY_LAST"; do
    [[ -n $m && -n ${CM_T[$m]} ]] && (( ${CM_HP[$m]:-1} > 0 )) && hostile "$m" || continue
    cheb $(( CM_X[m] - PX )) $(( CM_Y[m] - PY )); (( D <= 8 )) && { AT=$m; return 0; }
  done
  mons_rect $(( PX - 2 )) $(( PY - 2 )) $(( PX + 2 )) $(( PY + 2 ))
  for m in "${MR[@]}"; do                          # anything already fighting me at close range
    (( M_KIND[${CM_T[m]}] == 0 && M_AGGRO[${CM_T[m]}] > 0 )) || continue
    cheb $(( CM_X[m] - PX )) $(( CM_Y[m] - PY )); (( D <= 2 && D < best )) && { best=$D; AT=$m; }
  done
  [[ -n $AT ]]
}

aly_step_to() {  # x y: one step towards it, never too far from me
  local dx=$(( $1 - AX )) dy=$(( $2 - AY )) sx sy c nx ny
  sx=$(( dx > 0 ? 1 : (dx < 0 ? -1 : 0) )) sy=$(( dy > 0 ? 1 : (dy < 0 ? -1 : 0) ))
  for c in "$sx,$sy" "$sx,0" "0,$sy" "$sx,1" "$sx,-1" "1,$sy" "-1,$sy" 0,1 0,-1 1,0 -1,0; do
    nx=$(( AX + ${c%,*} )) ny=$(( AY + ${c#*,} ))
    (( nx == AX && ny == AY )) && continue
    (( nx == PX && ny == PY )) && continue
    p_walk "$CUR_MAP" "$nx" "$ny" || continue
    mon_at "$nx" "$ny" && continue
    cheb $(( nx - PX )) $(( ny - PY )); (( D <= 5 )) || continue
    AX=$nx AY=$ny POS_DIRTY=1 MAP_DIRTY=1; return 0
  done
  return 1
}

aly_hit() {  # mid pct
  local m=$1 d
  [[ -n ${CM_T[$m]} ]] || return
  d=$(( ATK * $2 / 100 * (100 + ${TB_ALY:-0}) / 100 * (85 + RANDOM % 31) / 100 )); (( d < 1 )) && d=1
  (( RANDOM % 100 < 8 )) && d=$(( d * 2 ))
  send HIT "$MY_ID" "$CUR_MAP" "$m" "$d" 0
  CM_HP[$m]=$(( CM_HP[$m] - d )); (( CM_HP[$m] < 0 )) && CM_HP[$m]=0
  HITF[$m]=$NOW
  ft_add "${CM_X[$m]}" "${CM_Y[$m]}" "$d" $'\e[0;1;38;5;16;48;5;78m'
}

aly_tick() {
  (( ALLY >= 0 && ! DEAD && NOW >= ALY_NEXT )) || return
  [[ $ALY_MAP == "$CUR_MAP" ]] || { aly_place; return; }
  cheb $(( AX - PX )) $(( AY - PY )); (( D > 6 )) && { aly_place; return; }     # after a respawn, recall or waystone
  local i=$ALLY role=${ALY_ROLE[$ALLY]} m n h
  ALY_NEXT=$(( NOW + 250 ))
  if [[ $role == heal ]] && (( HP < MAXHP * 85 / 100 && NOW >= ALY_HEALT )); then
    heal_amount; h=$(( HEALV * 55 / 100 + MAXHP / 12 ))
    HP=$(( HP + h )); (( HP > MAXHP )) && HP=$MAXHP
    ft_add "$PX" "$PY" "+$h" $'\e[0;1;38;5;16;48;5;120m'
    add_fx holy "$PX,$PY" 1
    ALY_HEALT=$(( NOW + 4000 )) ALY_NEXT=$(( NOW + ALY_CD[i] )) POS_DIRTY=1 MAP_DIRTY=1
    return
  fi
  aly_target || return
  m=$AT
  cheb $(( CM_X[m] - AX )) $(( CM_Y[m] - AY ))
  if (( D > ALY_RNG[i] )); then                     # walk over (melee) or close in (ranged)
    aly_step_to "${CM_X[m]}" "${CM_Y[m]}"; ALY_NEXT=$(( NOW + 220 )); return
  fi
  aly_hit "$m" "${ALY_PCT[i]}"
  case $role in
    magic)                                           # splash: everything next to the target
      mons_rect $(( CM_X[m] - 1 )) $(( CM_Y[m] - 1 )) $(( CM_X[m] + 1 )) $(( CM_Y[m] + 1 ))
      for n in "${MR[@]}"; do
        [[ $n == "$m" ]] && continue
        cheb $(( CM_X[n] - CM_X[m] )) $(( CM_Y[n] - CM_Y[m] )); (( D <= 1 )) || continue
        hostile "$n" && aly_hit "$n" $(( ALY_PCT[i] * 60 / 100 ))
      done
      if (( i == 6 )); then add_fx fire "${CM_X[m]},${CM_Y[m]}" 1; else add_fx sound "${CM_X[m]},${CM_Y[m]}" 1; fi ;;
    ranged) add_fx bone "${CM_X[m]},${CM_Y[m]}" ;;
    *)      add_fx slash "${CM_X[m]},${CM_Y[m]}" 1 ;;
  esac
  ALY_NEXT=$(( NOW + ALY_CD[i] ))
  MAP_DIRTY=1
}

aly_key() {  # [y] panel: 1-8 call an ally, x sends it home
  case $1 in
    [0-9]|-|=) local k=${ALY_KEYS%%"$1"*} i
           i=${#k}
           if (( i >= NALY )); then return
           elif ! aly_has "$i"; then logm "You have not hired ${ALY_NAME[i]} yet." "$K_HURT"
           elif (( ALLY == i )); then aly_dismiss
           else aly_summon "$i"; fi ;;
    x|X) aly_dismiss ;;
  esac
}

ally_shop_key() {  # a mercenary's list: buy the companion with the number
  local i n=0 k
  for (( i = 0; i < NALY; i++ )); do
    (( ALY_SELL[i] == TALK_T )) || continue
    n=$(( n + 1 )); [[ $1 == "$n" ]] || continue
    if aly_has "$i"; then logm "${ALY_SHORT[i]} already travels with you - call them with [y]." "$K_SYS"; return; fi
    (( GOLD >= ALY_COST[i] )) || { logm "${ALY_SHORT[i]} costs ${ALY_COST[i]} gold." "$K_HURT"; return; }
    GOLD=$(( GOLD - ALY_COST[i] )); aly_unlock "$i"; save_char; return
  done
}

ui_allies() {
  local i st col n=0
  ui "  ALLIES - companions who fight at your side" "$K_LOOT$B"
  ui "  One ally walks with you at a time. Hire more from mercenaries in town." "$K_SYS"
  ui ""
  aly_fix
  local long=$(( VH >= NALY * 2 + 6 )) kc
  for (( i = 0; i < NALY; i++ )); do
    kc=${ALY_KEYS:i:1}
    if (( ALLY == i )); then st="with you" col=$K_GOOD
    elif aly_has "$i"; then st="ready" col=$K_CHAT
    elif (( ALY_SELL[i] >= 0 )); then st="hire: ${N_FULL[${ALY_SELL[i]}]}, ${ALY_COST[i]}g" col=$K_SYS
    else st="joins you on your story" col=$K_SYS; fi
    if (( TW2 )); then uix "  [$kc] ${GLYH[a$i]}$N ${col}$(printf '%-22s' "${ALY_NAME[i]}") $st$N" "  [$kc] xx $(printf '%-22s' "${ALY_NAME[i]}") $st"
    else uix "  [$kc] ${GLY[a$i]}$N ${col}$(printf '%-22s' "${ALY_NAME[i]}") $st$N" "  [$kc] x $(printf '%-22s' "${ALY_NAME[i]}") $st"; fi
    (( long )) && ui "        ${ALY_DESC[i]}" "$K_SYS"
  done
  ui ""
  ui "  [1-9 0 - =] call / send home   [x] send home   [y] or [esc] close" "$K_SYS"
}

ui_allyshop() {
  local i n=0
  [[ -n ${CM_T[$TALK_MID]} ]] || { UI=""; return; }
  ui "  ${N_FULL[$TALK_T]^^}'S COMPANIONS" "$K_LOOT$B"
  ui "  You have ${EMJ[gold]}$GOLD gold. Hired allies follow you forever - [y] calls them."
  ui ""
  aly_fix
  for (( i = 0; i < NALY; i++ )); do
    (( ALY_SELL[i] == TALK_T )) || continue
    n=$(( n + 1 ))
    local h="" row; aly_has "$i" && h="  - hired"
    printf -v row '%-22s %6sg%s' "${ALY_NAME[i]}" "${ALY_COST[i]}" "$h"
    if (( TW2 )); then uix "  [$n] ${GLYH[a$i]}$N $row" "  [$n] xx $row"
    else ui "  [$n] ${ALY_G[i]} $row"; fi
    ui "        ${ALY_DESC[i]}  (${ALY_ROLE[i]})" "$K_SYS"
  done
  ui ""
  ui "  [1-$n] hire   [esc] leave" "$K_SYS"
}
