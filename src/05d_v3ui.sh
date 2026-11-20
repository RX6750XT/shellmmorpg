# ---------------------------------------------------------------------------
#  Module 05d - v3.0 screens: talents [x], the jeweler (any smith), faction
#  quartermasters, questline choices, the quest log with questlines and
#  reputation, and the side-panel / map details for champions and effects.
# ---------------------------------------------------------------------------

# === talents ===================================================================================
TL_CUR=0
ui_talents() {
  local k i n r mx mark col req
  tal_points; tal_reset_cost
  ui "  TALENTS - ${C_NAME[CLS]}   $TSPENT spent, $TFREE free (one point every level)" "$K_LOOT$B"
  ui "  [w/s] choose  [enter] learn  [x] close  - forget them all at any inn ($TRC gold)" "$K_SYS"
  for (( k = 0; k < 3; k++ )); do
    ui "  ${TL_TREE[CLS * 3 + k]^^}  (${TTREE[k]})" "$B"$'\e[38;5;117m'
    for (( n = 0; n < 4; n++ )); do
      i=$(( k * 4 + n )) r=${TAL:i:1} mx=${TL_MAX[n]} req=""
      mark="   "; (( i == TL_CUR )) && mark="  >"
      col=$K_SYS
      if (( r >= mx )); then col=$K_LOOT
      elif (( r > 0 )); then col=$K_GOOD
      elif tal_can "$i"; then col=$K_CHAT
      else (( TTREE[k] < TL_REQ[n] )) && req="  (${TL_REQ[n]} in tree)"; fi
      tal_desc "$i"
      (( n == 3 )) && TD="capstone"
      printf -v PF '%s %-22s %s/%s  %s%s' "$mark" "${TL_NAME[CLS * 12 + i]}" "$r" "$mx" "$TD" "$req"
      ui "$PF" "$col"
    done
  done
  tal_desc "$TL_CUR"; tal_can "$TL_CUR"
  ui ""
  ui "  ${TL_NAME[CLS * 12 + TL_CUR]}: $TD${TWHY:+  - $TWHY}" "$K_CHAT"
}
tal_key() {
  case $1 in
    w|k|UP)    TL_CUR=$(( (TL_CUR + 11) % 12 )) ;;
    s|j|DOWN)  TL_CUR=$(( (TL_CUR + 1) % 12 )) ;;
    $'\r'|''|+|' '|l|RIGHT) tal_learn "$TL_CUR" ;;
  esac
}

