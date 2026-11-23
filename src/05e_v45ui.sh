# ---------------------------------------------------------------------------
#  Module 05e - v4.5 screens: paragon (on the talent screen), the mythic gate,
#  Hilda's stable and the mount list, the valor quartermaster, achievements and
#  titles, dailies and weeklies (the quest log's fourth tab).
# ---------------------------------------------------------------------------
TL_PAGE=0 DG_D=-1 DG_K=2 ACH_PG=0

ui_paragon() {
  local p=($PARA_P) i col bar
  para_points; para_next "$PARA"
  ui "  PARAGON $PARA   $PFREE point(s) to spend   [t] talents  [1-6] spend  [x] close" "$K_LOOT$B"
  if (( LVL >= MAXLVL )); then pbar "$XP" "$PNX" 20 $'\e[38;5;220m'; uix "  next paragon level: $PB $XP/$PNX" "  next paragon level: #################### $XP/$PNX"
  else ui "  From level $MAXLVL on, experience turns into paragon levels - a point each." "$K_SYS"; fi
  ui "  Points over 36 talents (level 38-40) count as paragon points too." "$K_SYS"
  ui ""
  for (( i = 0; i < 6; i++ )); do
    col=$K_SYS; (( p[i] > 0 )) && col=$K_GOOD; (( p[i] >= PARA_MAX[i] )) && col=$K_LOOT
    pbar "${p[i]}" "${PARA_MAX[i]}" 12 $'\e[38;5;117m'; bar=$PB
    printf -v PF '  [%d] %-10s %2d/%-2d ' $(( i + 1 )) "${PARA_NAME[i]}" "${p[i]}" "${PARA_MAX[i]}"
    uix "$col$PF$N$bar  ${K_SYS}${PARA_DESC[i]}$N" "$PF############  ${PARA_DESC[i]}"
  done
  ui ""
  ui "  Forget them (with your talents) at any inn." "$K_SYS"
}

# --- the mythic gate: at a dungeon entrance from level 40 ---------------------------------------------------
dgate_open() { DG_D=$1 DG_K=$KEYLV UI=dgate MAP_DIRTY=1; }      # your best key first
ui_dgate() {
  local d=$DG_D
  myth_afx; myth_txt "$DG_K"; myth_limit "$d"
  ui "  ${D_NAME[d]^^}" "$K_LOOT$B"
  ui ""
  ui "  [1] Enter as always (level ${D_REQ[d]})"
  if (( d == RAID_DT )); then
    ui "  The Eclipse Throne is a raid - bring friends. Nyxara grows with every"  "$K_SYS"
    ui "  hero who enters. Stand out of the marked ground, kill her guards when she"  "$K_SYS"
    ui "  hides behind her shield, run when the eclipse is total." "$K_SYS"
  elif (( ${D_RAID[$d]:-0} )); then                              # v8.0: the Sundered Sky
    ui "  The Sundered Sky is a raid for heroes of level 50 - bring friends. Aurelion"  "$K_SYS"
    ui "  grows with every hero who enters. Step off his solar flares, stand between"  "$K_SYS"
    ui "  the beams when he sunders the sky, kill his wardens when the sunfire shields"  "$K_SYS"
    ui "  him - and when he goes supernova, run as far as you can." "$K_SYS"
  else
    uix "  [2] ${K_LOOT}MYTHIC $MYT$N" "  [2] MYTHIC $MYT"
    ui "      [<] [>] key level ($DG_K of +$KEYLV)   time: $(( MYL / 60000 )) min   best: +$MYBEST" "$K_SYS"
    ui ""
    ui "  Mythic: every foe is level $MYTH_LVL and stronger with every key level." "$K_SYS"
    ui "  In time, your key rises (+2 if very fast). Deaths cost 5 seconds." "$K_SYS"
    ui "  The boss pays epic or better gear, perfect gems and valor." "$K_SYS"
    (( DG_K >= 2 )) && ui "  ${MYTH_A[MA]}: ${MYTH_AD[MA]}" "$K_SYS"
    (( DG_K >= 4 )) && ui "  ${CHP_NAME[MB]}: a third of all foes are ${CHP_DESC[MB]}" "$K_SYS"
    (( DG_K >= 7 )) && ui "  ${MYTH_C[MC]}: ${MYTH_CD[MC]}" "$K_SYS"
  fi
  ui ""
  ui "  [esc] step back" "$K_SYS"
}
dgate_key() {
  case $1 in
    1) dgate_go 0 ;;
    2) (( ${D_RAID[$DG_D]:-0} )) || dgate_go "$DG_K" ;;
    LEFT|'<'|,|a|h) (( DG_K > 2 )) && DG_K=$(( DG_K - 1 )) ;;
    RIGHT|'>'|.|d|l) (( DG_K < KEYLV )) && DG_K=$(( DG_K + 1 )) ;;
  esac
}
dgate_go() {  # mythic level (0 = normal)
  UI="" NEED_FULL=1
  (( NOW < dreq_until )) && return
  dreq_until=$(( NOW + 4000 ))
  send DREQ "$MY_ID" "$DG_D" "$1"
  if (( $1 )); then myth_txt "$1"; logm "You turn your key: Mythic $MYT..." "$K_LOOT"
  else logm "You open the gate to the ${D_NAME[DG_D]}..." "$K_SYS"; fi
}

