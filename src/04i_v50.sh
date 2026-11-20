# ---------------------------------------------------------------------------
#  Module 04i - v5.0 client: housing and collectables. A room upstairs at any
#  inn (rent, four sizes), walked like a little map of its own (H<owner>):
#  a bed (Well Rested), a chest, displays, a collection book, a guestbook.
#  Friends visit while the owner is online - the owner's client answers.
#  Collectables (C.<n>) are found on bosses, in every land, while fishing
#  and gathering, and along the story.
# ---------------------------------------------------------------------------
ROOM_T=0 ROOM_PAID=-1 ROOM_DOOR=1 REST_UNTIL=0 REST_PCT=0 GUESTS="" CLOG=""
ROOMD=() ROOMC=() ROOMM=()
V50_VARS=(ROOM_T ROOM_PAID ROOM_DOOR REST_UNTIL REST_PCT)
declare -A RM_AT=() VIS_INFO=() RM_ANS=()
RM_F=() RM_DSP=() RM_OWNER="" RM_TIER=0 RM_NCOL=0 RM_SIGNED=0 RM_SX=0 RM_SY=0 RM_NS=0
VIS_OWNER="" VIS_WANT="" VIS_T=0 DSP_I=0 DSP_CUR=0 BOOK_PG=0
DOOR_NAME=("locked - nobody comes in" "party - your party may visit" "open - everybody may visit")