# === the jeweler ==================================================================================
JW_TAB=0 JW_CUR=0 JW_STEP=0 JW_SOCK=0 ABC=abcdefghijklmnopqrstuvwxyz
jw_list() {  # -> JWL: gear that has or can get sockets ("E:W" worn, "I:3" bag slot)
  local s c i
  JWL=()
  for s in W A O H J; do
    eq_of "$s"; c=$EQC; [[ -n $c && $c != U.* ]] || continue
    JWL+=("E:$s")
  done
  for i in "${!INV[@]}"; do [[ ${INV[i]} == [WAOHJ].* ]] && JWL+=("I:$i"); done
}
jw_code() {  # "E:W" | "I:3" -> JC (the item code)
  if [[ $1 == E:* ]]; then eq_of "${1#E:}"; JC=$EQC; else JC=${INV[${1#I:}]}; fi
}
jw_store() {  # "E:W" | "I:3" new-code
  if [[ $1 == E:* ]]; then printf -v "EQ${1#E:}" '%s' "$2"; calc_stats; else INV[${1#I:}]=$2; fi
}
jw_gems() {  # -> JGL: the gem materials you own
  local i
  JGL=(); for i in ${MAT_GRP[3]}; do (( MATS[i] > 0 )) && JGL+=("$i"); done
}
jewel_open() { JW_TAB=0 JW_CUR=0 JW_STEP=0 UI=jewel MAP_DIRTY=1; }
ui_jewel() {
  local i e c n s g line sel
  [[ -n ${CM_T[$TALK_MID]} ]] || { UI=""; return; }
  ui "  JEWELCRAFTING - ${N_FULL[$TALK_T]}   ${EMJ[gold]}$GOLD gold" "$K_LOOT$B"
  if (( JW_TAB == 0 )); then ui "  [1] SOCKETS   2  combine gems     [tab] switch  [esc] leave" "$K_SYS"
  else ui "   1  sockets  [2] COMBINE GEMS     [tab] switch  [esc] leave" "$K_SYS"; fi
  ui ""
  if (( JW_TAB == 1 )); then
    ui "  Three gems of a grade make one of the next. Pick with [a]-[r]." "$K_SYS"
    n=0
    for (( g = 0; g < 6; g++ )); do
      for e in 1 2 3; do
        gem_mat "$g" "$e"; i=$GM; c=$(( 60 * e * e ))
        mat_icon "$i"
        line="  [${ABC:n:1}] $MI${MI:+ }${MAT_NAME[i]} x${MATS[i]}  ->  ${GEM_GRADE[e]} ${GEM_NAME[g]}  (${c}g)"
        if (( MATS[i] >= 3 )); then ui "$line" "$K_CHAT"; else ui "$line" "$K_SYS"; fi
        n=$(( n + 1 ))
      done
    done
    return
  fi
  jw_list
  (( ${#JWL[@]} )) || { ui "  You carry no gear that could hold a gem."; return; }
  (( JW_CUR >= ${#JWL[@]} )) && JW_CUR=$(( ${#JWL[@]} - 1 ))
  for i in "${!JWL[@]}"; do
    (( i >= VH - 9 )) && break
    jw_code "${JWL[i]}"; item_name "$JC" "$CLS"; gems_txt "$JC"; sock_cost "$JC"
    sel="  "; (( i == JW_CUR )) && sel="> "
    e="bag "; [[ ${JWL[i]} == E:* ]] && e="worn"
    line="  $sel$e  ${INAME}"; [[ -n $GTX ]] && line+="  $GTX"
    if (( i == JW_CUR )); then ui "$line" $'\e[1;'"${ICOL}m"; else ui "$line" $'\e['"${ICOL}m"; fi
  done
  ui ""
  jw_code "${JWL[JW_CUR]}"; item_name "$JC" "$CLS"; sock_info "$JC"; sock_cost "$JC"; gems_plain "$JC"
  case $JW_STEP in
    0) ui "  $INAME: $SN socket(s)${GPL:+ - $GPL}" "$K_CHAT"
       if (( SKC )); then ui "  [enter] set a gem   [n] add a socket ($SKC gold)" "$K_GOOD"
       elif (( SN )); then ui "  [enter] set a gem   (no more sockets fit this item)" "$K_GOOD"
       else ui "  This item can't take a socket." "$K_SYS"; fi ;;
    1) line="  Which socket? "; s=1
       for g in $SGEMS; do if [[ $g == __ ]]; then line+=" [$s] empty"; else gem_of "$g"; line+=" [$s] ${GEM_GRADE[GQ-1]} ${GEM_NAME[GK]}"; fi; s=$(( s + 1 )); done
       ui "$line" "$K_CHAT"; ui "  A gem already in the socket is destroyed." "$K_SYS" ;;
    2) jw_gems
       if (( ! ${#JGL[@]} )); then ui "  You have no gems. Rare monsters, champions, bosses, chests and ore veins drop them." "$K_SYS"
       else
         line="  Which gem?"; n=0
         for i in "${JGL[@]}"; do
           mat_icon "$i"; gem_kq "$i"; g=$GKI e=$GQI
           line+=" [${ABC:n:1}] ${MI:-${GEM_L[g]^^}$e}x${MATS[i]}"; n=$(( n + 1 ))
         done
         ui "$line" "$K_CHAT"
         n=0; line=""
         for i in "${JGL[@]}"; do
           gem_kq "$i"; g=$GKI e=$(( GQI - 1 )); local v=(${GEM_V[g]})
           line+="${GEM_L[g]^^}${e}=+${v[e]} ${GEM_FX[g]}  "; n=$(( n + 1 ))
         done
         ui "  $line" "$K_SYS"
       fi ;;
  esac
}
jewel_key() {
  local k=$1 i g n c
  case $k in
    $'\t') JW_TAB=$(( 1 - JW_TAB )) JW_STEP=0; return ;;
    1) (( JW_STEP == 0 && JW_TAB == 1 )) && { JW_TAB=0; return; } ;;
    2) (( JW_STEP == 0 )) && { JW_TAB=1; return; } ;;
  esac
  if (( JW_TAB == 1 )); then
    [[ $k == [a-r] ]] || return
    printf -v n '%d' "'$k"; n=$(( n - 97 ))
    g=$(( n / 3 )) i=$(( n % 3 + 1 ))
    gem_mat "$g" "$i"; c=$(( 60 * i * i ))
    (( MATS[GM] >= 3 )) || { logm "You need three of them." "$K_HURT"; return; }
    (( GOLD >= c )) || { logm "Not enough gold." "$K_HURT"; return; }
    MATS[GM]=$(( MATS[GM] - 3 )); GOLD=$(( GOLD - c ))
    gem_mat "$g" $(( i + 1 )); gem_get "$GM"; (( i == 3 )) && { GEMP=1; ach_check; }
    return
  fi
  jw_list; (( ${#JWL[@]} )) || return
  case $JW_STEP in
    0) case $k in
         w|k|UP)   (( JW_CUR > 0 )) && JW_CUR=$(( JW_CUR - 1 )) ;;
         s|j|DOWN) (( JW_CUR < ${#JWL[@]} - 1 )) && JW_CUR=$(( JW_CUR + 1 )) ;;
         $'\r'|''|' ') jw_code "${JWL[JW_CUR]}"; sock_info "$JC"; (( SN )) && JW_STEP=1 ;;
         n) jw_code "${JWL[JW_CUR]}"; sock_cost "$JC"
            (( SKC )) || return
            (( GOLD >= SKC )) || { logm "A socket costs $SKC gold." "$K_HURT"; return; }
            GOLD=$(( GOLD - SKC )); sock_add "$JC"; jw_store "${JWL[JW_CUR]}" "$CODE2"
            logm "${N_FULL[$TALK_T]} drills a new socket. ($SKC gold)" "$K_GOOD" ;;
       esac ;;
    1) jw_code "${JWL[JW_CUR]}"; sock_info "$JC"
       [[ $k == [1-3] ]] && (( k <= SN )) && { JW_SOCK=$(( k - 1 )) JW_STEP=2; } ;;
    2) jw_gems
       [[ $k == [a-r] ]] || return
       printf -v n '%d' "'$k"; n=$(( n - 97 ))
       (( n < ${#JGL[@]} )) || return
       i=${JGL[n]}; gem_kq "$i"; g=$GKI
       jw_code "${JWL[JW_CUR]}"
       sock_set "$JC" "$JW_SOCK" "${GEM_L[g]}$GQI"
       MATS[i]=$(( MATS[i] - 1 ))
       jw_store "${JWL[JW_CUR]}" "$CODE2"; item_name "$CODE2" "$CLS"
       logm "The ${MAT_NAME[i]} clicks into your $INAME." "$K_GOOD"
       JW_STEP=0 ;;
  esac
}

# === faction quartermasters =========================================================================
ui_wares() {
  local i col line
  [[ -n ${CM_T[$TALK_MID]} ]] || { UI=""; return; }
  wares_build "$TALK_T"
  (( WR_F >= 0 )) || { UI=talk; return; }
  rep_rank "$WR_F"
  ui "  QUARTERMASTER OF THE ${FAC_NAME[WR_F]^^}" "$K_LOOT$B"
  ui "  You are ${REP_NAME[RR < 0 ? 0 : RR]} (${REP[WR_F]} reputation).  ${EMJ[gold]}$GOLD gold" $'\e['"${FAC_COL[WR_F]}m"
  ui ""
  for i in "${!WR_NAME[@]}"; do
    printf -v line '  [%d] %-44s %6sg  %s' $(( i + 1 )) "${WR_NAME[i]}" "${WR_PRICE[i]}" "${REP_NAME[WR_RANK[i]]}"
    if (( RR >= WR_RANK[i] )); then col=$K_CHAT; (( GOLD >= WR_PRICE[i] )) || col=$K_HURT; else col=$K_SYS; fi
    ui "$line" "$col"
  done
  ui ""
  ui "  Quests for this faction's towns and lands raise your standing; so do the" "$K_SYS"
  ui "  questlines. Friendly 1500, Honored 4500, Revered 9000, Exalted 15000." "$K_SYS"
  ui "  Better standing also means up to 20% off in their shops.   [esc] back" "$K_SYS"
}
wares_key() { [[ $1 == [1-5] ]] && wares_buy $(( $1 - 1 )); }

# === a questline asks you to decide ==================================================================
ui_qchoice() {
  local l=$QCH_L opt w=$(( VW - 6 )) rest cut
  ql_step "$l"
  IFS='|' read -r -a opt <<< "${QS_CHA[QST]}"
  ui "  ${QL_NAME[l]^^} - A CHOICE" "$K_LOOT$B"
  ui ""
  rest="\"${QS_DONE[QST]}\" ${QS_CH[QST]}"
  while (( ${#rest} > w )); do
    cut=${rest:0:w}; cut=${cut% *}; ui "  $cut" "$K_CHAT"; rest=${rest:${#cut}}; rest=${rest# }
  done
  ui "  $rest" "$K_CHAT"
  ui ""
  ui "  [1] ${opt[0]}" "$K_GOOD"
  ui "  [2] ${opt[1]}" "$K_GOOD"
  ui ""
  ui "  Choices change who thinks well of you - and what you get." "$K_SYS"
}

# === the quest log =====================================================================================
QLOG_TAB=0
ui_qlog() {
  local q f tag plain n=0 i c st
  case $QLOG_TAB in 0) tag="[1] QUESTS  2 lines  3 reputation  4 daily" ;; 1) tag=" 1 quests [2] LINES  3 reputation  4 daily" ;;
    2) tag=" 1 quests  2 lines [3] REPUTATION  4 daily" ;; *) tag=" 1 quests  2 lines  3 reputation [4] DAILY" ;; esac
  ui "  QUEST LOG   $tag" "$K_LOOT$B"
  ui ""
  (( QLOG_TAB == 3 )) && { ui_dailies; return; }
  if (( QLOG_TAB == 2 )); then
    for (( i = 0; i < NFAC; i++ )); do
      rep_rank "$i"
      local nx=${REP_RANK[RR < 4 ? (RR < 0 ? 0 : RR + 1) : 4]} have=${REP[i]} bar
      (( RR >= 4 )) && nx=21000
      pbar "$(( have < 0 ? 0 : have ))" "$nx" 16 $'\e['"${REP_COL[RR < 0 ? 0 : RR]}m"; bar=$PB
      st=${REP_NAME[RR < 0 ? 0 : RR]}; (( RR < 0 )) && st=Unfriendly
      local fe=""; (( TW2 )) && fe="${FAC_E[i]} "
      printf -v PF '%-20s' "${FAC_NAME[i]}"
      uix "  $fe"$'\e['"${FAC_COL[i]}m$PF$N $bar $st ($have)"
    done
    ui ""
    ui "  Quests in a faction's towns and lands raise your standing with it." "$K_SYS"
    ui "  Their shops give 5% off per rank; their quartermaster (the questline" "$K_SYS"
    ui "  giver of each town, [6] in a conversation) sells gems, socketed gear" "$K_SYS"
    ui "  and, to the Revered, a unique." "$K_SYS"
    return
  fi
  if (( QLOG_TAB == 1 )); then
    for (( i = 0; i < NQL; i++ )); do
      c=${QLS:i:1}
      case $c in
        x) st="${K_LOOT}done$N"; [[ ${QLC:i:1} != - ]] && st+=" ${K_SYS}(you chose ${QLC:i:1^^})$N" ;;
        0) if (( LVL >= QL_LVL[i] )); then st="${K_GOOD}ask ${N_FULL[${QL_NPC[i]}]}$N"; else st="${K_SYS}from level ${QL_LVL[i]}$N"; fi ;;
        *) st="${K_CHAT}step $c/${QL_N[i]}$N" ;;
      esac
      local fe=""; (( TW2 )) && fe="${FAC_E[${QL_FAC[i]}]} "
      uix "  $fe${QL_NAME[i]}  - $st"
    done
    ui ""
    ui "  Every town has a questline. Its giver wears a ❕ (ASCII: orange !)." "$K_SYS"
    return
  fi
  story_qlog
  for (( i = 0; i < NQL; i++ )); do
    ql_step "$i" || continue
    qobj_parse "${QS_OBJ[QST]}"; obj_text "$OT" "$OA" "$ON" "${QLP[i]}"
    QTX=$OWX QTY=$OWY; track
    if ql_ready "$i"; then st="${K_GOOD}ready - return to ${N_FULL[${QL_NPC[i]}]}$N"; else st=""; fi
    uix "  ${K_LOOT}[line]$N ${QL_NAME[i]} ($QSI/${QL_N[i]}): $OTX" "  [line] ${QL_NAME[i]} ($QSI/${QL_N[i]}): $OTX"
    [[ -n $st ]] && uix "          $st" "          ready - return to ${N_FULL[${QL_NPC[i]}]}"
    [[ -z $st && -n $TRK ]] && ui "          ->  $TRK" "$K_SYS"
  done
  for q in "${PQ_CODES[@]}" "${QUESTS[@]}"; do
    [[ -n $q ]] || continue
    n=$(( n + 1 )); IFS=. read -r -a f <<< "$q"
    if (( n <= ${#PQ_CODES[@]} )); then tag="${K_PARTY}[party]$N"; plain="[party]"; else tag="${K_LOOT}[own]$N  "; plain="[own]  "; fi
    quest_info "$q"; track
    uix "  $tag $QGLY $QTXT" "  $plain $PLX $QTXT"
    ui "          $QWHERE${TRK:+   ->  $TRK}   - ${f[4]} XP, ${f[5]} gold" "$K_SYS"
  done
  (( n )) || { ui "  No quests yet. The quest board (!) in every town and NPCs with a"; ui "  yellow ! over their head have work for you."; }
  ui ""
  ui "  [1-3] tabs   [m] shows targets on the world map   [esc] close" "$K_SYS"
}

# === side panel and map details ==========================================================================
ps_line() {  # -> PSL: my status effects (empty if none)
  local i s=""
  for i in 0 1 2 3 4 5; do
    (( NOW < PS_UNTIL[i] )) || continue
    secs $(( PS_UNTIL[i] - NOW ))
    if (( TW2 )); then s+="${PS_E[i]}$TS "; else s+=$'\e['"${PS_COL[i]}m${PS_NAME[i]}$N $TS "; fi
  done
  (( BARRIER > 0 )) && s+="${K_GOOD}shield $BARRIER$N "
  PSL=$s
}
target_info() {  # mid -> TIL: champion / rare / weakness details for the side panel
  local t=${CM_T[$1]} s=""
  TIL=""
  (( M_KIND[t] == 0 )) || return
  (( ${CM_CH[$1]:-0} )) && s+=$'\e['"${CHP_COL[CM_CH[$1]-1]}m${CHP_NAME[CM_CH[$1]-1]}$N "
  (( M_BOSS[t] == 2 )) && s+=$'\e[1;38;5;220m'"elite$N "
  (( M_WK[t] >= 0 )) && s+="${K_GOOD}weak:${EL_NAME[M_WK[t]]}$N "
  (( M_RS[t] >= 0 )) && s+="${K_HURT}resists:${EL_NAME[M_RS[t]]}$N"
  TIL="   $s"
}
CHN=" "
chain_npcs() {  # -> CHN: everyone with questline business for me (refreshed once a second)
  local i
  CHN=" "
  for (( i = 0; i < NQL; i++ )); do
    if [[ ${QLS:i:1} == 0 ]]; then (( LVL >= QL_LVL[i] )) && CHN+="${QL_NPC[i]} "; continue; fi
    ql_step "$i" || continue
    if [[ ${QS_OBJ[QST]} == T.* ]]; then CHN+="${QS_OBJ[QST]#T.} "; elif ql_ready "$i"; then CHN+="${QL_NPC[i]} "; fi
  done
}
