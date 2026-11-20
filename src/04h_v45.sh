# ---------------------------------------------------------------------------
#  Module 04h - v4.5 client: professions and gems to level 40, paragon, mythic
#  keys, valor, mounts, dailies and weeklies, achievements and titles.
#  (Loaded after the UI modules: it overrides a few of their helpers.)
# ---------------------------------------------------------------------------
PARA=0 PARA_P="0 0 0 0 0 0" KEYLV=2 MYBEST=0 VALOR=0 MOUNTS="" MNT_CUR=0 RIDING=0 ACHS="" TITLE=-1
DAILY="" WEEKLY="" DCLR=0 RAIDK=0 RAREK=0 INVK=0 DLYK=0 MYDONE=0 GEMP=0
IN_MK=0 IN_LIM=0 IN_T0=0 IN_AFX=""
V45_VARS=(PARA KEYLV MYBEST VALOR MNT_CUR TITLE DCLR RAIDK RAREK INVK DLYK MYDONE GEMP)

v45_reset() {  # a new hero
  PARA=0 PARA_P="0 0 0 0 0 0" KEYLV=2 MYBEST=0 VALOR=0 MOUNTS="" MNT_CUR=0 RIDING=0 ACHS="" TITLE=-1
  DAILY="" WEEKLY="" DCLR=0 RAIDK=0 RAREK=0 INVK=0 DLYK=0 MYDONE=0 GEMP=0
  v50_reset; v45_fix
}
v45_fix() {
  local i
  [[ $PARA_P =~ ^(0|[1-9][0-9]?)( (0|[1-9][0-9]?)){5}$ ]] || PARA_P="0 0 0 0 0 0"     # (no "08": octal)
  while (( ${#MOUNTS} < NMNT )); do MOUNTS+="0"; done; MOUNTS=${MOUNTS:0:NMNT}
  [[ -z $ACHS ]] && ACH_QUIET=1                                # (an old hero: no fanfare for what is already done)
  while (( ${#ACHS} < NACH )); do ACHS+="0"; done; ACHS=${ACHS:0:NACH}
  (( MNT_CUR >= 0 && MNT_CUR < NMNT )) || MNT_CUR=0
  (( KEYLV >= 2 && KEYLV <= MYTH_MAX )) || KEYLV=2
  (( TITLE >= -1 && TITLE < NACH )) || TITLE=-1
  (( TITLE >= 0 )) && [[ ${ACHS:TITLE:1} != 1 ]] && TITLE=-1
  for i in "${!PROF_LV[@]}"; do (( PROF_LV[i] <= PROF_MAX )) || PROF_LV[i]=$PROF_MAX; done
  dly_fix; v50_fix
}
v45_load_kv() {  # key value: the lines load_char does not know
  case $1 in
    PARA_P) [[ $2 =~ ^(0|[1-9][0-9]?)( (0|[1-9][0-9]?)){5}$ ]] && PARA_P=$2 ;;
    MOUNTS|ACHS) [[ $2 =~ ^[01]{1,64}$ ]] && printf -v "$1" '%s' "$2" ;;
    DAILY|WEEKLY) [[ $2 =~ ^(0|[1-9][0-9]{0,6})(\ (0|[1-9][0-9]?):(0|[1-9][0-9]{0,5}):[01]){1,3}$ ]] && printf -v "$1" '%s' "$2" ;;
    PARA|KEYLV|MYBEST|VALOR|MNT_CUR|DCLR|RAIDK|RAREK|INVK|DLYK|MYDONE|GEMP) [[ $2 =~ ^[0-9]{1,9}$ ]] && printf -v "$1" '%d' "$(( 10#$2 ))" ;;
    TITLE) [[ $2 =~ ^-?[0-9]{1,3}$ ]] && TITLE=$2 ;;
    *) v50_load_kv "$1" "$2" ;;                                 # v5.0: housing and collectables
  esac
}
v45_save() {  # the lines save_char adds
  local k
  for k in "${V45_VARS[@]}"; do echo "$k=${!k}"; done
  echo "PARA_P=$PARA_P"; echo "MOUNTS=$MOUNTS"; echo "ACHS=$ACHS"; echo "DAILY=$DAILY"; echo "WEEKLY=$WEEKLY"
  v50_save
}