# --- mounts: Hilda's stable, and [Z] to choose yours ------------------------------------------------------------------
ui_stable() {
  local i st col hilda=0
  [[ $STABLE_SRC == talk && ${N_ROLE[${TALK_T:-0}]:-} == stable ]] && hilda=1
  if (( hilda )); then ui "  ${N_FULL[$TALK_T]^^}'S STABLE   [key] buy   [enter] ride the chosen one   [esc] close" "$K_LOOT$B"
  else ui "  YOUR MOUNTS   [1-9 a-d] choose   [z] mount / dismount   [esc] close" "$K_LOOT$B"; fi
  ui ""
  for (( i = 0; i < NMNT; i++ )); do
    if mount_has "$i"; then st="owned"; col=$K_GOOD; (( i == MNT_CUR )) && st="owned - riding this one" col=$K_LOOT
    else st=${MNT_SRC[i]}; col=$K_SYS; fi
    printf -v PF '%-15s +%3d%%  ' "${MNT_NAME[i]}" "${MNT_SPD[i]}"
    if (( TW2 )); then uix "  [${MNT_KEYS:i:1}] ${MNT_E[i]} $col$PF$N${K_SYS}$st$N" "  [${MNT_KEYS:i:1}] xx $PF$st"
    else uix "  [${MNT_KEYS:i:1}] $col$PF$N${K_SYS}$st$N" "  [${MNT_KEYS:i:1}] $PF$st"; fi
  done
  ui ""
  ui "  On horseback you travel faster. Fighting or getting hit throws you off," "$K_SYS"
  ui "  and mounts stay outside dungeons." "$K_SYS"
}
stable_key() {
  local i
  case $1 in
    [1-9a-d]) i=${MNT_KEYS%%"$1"*}; i=${#i}; (( i < NMNT )) || return
           if [[ $STABLE_SRC == talk ]] && (( MNT_GOLD[i] > 0 )) && ! mount_has "$i"; then mount_buy "$i"
           elif mount_has "$i"; then MNT_CUR=$i; logm "You will ride the ${MNT_NAME[i]}." "$K_GOOD"
           else logm "${MNT_NAME[i]}: ${MNT_SRC[i]}." "$K_SYS"; fi ;;
    z|$'\r'|'') UI="" NEED_FULL=1; mount_toggle ;;
  esac
}

