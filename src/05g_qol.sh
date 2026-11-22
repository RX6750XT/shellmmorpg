# ---------------------------------------------------------------------------
#  Module 05g - comfort (v7.1): special keys (PgUp/PgDn/Home/End/Del,
#  modified arrows), a chat line that edits like a shell (cursor, history,
#  Tab completes names, ctrl+w/u), a chat log that scrolls (with times,
#  wrapped, three tabs), panels taller than the window scroll, quitting asks
#  first, the bell can be switched off.
# ---------------------------------------------------------------------------
KEY="" QUIT_ASK=0 CHAT_POS=0 CHAT_HI=-1 CHAT_SAVE="" LAST_WHISP="" BELL_ON=1
CHAT_HIST=()
CL_TAB=0 CL_OFF=0 CL_KEY="" CL_TOT=0 CLW_T=() CLW_C=()
UI_SCR=0 UI_SCR_UI="" UI_FOCUS=-1
LSEQ=0

bell() { (( BELL_ON )) && printf '\a'; }

key_esc() {  # after an ESC byte: read the rest of the sequence -> KEY (ESC UP DOWN LEFT RIGHT HOME END DEL PGUP PGDN, "" = unknown)
  local c s=""
  KEY=ESC
  IFS= read -rsn1 -t 0.01 c || return 0
  if [[ $c != '[' && $c != O ]]; then KEY=""; return 0; fi          # alt+key: nothing
  while IFS= read -rsn1 -t 0.01 c; do
    s+=$c
    [[ $c == [A-Za-z~] ]] && break
    (( ${#s} > 7 )) && break
  done
  case $s in
    A|*\;?A) KEY=UP ;;   B|*\;?B) KEY=DOWN ;;  C|*\;?C) KEY=RIGHT ;;  D|*\;?D) KEY=LEFT ;;
    H|1~|7~|*\;?H) KEY=HOME ;;  F|4~|8~|*\;?F) KEY=END ;;
    3~) KEY=DEL ;;  5~) KEY=PGUP ;;  6~) KEY=PGDN ;;
    *) KEY="" ;;
  esac
}