# --- professions: tables instead of index ranges ---------------------------------------------------------
node_prof() { NPK=${NODE_PK[$1]:-1}; }                         # node type -> NPK (1 mining, 2 herbalism)
mat_prof() { MP_K=${MAT_PK[$1]:-0}; }                           # material -> MP_K
mat_node() {  # material -> MNT_T: the node it grows on ("" for fish and gems)
  local t; MNT_T=""
  for t in "${NODE_T[@]}"; do (( NODE_MAT[$t] == $1 )) && { MNT_T=$t; return 0; }; done
  return 1
}

# --- paragon ----------------------------------------------------------------------------------------------
para_points() {  # -> PPT (earned) PSP (spent) PFREE
  local v; PSP=0
  for v in $PARA_P; do PSP=$(( PSP + v )); done
  PPT=$(( PARA + (LVL - 1 > 36 ? LVL - 37 : 0) )); PFREE=$(( PPT - PSP )); (( PFREE < 0 )) && PFREE=0
}
para_learn() {  # stat index
  local p=($PARA_P) i=$1
  (( i >= 0 && i < 6 )) || return 1
  para_points
  (( PFREE > 0 )) || { logm "No paragon points to spend - they come with experience after level $MAXLVL." "$K_SYS"; return 1; }
  (( p[i] < PARA_MAX[i] )) || { logm "${PARA_NAME[i]} is at its maximum." "$K_SYS"; return 1; }
  p[i]=$(( p[i] + 1 )); PARA_P="${p[*]}"; calc_stats
  logm "${PARA_NAME[i]} ${p[i]}/${PARA_MAX[i]} (${PARA_DESC[i]})." "$K_GOOD"
}
para_bonus() {  # -> PB_DMG PB_HP PB_CRIT PB_RES PB_MP PB_CD
  local p=($PARA_P)
  PB_DMG=${p[0]:-0} PB_HP=${p[1]:-0} PB_CRIT=$(( ${p[2]:-0} / 2 )) PB_RES=${p[3]:-0} PB_MP=${p[4]:-0} PB_CD=${p[5]:-0}
}
para_xp() {  # after level 40: experience turns into paragon levels
  (( LVL >= MAXLVL )) || return
  para_next "$PARA"
  while (( XP >= PNX )); do
    XP=$(( XP - PNX )) PARA=$(( PARA + 1 ))
    logm "${EMJ[lvl]}*** PARAGON $PARA! A point to spend - [x], then [p]. ***" "$K_ANN"
    send EVT "$MY_ID" "$MY_NAME" "reached paragon level $PARA!"
    para_next "$PARA"
  done
  XPNEXT=$PNX
}