v50_reset() {  # a new hero
  ROOM_T=0 ROOM_PAID=-1 ROOM_DOOR=1 REST_UNTIL=0 REST_PCT=0 GUESTS="" CLOG="" ROOMD=() ROOMC=() ROOMM=()
  v50_fix
}
v50_fix() {
  local i n
  (( ROOM_T >= 0 && ROOM_T <= NROOM )) || ROOM_T=0
  (( ROOM_DOOR >= 0 && ROOM_DOOR <= 2 )) || ROOM_DOOR=1
  (( REST_PCT <= 40 )) || REST_PCT=0
  while (( ${#CLOG} < NCOL )); do CLOG+=0; done; CLOG=${CLOG:0:NCOL}
  n=${ROOM_NDSP[ROOM_T]:-0}
  ROOMD=("${ROOMD[@]:0:n}"); for (( i = ${#ROOMD[@]}; i < n; i++ )); do ROOMD[i]=-; done
  ROOMC=("${ROOMC[@]:0:${ROOM_CAP[ROOM_T]:-0}}")
  for (( i = 0; i < NMAT; i++ )); do ROOMM[i]=${ROOMM[i]:-0}; done
}
v50_load_kv() {  # key value: the lines load_char and v45_load_kv do not know
  local x i=0
  case $1 in
    ROOM_T|ROOM_DOOR|REST_PCT) [[ $2 =~ ^[0-9]{1,2}$ ]] && printf -v "$1" '%d' "$(( 10#$2 ))" ;;
    REST_UNTIL) [[ $2 =~ ^[0-9]{1,14}$ ]] && REST_UNTIL=$(( 10#$2 )) ;;
    ROOM_PAID) [[ $2 =~ ^(-1|[0-9]{1,7})$ ]] && { if [[ $2 == -1 ]]; then ROOM_PAID=-1; else ROOM_PAID=$(( 10#$2 )); fi; } ;;
    CLOG)   [[ $2 =~ ^[01]{1,256}$ ]] && CLOG=$2 ;;
    ROOMD)  ROOMD=(); for x in $2; do if [[ $x == - ]] || valid_item "$x"; then ROOMD+=("$x"); else ROOMD+=(-); fi; done ;;
    ROOMC)  ROOMC=(); for x in $2; do valid_item "${x%!}" && ROOMC+=("$x"); done ;;
    ROOMM)  for x in $2; do [[ $x =~ ^[0-9]{1,6}$ ]] && (( i < NMAT )) && ROOMM[i]=$(( 10#$x )); i=$(( i + 1 )); done ;;
    GUESTS) [[ $2 =~ ^([A-Za-z0-9_-]{1,12}:[0-9]{1,6}( |$)){0,12}$ ]] && GUESTS=$2 ;;
  esac
}
v50_save() {  # the lines save_char adds
  local k
  for k in "${V50_VARS[@]}"; do echo "$k=${!k}"; done
  echo "CLOG=$CLOG"; echo "ROOMD=${ROOMD[*]}"; echo "ROOMC=${ROOMC[*]}"; echo "ROOMM=${ROOMM[*]}"; echo "GUESTS=$GUESTS"
}

# --- collectables -------------------------------------------------------------------------------------------
col_has() { [[ ${CLOG:$1:1} == 1 ]]; }                         # index -> 0 if ever found
col_mark() { col_has "$1" || CLOG="${CLOG:0:$1}1${CLOG:$1+1}"; }
col_count() {  # -> CLN (found) CLSD[set] (found per set) CLST[set] (all per set) - it only depends on CLOG
  local i s
  [[ $CLN_K == "$CLOG" && -n $CLN_K ]] && return
  CLN_K=$CLOG CLN=0 CLSD=() CLST=()
  for (( s = 0; s < NCS; s++ )); do CLSD[s]=0 CLST[s]=0; done
  for (( i = 0; i < NCOL; i++ )); do
    s=${CL_SET[i]}; CLST[s]=$(( CLST[s] + 1 ))
    [[ ${CLOG:i:1} == 1 ]] && { CLN=$(( CLN + 1 )) CLSD[s]=$(( CLSD[s] + 1 )); }
  done
}
col_where() {  # index -> CW_AT: where you keep it now ("" = nowhere)
  local c="C.$1" x
  CW_AT=""
  for x in "${ROOMD[@]}"; do [[ $x == "$c" ]] && { CW_AT="on display"; return; }; done
  for x in "${INV[@]}"; do [[ ${x%!} == "$c" ]] && { CW_AT="in your bags"; return; }; done
  for x in "${ROOMC[@]}"; do [[ ${x%!} == "$c" ]] && { CW_AT="in your room chest"; return; }; done
  for x in "${BANK[@]}"; do [[ ${x%!} == "$c" ]] && { CW_AT="in your vault"; return; }; done
}
col_scan() {  # everything you hold counts as found (trades, gifts, the vault)
  local x
  for x in "${INV[@]}" "${ROOMD[@]}" "${ROOMC[@]}" "${BANK[@]}"; do
    [[ $x == C.* ]] && { x=${x%!}; x=${x#C.}; [[ $x =~ ^(0|[1-9][0-9]{0,2})$ ]] && (( x < NCOL )) && col_mark "$x"; }
  done
}
col_pick() {  # set -> CP: a random member, rare ones are rarer; something new is a bit more likely
  local l=(${COL_SETL[$1]}) i tot r try
  CP=${l[0]}
  for try in 1 2; do
    tot=0; for i in "${l[@]}"; do tot=$(( tot + COL_W[CL_RR[i]] )); done
    r=$(( RANDOM % tot ))
    for i in "${l[@]}"; do r=$(( r - COL_W[CL_RR[i]] )); (( r < 0 )) && { CP=$i; break; }; done
    col_has "$CP" || break
    (( RANDOM % 2 )) && break
  done
}
col_give() {  # index: a collectable for you
  local i=$1 c="C.$1" first=1 to="" s=${CL_SET[$1]}
  col_has "$i" && first=0
  col_mark "$i"
  if (( ${#INV[@]} < BAGS )); then INV+=("$c"); NEWG[$c]=1
  elif (( ROOM_T > 0 && ${#ROOMC[@]} < ROOM_CAP[ROOM_T] )); then ROOMC+=("$c"); to=" Your bags are full - the innkeepers carried it to your room chest."
  else INV+=("$c"); NEWG[$c]=1; fi                      # too precious to sell: it squeezes in, like a unique
  item_name "$c" "$CLS"; item_icon "$c" "$CLS"
  logm "${EMJ[loot]}COLLECTABLE: $II${II:+ }$INAME (${CS_NAME[s]})$to" $'\e['"${ICOL}m"
  if (( first )); then
    col_count
    logm "New for your collection: ${CLSD[s]}/${CLST[s]} ${CS_NAME[s]}, $CLN/$NCOL in all. Show it off in your room!" "$K_ANN"
    (( CL_RR[i] >= 2 )) && send EVT "$MY_ID" "$MY_NAME" "found the $INAME for their collection!"
    ach_check
  fi
}
col_kill() {  # monster type champion: trophies from bosses, curios from the creatures of every land
  local t=$1 ch=${2:-0} i chance
  i=${COL_BOSS[$t]}
  if [[ -n $i ]]; then
    if col_has "$i"; then chance=12; else chance=40; fi
    (( RANDOM % 100 < chance )) && col_give "$i"
    return
  fi
  if (( M_KIND[t] == 4 )); then                         # treasure chests hide odd things
    (( RANDOM % 100 < 6 )) && { col_pick $(( 3 + RANDOM % 2 )); col_give "$CP"; }
    return
  fi
  (( M_KIND[t] == 0 )) && [[ $CUR_MAP == W ]] || return
  in_safe_xy "$PX" "$PY" && return
  RNAME=""; region_of "$PX" "$PY" nosafe; i=${COL_CUR[$RNAME]}
  [[ -n $i ]] || return
  if col_has "$i"; then chance=4; else chance=15; fi    # per thousand
  (( ch )) && chance=$(( chance * 3 ))
  (( M_BOSS[t] == 2 )) && chance=$(( chance * 15 ))
  (( RANDOM % 1000 < chance )) && col_give "$i"
}
col_find() { (( RANDOM % 1000 < 30 )) && { col_pick "$1"; col_give "$CP"; }; }   # set: a find while fishing (3) or gathering (4)
col_story() {  # the story pays a relic every sixth chapter (old heroes get theirs at once)
  local i
  for i in ${COL_SETL[5]}; do
    (( STORY >= CL_REF[i] )) && ! col_has "$i" && col_give "$i"
  done
}
col_dupes() {  # -> DUP (indexes in INV) DUPV (what they sell for): unlocked collectables you already own once
  local i c held=" "
  DUP=() DUPV=0
  for c in "${ROOMD[@]}" "${ROOMC[@]}" "${BANK[@]}"; do [[ $c == C.* ]] && held+="${c%!} "; done   # displayed and stored ones are keepers
  for c in "${INV[@]}"; do [[ $c == C.*! ]] && held+="${c%!} "; done                               # and so are locked ones
  for i in "${!INV[@]}"; do
    c=${INV[i]}; [[ $c == C.* && $c != *! ]] || continue
    if [[ $held == *" $c "* ]]; then DUP+=("$i"); item_stats "$c"; DUPV=$(( DUPV + ISELL ))
    else held+="$c "; fi                                                  # the first copy in your bags stays
  done
}

# --- the room: building it, walking in and out ----------------------------------------------------------------
room_map() { RMAP="H$(( 16#$1 ))"; }                           # owner id -> RMAP (the map name everybody uses)
room_build() {  # map tier -> MAPROW, RM_F ("kind x y slot"), RM_AT, RM_SX RM_SY (just inside the door), RM_NS
  local rows r y x c row n=0 s=0 IFS=/
  rows=(${ROOM_LAY[$2]})
  IFS=$' \t\n'
  RM_F=() RM_AT=()
  for (( y = 0; y < ${#rows[@]}; y++ )); do
    r=${rows[y]} row=""
    for (( x = 0; x < ${#r}; x++ )); do
      c=${r:x:1}
      case $c in
        '#') row+='#' ;;
        '<') row+='<'; RM_SX=$x RM_SY=$(( y - 1 )) ;;
        .)   row+=_ ;;
        *)   row+=+; RM_AT["$x,$y"]=$n
             if [[ $c == D ]]; then RM_F[n]="D $x $y $s"; s=$(( s + 1 )); else RM_F[n]="$c $x $y -"; fi
             n=$(( n + 1 )) ;;
      esac
    done
    MAPROW["$1:$y"]=$row
  done
  MAPW[$1]=${#rows[0]} MAPH[$1]=${#rows[@]} RM_NS=$s
}
dsp_look() {  # code -> DLE (HD sprite) DLG (ASCII glyph) DLC (color)
  item_stats "$1"; item_name "$1" "$CLS"
  DLC=$ICOL DLE=$IKE
  if [[ $IK == C ]]; then DLG=${CL_G[IKD]}
  elif [[ -n $IUQ ]]; then DLG='*'
  else case $IK in W) DLG=/ ;; A) DLG=']' ;; O) DLG=')' ;; H) DLG='^' ;; J) DLG='"' ;; *) DLG=b ;; esac; fi
  [[ $DLE == ?' ' ]] && DLE="${DLE:0:1} "                       # narrow sprites keep their padding
}
room_glyphs() {  # the sprites of all furniture, from what stands on the displays
  local i a k c e g col
  for i in "${!RM_F[@]}"; do
    a=(${RM_F[i]}); k=${a[0]}
    if [[ $k == D ]]; then
      c=${RM_DSP[a[3]]:--}
      if [[ $c == - ]]; then e=${FURN_E[D]} g=${FURN_G[D]} col=${FURN_C[D]}
      else dsp_look "$c"; e=$DLE g=$DLG col=$DLC; fi
      GLYH[h$i]=$'\e[0;48;5;'"${RM_PED}m$e"
    else
      e=${FURN_E[$k]} g=${FURN_G[$k]} col=${FURN_C[$k]}; GLYH[h$i]=$e
    fi
    GLY[h$i]=$'\e[0;'"${col}m$g"
  done
  MAP_DIRTY=1
}
room_overlay() {  # cx0 cy0: furniture into the frame (called by render_map)
  local i a dx dy
  for i in "${!RM_F[@]}"; do
    a=(${RM_F[i]}); dx=$(( a[1] - $1 )) dy=$(( a[2] - $2 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) && RI[dy]+="$(( dx * 10 + 3 )):1:h$i "
  done
}
room_go() {  # owner-id tier "displays": walk up into a room (from the open world only)
  [[ $CUR_MAP == W ]] || return
  (( DEAD )) && return
  room_map "$1"
  WX=$PX WY=$PY                                            # where the stairs bring you back down
  mount_off quiet; FISH_ST=0 GATH_MID=""
  room_build "$RMAP" "$2"; drop_vrows "$RMAP"
  RM_OWNER=$1 RM_TIER=$2 RM_DSP=($3) RM_SIGNED=0
  CUR_MAP=$RMAP CUR_DT=-1 PX=$RM_SX PY=$RM_SY UI="" clear_until=0
  cm_clear; set_palette -2; room_glyphs
  POS_DIRTY=1 MAP_DIRTY=1 NEED_FULL=1
  (( ALLY >= 0 )) && aly_place
}
room_leave() {  # [text]: back down to the taproom
  [[ $CUR_MAP == H* ]] || return
  leave_instance quiet
  logm "${1:-You go back down to the taproom.}" "$K_SYS"
}
room_left() { RM_F=() RM_AT=() RM_DSP=() RM_OWNER="" VIS_OWNER="" VIS_WANT=""; }   # (leave_instance calls it)
room_mine() { [[ $CUR_MAP == H* && $RM_OWNER == "$MY_ID" ]]; }
room_shown() { local x; RSH=0; for x in "${ROOMD[@]}"; do [[ $x != - ]] && RSH=$(( RSH + 1 )); done; }   # -> RSH

# --- renting -----------------------------------------------------------------------------------------------------
rent_week() { RWK=$(( (NOW / 86400000 + 3) / 7 )); }            # weeks start on Monday, like the mythic affixes
room_pay() {  # -> 0 if this week's rent is paid (pays it now if it can)
  local r=${ROOM_RENT[ROOM_T]}
  rent_week
  (( ROOM_PAID >= RWK )) && return 0
  if (( GOLD >= r )); then GOLD=$(( GOLD - r )); logm "${EMJ[gold]}You pay this week's rent: ${r}g." "$K_LOOT"
  elif (( BANKG >= r )); then BANKG=$(( BANKG - r )); logm "${EMJ[gold]}This week's rent (${r}g) comes out of your vault." "$K_LOOT"
  else logm "This week's rent is ${r}g and you can't pay it. Your things are safe - come back with the gold." "$K_HURT"; return 1; fi
  ROOM_PAID=$RWK; save_char
}
room_rent() {  # tier: move in, or move up to a bigger room (everything moves along)
  local t=$1 cost first=0
  (( t >= 1 && t <= NROOM )) || return 1
  if (( t == ROOM_T )); then logm "That is your room already." "$K_SYS"; return 1; fi
  if (( t < ROOM_T )); then logm "Your ${ROOM_NAME[ROOM_T]} is bigger - the guild does not move anybody down." "$K_SYS"; return 1; fi
  (( LVL >= ROOM_LVL[t] )) || { logm "The ${ROOM_NAME[t]} is kept for heroes of level ${ROOM_LVL[t]} and up." "$K_HURT"; return 1; }
  cost=$(( ROOM_COST[t] - ROOM_COST[ROOM_T] ))
  (( GOLD >= cost )) || { logm "The ${ROOM_NAME[t]} costs ${cost}g to move in (you have $GOLD)." "$K_HURT"; return 1; }
  (( ROOM_T == 0 )) && first=1
  GOLD=$(( GOLD - cost )) ROOM_T=$t
  rent_week; ROOM_PAID=$RWK
  v50_fix
  if (( first )); then logm "🔑 The key to your ${ROOM_NAME[t]} is yours! Any innkeeper takes you up - [9] when you talk to them." "$K_ANN"
  else logm "🔑 You move up into the ${ROOM_NAME[t]}. Your things are already there." "$K_ANN"; fi
  send EVT "$MY_ID" "$MY_NAME" "rents the ${ROOM_NAME[t]} at the inn!"
  ach_check; save_char
}
room_home() {  # go up to my own room
  (( ROOM_T )) || { logm "You have no room yet - rent one here first." "$K_SYS"; return; }
  room_pay || return
  room_go "$MY_ID" "$ROOM_T" "${ROOMD[*]}"
  logm "You climb the stairs to your ${ROOM_NAME[ROOM_T]}. Walk into things to use them." "$K_GOOD"
  room_bcast
}
door_next() { ROOM_DOOR=$(( (ROOM_DOOR + 1) % 3 )); logm "Your door: ${DOOR_NAME[ROOM_DOOR]}." "$K_SYS"; save_char; room_bcast; }

# --- inside: the furniture ---------------------------------------------------------------------------------------
room_use() {  # furniture index
  local a=(${RM_F[$1]}) k who=${OP_NAME[$RM_OWNER]:-someone}
  k=${a[0]}
  case $k in
    B) if room_mine; then room_sleep; else logm "That is $who's bed. Better not."; fi ;;
    C) if room_mine; then room_chest; else logm "$who's chest is locked. Of course it is."; fi ;;
    D) if room_mine; then DSP_I=${a[3]} DSP_CUR=0 UI=dsp
       else dsp_examine "${a[3]}"; fi ;;
    K) if room_mine; then BOOK_PG=0 UI=book; else logm "$who's collection book: $RM_NCOL of $NCOL collectables found."; fi ;;
    G) if room_mine; then UI=guest; else room_sign; fi ;;
    *) logm "${FURN_SAY[$k]}" ;;
  esac
  MAP_DIRTY=1
}
room_sleep() {
  room_shown
  local p=$(( ROOM_REST[ROOM_T] + (RSH / 4 > 10 ? 10 : RSH / 4) ))
  REST_PCT=$p REST_UNTIL=$(( NOW + REST_MS ))
  rest "You sleep in your own bed and wake up Well Rested: +$p% experience from fights for 30 minutes."
  save_char
}
room_chest() {
  BK_TAB=2 BK_INPUT="" BK_SIDE=0 BK_CUR=(0 0) BK_TOP=(0 0)
  UI=bank MAP_DIRTY=1
}
dsp_examine() {  # slot (a visitor looks at a display)
  local c=${RM_DSP[$1]:--}
  if [[ $c == - ]]; then logm "An empty display."; return; fi
  item_name "$c" "$CLS"; item_icon "$c" "$CLS"
  if [[ $IK == C ]]; then logm "On display: $II${II:+ }$INAME - ${CS_NAME[${CL_SET[IKD]}]}. \"${CL_FL[IKD]}\"" $'\e['"${ICOL}m"
  else bonus_txt; logm "On display: $II${II:+ }$INAME${IVAL:+ (+$IVAL)}${BTX:+, $BTX}" $'\e['"${ICOL}m"; fi
}
dsp_put() {  # slot bag-index: put something on a display (what stood there goes back into your bags)
  local s=$1 i=$2 c old
  c=${INV[i]}; [[ -n $c ]] || return 1
  old=${ROOMD[s]:--}
  unset "INV[i]"; INV=("${INV[@]}"); unset "NEWG[${c%!}]"
  ROOMD[s]=${c%!}
  [[ $old != - ]] && INV+=("$old")
  item_name "$c" "$CLS"; logm "You put the $INAME on display." "$K_GOOD"
  room_refresh
}
dsp_take() {  # slot
  local s=$1 c=${ROOMD[$1]:--}
  [[ $c != - ]] || return 1
  (( ${#INV[@]} < BAGS )) || { logm "Your bags are full." "$K_HURT"; return 1; }
  INV+=("$c"); ROOMD[s]=-
  item_name "$c" "$CLS"; logm "You take the $INAME back." "$K_SYS"
  room_refresh
}
room_refresh() {  # my displays changed: redraw, tell visitors, save
  room_mine && { RM_DSP=("${ROOMD[@]}"); room_glyphs; }
  room_bcast; ach_check; save_char
}

# --- the guestbook ------------------------------------------------------------------------------------------------
guest_add() {  # name: newest first, everybody once, twelve at most
  local n=$1 e out="$1:$(( NOW / 86400000 ))" k=1
  for e in $GUESTS; do
    [[ ${e%%:*} == "$n" ]] && continue
    (( k >= 12 )) && break
    out+=" $e"; k=$(( k + 1 ))
  done
  GUESTS=$out
}
room_sign() {
  (( RM_SIGNED )) && { logm "You already signed it."; return; }
  RM_SIGNED=1
  send RSIGN "$MY_ID" "$MY_NAME" "$RM_OWNER"
  logm "You sign ${OP_NAME[$RM_OWNER]:-the owner}'s guestbook." "$K_GOOD"
}

# --- visiting (player to player, through the hub) ---------------------------------------------------------------
room_list() { local IFS=,; RLIST="${ROOMD[*]}"; }              # -> RLIST "C.5,-,U.3"
door_lets() {  # id -> 0 if my door lets that player in
  (( ROOM_T )) || return 1
  case $ROOM_DOOR in 2) return 0 ;; 1) in_party "$1" ;; *) return 1 ;; esac
}
room_bcast() {  # tell everybody in my room what it looks like now (tier 0: the door closed)
  local id here=0 t=$ROOM_T
  (( ROOM_T )) || return
  room_map "$MY_ID"
  for id in "${!OP_MAP[@]}"; do [[ ${OP_MAP[$id]} == "$RMAP" ]] && here=1; done
  (( here )) || return
  (( ROOM_DOOR == 0 )) && t=0
  col_count; room_list
  send ROOM "$MY_ID" "$MY_NAME" '*' "$t" "$CLN" "$RLIST"
}
visit_ask() { VIS_INFO=() VIS_T=$NOW UI=visit MAP_DIRTY=1; send RASK "$MY_ID" "$MY_NAME"; }
visit_go() {  # owner id
  [[ -n ${OP_NAME[$1]} ]] || return
  VIS_WANT=$1
  send RREQ "$MY_ID" "$MY_NAME" "$1"
  logm "You ask the innkeeper to take you up to ${OP_NAME[$1]}'s room..." "$K_SYS"
}
room_msg() {  # typ from name b c d e  (cli_line hands over RASK RHAS RREQ ROOM RNO RSIGN)
  local typ=$1 from=$2 nm=$3 b=$4 c=$5 d=$6 e=$7 x l=() ok=() n
  if [[ $typ == @(RASK|RREQ|RSIGN) ]]; then                       # what makes me answer: once a second per player
    (( NOW - ${RM_ANS[$from:$typ]:-0} >= 1000 )) || return
    RM_ANS[$from:$typ]=$NOW; (( ${#RM_ANS[@]} > 200 )) && RM_ANS=()
  fi
  case $typ in
    RASK) door_lets "$from" || return
          room_shown; col_count
          send RHAS "$MY_ID" "$MY_NAME" "$from" "$ROOM_T" "$RSH" "$CLN" ;;
    RHAS) [[ $b == "$MY_ID" ]] && [[ $c =~ ^[1-4]$ ]] && isnum "$d" && isnum "$e" || return
          (( d <= 99 && e <= NCOL )) || return
          VIS_INFO[$from]="$c $d $e"; MAP_DIRTY=1 ;;
    RREQ) [[ $b == "$MY_ID" ]] || return
          if (( ! ROOM_T )); then send RNO "$MY_ID" "$MY_NAME" "$from" none
          elif ! door_lets "$from"; then x=locked; (( ROOM_DOOR )) && x=party; send RNO "$MY_ID" "$MY_NAME" "$from" "$x"
          else
            col_count; room_list
            send ROOM "$MY_ID" "$MY_NAME" "$from" "$ROOM_T" "$CLN" "$RLIST"
            logm "$nm comes up to visit your ${ROOM_NAME[ROOM_T]}." "$K_PARTY"
          fi ;;
    RNO)  [[ $b == "$MY_ID" && $VIS_WANT == "$from" ]] || return
          VIS_WANT=""
          case $c in
            none)  logm "$nm has no room at the inn." "$K_SYS" ;;
            party) logm "$nm's door only opens for their party." "$K_SYS" ;;
            *)     logm "$nm's door is locked." "$K_SYS" ;;
          esac ;;
    ROOM) [[ $c =~ ^[0-4]$ ]] && isnum "$d" || return
          (( d <= NCOL )) || d=0
          n=${ROOM_NDSP[c]:-0}
          IFS=, read -r -a l <<< "$e"
          for x in "${l[@]:0:n}"; do if [[ $x == - ]] || valid_item "$x"; then ok+=("$x"); else ok+=(-); fi; done
          while (( ${#ok[@]} < n )); do ok+=(-); done
          if [[ $b == "$MY_ID" && $VIS_WANT == "$from" ]]; then          # the door opens for me
            VIS_WANT=""
            (( c )) || return
            [[ $CUR_MAP == W ]] || return
            room_go "$from" "$c" "${ok[*]}"; VIS_OWNER=$from RM_NCOL=$d
            logm "You step into $nm's ${ROOM_NAME[c]}. Walk into the displays to look at them - and sign the guestbook!" "$K_GOOD"
          elif [[ $b == '*' && $VIS_OWNER == "$from" ]]; then           # the owner changed something
            room_map "$from"; [[ $CUR_MAP == "$RMAP" ]] || return
            if (( c == 0 )); then room_leave "$nm closed the door - the innkeeper shows you out."; return; fi
            if (( c != RM_TIER )); then
              local ox=$PX oy=$PY
              room_build "$RMAP" "$c"; drop_vrows "$RMAP"; RM_TIER=$c
              p_walk "$RMAP" "$ox" "$oy" && [[ -z ${RM_AT[$ox,$oy]} ]] && PX=$ox PY=$oy || { PX=$RM_SX PY=$RM_SY; }
              NEED_FULL=1
            fi
            RM_DSP=("${ok[@]}") RM_NCOL=$d; room_glyphs
          fi ;;
    RSIGN) [[ $b == "$MY_ID" ]] && (( ROOM_T )) || return
           room_map "$MY_ID"; [[ ${OP_MAP[$from]} == "$RMAP" ]] || return     # only people who stand in my room
           guest_add "$nm"; logm "📒 $nm signed your guestbook!" "$K_PARTY"; save_char; ach_check ;;
  esac
}

# --- achievements (index ACH50 and up) -------------------------------------------------------------------------------
ach_ok50() {
  local j=$(( $1 - ACH50 )) s
  case $j in
    0) (( ROOM_T >= 1 )) ;; 1) (( ROOM_T >= 4 )) ;;
    2|3|4) col_count; case $j in 2) (( CLN >= 20 )) ;; 3) (( CLN >= 50 )) ;; *) (( CLN >= NCOL )) ;; esac ;;
    5|6|7|8|9|10) s=$(( j - 5 )); col_count; (( CLSD[s] >= CLST[s] )) ;;
    11) room_shown; (( RSH >= 20 )) ;;
    12) set -- $GUESTS; (( $# >= 5 )) ;;
    *) ach_ok60 "$1" ;;                                        # v6.0
  esac
}

v50_tick() {  # once a second
  if (( NOW - ${COL_T:-0} >= 5000 )); then COL_T=$NOW; col_scan; col_story; fi
  if [[ -n $VIS_OWNER && -z ${OP_NAME[$VIS_OWNER]} ]]; then room_leave "Your host has left the world - the innkeeper shows you out."; fi
  [[ -n $VIS_WANT ]] && [[ -z ${OP_NAME[$VIS_WANT]} ]] && VIS_WANT=""
}