# --- the valor quartermaster ------------------------------------------------------------------------------------------
ui_valor() {
  local i col
  ui "  VALOR QUARTERMASTER   you have $VALOR valor   [1-9] buy   [esc] close" "$K_LOOT$B"
  ui ""
  for (( i = 0; i < ${#VW_NAME[@]}; i++ )); do
    col=$K_SYS; (( VALOR >= VW_COST[i] )) && col=$K_GOOD
    printf -v PF '  [%d] %-42s %5d valor' $(( i + 1 )) "${VW_NAME[i]}" "${VW_COST[i]}"
    ui "$PF" "$col"
  done
  ui ""
  ui "  Valor: Mythic dungeons (more for higher keys), the Eclipse Throne," "$K_SYS"
  ui "  invasions, dailies (30) and weeklies (150)." "$K_SYS"
}
valor_key() { [[ $1 == [1-9] ]] && valor_buy $(( $1 - 1 )); }

# --- achievements -------------------------------------------------------------------------------------------------------
ui_ach() {
  local i n=0 a nm what tt col per first last mark
  for (( i = 0; i < NACH; i++ )); do [[ ${ACHS:i:1} == 1 ]] && n=$(( n + 1 )); done
  my_title
  ui "  ACHIEVEMENTS  $n/$NACH   title: ${TTL:-none}   [t] change title  [<][>] page  [o] close" "$K_LOOT$B"
  ui ""
  per=$(( VH - 4 )); (( per < 8 )) && per=8
  first=$(( ACH_PG * per )); (( first >= NACH )) && { ACH_PG=0; first=0; }
  last=$(( first + per )); (( last > NACH )) && last=$NACH
  for (( i = first; i < last; i++ )); do
    a=${ACH[i]}; nm=${a%%:*} a=${a#*:} what=${a%%:*} tt=${a#*:}
    if [[ ${ACHS:i:1} == 1 ]]; then col=$K_LOOT mark="*"; (( TW2 )) && mark="🏆"; else col=$K_SYS mark="."; (( TW2 )) && mark="  "; fi
    printf -v PF '%-16s %s' "$nm" "$what"
    [[ -n $tt ]] && PF+="  (title: $tt)"
    if (( TW2 )); then uix "  $mark $col$PF$N" "  xx $PF"; else uix "  $mark $col$PF$N" "  x $PF"; fi
  done
}
ach_key() {
  case $1 in
    t) title_next ;;
    RIGHT|'>'|.|d|l|' ') ACH_PG=$(( ACH_PG + 1 )) ;;
    LEFT|'<'|,|a|h) (( ACH_PG > 0 )) && ACH_PG=$(( ACH_PG - 1 )) ;;
  esac
}

# --- dailies and weeklies (quest log, tab 4) ---------------------------------------------------------------------------
ui_dailies() {
  local i a e need col mk
  dly_fix
  if (( LVL < 30 )); then ui "  Dailies and weeklies open at level 30." "$K_SYS"; return; fi
  ui "  TODAY" "$B"
  a=($DAILY)
  for (( i = 0; i < ${#DLY_CUR[@]}; i++ )); do
    e=(${a[i+1]//:/ }); need=${DLY_CUR[i]#*:}; need=${need%%:*}; dly_text "${DLY_CUR[i]}"
    col=$K_CHAT; (( e[2] )) && col=$K_GOOD
    mk="."; (( e[2] )) && mk="+"
    printf -v PF '  %s %-46s %s/%s' "$mk" "$DTX" "${e[1]}" "$need"
    ui "$PF" "$col"
  done
  ui "  each: 30 valor, gold and experience - new tasks every day" "$K_SYS"
  ui ""
  ui "  THIS WEEK" "$B"
  a=($WEEKLY)
  for (( i = 0; i < ${#WKY_CUR[@]}; i++ )); do
    e=(${a[i+1]//:/ }); need=${WKY_CUR[i]#*:}; need=${need%%:*}; dly_text "${WKY_CUR[i]}"
    col=$K_CHAT; (( e[2] )) && col=$K_GOOD
    mk="."; (( e[2] )) && mk="+"
    printf -v PF '  %s %-46s %s/%s' "$mk" "$DTX" "${e[1]}" "$need"
    ui "$PF" "$col"
  done
  ui "  each: 150 valor, a perfect gem and lots of experience" "$K_SYS"
  ui ""
  myth_afx
  ui "  MYTHIC   your key: +$KEYLV   best in time: +$MYBEST   valor: $VALOR" "$B"
  ui "  this week: ${MYTH_A[MA]} (+2), ${CHP_NAME[MB]} (+4), ${MYTH_C[MC]} (+7)" "$K_SYS"
}
