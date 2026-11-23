# ---------------------------------------------------------------------------
#  Module 05f - v5.0 screens: the rooms at the inn (renting, the door,
#  visiting), a display in your room, the collection book, the guestbook.
# ---------------------------------------------------------------------------

# --- the innkeeper: rooms upstairs -------------------------------------------------------------------------------
ui_inn() {
  local i cost col st wide=0
  (( MW >= 70 && VH >= 23 )) && wide=1
  rent_week
  ui "  ROOMS AT THE INN" "$K_LOOT$B"
  ui "  Every inn of the realm keeps your room ready for you." "$K_SYS"
  ui ""
  if (( ROOM_T )); then
    room_shown
    ui "  Your ${ROOM_NAME[ROOM_T]}: $RSH/${ROOM_NDSP[ROOM_T]} on display, chest ${#ROOMC[@]}/${ROOM_CAP[ROOM_T]}" "$B"
    if (( ROOM_PAID >= RWK )); then ui "  Rent ${ROOM_RENT[ROOM_T]}g a week - paid for this week." "$K_GOOD"
    else ui "  Rent ${ROOM_RENT[ROOM_T]}g a week - due when you go up." "$K_LOOT"; fi
    ui "  [1] Go up to my room" "$K_GOOD$B"
  else
    ui "  Rent a room: a bed to wake up Well Rested, a chest" "$K_CHAT"
    ui "  and displays to show off your treasures." "$K_CHAT"
  fi
  ui ""
  for (( i = 1; i <= NROOM; i++ )); do
    cost=$(( ROOM_COST[i] - ROOM_COST[ROOM_T] ))
    if (( i == ROOM_T )); then st="your room" col=$K_GOOD
    elif (( i < ROOM_T )); then st="smaller than yours" col=$K_SYS
    elif (( LVL < ROOM_LVL[i] )); then st="from level ${ROOM_LVL[i]}" col=$K_SYS
    else
      st="${cost}g + ${ROOM_RENT[i]}g/week"; (( ROOM_T )) && st="move up: ${cost}g"
      col=$K_CHAT; (( GOLD >= cost )) || col=$K_HURT
    fi
    printf -v PF '  [%d] %-12s %s' $(( i + 1 )) "${ROOM_NAME[i]}" "$st"
    ui "$PF" "$col"
    printf -v PF '      %d displays, chest %d, rested +%d%%' "${ROOM_NDSP[i]}" "${ROOM_CAP[i]}" "${ROOM_REST[i]}"
    ui "$PF" "$K_SYS"
    (( wide )) && ui "      ${ROOM_DESC[i]}" "$K_SYS"
  done
  ui ""
  (( ROOM_T )) && ui "  [d] door: ${DOOR_NAME[ROOM_DOOR]}"
  ui "  [v] visit a friend's room   [esc] back" "$K_SYS"
}
inn_key() {
  case $1 in
    1) room_home ;;
    [2-9]) (( $1 - 1 <= NROOM )) && room_rent $(( $1 - 1 )) ;;
    d) (( ROOM_T )) && door_next ;;
    v) visit_ask ;;
  esac
}