# --- valor ---------------------------------------------------------------------------------------------------
valor_add() {  # amount why
  (( $1 > 0 )) || return
  VALOR=$(( VALOR + $1 ))
  logm "+$1 valor${2:+ ($2)}  -  $VALOR in all. Spend it at a Valor Quartermaster." "$K_LOOT"
}
valor_buy() {  # index
  local i=$1 w c s
  (( i >= 0 && i < ${#VW_NAME[@]} )) || return
  c=${VW_COST[i]} w=${VW_WHAT[i]}
  (( VALOR >= c )) || { logm "You need ${c} valor (you have $VALOR)." "$K_HURT"; return; }
  case $w in
    gem) gem_mat $(( RANDOM % 6 )) 4; VALOR=$(( VALOR - c )); MATS[GM]=$(( MATS[GM] + 1 )); MAT_NEW[GM]=$(( ${MAT_NEW[GM]:-0} + 1 ))
         logm "A ${MAT_NAME[GM]} is yours." "$K_LOOT"; GEMP=1 ;;
    m*)  s=${w#m}; [[ ${MOUNTS:s:1} == 1 ]] && { logm "You already own the ${MNT_NAME[s]}." "$K_SYS"; return; }
         VALOR=$(( VALOR - c )); mount_give "$s" ;;
    LW|W|A|H|O|J)
         (( ${#INV[@]} < BAGS )) || { logm "Your bags are full." "$K_HURT"; return; }
         if [[ $w == LW ]]; then epic_item W 3 3 12; else epic_item "$w" 2 2 12; fi
         VALOR=$(( VALOR - c )); INV+=("$ITEM"); NEWG[$ITEM]=1; item_name "$ITEM" "$CLS"
         logm "The quartermaster hands you $INAME." $'\e['"${ICOL}m" ;;
  esac
  ach_check
}

# --- mounts --------------------------------------------------------------------------------------------------
mount_give() {  # index
  [[ ${MOUNTS:$1:1} == 1 ]] && return
  MOUNTS="${MOUNTS:0:$1}1${MOUNTS:$1+1}"; MNT_CUR=$1
  logm "${MNT_E[$1]} The ${MNT_NAME[$1]} is yours! Ride with [z], choose your mount with [Z]." "$K_ANN"
  send EVT "$MY_ID" "$MY_NAME" "rides a ${MNT_NAME[$1]} now!"
  ach_check
}
mount_has() { [[ ${MOUNTS:$1:1} == 1 ]]; }
mount_toggle() {
  if (( RIDING )); then mount_off; return; fi
  mount_has "$MNT_CUR" || { logm "You have no mount yet - Hilda the Stablemaster in Hearthmoor sells horses." "$K_SYS"; return; }
  [[ $CUR_MAP == W ]] || { logm "No mounts in dungeons." "$K_SYS"; return; }
  (( NOW - last_hurt > 3000 && NOW - ${last_att:-0} > 2000 )) || { logm "You can't mount up in the middle of a fight." "$K_HURT"; return; }
  RIDING=1 POS_DIRTY=1 MAP_DIRTY=1
  logm "${MNT_E[MNT_CUR]} You mount your ${MNT_NAME[MNT_CUR]} (+${MNT_SPD[MNT_CUR]}% speed)." "$K_GOOD"
}
mount_off() { (( RIDING )) || return; RIDING=0 POS_DIRTY=1 MAP_DIRTY=1; [[ $1 == quiet ]] || logm "You dismount." "$K_SYS"; }
mount_buy() {  # index (at Hilda's)
  local i=$1 r
  (( i >= 0 && i < NMNT && MNT_GOLD[i] > 0 )) || return
  mount_has "$i" && { logm "You already own the ${MNT_NAME[i]}." "$K_SYS"; return; }
  r=${MNT_REQ[i]}
  case $r in
    lvl:*) (( LVL >= ${r#lvl:} )) || { logm "Hilda: 'Come back at level ${r#lvl:}, this one bites.'" "$K_HURT"; return; } ;;
    rep:*) r=${r#rep:}; (( REP[${r%%:*}] >= ${r#*:} )) || { logm "Hilda: 'Only for the Honored of the ${FAC_NAME[${r%%:*}]}.'" "$K_HURT"; return; } ;;
  esac
  (( GOLD >= MNT_GOLD[i] )) || { logm "You need ${MNT_GOLD[i]} gold." "$K_HURT"; return; }
  GOLD=$(( GOLD - MNT_GOLD[i] )); mount_give "$i"
}
mount_delay() {  # next_move after a step: faster on horseback
  (( RIDING )) || return
  next_move=$(( NOW + (next_move - NOW) * 100 / (100 + MNT_SPD[MNT_CUR]) ))
}

# --- mythic keys ------------------------------------------------------------------------------------------------
myth_txt() {  # level -> MYT: "+7  Tyrannical, Molten, Raging"
  myth_afx; MYT="+$1"
  (( $1 >= 2 )) && MYT+="  ${MYTH_A[MA]}"
  (( $1 >= 4 )) && MYT+=", ${CHP_NAME[MB]}"
  (( $1 >= 7 )) && MYT+=", ${MYTH_C[MC]}"
}
myth_done() {  # level upgrade seconds valor (from the server)
  local k=$1 up=$2 s=$3
  MYDONE=$(( MYDONE + 1 ))
  if (( up > 0 )); then
    (( k > MYBEST )) && MYBEST=$k
    (( k + up > KEYLV )) && KEYLV=$(( k + up )); (( KEYLV > MYTH_MAX )) && KEYLV=$MYTH_MAX
    logm "MYTHIC +$k IN TIME ($(( s / 60 )):$(printf '%02d' $(( s % 60 )))) - your key rises to +$KEYLV!" "$K_ANN"
    send EVT "$MY_ID" "$MY_NAME" "completed a Mythic +$k in time!"
    dly_ev myth; (( k >= 15 )) && mount_give 6
  else
    logm "Mythic +$k completed - but too slow. Your key stays at +$KEYLV." "$K_SYS"
  fi
  dly_ev mythn
  valor_add "$4" "Mythic +$k"
  ach_check
}
myth_left() {  # -> MLS seconds left on the clock (negative: over time)
  MLS=$(( (IN_LIM - (NOW - IN_T0)) / 1000 ))
}

# --- dailies and weeklies -----------------------------------------------------------------------------------------
dly_pick() {  # seed count templates... -> DP: "kind:need:text" picks
  local seed=$1 n=$2 i j t; shift 2
  local pool=("$@") out=()
  for (( i = 0; i < n && ${#pool[@]}; i++ )); do
    j=$(( (seed * 7919 + i * 104729) % ${#pool[@]} )); t=${pool[j]}
    out+=("$t"); pool=("${pool[@]:0:j}" "${pool[@]:j+1}")
  done
  DP=("${out[@]}")
}
dly_fix() {  # new day / new week: new tasks
  local p pool=() t i r
  week_now
  if [[ ${DAILY%% *} != "$DAYN" ]]; then
    for t in "${DLY_T[@]}"; do [[ $t == myth* ]] && (( LVL < MAXLVL )) && continue; pool+=("$t"); done
    dly_pick "$DAYN" 3 "${pool[@]}"
    DAILY=$DAYN
    for (( i = 0; i < 3; i++ )); do DAILY+=" $(( ( (DAYN + i) * 31 ) % 100 )):0:0"; done
    DLY_CUR=("${DP[@]}")
  fi
  if [[ ${WEEKLY%% *} != "$WEEK" ]]; then
    WEEKLY=$WEEK; for (( i = 0; i < 2; i++ )); do WEEKLY+=" 0:0:0"; done
  fi
  dly_tasks
}
dly_tasks() {  # -> DLY_CUR (3 dailies) WKY_CUR (2 weeklies), DREG (the region of the kill daily)
  local pool=() t
  for t in "${DLY_T[@]}"; do [[ $t == myth* ]] && (( LVL < MAXLVL )) && continue; pool+=("$t"); done
  dly_pick "${DAILY%% *}" 3 "${pool[@]}"; DLY_CUR=("${DP[@]}")
  dly_pick "$(( ${WEEKLY%% *} + 5 ))" 2 "${WKY_T[@]}"; WKY_CUR=("${DP[@]}")
  DREG=${DLY_REG[$(( ${DAILY%% *} % ${#DLY_REG[@]} ))]}
}
dly_text() {  # "kind:need:text" -> DTX
  DTX=${1#*:}; DTX=${DTX#*:}; DTX=${DTX//%R/$DREG}
}
dly_ev() {  # kind [amount]: progress on today's and this week's tasks
  (( LVL >= 30 )) || return
  local k=$1 n=${2:-1} i a f need set
  [[ -n $DAILY ]] || dly_fix
  for set in d w; do
    if [[ $set == d ]]; then a=($DAILY) f=("${DLY_CUR[@]}"); else a=($WEEKLY) f=("${WKY_CUR[@]}"); fi
    for (( i = 0; i < ${#f[@]}; i++ )); do
      [[ ${f[i]%%:*} == "$k" ]] || continue
      local e=(${a[i+1]//:/ }); (( e[2] )) && continue
      need=${f[i]#*:}; need=${need%%:*}
      e[1]=$(( e[1] + n )); (( e[1] >= need )) && { e[1]=$need e[2]=1; dly_reward "$set" "${f[i]}"; }
      a[i+1]="${e[0]}:${e[1]}:${e[2]}"
    done
    if [[ $set == d ]]; then DAILY="${a[*]}"; else WEEKLY="${a[*]}"; fi
  done
}
dly_reward() {  # d|w task
  dly_text "$2"
  if [[ $1 == d ]]; then
    DLYK=$(( DLYK + 1 )); GOLD=$(( GOLD + 20 * LVL + 200 ))
    logm "DAILY DONE: $DTX!  +$(( 20 * LVL + 200 )) gold" "$K_ANN"; valor_add 30 daily; gain_xp $(( 300 * LVL ))
  else
    gem_mat $(( RANDOM % 6 )) 4; MATS[GM]=$(( MATS[GM] + 1 ))
    logm "WEEKLY DONE: $DTX!  +1 ${MAT_NAME[GM]}" "$K_ANN"; valor_add 150 weekly; gain_xp $(( 1000 * LVL ))
  fi
  ach_check
}
dly_kill() {  # monster type: kills count for the dailies
  (( LVL >= 30 )) || return
  local t=$1
  if [[ $CUR_MAP == W ]]; then region_of "$PX" "$PY" nosafe; [[ $RNAME == "$DREG" ]] && dly_ev kill; fi
  (( ${CM_CH[$KILL_MID]:-0} )) && dly_ev champ
  (( M_BOSS[t] == 2 )) && { dly_ev rare; RAREK=$(( RAREK + 1 )); }
  (( M_BOSS[t] == 1 )) && [[ $CUR_MAP == W ]] && [[ " ${WB_LIST[*]} " == *" $t "* ]] && dly_ev wboss
  if (( t == RD_NYX )); then
    RAIDK=$(( RAIDK + 1 )); dly_ev raid; valor_add 80 "the Eclipse Throne"
    (( RANDOM % 100 < 10 )) && mount_give 7
  fi
  (( t == W_RIDER && RANDOM % 100 < 8 )) && mount_give 5
}

# --- achievements and titles -------------------------------------------------------------------------------------------
ach_ok() {  # index -> 0 if earned
  local i=$1 n f
  case $i in
    0) (( LVL >= 20 )) ;; 1) (( LVL >= 30 )) ;; 2) (( LVL >= 40 )) ;; 3) (( PARA >= 10 )) ;; 4) (( PARA >= 50 )) ;;
    5) (( KILLS >= 2000 )) ;; 6) (( KILLS >= 10000 )) ;; 7) (( STORY >= 24 )) ;; 8) (( STORY >= NST )) ;;
    9|10) n=${QLS//[^x]/}; if (( i == 9 )); then (( ${#n} >= 10 )); else (( ${#n} >= NQL )); fi ;;
    11) (( DCLR >= 25 )) ;; 12) (( DCLR >= 100 )) ;;
    13) (( MYBEST >= 5 )) ;; 14) (( MYBEST >= 10 )) ;; 15) (( MYBEST >= 15 )) ;; 16) (( MYBEST >= 20 )) ;;
    17) (( RAIDK >= 1 )) ;; 18) (( RAIDK >= 10 )) ;;
    19|20) n=0; for f in "${REP[@]}"; do (( f >= REP_RANK[4] )) && n=$(( n + 1 )); done
           if (( i == 19 )); then (( n >= 1 )); else (( n >= NFAC )); fi ;;
    21) (( PROF_LV[0] >= PROF_MAX || PROF_LV[1] >= PROF_MAX || PROF_LV[2] >= PROF_MAX )) ;;
    22) (( PROF_LV[0] >= PROF_MAX && PROF_LV[1] >= PROF_MAX && PROF_LV[2] >= PROF_MAX )) ;;
    23) [[ $MOUNTS == *1* ]] ;; 24) [[ ${MOUNTS//1/} == "" ]] ;;
    25) (( RAREK >= 15 )) ;; 26) (( INVK >= 5 )) ;; 27) (( DLYK >= 50 )) ;;
    28) n=${EXPW//0/}; (( ${#n} * 100 >= ${#EXPW} * 80 )) ;;
    29) n=${SEEN//0/}; (( ${#n} >= 200 )) ;;
    30) (( GOLD >= 250000 )) ;; 31) (( GEMP )) ;;
    *) ach_ok50 "$i" ;;                                         # v5.0
  esac
}
ach_check() {  # unlock what is earned (cheap: a few tests per achievement)
  local i nm w
  [[ -n $ACHS ]] || v45_fix
  for (( i = 0; i < NACH; i++ )); do
    [[ ${ACHS:i:1} == 1 ]] && continue
    ach_ok "$i" || continue
    ACHS="${ACHS:0:i}1${ACHS:i+1}"; nm=${ACH[i]%%:*} w=${ACH[i]#*:}; w=${w%%:*}
    logm "🏆 ACHIEVEMENT: $nm - $w" "$K_ANN"
    (( ACH_QUIET )) || send EVT "$MY_ID" "$MY_NAME" "earned the achievement '$nm'!"
  done
  ACH_QUIET=0
}
ach_title() { local a=${ACH[$1]##*:}; ATT=$a; }                    # index -> ATT ("" none)
title_next() {  # cycle through the titles you have earned
  local i j
  for (( j = 1; j <= NACH + 1; j++ )); do
    i=$(( (TITLE + j + 1) % (NACH + 1) - 1 ))
    (( i < 0 )) && { TITLE=-1; logm "No title." "$K_SYS"; return; }
    [[ ${ACHS:i:1} == 1 ]] || continue
    ach_title "$i"; [[ -n $ATT ]] || continue
    TITLE=$i; logm "You are now known as $MY_NAME $ATT." "$K_GOOD"; return
  done
}
my_title() { TTL=""; (( TITLE >= 0 )) && { ach_title "$TITLE"; TTL=$ATT; }; }

v45_tick() {  # once a second
  (( NOW - ${ACH_T:-0} >= 5000 )) && { ACH_T=$NOW; ach_check; }
  if [[ ${DAILY%% *} != "${DAYN:-x}" ]] || (( NOW - ${DLY_T0:-0} > 60000 )); then DLY_T0=$NOW; week_now; [[ ${DAILY%% *} == "$DAYN" ]] || dly_fix; fi
}