# --- the chat line ------------------------------------------------------------------------------
chat_open() { CHATTING=1 CHAT_BUF=$1 CHAT_POS=${#1} CHAT_HI=-1 CHAT_SAVE=""; }

chat_hist_add() {
  [[ -n ${1//[[:space:]]/} ]] || return
  (( ${#CHAT_HIST[@]} )) && [[ ${CHAT_HIST[-1]} == "$1" ]] && return
  CHAT_HIST+=("$1")
  (( ${#CHAT_HIST[@]} > 50 )) && CHAT_HIST=("${CHAT_HIST[@]:10}")
}

CHAT_CMDS=(/p /w /r /invite /accept /leave /me /home /trade /give /symbol /color /who /bell /help /admin)
chat_complete() {  # Tab: complete the word before the cursor - a player's name, or a /command at the start
  local pre=${CHAT_BUF:0:CHAT_POS} post=${CHAT_BUF:CHAT_POS} word cands=() c id common i a b
  word=${pre##* }
  [[ -n $word ]] || return
  if [[ $word == /* && $pre == "$word" ]]; then
    for c in "${CHAT_CMDS[@]}"; do [[ $c == "$word"* ]] && cands+=("$c"); done
  else
    for id in "${!OP_NAME[@]}"; do [[ ${OP_NAME[$id],,} == "${word,,}"* ]] && cands+=("${OP_NAME[$id]}"); done
    [[ ${MY_NAME,,} == "${word,,}"* ]] && cands+=("$MY_NAME")
  fi
  (( ${#cands[@]} )) || return
  if (( ${#cands[@]} == 1 )); then c="${cands[0]} "
  else                                                     # several: as far as they agree, and show them
    common=${cands[0]}
    for c in "${cands[@]}"; do
      for (( i = 0; i < ${#common}; i++ )); do a=${common:i:1} b=${c:i:1}; [[ ${a,,} == "${b,,}" ]] || break; done
      common=${common:0:i}
    done
    (( ${#common} >= ${#word} )) || common=$word
    c=$common
    logm "Tab: ${cands[*]}" "$K_SYS"
  fi
  pre=${pre:0:${#pre}-${#word}}$c
  CHAT_BUF=${pre:0:180}$post CHAT_POS=${#pre}
  (( CHAT_POS > ${#CHAT_BUF} )) && CHAT_POS=${#CHAT_BUF}
}

chat_key() {
  local k=$1 a n
  case $k in
    ''|$'\r'|$'\n') CHATTING=0; chat_hist_add "$CHAT_BUF"; chat_submit; CHAT_BUF="" CHAT_POS=0 ;;
    ESC)            CHATTING=0 CHAT_BUF="" CHAT_POS=0 ;;
    $'\x7f'|$'\b')  (( CHAT_POS > 0 )) && { CHAT_BUF=${CHAT_BUF:0:CHAT_POS-1}${CHAT_BUF:CHAT_POS}; CHAT_POS=$(( CHAT_POS - 1 )); } ;;
    DEL|$'\x04')    CHAT_BUF=${CHAT_BUF:0:CHAT_POS}${CHAT_BUF:CHAT_POS+1} ;;
    LEFT|$'\x02')   (( CHAT_POS > 0 )) && CHAT_POS=$(( CHAT_POS - 1 )) ;;
    RIGHT|$'\x06')  (( CHAT_POS < ${#CHAT_BUF} )) && CHAT_POS=$(( CHAT_POS + 1 )) ;;
    HOME|$'\x01')   CHAT_POS=0 ;;
    END|$'\x05')    CHAT_POS=${#CHAT_BUF} ;;
    $'\x15')        CHAT_BUF=${CHAT_BUF:CHAT_POS} CHAT_POS=0 ;;                   # ctrl+u: everything before the cursor
    $'\x0b')        CHAT_BUF=${CHAT_BUF:0:CHAT_POS} ;;                             # ctrl+k: everything after it
    $'\x17')                                                                       # ctrl+w: the word before the cursor
      a=${CHAT_BUF:0:CHAT_POS}; a=${a%"${a##*[! ]}"}
      if [[ $a == *' '* ]]; then a="${a% *} "; else a=""; fi
      CHAT_BUF=$a${CHAT_BUF:CHAT_POS} CHAT_POS=${#a} ;;
    $'\t')          chat_complete ;;
    UP)  n=${#CHAT_HIST[@]}; (( n )) || return
         if (( CHAT_HI < 0 )); then CHAT_SAVE=$CHAT_BUF CHAT_HI=$(( n - 1 )); elif (( CHAT_HI > 0 )); then CHAT_HI=$(( CHAT_HI - 1 )); fi
         CHAT_BUF=${CHAT_HIST[CHAT_HI]} CHAT_POS=${#CHAT_HIST[CHAT_HI]} ;;
    DOWN) (( CHAT_HI >= 0 )) || return
         if (( CHAT_HI < ${#CHAT_HIST[@]} - 1 )); then CHAT_HI=$(( CHAT_HI + 1 )); CHAT_BUF=${CHAT_HIST[CHAT_HI]}
         else CHAT_HI=-1 CHAT_BUF=$CHAT_SAVE; fi
         CHAT_POS=${#CHAT_BUF} ;;
    *)   if (( ${#k} == 1 )) && [[ $k != [[:cntrl:]] ]] && (( ${#CHAT_BUF} < 180 )); then
           CHAT_BUF=${CHAT_BUF:0:CHAT_POS}$k${CHAT_BUF:CHAT_POS}; CHAT_POS=$(( CHAT_POS + 1 ))
         fi ;;
  esac
}

render_input() {
  local w=$(( COLS - 9 )) l=$'\e['"$INPY;1H" t off cur
  if (( CHATTING )); then
    (( CHAT_POS > ${#CHAT_BUF} )) && CHAT_POS=${#CHAT_BUF}
    off=0; (( CHAT_POS >= w )) && off=$(( CHAT_POS - w + 1 ))     # the cursor stays in view
    t=${CHAT_BUF:off:w}; cur=$(( CHAT_POS - off ))
    local c=${t:cur:1}; [[ -n $c ]] || c=' '
    l+=$' \e[1;38;5;51msay>'"$N ${t:0:cur}"$'\e[7m'"$c"$'\e[27m'"${t:cur+1}"
  elif (( QUIT_ASK )); then
    l+=$' \e[1;38;5;226mQuit the game? Your hero is saved.  [y] yes   any other key: keep playing'"$N"
  else
    t=" [wasd] move [1-3] skills [e/r] potions [u] eat [g] fish/gather [i]nv [x] talents [y] allies [p]rof [m]ap [q]uests [b]easts [c]hat log [H] collection [v] graphics [enter] chat [?] help"
    l+="${K_SYS}${t:0:COLS-1}$N"
  fi
  emit inp "$l"$'\e[K'
}

# --- the chat log [c]: chat, events or both, with the time, wrapped, scrolling ---------------------------
cl_wrap() {  # text color time width -> appends to CLW_T / CLW_C
  local t="$3 $1" w=$4 cut sp
  while (( ${#t} > w )); do
    cut=${t:0:w}; sp=${cut% *}; [[ $cut == *' '* ]] && (( ${#sp} > 8 )) && cut=$sp   # (a break at a space, not inside the indent)
    CLW_T+=("$cut"); CLW_C+=("$2")
    t="      ${t:${#cut}}"; t="      ${t##+( )}"
  done
  CLW_T+=("$t"); CLW_C+=("$2")
}

cl_build() {  # -> CLW_T CLW_C: the wrapped lines of the current tab (cached)
  local w=$(( VW - 6 )) i j ne=${#LOG_T[@]} nc=${#CHL_T[@]} key
  key="$CL_TAB:$w:$LSEQ:$ne:$nc"
  [[ $key == "$CL_KEY" ]] && return
  CL_KEY=$key CLW_T=() CLW_C=()
  case $CL_TAB in
    0) for (( i = 0; i < nc; i++ )); do cl_wrap "${CHL_T[i]}" "${CHL_C[i]}" "${CHL_TM[i]:-     }" "$w"; done ;;
    1) for (( i = 0; i < ne; i++ )); do cl_wrap "${LOG_T[i]}" "${LOG_C[i]}" "${LOG_TM[i]:-     }" "$w"; done ;;
    *) i=0 j=0                                                    # both, in the order they happened
       while (( i < ne || j < nc )); do
         if (( j >= nc || (i < ne && ${LOG_S[i]:-0} <= ${CHL_S[j]:-0}) )); then
           cl_wrap "${LOG_T[i]}" "${LOG_C[i]}" "${LOG_TM[i]:-     }" "$w"; i=$(( i + 1 ))
         else cl_wrap "${CHL_T[j]}" "${CHL_C[j]}" "${CHL_TM[j]:-     }" "$w"; j=$(( j + 1 )); fi
       done ;;
  esac
}

ui_chatlog() {
  local rows=$(( VH - 2 )) n first i tabs="" t lab
  cl_build
  n=${#CLW_T[@]}
  (( CL_OFF > 0 && n > CL_TOT )) && CL_OFF=$(( CL_OFF + n - CL_TOT ))   # scrolled up: new lines do not move the view
  CL_TOT=$n
  (( CL_OFF > n - rows )) && CL_OFF=$(( n - rows )); (( CL_OFF < 0 )) && CL_OFF=0
  for t in 0 1 2; do
    lab=(chat events everything); lab=${lab[t]}
    if (( t == CL_TAB )); then tabs+=$'\e[1;7m'" [$(( t + 1 ))] $lab "$'\e[0m'"$K_SYS "; else tabs+="$K_SYS [$(( t + 1 ))] $lab  "; fi
  done
  uix "  ${K_LOOT}${B}LOG$N  $tabs$N" "  LOG   [1] chat    [2] events    [3] everything  "
  first=$(( n - rows - CL_OFF )); (( first < 0 )) && first=0
  for (( i = first; i < first + rows; i++ )); do
    if (( i < n )); then ui "  ${CLW_T[i]}" "${CLW_C[i]}"; else ui ""; fi
  done
  (( n )) || UIT[1]="  nothing yet - press [enter] to chat"
  if (( CL_OFF )); then t="  ▼$CL_OFF [End]"; else t="  "; fi
  ui "$t ↑↓ PgUp PgDn scroll  [Home] oldest  [c] close" "$K_SYS"
}

chatlog_key() {
  local page=$(( VH - 3 ))
  case $1 in
    1|2|3) CL_TAB=$(( $1 - 1 )) CL_OFF=0 ;;
    $'\t'|RIGHT) CL_TAB=$(( (CL_TAB + 1) % 3 )) CL_OFF=0 ;;
    LEFT)        CL_TAB=$(( (CL_TAB + 2) % 3 )) CL_OFF=0 ;;
    UP|k|w)      CL_OFF=$(( CL_OFF + 1 )) ;;
    DOWN|j|s)    (( CL_OFF > 0 )) && CL_OFF=$(( CL_OFF - 1 )) ;;
    PGUP)        CL_OFF=$(( CL_OFF + page )) ;;
    PGDN|' ')    CL_OFF=$(( CL_OFF - page )); (( CL_OFF < 0 )) && CL_OFF=0 ;;
    HOME|g)      CL_OFF=999999 ;;
    END|G)       CL_OFF=0 ;;
    c)           UI="" ;;
    ''|$'\r'|t)  chat_open "" ;;
    /)           chat_open "/" ;;
  esac
}

# --- panels taller than the window scroll (PgUp/PgDn, Home/End) -------------------------------------
ui_scroll() {  # called by render_ui after a panel was built: cut UIT/UIC/UIL to the window, with a marker line
  local n=${#UIT[@]} rows max
  [[ $UI == "$UI_SCR_UI" ]] || { UI_SCR=0 UI_SCR_UI=$UI; }
  if (( n <= VH )); then UI_SCR=0; return; fi
  rows=$(( VH - 1 )) max=$(( n - rows ))
  if (( UI_FOCUS >= 0 )); then                         # a list with a cursor: keep it in view
    (( UI_FOCUS < UI_SCR + 2 )) && UI_SCR=$(( UI_FOCUS - 2 ))
    (( UI_FOCUS > UI_SCR + rows - 3 )) && UI_SCR=$(( UI_FOCUS - rows + 3 ))
  fi
  (( UI_SCR > max )) && UI_SCR=$max; (( UI_SCR < 0 )) && UI_SCR=0
  UIT=("${UIT[@]:UI_SCR:rows}") UIC=("${UIC[@]:UI_SCR:rows}") UIL=("${UIL[@]:UI_SCR:rows}")
  local up="" dn=""
  (( UI_SCR > 0 )) && up="▲ "; (( UI_SCR < max )) && dn="▼ "
  ui "  ${up}${dn}$(( UI_SCR + 1 ))-$(( UI_SCR + rows )) of $n  [PgUp] [PgDn] scroll" "$K_SYS"
}

ui_scroll_key() {  # PgUp PgDn Home End in any panel
  local page=$(( VH - 3 ))
  case $1 in
    PGUP) UI_SCR=$(( UI_SCR - page )) ;;
    PGDN) UI_SCR=$(( UI_SCR + page )) ;;
    HOME) UI_SCR=0 ;;
    END)  UI_SCR=999999 ;;
  esac
  (( UI_SCR < 0 )) && UI_SCR=0
  UI_FOCUS=-1
}

# --- waystones: every stone can be picked (there are more than ten) ------------------------------------
WAY_CUR=-1
way_list() {  # -> WAY_L: the indexes of the attuned waystones
  local i; WAY_L=()
  for i in "${!WAYSTONES[@]}"; do [[ ${WAYS:i:1} == 1 ]] && WAY_L+=("$i"); done
}

ui_way() {
  local i a cost=$(( 10 + LVL * 3 )) n=0 lab sel
  way_list
  { (( WAY_CUR >= 0 )) && [[ ${WAYS:WAY_CUR:1} == 1 ]]; } || WAY_CUR=${WAY_L[0]:--1}
  ui "  WAYSTONE NETWORK" "$K_LOOT$B"
  ui "  Travel to any attuned waystone for $cost gold. You have $GOLD gold."
  ui ""
  for i in "${!WAYSTONES[@]}"; do
    a=(${WAYSTONES[i]})
    if [[ ${WAYS:i:1} == 1 ]]; then
      n=$(( n + 1 )); lab="   "; (( n <= 10 )) && lab="[$(( n % 10 ))]"
      sel="  "; (( i == WAY_CUR )) && { sel="▶ "; UI_FOCUS=${#UIT[@]}; }
      cheb $(( a[1] - PX )) $(( a[2] - PY ))
      if (( D <= 3 )) && [[ $CUR_MAP == W ]]; then ui "$sel$lab ${EMJ[way]}${a[0]//_/ }   (you are here)" "$K_SYS"
      elif (( i == WAY_CUR )); then ui "$sel$lab ${EMJ[way]}${a[0]//_/ }" "$B"
      else ui "$sel$lab ${EMJ[way]}${a[0]//_/ }"; fi
    else
      ui "      ??? - not attuned yet" "$K_SYS"
    fi
  done
  ui ""
  ui "  Walk past a waystone (&) once to attune it." "$K_SYS"
  ui "  [↑↓] choose  [enter] travel  [1-0] quick  [esc] close" "$K_SYS"
}

way_key() {
  local i p=-1
  way_list
  for i in "${!WAY_L[@]}"; do [[ ${WAY_L[i]} == "$WAY_CUR" ]] && p=$i; done
  case $1 in
    [0-9]) i=$(( $1 == 0 ? 9 : $1 - 1 )); (( i < ${#WAY_L[@]} )) && way_travel "${WAY_L[i]}" ;;
    UP|w|k)   (( p > 0 )) && WAY_CUR=${WAY_L[p-1]} ;;
    DOWN|s|j) (( p >= 0 && p < ${#WAY_L[@]} - 1 )) && WAY_CUR=${WAY_L[p+1]} ;;
    PGUP|HOME) WAY_CUR=${WAY_L[0]:--1} ;;
    PGDN|END)  WAY_CUR=${WAY_L[-1]:--1} ;;
    ''|$'\r'|' ') (( WAY_CUR >= 0 )) && way_travel "$WAY_CUR" ;;
  esac
}

# --- settings that stay: graphics and the bell ------------------------------------------------------------
save_gfx() { mkdir -p "${GFX_FILE%/*}" 2>/dev/null; printf 'GFX=%s\nBELL=%s\n' "$GFX" "$BELL_ON" > "$GFX_FILE" 2>/dev/null; }
[[ -f $GFX_FILE && $'\n'$(<"$GFX_FILE") == *$'\n'BELL=0* ]] && BELL_ON=0