# --- visiting: who has a room for me? -----------------------------------------------------------------------------------
visit_list() {  # -> VIS_L: the owners who answered, sorted by name
  local id l=() s
  for id in "${!VIS_INFO[@]}"; do [[ -n ${OP_NAME[$id]} ]] && l+=("${OP_NAME[$id],,} $id"); done
  VIS_L=()
  (( ${#l[@]} )) || return
  while read -r s id; do VIS_L+=("$id"); done < <(printf '%s\n' "${l[@]}" | sort)
}
ui_visit() {
  local i id a
  visit_list
  ui "  VISIT A ROOM" "$K_LOOT$B"
  ui "  Whose door is open to you? (they must be online)" "$K_SYS"
  ui ""
  for (( i = 0; i < ${#VIS_L[@]} && i < 9; i++ )); do
    id=${VIS_L[i]} a=(${VIS_INFO[$id]})
    ui "  [$(( i + 1 ))] ${OP_NAME[$id]}'s ${ROOM_NAME[a[0]]}" "$K_CHAT$B"
    ui "      ${a[1]} on display, ${a[2]}/$NCOL collectables found" "$K_SYS"
  done
  if (( ! ${#VIS_L[@]} )); then
    if (( NOW - VIS_T < 3000 )); then ui "  The innkeeper asks around the taproom..." "$K_SYS"
    else ui "  Nobody's door is open to you right now." "$K_SYS"; fi
  fi
  ui ""
  ui "  [1-9] knock   [r] ask again   [esc] back" "$K_SYS"
}
visit_key() {
  case $1 in
    [1-9]) visit_list; local id=${VIS_L[$(( $1 - 1 ))]}; [[ -n $id ]] && { visit_go "$id"; UI=""; } ;;
    r) visit_ask ;;
  esac
}

# --- a display in my room -------------------------------------------------------------------------------------------------
dsp_row() {  # code -> RC RP: icon, name, what it is
  local c=$1
  rb; item_name "$c" "$CLS"; item_icon "$c" "$CLS"
  [[ -n $II ]] && rt "$II "
  rt "$INAME" "$ICOL"
  if [[ $IK == C ]]; then rt "  ${CS_NAME[${CL_SET[IKD]}]}" "38;5;245"
  elif [[ $IK == B ]]; then rt "  bag" "38;5;245"
  else rt "  ${RAR_NAME[IRR],,} ${SLOT_LABEL[$IK],,}" "38;5;245"; fi
}
ui_dsp() {
  local i n=${#INV[@]} H top c mk
  room_mine || { UI=""; return; }
  ui "  DISPLAY $(( DSP_I + 1 )) OF ${ROOM_NDSP[ROOM_T]}" "$K_LOOT$B"
  c=${ROOMD[DSP_I]:--}
  if [[ $c == - ]]; then ui "  It is empty." "$K_SYS"
  else dsp_row "$c"; RC=$'\e[0§m'"  on it: $RC" RP="  on it: $RP"; uxs; ui "  [t] take it back into your bags" "$K_SYS"; fi
  ui ""
  ui "  PUT SOMETHING ON IT - from your bags" "$B"
  H=$(( VH - 8 )); (( H < 3 )) && H=3
  (( DSP_CUR >= n )) && DSP_CUR=$(( n - 1 )); (( DSP_CUR < 0 )) && DSP_CUR=0
  top=$(( DSP_CUR - H / 2 )); (( top > n - H )) && top=$(( n - H )); (( top < 0 )) && top=0
  (( n )) || ui "  (your bags are empty)" "$K_SYS"
  for (( i = top; i < n && i < top + H; i++ )); do
    dsp_row "${INV[i]}"
    if (( i == DSP_CUR )); then mk=$'\e[0;1;38;5;226m▶ '; else mk="  "; fi
    RC="$mk$RC" RP="  $RP"; uxs
  done
  ui ""
  ui "  [↑↓] choose  [enter] put it on display  [esc] done" "$K_SYS"
}
dsp_key() {
  case $1 in
    UP|w) (( DSP_CUR > 0 )) && DSP_CUR=$(( DSP_CUR - 1 )) ;;
    DOWN|s) (( DSP_CUR < ${#INV[@]} - 1 )) && DSP_CUR=$(( DSP_CUR + 1 )) ;;
    ''|$'\r'|' '|e) dsp_put "$DSP_I" "$DSP_CUR" ;;
    t) dsp_take "$DSP_I" ;;
  esac
}

# --- the collection book -----------------------------------------------------------------------------------------------------
ui_book() {
  local s i L=() P=() per pages first last e nm st col
  col_count
  for (( s = 0; s < NCS; s++ )); do
    if (( TW2 )); then e="${CS_E[s]} "; else e=""; fi
    L+=("  $K_LOOT$B$e${CS_NAME[s]^^}$N $K_SYS${CLSD[s]}/${CLST[s]} - ${CS_HOW[s]}$N")
    P+=("  $e${CS_NAME[s]^^} ${CLSD[s]}/${CLST[s]} - ${CS_HOW[s]}")
    for i in ${COL_SETL[s]}; do
      if col_has "$i"; then
        col_where "$i"; st=${CW_AT:-found, not kept}
        col=${RAR_COL[${CL_RR[i]}]}; [[ -z $CW_AT ]] && col="38;5;245"
        if (( TW2 )); then e="${CL_E[i]} "; else e="${CL_G[i]} "; fi
        printf -v nm '%-30s' "${CL_NAME[i]}"
        L+=("    $e"$'\e['"${col}m$nm$N $K_SYS$st$N"); P+=("    $e$nm $st")
      else
        if (( TW2 )); then e="❔ "; else e="? "; fi
        L+=("    $e$K_SYS??? - ${CL_SRC[i]}$N"); P+=("    $e??? - ${CL_SRC[i]}")
      fi
    done
  done
  per=$(( VH - 3 )); (( per < 5 )) && per=5
  pages=$(( (${#L[@]} + per - 1) / per ))
  (( BOOK_PG >= pages )) && BOOK_PG=$(( pages - 1 )); (( BOOK_PG < 0 )) && BOOK_PG=0
  first=$(( BOOK_PG * per )) last=$(( first + per ))
  ui "  COLLECTION BOOK  $CLN/$NCOL found   page $(( BOOK_PG + 1 ))/$pages  [<][>] turn  [esc]" "$K_LOOT$B"
  ui ""
  for (( i = first; i < last && i < ${#L[@]}; i++ )); do uix "${L[i]}" "${P[i]}"; done
}
book_key() {
  case $1 in
    RIGHT|'>'|.|d|l|' ') BOOK_PG=$(( BOOK_PG + 1 )) ;;
    LEFT|'<'|,|a|h) (( BOOK_PG > 0 )) && BOOK_PG=$(( BOOK_PG - 1 )) ;;
  esac
}

# --- the guestbook --------------------------------------------------------------------------------------------------------------
ui_guest() {
  local e n d today=$(( NOW / 86400000 )) k=0
  set -- $GUESTS
  ui "  YOUR GUESTBOOK   $# signature(s)   [esc] close" "$K_LOOT$B"
  ui ""
  (( $# )) || ui "  Nobody has signed it yet. Invite your friends up!" "$K_SYS"
  for e in "$@"; do
    n=${e%%:*} d=$(( today - ${e#*:} ))
    if (( d <= 0 )); then d="today"; elif (( d == 1 )); then d="yesterday"; else d="$d days ago"; fi
    printf -v PF '  %-14s %s' "$n" "$d"; ui "$PF" "$K_CHAT"
    k=$(( k + 1 )); (( k >= VH - 5 )) && break
  done
  ui ""
  ui "  Visitors sign it when they walk into it." "$K_SYS"
}
