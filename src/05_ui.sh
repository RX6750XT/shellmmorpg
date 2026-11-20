# ---------------------------------------------------------------------------
#  Module 05 - screen and input: layout, the map frame, side panel, log,
#  menus drawn inside the frame, key handling and the client / dedicated
#  server main loops. Frames only send the screen lines that changed (emit).
# ---------------------------------------------------------------------------
layout() {
  local s r c
  s=$(stty size 2>/dev/null); r=${s% *}; c=${s#* }
  isnum "$r" && (( r > 0 )) || r=40
  isnum "$c" && (( c > 0 )) || c=120
  ROWS=$r COLS=$c
  SMALL=$(( COLS < 100 || ROWS < 30 ))
  if (( TW == 2 )); then      # HD: tiles are 2 columns wide (and look square)
    VW=$(( (COLS - 44) / 2 )); (( VW > 45 )) && VW=45; (( VW % 2 )) || VW=$(( VW - 1 )); (( VW < 21 )) && VW=21
  else
    VW=$(( COLS - 44 )); (( VW > 81 )) && VW=81; (( VW % 2 )) || VW=$(( VW - 1 )); (( VW < 41 )) && VW=41
  fi
  VH=$(( ROWS - 10 )); (( VH > 31 )) && VH=31; (( VH % 2 )) || VH=$(( VH - 1 )); (( VH < 13 )) && VH=13
  MW=$(( VW * TW ))
  PCOL=$(( MW + 4 )) LOGY=$(( VH + 4 )) INPY=$(( VH + 10 ))
  printf -v BLANK '%*s' 240 ''
  NEED_FULL=1 MAP_DIRTY=1 WM_CZ="" CLIPC=()
  [[ $UI == map ]] && wm_open keep
}

# SCR[key] = what a screen line shows right now: a frame only sends the lines that changed
declare -A SCR=()
emit() { [[ ${SCR[$1]} == "$2" ]] && return; SCR[$1]=$2; out+=$2; }   # key text

draw_frame() {
  local bar r
  SCR=()
  printf -v bar '%*s' "$MW" ''; bar=${bar// /─}
  out+=$'\e[0m\e[2J'"$K_FRAME"$'\e[2;1H'"╭${bar}╮"
  for (( r = 3; r < VH + 3; r++ )); do out+=$'\e['"$r;1H│"$'\e['"$r;$(( MW + 2 ))H│"; done
  out+=$'\e['"$(( VH + 3 ));1H╰${bar}╯$N"
}

update_fog() {
  local map=$CUR_MAP mw=${MAPW[$CUR_MAP]} mh=${MAPH[$CUR_MAP]} dy y half x1 x2 real mem
  for (( dy = -LRY; dy <= LRY; dy++ )); do
    y=$(( PY + dy )); (( y < 0 || y >= mh )) && continue
    half=${LSPAN[dy+LRY]}; x1=$(( PX - half )) x2=$(( PX + half ))
    (( x1 < 0 )) && x1=0; (( x2 > mw - 1 )) && x2=$(( mw - 1 ))
    real=${MAPROW[$map:$y]} mem=${EXPL[$map:$y]}
    EXPL["$map:$y"]="${mem:0:x1}${real:x1:x2-x1+1}${mem:x2+1}"
  done
}

# compose lo hi item... : colorize ${row:lo..hi} and splice in glyphs/tags.
# item = "<x*10+prio>:<width>:<key>" ; key = glyph key in GLY, or t<n> for TAGS[n]
compose() {
  local lo=$1 hi=$2 pos=$1 it s x w k i j t arr=()
  shift 2
  for it in "$@"; do
    s=${it%%:*}; x=$(( s / 10 )); t=${it#*:}; w=${t%%:*}
    (( x >= lo && x + w - 1 <= hi )) && arr+=("$it")
  done
  for (( i = 1; i < ${#arr[@]}; i++ )); do
    t=${arr[i]}; j=$(( i - 1 ))
    while (( j >= 0 && ${arr[j]%%:*} > ${t%%:*} )); do arr[j+1]=${arr[j]}; j=$(( j - 1 )); done
    arr[j+1]=$t
  done
  COMP=""
  for it in "${arr[@]}"; do
    s=${it%%:*}; x=$(( s / 10 )); t=${it#*:}; w=${t%%:*}; k=${t#*:}
    (( x < pos )) && continue
    if (( LITMODE )) && [[ $k == m* ]] && ! is_lit "$x"; then continue; fi    # hidden in the dark
    if (( x > pos )); then CZ=${row:pos:x-pos}; PZ=$pos; paint; COMP+=$CZ; fi
    if [[ $k == t* ]]; then COMP+=${TAGS[${k#t}]}
    elif (( TW == 2 )); then                                   # sprite on the ground it stands on
      if (( LITMODE )) && ! is_lit "$x"; then COMP+="$Z_DARKBG${GLYH[$k]:-${GLY[$k]} }"
      else COMP+="${TBG[${row:x:1}]}${GLYH[$k]:-${GLY[$k]} }"; fi
    else COMP+=${GLY[$k]}; fi
    pos=$(( x + w ))
  done
  if (( pos <= hi )); then CZ=${row:pos:hi-pos+1}; PZ=$pos; paint; COMP+=$CZ; fi
}
paint() {  # colorize; night/storm: only the lit spans (LITR) get color; world map: grey sketch
  if (( COMP_DIM && TW == 2 )); then local Z_DARK=$'\e[0;38;5;240;48;5;234m'; dark_paint; return; fi
  if (( COMP_DIM )); then
    CZ=${CZ//[SNAI_:%KJDEqMHB]/.}; CZ=${CZ//[snF]/,}; CZ=${CZ//[PYWyU]/T}; CZ=${CZ//[LG]/'~'}; CZ=${CZ//[RCVX]/^}; CZ=${CZ//Z/.}; CZ=${CZ//[QO]/.}
    CZ="$Z_FOG$CZ"; return
  fi
  (( LITMODE )) || { colorize_at; return; }
  local s=$CZ p=$PZ e=$(( PZ + ${#CZ} - 1 )) iv a b hi o=""
  for iv in $LITR; do
    a=${iv%:*} b=${iv#*:}
    (( b < p )) && continue
    (( a > e )) && break
    if (( a > p )); then
      if (( TR_ON )); then dark_at "$p" $(( a - p )); else CZ=${s:0:a-p}; dark_paint; fi
      o+=$CZ; s=${s:a-p}; p=$a
    fi
    hi=$(( b < e ? b : e ))
    CZ=${s:0:hi-p+1}; PZ=$p; colorize_at; o+=$CZ; s=${s:hi-p+1}; p=$(( hi + 1 ))
    (( p > e )) && break
  done
  if (( p <= e )); then if (( TR_ON )); then dark_at "$p" "${#s}"; else CZ=$s; dark_paint; fi; o+=$CZ; fi
  CZ=$o
}

free_span() {  # row x len -> 0 if no item of that row overlaps
  local it s x t w
  for it in ${RI[$1]}; do
    s=${it%%:*}; x=$(( s / 10 )); t=${it#*:}; w=${t%%:*}
    (( x + w >= $2 && x <= $2 + $3 )) && return 1    # keep one cell distance to everything
  done
  return 0
}

add_tag() {  # dx dy text style - finds a free spot above/below, sliding sideways if needed
  local txt=" $3 " len tx t0 ty o x
  if (( TW == 2 )); then                      # HD: a tag covers whole tiles (2 columns each)
    dispw "$3"
    if (( ${#3} == 1 )); then if (( DW == 2 )); then txt=$3; else txt=" $3"; fi; fi   # lone emoji: exactly one tile
    dispw "$txt"; (( DW % 2 )) && { txt+=" "; DW=$(( DW + 1 )); }
    len=$(( DW / 2 ))
  else len=${#txt}; fi
  (( len > VW )) && return
  t0=$(( $1 - len / 2 ))
  for ty in $(( $2 - 1 )) $(( $2 + 1 )) $(( $2 - 2 )) $(( $2 + 2 )); do
    (( ty >= 0 && ty < VH )) || continue
    for (( o = 0; o <= len; o++ )); do
      for x in $(( t0 - o )) $(( t0 + o )); do
        tx=$x; (( tx < 0 )) && tx=0; (( tx > VW - len )) && tx=$(( VW - len ))
        (( tx <= $1 && tx + len > $1 )) || continue      # the tag must sit right above/below its owner
        free_span "$ty" "$tx" "$len" || continue
        TAGS+=("$4$txt$N"); RI[ty]+="$(( tx * 10 + 5 )):$len:t$(( ${#TAGS[@]} - 1 )) "
        return
      done
    done
  done
}

render_rows() {  # the terrain of every view row (+ sprites and tags); called by render_map
  # byte-wise string offsets are much faster - every string cut here is ASCII or a tile row cut by byte offsets
  local LC_ALL=C ry y row mem dy lx1 lx2
  TR_ON=1 TR_X0=$cx0 TR_W=$mw
  for (( ry = 0; ry < VH; ry++ )); do
    y=$(( cy0 + ry ))
    if (( y < 0 || y >= mh )); then emit "m$ry" $'\e['"$(( ry + 3 ));2H$N${BLANK:0:MW}"; continue; fi
    if (( TW == 2 )); then [[ -n ${VROW[$map:$y]} ]] || build_vrow "$map" "$y"; row=${VROW[$map:$y]}; else row=${MAPROW[$map:$y]}; fi
    tiles_row "$map" "$y"
    if (( cx0 < 0 )); then row="${BLANK:0:-cx0}$row"; row=${row:0:VW}; else row=${row:cx0:VW}; fi
    (( ${#row} < VW )) && row+=${BLANK:0:VW-${#row}}
    if (( dark )); then
      mem=${EXPL[$map:$y]}
      if (( cx0 < 0 )); then mem="${BLANK:0:-cx0}$mem"; mem=${mem:0:VW}; else mem=${mem:cx0:VW}; fi
      (( ${#mem} < VW )) && mem+=${BLANK:0:VW-${#mem}}
      mem=${mem//_/.}
      dy=$(( y - PY ))
      if (( dy >= -LRY && dy <= LRY )); then
        lx1=$(( PX - LSPAN[dy+LRY] - cx0 )) lx2=$(( PX + LSPAN[dy+LRY] - cx0 ))
        (( lx1 < 0 )) && lx1=0; (( lx2 > VW - 1 )) && lx2=$(( VW - 1 ))
        compose "$lx1" "$lx2" ${RI[ry]}
        CZ=${mem:0:lx1}; mem_paint; row=$CZ$COMP
        CZ=${mem:lx2+1}; mem_paint; row+=$CZ
      else
        CZ=$mem; mem_paint; row=$CZ
      fi
    else
      LITR=${LIT[ry]}
      compose 0 $(( VW - 1 )) ${RI[ry]}
      row=$COMP
    fi
    emit "m$ry" $'\e['"$(( ry + 3 ));2H$row"
  done
}

render_map() {
  local map=$CUR_MAP mw=${MAPW[$CUR_MAP]} mh=${MAPH[$CUR_MAP]} cx0 cy0 ry y row m dx dy p i txt
  local lx1 lx2 mem dark=0
  RI=() TAGS=()
  cx0=$(( PX - VW / 2 )) cy0=$(( PY - VH / 2 ))
  if (( mw > VW )); then (( cx0 < 0 )) && cx0=0; (( cx0 > mw - VW )) && cx0=$(( mw - VW )); else cx0=$(( (mw - VW) / 2 )); fi
  if (( mh > VH )); then (( cy0 < 0 )) && cy0=0; (( cy0 > mh - VH )) && cy0=$(( mh - VH )); else cy0=$(( (mh - VH) / 2 )); fi
  if (( TW == 2 )); then                       # rolling waves & bubbling lava
    if (( NOW / 700 % 2 )); then Z2_i=$WAVE Z2_j=$CALM; else Z2_i=$CALM Z2_j=$WAVE; fi
    if (( NOW / 450 % 2 )); then Z2_LAVA=$LAVA_A Z2_v=$LAVA_B; else Z2_LAVA=$LAVA_B Z2_v=$LAVA_A; fi
    TR_PH=$(( (NOW / 700 % 2) * 2 + NOW / 450 % 2 ))
  fi
  mons_rect "$cx0" "$cy0" $(( cx0 + VW - 1 )) $(( cy0 + VH - 1 )); local vis=("${MR[@]}")
  for m in "${vis[@]}"; do
    dx=$(( CM_X[m] - cx0 )) dy=$(( CM_Y[m] - cy0 ))
    if (( NOW - ${HITF[$m]:-0} < 160 )); then                  # flash red when hit
      i=${CM_T[m]}
      GLY[mx$m]=$'\e[0;1;38;5;231;48;5;196m'"${M_GLY[i]}" GLYH[mx$m]=$'\e[0;48;5;196m'"${MEMO[i]:-${M_GLY[i]} }"
      RI[dy]+="$(( dx * 10 + 3 )):1:mx$m "; MAP_DIRTY=1
    else
      RI[dy]+="$(( dx * 10 + 3 )):1:m${CM_T[m]} "
    fi
  done
  for p in "${!OP_MAP[@]}"; do
    [[ ${OP_MAP[$p]} == "$map" && -n ${GLY[p$p]} ]] || continue
    dx=$(( ${OP_X[$p]} - cx0 )) dy=$(( ${OP_Y[$p]} - cy0 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) && RI[dy]+="$(( dx * 10 + 2 )):1:p$p "
  done
  if (( ALLY >= 0 )) && [[ $ALY_MAP == "$map" ]]; then         # my ally, then everybody else's
    dx=$(( AX - cx0 )) dy=$(( AY - cy0 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) && RI[dy]+="$(( dx * 10 + 4 )):1:a$ALLY "
  fi
  for p in "${!OP_ALY[@]}"; do
    [[ ${OP_MAP[$p]} == "$map" ]] || continue
    dx=$(( ${OP_AX[$p]} - cx0 )) dy=$(( ${OP_AY[$p]} - cy0 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) && RI[dy]+="$(( dx * 10 + 4 )):1:a${OP_ALY[$p]} "
  done
  for i in "${!FX_E[@]}"; do
    if (( FX_E[i] < NOW )); then unset "FX_X[i]" "FX_Y[i]" "FX_K[i]" "FX_E[i]"; continue; fi
    dx=$(( FX_X[i] - cx0 )) dy=$(( FX_Y[i] - cy0 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) && RI[dy]+="$(( dx * 10 + ${FXP[${FX_K[i]}]:-0} )):1:f${FX_K[i]} "
  done
  [[ $map == W && -n $CW ]] && add_particles
  [[ $map == H* ]] && room_overlay "$cx0" "$cy0"               # v5.0: the furniture of a room
  if (( DEAD )); then GLY[self]=$'\e[0;38;5;240m'"$SYM" GLYH[self]=$'\e[0;48;5;238m💀'
  elif (( NOW - last_hurt < 180 )); then
    GLY[self]=$'\e[0;1;38;5;231;48;5;196m'"$SYM" GLYH[self]=$'\e[0;48;5;196m'"${CEMO[CLS]}"; MAP_DIRTY=1
  elif (( RIDING )); then GLY[self]=$'\e[0;1;7;38;5;'"${P_COLC[COLR]}m$SYM" GLYH[self]=$'\e[0;48;5;'"${P_COLC[COLR]}m${MNT_E[MNT_CUR]}"
  else GLY[self]=$'\e[0;1;7;38;5;'"${P_COLC[COLR]}m$SYM" GLYH[self]=$'\e[0;48;5;'"${P_COLC[COLR]}m${CEMO[CLS]}"; fi
  dx=$(( PX - cx0 )) dy=$(( PY - cy0 )); RI[dy]+="$(( dx * 10 + 1 )):1:self "
  ft_items "$cx0" "$cy0"; hp_tag "$cx0" "$cy0"
  # name tags & chat bubbles (only for players that are actually visible)
  for p in "${!OP_MAP[@]}"; do
    [[ ${OP_MAP[$p]} == "$map" ]] || continue
    dx=$(( ${OP_X[$p]} - cx0 )) dy=$(( ${OP_Y[$p]} - cy0 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) || continue
    if [[ $map == D* ]]; then cheb $(( ${OP_X[$p]} - PX )) $(( ${OP_Y[$p]} - PY )); (( D <= LRY )) || continue; fi
    if (( ${OP_SAYT[$p]:-0} > NOW )); then
      add_tag "$dx" "$dy" "${OP_SAY[$p]:0:26}" $'\e[0;38;5;16;48;5;254m'
    elif (( TAGS_ON )); then
      if (( ${OP_WANTED[$p]:-0} > NOW )); then add_tag "$dx" "$dy" "${OP_NAME[$p]} WANTED" $'\e[0;1;38;5;231;48;5;124m'
      elif in_party "$p"; then add_tag "$dx" "$dy" "${OP_NAME[$p]}" $'\e[0;38;5;'"${P_COLC[${OP_COL[$p]:-0}]};48;5;22m"
      else add_tag "$dx" "$dy" "${OP_NAME[$p]}" $'\e[0;38;5;'"${P_COLC[${OP_COL[$p]:-0}]};48;5;235m"; fi
    fi
  done
  (( MY_SAYT > NOW )) && add_tag $(( PX - cx0 )) $(( PY - cy0 )) "${MY_SAY:0:26}" $'\e[0;38;5;16;48;5;254m'
  if [[ $map == W && -n $WB_CID && -n ${CM_T[$WB_CID]} ]]; then   # the world boss wears a big red name
    dx=$(( CM_X[$WB_CID] - cx0 )) dy=$(( CM_Y[$WB_CID] - cy0 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) && add_tag "$dx" "$dy" "${EMJ[crown]}${M_NAME[${CM_T[$WB_CID]}]}" $'\e[0;1;38;5;231;48;5;124m'
  fi
  if [[ $map == W ]]; then                  # quest givers show !, delivery targets show ?
    local t
    for m in "${vis[@]}"; do
      t=${CM_T[m]}
      if (( M_KIND[t] == 0 )); then                                # v3.0: champions and elites stand out
        if (( ${CM_CH[$m]:-0} )); then
          if (( TW2 )); then add_tag $(( CM_X[m] - cx0 )) $(( CM_Y[m] - cy0 )) "${CHP_E[CM_CH[m]-1]}" $'\e[0;48;5;236m'
          else add_tag $(( CM_X[m] - cx0 )) $(( CM_Y[m] - cy0 )) "*" $'\e[0;'"${CHP_COL[CM_CH[m]-1]};48;5;236m"; fi
        elif (( M_BOSS[t] == 2 )); then
          if (( TW2 )); then add_tag $(( CM_X[m] - cx0 )) $(( CM_Y[m] - cy0 )) "💀" $'\e[0;48;5;236m'
          else add_tag $(( CM_X[m] - cx0 )) $(( CM_Y[m] - cy0 )) "E" $'\e[0;1;38;5;231;48;5;124m'; fi
        fi
        continue
      fi
      (( M_KIND[t] == 1 )) || continue
      dx=$(( CM_X[m] - cx0 )) dy=$(( CM_Y[m] - cy0 ))
      if (( TW2 )); then
        if story_npc "$t"; then add_tag "$dx" "$dy" "⭐" $'\e[0;48;5;236m'
        elif chain_npc "$t"; then add_tag "$dx" "$dy" "❕" $'\e[0;48;5;236m'
        elif turnin_for "$t"; then add_tag "$dx" "$dy" "❓" $'\e[0;48;5;236m'
        elif [[ -n ${N_QK[$t]}${N_QD[$t]} ]]; then add_tag "$dx" "$dy" "❗" $'\e[0;48;5;236m'; fi
      elif story_npc "$t"; then add_tag "$dx" "$dy" "*" $'\e[0;1;38;5;16;48;5;214m'
      elif chain_npc "$t"; then add_tag "$dx" "$dy" "!" $'\e[0;1;38;5;16;48;5;208m'
      elif turnin_for "$t"; then add_tag "$dx" "$dy" "?" $'\e[0;1;38;5;16;48;5;46m'
      elif [[ -n ${N_QK[$t]}${N_QD[$t]} ]]; then add_tag "$dx" "$dy" "!" $'\e[0;1;38;5;16;48;5;226m'; fi
    done
  fi
  LITMODE=0 LITR=""
  if [[ $map == D* ]]; then dark=1; update_fog
  elif [[ $map == W ]] && (( NR > 0 || WR > 0 )); then LITMODE=1; build_lit "$cx0" "$cy0"; fi
  render_rows
  unset "SCR[m$(( VH - 2 ))]" "SCR[m$(( VH - 3 ))]" "SCR[m$(( VH / 2 ))]" "SCR[m$(( VH / 2 - 5 ))]"   # under the overlays
  out+=$N
  LITMODE=0 TR_ON=0
  draw_overlay
  if (( DEAD )); then
    local msg="   YOU DIED - respawning in $(( (dead_until - NOW + 999) / 1000 ))s   "
    out+=$'\e['"$(( VH / 2 + 3 ));$(( (MW - ${#msg}) / 2 + 2 ))H"$'\e[1;97;41m'"$msg$N"
  elif (( clear_until )); then
    local msg="   DUNGEON CLEARED - teleporting in $(( (clear_until - NOW + 999) / 1000 ))s   "
    out+=$'\e['"$(( VH / 2 - 2 ));$(( (MW - ${#msg}) / 2 + 2 ))H"$'\e[1;30;43m'"$msg$N"
  fi
}

render_header() {
  local loc st on=$(( ${#OP_NAME[@]} + 1 ))
  if [[ $CUR_MAP == W ]]; then
    region_of "$PX" "$PY"
    if [[ $RLVL == safe ]]; then loc="$RNAME ${K_GOOD}(safe)$N"; else loc="$RNAME ${K_SYS}(lvl $RLVL)$N"; fi
  elif [[ $CUR_MAP == H* ]]; then                                     # v5.0: a room at the inn
    if [[ $RM_OWNER == "$MY_ID" ]]; then loc=$'\e[38;5;180m'"your ${ROOM_NAME[RM_TIER]}$N"
    else loc=$'\e[38;5;180m'"${OP_NAME[$RM_OWNER]:-someone}'s ${ROOM_NAME[RM_TIER]}$N"; fi
  else
    loc=$'\e[38;5;203m'"${D_NAME[CUR_DT]}$N"
  fi
  if (( ! net_up )); then st="${K_HURT}offline - reconnecting$N"
  elif [[ $MODE == host ]]; then st="hosting :$NET_PORT"
  else st="online @ $NET_HOST:$NET_PORT"; fi
  clock_txt
  local wt=""; [[ -n $CW ]] && wt=" "$'\e[38;5;153m'"${TW2:+${WEA_E[$CW]} }${WEA_LABEL[$CW]}$N"
  local h=$'\e[1;38;5;214m shellmmorpg'"$N ${K_SYS}|$N ${B}$loc ${K_SYS}|$N $CLKT$wt ${K_SYS}| $PX,$PY | $on online | $st$N"
  (( WANTED_UNTIL > NOW )) && h+="  "$'\e[1;5;38;5;231;48;5;124m'" WANTED $(( (WANTED_UNTIL - NOW + 999) / 1000 ))s $N"
  clipc "$h" "$COLS"
  emit hdr $'\e[1;1H\e[48;5;235m'"${CL//"$N"/$'\e[0;48;5;235m'}"$'\e[K\e[0m'
}

dir_of() {  # dx dy -> DIR
  local h="" v=""
  (( $2 < -1 )) && v=N; (( $2 > 1 )) && v=S; (( $1 < -1 )) && h=W; (( $1 > 1 )) && h=E
  DIR="$v$h"; [[ -n $DIR ]] || DIR=here
}

psym() {  # id -> PS (colored symbol of a player)
  PS=$'\e[1;38;5;'"${P_COLC[${OP_COL[$1]:-0}]}m${OP_SYM[$1]:-@}$N"
}

PEQ_K="" PEQ_L=() PRAW=()
render_panel() {
  local L=() k s c txt id nm tag i line
  L+=($'\e[1;7;38;5;'"${P_COLC[COLR]}m$SYM$N ${B}$MY_NAME$N  ${K_SYS}Lv$N ${B}$LVL$N ${C_NAME[CLS]}")
  (( PARA )) && L[0]+=" ${K_LOOT}P$PARA$N"
  (( TITLE >= 0 )) && { my_title; L+=("  ${K_SYS}$TTL$N"); }
  hp_col "$HP" "$MAXHP"; pbar "$HP" "$MAXHP" 18 "$HC"; L+=("HP $PB $HP/$MAXHP")
  pbar "$MP" "$MAXMP" 18 $'\e[38;5;33m';  L+=("MP $PB $MP/$MAXMP")
  pbar "$XP" "$XPNEXT" 18 $'\e[38;5;220m'; L+=("XP $PB $(( XP * 100 / XPNEXT ))%")
  if (( IN_MK )) && [[ $CUR_MAP == D* ]]; then                       # v4.5: the mythic clock
    myth_left; local mc=$K_GOOD; (( MLS < 60 )) && mc=$K_HURT; (( MLS < 0 )) && mc=$K_SYS
    printf -v PF '%d:%02d' $(( (MLS < 0 ? -MLS : MLS) / 60 )) $(( (MLS < 0 ? -MLS : MLS) % 60 ))
    local ov=""; (( MLS < 0 )) && ov="over "
    L+=("${K_LOOT}MYTHIC +$IN_MK$N  $mc$ov$PF$N")
  fi
  if (( TW2 )); then L+=("💰 ${K_LOOT}$GOLD$N   ${K_SYS}[e]$N 🍷 $POT_H+$POT_GH   ${K_SYS}[r]$N 🧪 $POT_M+$POT_GM")
  else L+=("${K_LOOT}$GOLD gold$N  ${K_SYS}[e]$N $POT_H+$POT_GH HP  ${K_SYS}[r]$N $POT_M+$POT_GM MP"); fi
  if [[ $PEQ_K != "$TW2|$CLS|$EQW|$EQA|$EQO|$EQH|$EQJ" ]]; then   # gear lines only change with the gear
    PEQ_K="$TW2|$CLS|$EQW|$EQA|$EQO|$EQH|$EQJ" PEQ_L=()
    if (( TW2 )); then
      item_name "$EQW" "$CLS"; item_icon "$EQW" "$CLS"; PEQ_L+=("$II "$'\e['"${ICOL}m$INAME$N +$IVAL")
      item_name "$EQA" "$CLS"; item_icon "$EQA" "$CLS"; PEQ_L+=("$II "$'\e['"${ICOL}m$INAME$N +$IVAL")
      txt=""
      for k in O H J; do
        eq_of "$k"
        if [[ -n $EQC ]]; then item_name "$EQC" "$CLS"; txt+="$IKE "$'\e['"${ICOL}m${IKN}$N  "; else txt+="${K_SYS}no ${SLOT_LABEL[$k],,}$N  "; fi
      done
      PEQ_L+=("$txt")
    else
      item_name "$EQW" "$CLS"; PEQ_L+=("${K_SYS}Wpn$N "$'\e['"${ICOL}m$INAME$N +$IVAL")
      item_name "$EQA" "$CLS"; PEQ_L+=("${K_SYS}Arm$N "$'\e['"${ICOL}m$INAME$N +$IVAL")
      txt=""
      for k in O H J; do
        eq_of "$k"
        if [[ -n $EQC ]]; then item_name "$EQC" "$CLS"; txt+="${K_SYS}${SLOT_LABEL[$k]:0:3}$N "$'\e['"${ICOL}m${IKN}$N  "; fi
      done
      [[ -n $txt ]] && PEQ_L+=("$txt")
    fi
  fi
  L+=("${PEQ_L[@]}")
  txt="${K_SYS}Attack$N $ATK  ${K_SYS}Armor$N $ARMOR  ${K_SYS}Crit$N $CRIT% "
  if (( TW2 )); then          # v1.7: running effects as icons
    active_fx; (( ${#AFX_E[@]} )) && { txt+=" "; for k in "${AFX_E[@]}"; do txt+=$k; done; }
    (( NOW < immune_until )) && txt+="✨"
  else
  (( NOW < buff_until ))   && txt+=" ${K_GOOD}FURY$N"
  (( NOW < anthem_until )) && txt+=" ${K_GOOD}ANTHEM$N"
  (( NOW < str_until ))    && txt+=" ${K_GOOD}STR$N"
  (( NOW < iron_until ))   && txt+=" ${K_GOOD}IRON$N"
  (( NOW < swift_until ))  && txt+=" ${K_GOOD}SWIFT$N"
  (( NOW < immune_until )) && txt+=" ${K_GOOD}IMMUNE$N"
  (( NOW < fed_until ))    && txt+=" ${K_GOOD}FED$N"
  (( NOW < fireward_until )) && txt+=" ${K_GOOD}WARD$N"
  (( NOW < frost_until ))  && txt+=" ${K_GOOD}FROST$N"
  (( NOW < veil_until ))   && txt+=" ${K_GOOD}VEIL$N"
  fi
  ps_line; [[ -n $PSL ]] && L+=("$PSL")
  tal_points; (( TFREE > 0 )) && L+=("${K_GOOD}$TFREE talent point(s) to spend - [x]$N")
  hdr SKILLS; L+=("$txt" "" "$HDR")
  for k in 0 1 2; do
    s=$(( CLS * 3 + k ))
    c=$(( SKCD[k] - NOW ))
    if (( c > 0 )); then txt="${K_SYS}$(( (c + 999) / 1000 ))s$N"
    elif (( MP < S_MP[s] )); then txt="${K_HURT}no mana$N"
    else txt="${K_GOOD}ready$N"; fi
    printf -v line '[%d] %-13s %2dmp ' $(( k + 1 )) "${S_NAME[s]}" "${S_MP[s]}"
    (( TW2 )) && line="${line:0:4}${SKILL_E[s]}${line:3}"
    L+=("$line$txt")
  done
  if [[ -n $TARGET && -n ${CM_T[$TARGET]} ]]; then
    k=${CM_T[$TARGET]}
    pbar "${CM_HP[$TARGET]}" "${CM_MAX[$TARGET]}" 18 $'\e[38;5;160m'
    con_col "${M_LVL[k]}"
    hdr TARGET; L+=("" "$HDR ${GLYP[m$k]}$N ${CC}${N_FULL[$k]:-${M_NAME[k]}}$N ${K_SYS}Lv ${M_LVL[k]}$N" "   $PB ${CM_HP[$TARGET]}")
    target_info "$TARGET"; [[ -n $TIL ]] && L+=("$TIL")
  fi
  if [[ -n $MY_PARTY ]]; then
    hdr PARTY; L+=("" "$HDR")
    for id in "${PARTY_IDS[@]}"; do
      [[ $id == "$MY_ID" ]] && continue
      nm=${OP_NAME[$id]:-?}
      if [[ -z ${OP_MAP[$id]} ]]; then tag="${K_SYS}offline$N"
      elif [[ ${OP_DEAD[$id]} == 1 ]]; then tag="${K_HURT}dead$N"
      elif [[ ${OP_MAP[$id]} != "$CUR_MAP" ]]; then tag="${K_SYS}away$N"
      else cheb $(( ${OP_X[$id]} - PX )) $(( ${OP_Y[$id]} - PY )); tag="${K_SYS}${D}m$N"; fi
      pbar "${OP_HP[$id]:-0}" "${OP_MAX[$id]:-1}" 8 $'\e[38;5;46m'
      [[ $id == "$PARTY_LEADER" ]] && nm="$nm*"
      printf -v line '%-11s' "$nm"; psym "$id"
      L+=("$PS ${K_PARTY}$line$N $PB ${C_NAME[${OP_CLS[$id]:-0}]:0:4} ${OP_LVL[$id]:-?} $tag")
    done
  fi
  if [[ -n $WB_CID ]]; then
    k=$WB_CT; con_col "${M_LVL[k]}"; QTX=$WB_CX QTY=$WB_CY; track
    L+=("" $'\e[1;38;5;231;48;5;124m'" WORLD BOSS $N ${GLYP[m$k]}$N ${CC}${M_NAME[k]}$N ${K_SYS}Lv ${M_LVL[k]} $TRK$N")
  fi
  story_line
  if [[ -n $SL ]] || (( ${#QUESTS[@]} + ${#PQ_CODES[@]} )); then
    hdr QUESTS; L+=("" "$HDR")
    [[ -n $SL ]] && L+=(" ${K_LOOT}$SL$N")
    for k in "${PQ_CODES[@]}"; do quest_info "$k"; track; L+=(" ${K_PARTY}P$N $QGLY $QSHORT ${K_SYS}$TRK$N"); done
    for k in "${QUESTS[@]}"; do quest_info "$k"; track; L+=(" ${K_LOOT}!$N $QGLY $QSHORT ${K_SYS}$TRK$N"); done
  fi
  c=0
  for id in "${!OP_MAP[@]}"; do
    [[ ${OP_MAP[$id]} == "$CUR_MAP" ]] && ! in_party "$id" || continue
    cheb $(( ${OP_X[$id]} - PX )) $(( ${OP_Y[$id]} - PY )); (( D <= 30 )) || continue
    (( c == 0 )) && { hdr NEARBY; L+=("" "$HDR"); }
    dir_of $(( ${OP_X[$id]} - PX )) $(( ${OP_Y[$id]} - PY )); psym "$id"
    txt="$PS ${OP_NAME[$id]} ${K_SYS}${C_NAME[${OP_CLS[$id]:-0}]} ${OP_LVL[$id]} - ${D}m $DIR$N"
    (( ${OP_WANTED[$id]:-0} > NOW )) && txt+=" ${K_HURT}WANTED$N"
    L+=("$txt")
    c=$(( c + 1 )); (( c >= 3 )) && break
  done
  local pw=$(( COLS - PCOL + 1 ))
  for (( i = 0; i < VH + 2; i++ )); do
    [[ ${L[i]} == "${PRAW[i]}" && -n ${SCR[p$i]+x} ]] && continue     # same line as last frame and still on screen
    PRAW[i]=${L[i]}; clipc "${L[i]}" "$pw"; emit "p$i" $'\e['"$(( i + 2 ));${PCOL}H$CL"$'\e[K'
  done
}

render_log() {  # events on top, the last chat lines below
  local ne=${#LOG_T[@]} nc=${#CHL_T[@]} rows_c i r=0 w=$(( COLS - 2 )) start
  rows_c=$(( nc < 3 ? nc : 3 ))
  start=$(( ne - (6 - rows_c) )); (( start < 0 )) && start=0
  local l
  for (( i = start; i < start + 6 - rows_c; i++ )); do
    l=$'\e['"$(( LOGY + r ));1H"
    (( i < ne )) && { clipc "${LOG_C[i]}${LOG_T[i]:0:w}" "$w"; l+=" $CL"; }
    emit "l$r" "$l"$'\e[K'; r=$(( r + 1 ))
  done
  for (( i = nc - rows_c; i < nc; i++ )); do
    clipc "${CHL_C[i]}${CHL_T[i]:0:w}" "$w"
    emit "l$r" $'\e['"$(( LOGY + r ));1H"$'\e[48;5;234m'" ${CL%$'\e[0m'}"$'\e[K'"$N"; r=$(( r + 1 ))
  done
}

render_input() {
  local t=$CHAT_BUF w=$(( COLS - 12 )) l=$'\e['"$INPY;1H"
  if (( CHATTING )); then
    (( ${#t} > w )) && t=${t: -w}
    l+=$' \e[1;38;5;51msay>'"$N $t"$'\e[5m_\e[0m'
  else
    t=" [wasd] move [1-3] skills [e/r] potions [u] eat [g] fish/gather [i]nv [x] talents [y] allies [p]rof [m]ap [q]uests [b]easts [c]hat log [H] collection [v] graphics [enter] chat [?] help"
    l+="${K_SYS}${t:0:COLS-1}$N"
  fi
  emit inp "$l"$'\e[K'
}

# --- full-screen panels drawn inside the map frame ------------------------
ui() { UIT+=("$1"); UIC+=("${2:-$K_CHAT}"); UIL+=(-1); }
uix() {  # pre-colored line [its plain twin, for the width - measured if left out]
  UIT+=("$1"); UIC+=("")
  if (( $# > 1 )); then dispw "$2"; else plain "$1"; dispw "$PL"; fi
  UIL+=("$DW")
}

ui_talk() {
  local t=$TALK_T role=${N_ROLE[$TALK_T]}
  if (( TW2 )); then ui "  ${MEMO[t]} ${N_FULL[$t]}" "$B"$'\e[38;5;117m'; else ui "  ${N_FULL[$t]}" "$B"$'\e[38;5;117m'; fi
  ui ""
  local rest="\"$TALK_LINE\"" w=$(( VW - 6 )) cut
  while (( ${#rest} > w )); do
    cut=${rest:0:w}; cut=${cut% *}; (( ${#cut} < 10 )) && cut=${rest:0:w}
    ui "  $cut" "$K_CHAT"; rest=${rest:${#cut}}; rest=${rest# }
  done
  ui "  $rest" "$K_CHAT"
  ui ""
  case $role in
    inn|medic) ui "  [1] Rest and recover (free)" ;;
    guard|villager) ;;
    bank) ui "  [1] Open my vault and the shared chest" "$K_LOOT" ;;
    merc) ui "  [1] Show me your companions" "$K_LOOT" ;;
    stable) ui "  [1] Show me your horses" "$K_LOOT" ;;
    valor) ui "  [1] What does valor buy? ($VALOR valor)" "$K_LOOT" ;;
    *) ui "  [1] Let me see your wares" ;;
  esac
  ui "  [2] Heard any rumors?"
  [[ -n ${N_QK[$t]}${N_QD[$t]} ]] && ui "  [3] Do you have any work for me?" "$K_LOOT"
  case $role in
    smith) ui "  [4] Forge gear from my ore" "$K_GOOD" ;;
    alchemist|hermit) ui "  [4] Brew potions from my herbs" "$K_GOOD" ;;
    inn) ui "  [4] May I use your kitchen? (cook fish)" "$K_GOOD" ;;
  esac
  if ql_for_npc "$t"; then                                       # v3.0: questlines and quartermasters
    case ${QLS:QLN:1} in
      0) if (( LVL >= QL_LVL[QLN] )); then ui "  [5] ${QL_NAME[QLN]}  (new questline)" $'\e[1;38;5;214m'
         else ui "  [5] ${QL_NAME[QLN]}  (from level ${QL_LVL[QLN]})" "$K_SYS"; fi ;;
      x) ui "  [5] ${QL_NAME[QLN]}  (completed)" "$K_SYS" ;;
      *) if ql_ready "$QLN"; then ui "  [5] ${QL_NAME[QLN]}  - I have done it!" "$K_GOOD"
         else ui "  [5] ${QL_NAME[QLN]}  (step ${QLS:QLN:1}/${QL_N[QLN]})" $'\e[38;5;214m'; fi ;;
    esac
    ui "  [6] Show me the ${FAC_NAME[${QL_FAC[QLN]}]}'s wares" "$K_LOOT"
  fi
  [[ $role == smith ]] && ui "  [7] Set gems into my gear (jewelcrafting)" $'\e[1;38;5;213m'
  if [[ $role == inn ]]; then
    tal_reset_cost; ui "  [8] Help me forget my talents ($TRC gold)" "$K_SYS"
    if (( ROOM_T )); then ui "  [9] Rooms upstairs - your ${ROOM_NAME[ROOM_T]}, visits" $'\e[1;38;5;180m'
    else ui "  [9] Rooms upstairs - rent one, or visit a friend" $'\e[1;38;5;180m'; fi
  fi
  ui ""
  if (( TALK_CONFIRM )); then ui "  Really attack ${N_FULL[$t]}? You will be WANTED. Press [x] again." "$K_HURT"
  else ui "  [x] Attack ${N_FULL[$t]}" "$K_SYS"; fi
  ui "  [esc] Goodbye" "$K_SYS"
}

ui_shop() {
  local i code total=0 title
  [[ -n ${CM_T[$TALK_MID]} ]] || { UI=""; return; }
  shop_build "$SHOP"
  case $SHOP in
    general) title="MARA'S GENERAL STORE" ;; smith) title="BROM'S FORGE" ;; alchemist) title="YSOLDE'S ALCHEMY" ;;
    trader) title="GARRICK'S TRADING POST" ;; hermit) title="ORWIN'S HUT" ;; spice) title="NADIA'S SPICE STALL" ;;
    *) title="${N_FULL[$TALK_T]^^}'S SUPPLIES" ;;
  esac
  (( TALK_T >= NPC1 )) && title="${N_FULL[$TALK_T]^^}"
  ui "  $title" "$K_LOOT$B"
  ui "  You have ${EMJ[gold]}$GOLD gold."
  ui ""
  local pc=$(( TW2 ? 61 : 60 )) c ok col
  (( pc > MW - 8 )) && pc=$(( MW - 8 ))
  for i in "${!SH_ID[@]}"; do
    c=${SH_ID[i]}; rb; rt "  [$(( i + 1 ))] " "38;5;245"
    if [[ $c == [WAOHJ].* ]]; then        # gear: icon, name, stats, power change, price
      item_name "$c" "$CLS"; item_icon "$c" "$CLS"; bonus_txt
      ok=0; [[ $ICLS == *"$CLS"* ]] && ok=1
      [[ -n $II ]] && rt "$II "
      padt "$INAME" $(( TW2 ? 24 : 30 )); rt "$PADS " "$ICOL"
      local st=""; (( IVAL )) && { st="+$IVAL dmg "; [[ $IK != W ]] && st="+$IVAL arm "; }
      padt "$st$BTX" 17; rt "$PADS" "38;5;250"
      if (( ok )); then pv_slot "$IK" "$c"; pv_delta; padr " $DLP" 6; rt "$PADS" "$DLC"; else rt " ✖    " "38;5;203"; fi
    elif [[ $c == B.* ]]; then            # bags: size and what it does to your capacity
      item_name "$c" "$CLS"; item_icon "$c" "$CLS"
      [[ -n $II ]] && rt "$II "
      padt "$INAME" $(( TW2 ? 24 : 30 )); rt "$PADS " "$ICOL"
      padt "bag, $IVAL slots" 17; rt "$PADS" "38;5;250"
      bag_gain "${c#B.}"; if (( BG > 0 )); then padr " ▲$BG" 6; rt "$PADS" "1;38;5;84"; else rt " =    " "38;5;242"; fi
    else
      ci "$c"; [[ -n $CI ]] && rt "$CI"
      padt "${SH_LABEL[i]}" $(( pc - 6 - (TW2 ? 3 : 0) )); rt "$PADS" "38;5;252"
    fi
    rpad "$pc"; col="1;38;5;220"; (( GOLD >= SH_PRICE[i] )) || col="38;5;203"
    printf -v PF '%6sg' "${SH_PRICE[i]}"; rt "$PF" "$col"
    uxs
  done
  ui ""
  junk_value
  for code in "${INV[@]}"; do [[ $code == *! || $code == C.* ]] && continue; item_stats "$code"; total=$(( total + ISELL )); done
  ui "  [j] Sell junk (gear worse than yours: $JUNK items)   +${JVAL}g"
  local lk=0; for code in "${INV[@]}"; do [[ $code == *! || $code == C.* ]] && lk=$(( lk + 1 )); done   # (collectables are never sold)
  if (( lk )); then ui "  [s] Sell everything but locked items and collectables ($(( ${#INV[@]} - lk )) items)   +${total}g"
  else ui "  [s] Sell everything in your bags (${#INV[@]} items)   +${total}g"; fi
  if [[ $SHOP == @(general|trader|spice) ]]; then
    fish_value; ui "  [f] Sell all your fish ($FISHN)   +${FISHV}g"
    col_dupes; (( ${#DUP[@]} )) && ui "  [c] Sell duplicate collectables (${#DUP[@]})   +${DUPV}g"
  fi
  ui ""
  [[ $SHOP == smith ]] && ui "  Reforging upgrades the rarity of what you WEAR. It can fail." "$K_SYS"
  ui "  [esc] leave" "$K_SYS"
}

ui_quest() {
  local i f leader=1 title
  [[ -n $MY_PARTY && $PARTY_LEADER != "$MY_ID" ]] && leader=0
  if [[ $QSRC == board ]]; then title="QUEST BOARD OF HEARTHMOOR"; else title="${N_FULL[$QSRC]^^} HAS WORK FOR YOU"; fi
  ui "  $title" "$K_LOOT$B"
  if [[ -n $MY_PARTY ]]; then
    ui "  Party quests (${#PQ_CODES[@]}/3) - shared progress, +25% rewards:" "$B$K_PARTY"
    for f in "${PQ_CODES[@]}"; do quest_info "$f"; uix "    $QGLY ${K_PARTY}$QTXT$N" "    $PLX $QTXT"; done
  fi
  ui "  Your quests (${#QUESTS[@]}/3):" "$B"
  (( ${#QUESTS[@]} )) || ui "    none" "$K_SYS"
  for f in "${QUESTS[@]}"; do quest_info "$f"; uix "    $QGLY $QTXT" "    $PLX $QTXT"; done
  ui ""
  ui "  Offers:" "$B"
  for i in "${!OFFERS[@]}"; do
    quest_info "${OFFERS[i]}"; IFS=. read -r -a f <<< "${OFFERS[i]}"
    uix "  [$(( i + 1 ))] $QGLY ${K_CHAT}${QTXT%% (*}$N" "  [x] $PLX ${QTXT%% (*}"
    ui "        $QWHERE  -  ${f[4]} XP, ${f[5]} gold" "$K_SYS"
  done
  ui ""
  if (( ! leader )); then ui "  Only your party leader (${OP_NAME[$PARTY_LEADER]:-?}) can accept quests for the party." "$K_HURT"
  elif [[ -n $MY_PARTY ]]; then ui "  [1-${#OFFERS[@]}] accept for the WHOLE party   [esc] close" "$K_SYS"
  else ui "  [1-${#OFFERS[@]}] accept a quest   [esc] close" "$K_SYS"; fi
}

bcell() {  # monster type width -> BC (colored) BP (plain), both exactly <width> wide
  local t=$1 w=$2 nm lv
  printf -v lv 'L%-2d' "${M_LVL[t]}"
  if [[ ${SEEN:t:1} == 1 ]]; then
    printf -v nm '%-*s' $(( w - 5 - ${#PLX} )) "${M_NAME[t]:0:w-5-${#PLX}}"
    con_col "${M_LVL[t]}"; BC="${GLYP[m$t]}$N $nm ${CC}$lv$N" BP="$PLX $nm $lv"
  else
    printf -v nm '%-*s' $(( w - 5 - ${#PLX} )) "???"
    BC="${K_SYS}${PLX//x/?} $nm $lv$N" BP="$PLX $nm $lv"
  fi
}

BEAST_PG=0
ui_bestiary() {  # all hostile creatures sorted by level, in pages that fit the frame
  local list=() t i j tmp seen=0 cols rows w r c idx line plain per pages p0
  for (( t = 0; t < NM; t++ )); do (( M_KIND[t] == 0 )) && list+=("$t"); done
  for (( i = 1; i < ${#list[@]}; i++ )); do
    tmp=${list[i]}; j=$(( i - 1 ))
    while (( j >= 0 && M_LVL[list[j]] > M_LVL[tmp] )); do list[j+1]=${list[j]}; j=$(( j - 1 )); done
    list[j+1]=$tmp
  done
  for t in "${list[@]}"; do [[ ${SEEN:t:1} == 1 ]] && seen=$(( seen + 1 )); done
  rows=$(( VH - 5 )); (( rows < 1 )) && rows=1
  cols=$(( (VW - 2) / 18 )); (( cols < 1 )) && cols=1           # cells are at least 16 columns wide
  per=$(( rows * cols ))
  (( per > ${#list[@]} )) && { cols=$(( (${#list[@]} + rows - 1) / rows )); per=$(( rows * cols )); }
  w=$(( (VW - 2) / cols - 2 )); (( w > 26 )) && w=26
  pages=$(( (${#list[@]} + per - 1) / per ))
  (( BEAST_PG >= pages )) && BEAST_PG=$(( pages - 1 )); (( BEAST_PG < 0 )) && BEAST_PG=0
  p0=$(( BEAST_PG * per ))
  ui "  BESTIARY - $seen of ${#list[@]} creatures discovered" "$K_LOOT$B"
  ui "  colors: grey trivial, green easy, yellow even, orange hard, red deadly" "$K_SYS"
  ui ""
  for (( r = 0; r < rows; r++ )); do
    line="  " plain="  "
    for (( c = 0; c < cols; c++ )); do
      idx=$(( p0 + c * rows + r )); (( idx < ${#list[@]} && idx < p0 + per )) || continue
      bcell "${list[idx]}" "$w"; line+="$BC  "; plain+="$BP  "
    done
    uix "$line" "$plain"
  done
  ui ""
  if (( pages > 1 )); then ui "  page $(( BEAST_PG + 1 ))/$pages - [<] [>] turn the page - [esc] close" "$K_SYS"
  else ui "  Quests tell you where each creature lives. [esc] close" "$K_SYS"; fi
}

ui_chatlog() {
  local half i ne=${#LOG_T[@]} nc=${#CHL_T[@]}
  half=$(( (VH - 4) / 2 ))
  ui "  EVENTS" "$B"
  for (( i = ne - half; i < ne; i++ )); do (( i >= 0 )) && ui "  ${LOG_T[i]}" "${LOG_C[i]}"; done
  ui "  CHAT" "$B"
  (( nc )) || ui "  nobody said anything yet - press [enter] to chat" "$K_SYS"
  for (( i = nc - half; i < nc; i++ )); do (( i >= 0 )) && ui "  ${CHL_T[i]}" "${CHL_C[i]}"; done
}

ui_way() {
  local i a cost=$(( 10 + LVL * 3 ))
  ui "  WAYSTONE NETWORK" "$K_LOOT$B"
  ui "  Travel to any attuned waystone for $cost gold. You have $GOLD gold."
  ui ""
  for i in "${!WAYSTONES[@]}"; do
    a=(${WAYSTONES[i]})
    if [[ ${WAYS:i:1} == 1 ]]; then
      cheb $(( a[1] - PX )) $(( a[2] - PY ))
      if (( D <= 3 )) && [[ $CUR_MAP == W ]]; then ui "  [$(( (i + 1) % 10 ))] ${EMJ[way]}${a[0]//_/ }   (you are here)" "$K_SYS"
      else ui "  [$(( (i + 1) % 10 ))] ${EMJ[way]}${a[0]//_/ }"; fi
    else
      ui "  [ ] ??? - not attuned yet" "$K_SYS"
    fi
  done
  ui ""
  ui "  Walk past a waystone (&) once to attune it.   [esc] close" "$K_SYS"
}

HELP_PG=0
ui_help() {  # two pages: [<] [>] turn
  if (( HELP_PG == 0 )); then
  ui "  CONTROLS                                          page 1/4  [>] more" "$B"
  ui "  w a s d / arrows / h j k l   walk - walk into foes to hit"
  ui "  walk into an NPC to talk  -  f / space attack next to you"
  ui "  1 2 3 skills   e / r potions   u eat   i inventory   y allies"
  ui "  x talents  g fish / gather  p professions  m map  z ride  o achievements"
  ui "  q quests, questlines, reputation  b bestiary  c chat log  H collection"
  ui "  v graphics   Q quit   enter chat - /p party  /w name msg"
  ui "  /invite /accept /leave /trade name /give name gold|#item /who"
  ui "  THE WORLD" "$B"
  ui "  Hearthmoor is the heart. South: desert (Oasis of Kadar), the Isles,"
  ui "  the Badlands. East: tundra, Ashen Wastes, Crystal Highlands, Jungle,"
  ui "  Void Rift. Level 30-40: Duskwood, Sunken Kingdom, Stormreach, Gloomcap,"
  ui "  Dragonspine, Bonefields, Starfall Crater. Waystones (&) link 17 towns."
  ui "  NPCs: yellow ! quests, ❕/orange ! a questline, ? a letter, star"
  ui "  the story (talk to Old Tom first). 18 dungeons (>), level 3 to 39."
  ui "  Night: only torches light the way. Weather: sandstorms blind,"
  ui "  blizzards slow, ash burns (tonics!). Murder makes you WANTED."
  ui "  Bankers (B): your vault + a chest shared by all your heroes."
  ui "  [esc] close" "$K_SYS"
  elif (( HELP_PG == 1 )); then
  ui "  DEEPER                                       page 2/4  [<] [>] more" "$B"
  ui "  Talents [x]: a point every level, three trees per class, a"
  ui "  capstone at 10 points in a tree. Forget them at any inn."
  ui "  Elements: skills deal fire, frost, poison, shadow, holy or arcane"
  ui "  damage. Every creature is weak to one and resists one - the"
  ui "  target panel says which. Resistances protect you from magic."
  ui "  Monsters poison, bleed, burn, chill, stun and weaken you. Potions"
  ui "  cure poison and bleeding; resting and cleansing skills cure all."
  ui "  Champions (marked) are stronger: 3x XP, better loot, gems."
  ui "  Rare elites roam every region - bounty boards want them dead."
  ui "  Gems drop from rares, champions, bosses, chests and ore. Any smith"
  ui "  sets them into socketed gear [7] and combines three into one better."
  ui "  Questlines: every town has its own story - and its own choices."
  ui "  Quests raise your standing with the six factions: discounts and"
  ui "  their quartermaster [6] sells socketed gear and a unique."
  ui "  Quests now also ask you to collect, deliver, scout and hunt bounties."
  ui "  [esc] close   [>] endgame" "$K_SYS"
  elif (( HELP_PG == 2 )); then
  ui "  ENDGAME                                      page 3/4  [<] [>] more" "$B"
  ui "  Mythic: at level 40 every dungeon gate asks: normal or mythic? Foes are"
  ui "  level 40 and stronger with every key level (+2 to +20); weekly affixes;"
  ui "  beat the clock and your key rises. Pays epic+ gear, perfect gems, valor."
  ui "  The Eclipse Throne (raid, Starfall Crater, east rim): Nyxara grows with"
  ui "  every hero - stay out of marked ground, kill her guards, run from the"
  ui "  total eclipse. Invasions: now and then the Horde attacks a town."
  ui "  Valor: buy Godforged gear, perfect gems and mounts from Hale (Hearthmoor)"
  ui "  or Seren (Dawnspire). Dailies and weeklies: [q], tab 4 (from level 30)."
  ui "  Paragon: after 40, experience gives paragon points - [x], then [p]."
  ui "  Mounts: Hilda sells horses in Hearthmoor. [z] ride, [Z] choose a mount."
  ui "  Achievements and titles: [o]. Professions go to 40; new ore, herbs, fish."
  ui "  Perfect gems: combine three flawless ones at any smith."
  ui "  [esc] close   [>] your home" "$K_SYS"
  else
  ui "  A HOME OF YOUR OWN                                page 4/4  [<] back" "$B"
  ui "  Every innkeeper rents rooms upstairs [9]: four sizes, a weekly rent, and"
  ui "  the same room waits for you at every inn. Walk into the furniture:"
  ui "  the bed makes you Well Rested (more XP from fights for 30 minutes),"
  ui "  the chest stores items and materials, displays show off your finds,"
  ui "  the bookshelf opens your collection book, visitors sign the guestbook."
  ui "  Collectables: 80 of them in six sets - boss trophies, world boss"
  ui "  trophies, a curio for every land, odd things from fishing and gathering,"
  ui "  relics of the story. [H] shows what you have found and where the rest is."
  ui "  Visits: [9] then [v] - your friends must be online. Your door decides"
  ui "  who may come in: nobody, your party or everybody."
  ui "  Shops buy collectables you have twice [c]. Lock one [l] to keep it."
  ui "  [esc] close" "$K_SYS"
  fi
}

wm_open() {  # [keep] -> fit zoom, center on me
  local z=1 VW=$MW
  while (( MAPW[W] / z > VW || MAPH[W] / z > VH - 1 )); do z=$(( z * 2 )); done
  WM_FIT=$z
  if [[ $1 != keep ]]; then
    WM_Z=$z
    if [[ $CUR_MAP == W ]]; then WM_X=$PX WM_Y=$PY; else WM_X=$WX WM_Y=$WY; fi
  fi
  (( WM_Z > WM_FIT )) && WM_Z=$WM_FIT
  WM_CZ=""
}

wm_build() {  # rows sampled at the current zoom, cached
  [[ $WM_CZ == "$WM_Z:$TW" ]] && return
  local z=$WM_Z y x row line
  WMR=()
  for (( y = 0; y * z < MAPH[W]; y++ )); do
    if (( TW == 2 )); then row=${VROW[W:$(( y * z ))]:-${MAPROW[W:$(( y * z ))]}}; else row=${MAPROW[W:$(( y * z ))]}; fi
    if (( z == 1 )); then WMR[y]=$row; continue; fi
    line=""
    for (( x = 0; x * z < MAPW[W]; x++ )); do line+=${row:x*z:1}; done
    WMR[y]=$line
  done
  WM_CZ="$z:$TW"
}

wm_seen() { local k=$(( ($2 / 8) * NCHX + $1 / 8 )); [[ ${EXPW:k:1} == 1 ]]; }

wm_key() {
  local vh=$(( VH - 1 )) VW=$MW
  case $1 in
    m) UI="" ;;
    w|k|UP)    WM_Y=$(( WM_Y - vh / 3 * WM_Z )) ;;
    s|j|DOWN)  WM_Y=$(( WM_Y + vh / 3 * WM_Z )) ;;
    a|h|LEFT)  WM_X=$(( WM_X - VW / 3 * WM_Z )) ;;
    d|l|RIGHT) WM_X=$(( WM_X + VW / 3 * WM_Z )) ;;
    +|=) (( WM_Z > 1 )) && WM_Z=$(( WM_Z / 2 )) ;;
    -|_) (( WM_Z < WM_FIT )) && WM_Z=$(( WM_Z * 2 )) ;;
    c) if [[ $CUR_MAP == W ]]; then WM_X=$PX WM_Y=$PY; else WM_X=$WX WM_Y=$WY; fi ;;
  esac
  (( WM_X < 0 )) && WM_X=0; (( WM_X >= MAPW[W] )) && WM_X=$(( MAPW[W] - 1 ))
  (( WM_Y < 0 )) && WM_Y=0; (( WM_Y >= MAPH[W] )) && WM_Y=$(( MAPH[W] - 1 ))
}

ui_map() {
  local z vh=$(( VH - 1 )) ry sy sx0 sy0 row RI=() RF=() TAGS=() x y i id d a mw mh q cx v1 v2 cy k qw
  (( TW2 && WM_Z <= 2 )) && { TW=2; VW=$(( MW / 2 )); }      # zoomed in far enough: emoji world map
  wm_build; z=$WM_Z
  mw=${#WMR[0]} mh=${#WMR[@]}
  sx0=$(( WM_X / z - VW / 2 )) sy0=$(( WM_Y / z - vh / 2 ))
  if (( mw <= VW )); then sx0=$(( (mw - VW) / 2 )); else (( sx0 < 0 )) && sx0=0; (( sx0 > mw - VW )) && sx0=$(( mw - VW )); fi
  if (( mh <= vh )); then sy0=$(( (mh - vh) / 2 )); else (( sy0 < 0 )) && sy0=0; (( sy0 > mh - vh )) && sy0=$(( mh - vh )); fi
  GLY[wdun]=$Z_ENT GLY[wway]=$Z_WAY GLY[wqg]=$'\e[0;1;38;5;16;48;5;226m!' GLY[wbank]=$'\e[0;1;38;5;16;48;5;220mB' GLY[wqt]=$'\e[0;1;5;38;5;226mx'
  poi() {  # world x y prio key [force]
    local vx=$(( $1 / z - sx0 )) vy=$(( $2 / z - sy0 ))
    (( vx >= 0 && vx < VW && vy >= 0 && vy < vh )) || return
    [[ $5 == 1 ]] && RF[vy]+="$(( vx * 10 + $3 )):1:$4 "
    [[ $5 == 1 ]] || wm_seen "$1" "$2" || return
    RI[vy]+="$(( vx * 10 + $3 )):1:$4 "
  }
  if [[ $CUR_MAP == W ]]; then x=$PX y=$PY; else x=$WX y=$WY; fi
  GLY[self]=$'\e[0;1;7;38;5;'"${P_COLC[COLR]}m$SYM"
  poi "$x" "$y" 1 self 1
  for id in "${!OP_MAP[@]}"; do [[ ${OP_MAP[$id]} == W && -n ${GLY[p$id]} ]] && poi "${OP_X[$id]}" "${OP_Y[$id]}" 2 "p$id" 1; done
  for q in "${PQ_CODES[@]}" "${QUESTS[@]}"; do [[ -n $q ]] && { quest_info "$q"; [[ -n $QTX ]] && poi "$QTX" "$QTY" 3 wqt 1; }; done
  if [[ -n $WB_CID ]]; then
    GLY[wwb]=$'\e[0;5;'"${M_COL[WB_CT]}m${M_GLY[WB_CT]}" GLYH[wwb]=$'\e[0;5;48;5;124m'"${MEMO[WB_CT]}"
    poi "$WB_CX" "$WB_CY" 0 wwb 1
  fi
  for (( d = 0; d < NDT; d++ )); do poi "${D_ENTX[d]}" "${D_ENTY[d]}" 4 wdun; done
  for i in "${!WAYSTONES[@]}"; do a=(${WAYSTONES[i]}); poi "${a[1]}" "${a[2]}" 4 wway; done
  for i in "${NPC_SPAWNS[@]}"; do a=($i); [[ -n ${N_QK[${a[0]}]}${N_QD[${a[0]}]} ]] && poi "${a[1]}" "${a[2]}" 4 wqg; done
  for i in "${NPC_SPAWNS[@]}"; do a=($i); [[ ${N_ROLE[${a[0]}]} == bank ]] && poi "${a[1]}" "${a[2]}" 4 wbank; done
  for i in "${REGIONS[@]}"; do                       # region names
    a=($i); [[ ${a[5]} == safe ]] && continue
    x=$(( (a[0] + a[2]) / 2 )) y=$(( (a[1] + a[3]) / 2 ))
    wm_seen "$x" "$y" || continue
    v1=$(( x / z - sx0 )) v2=$(( y / z - sy0 )); q=" ${a[4]//_/ } "
    (( TW == 2 && ${#q} % 2 )) && q+=" "
    qw=$(( ${#q} / TW ))
    (( v2 >= 0 && v2 < vh )) || continue
    v1=$(( v1 - qw / 2 )); (( v1 < 0 || v1 + qw > VW )) && continue
    free_span "$v2" "$v1" "$qw" || continue
    TAGS+=($'\e[0;1;38;5;231;48;5;236m'"$q$N"); RI[v2]+="$(( v1 * 10 + 5 )):$qw:t$(( ${#TAGS[@]} - 1 )) "
  done
  for (( ry = 0; ry < vh; ry++ )); do
    sy=$(( sy0 + ry ))
    out+=$'\e['"$(( ry + 3 ));2H$N"
    if (( sy < 0 || sy >= mh )); then out+=${BLANK:0:VW*TW}; continue; fi
    row=${WMR[sy]}
    if (( sx0 < 0 )); then row="${BLANK:0:-sx0}$row"; row=${row:0:VW}; else row=${row:sx0:VW}; fi
    (( ${#row} < VW )) && row+=${BLANK:0:VW-${#row}}
    cy=$(( sy * z / 8 ))                               # explored 8x8 chunks in color, the rest grey
    local spans="" pv=-1 st=0 vx e
    for (( vx = 0; vx < VW; vx++ )); do
      x=$(( (sx0 + vx) * z ))
      if (( sx0 + vx < 0 || x >= MAPW[W] )); then e=1
      else k=$(( cy * NCHX + x / 8 )); e=${EXPW:k:1}; fi
      if [[ $e != "$pv" ]]; then (( vx > 0 )) && spans+="$st:$(( vx - 1 )):$pv "; st=$vx pv=$e; fi
      (( x >= 0 && z < 8 && x / 8 == (x + z) / 8 )) && { vx=$(( vx + (8 - x % 8) / z - 1 )); (( vx > VW - 1 )) && vx=$(( VW - 1 )); }
    done
    spans+="$st:$(( VW - 1 )):$pv"
    for e in $spans; do
      v1=${e%%:*}; v2=${e#*:}; v2=${v2%:*}
      if [[ ${e##*:} == 1 ]]; then COMP_DIM=0; compose "$v1" "$v2" ${RI[ry]}
      else COMP_DIM=1; compose "$v1" "$v2" ${RF[ry]}; fi
      out+=$COMP
    done
    COMP_DIM=0
  done
  local lg=" 1:$z +/-  @ you  ! quests  x target  > dungeon  & waystone  B bank"
  [[ -n $WB_CID ]] && lg+="  ${M_GLY[WB_CT]} world boss"
  (( ${#lg} > MW )) && lg=${lg:0:MW}
  lg=${lg//"@ you"/$'\e[1;7;38;5;'"${P_COLC[COLR]}m$SYM$N${K_SYS} you"}
  lg=${lg//"! quests"/$'\e[1;38;5;16;48;5;226m!'"$N${K_SYS} quests"}
  lg=${lg//"x target"/$'\e[1;38;5;226mx'"$N${K_SYS} target"}
  lg=${lg//"> dungeon"/"${Z_ENT}$N${K_SYS} dungeon"}
  lg=${lg//"& waystone"/"${Z_WAY}$N${K_SYS} waystone"}
  lg=${lg//"B bank"/"${GLY[wbank]}$N${K_SYS} bank"}
  [[ -n $WB_CID ]] && lg=${lg//"  ${M_GLY[WB_CT]} world boss"/"  "$'\e[0;5;'"${M_COL[WB_CT]}m${M_GLY[WB_CT]}$N${K_SYS} world boss"}
  out+=$'\e['"$(( VH + 2 ));2H$N${BLANK:0:MW}"$'\e['"$(( VH + 2 ));2H${K_SYS}$lg$N"
}

render_ui() {   # panels use every column of the frame, the world map is drawn in ASCII
  local r t VW=$MW TW=1
  UIT=() UIC=() UIL=()
  for (( r = 0; r < VH; r++ )); do unset "SCR[m$r]"; done          # the map rows are covered now
  if [[ $UI == map ]]; then ui_map; return; fi
  case $UI in
    shop) ui_shop ;; inv) ui_inv ;; quest) ui_quest ;; help) ui_help ;; talk) ui_talk ;;
    qlog) ui_qlog ;; beasts) ui_bestiary ;; chatlog) ui_chatlog ;; way) ui_way ;;
    prof) ui_prof ;; craft) ui_craft ;; trade) [[ -n $TR_WITH ]] && ui_trade || UI="" ;; bank) ui_bank ;;
    allies) ui_allies ;; allyshop) ui_allyshop ;; story) ui_story ;;
    talents) if (( TL_PAGE )); then ui_paragon; else ui_talents; fi ;; jewel) ui_jewel ;; wares) ui_wares ;; qchoice) ui_qchoice ;;
    dgate) ui_dgate ;; stable) ui_stable ;; valor) ui_valor ;; ach) ui_ach ;;
    inn) ui_inn ;; visit) ui_visit ;; dsp) ui_dsp ;; book) ui_book ;; guest) ui_guest ;;
  esac
  [[ -n $UI ]] || { MAP_DIRTY=1; return; }
  for (( r = 0; r < VH; r++ )); do
    if (( ${UIL[r]:--1} > VW )); then             # too wide for the frame: cut, keep the colors
      clipl "${UIT[r]}" "$VW"; out+=$'\e['"$(( r + 3 ));2H$N$CL"
    elif (( ${UIL[r]:--1} >= 0 )); then
      out+=$'\e['"$(( r + 3 ));2H$N${UIT[r]}$N${BLANK:0:VW-UIL[r]}"
    else
      t=${UIT[r]}; dispw "$t"
      while (( DW > VW )); do t=${t:0:${#t}-1}; dispw "$t"; done
      out+=$'\e['"$(( r + 3 ));2H$N${UIC[r]}$t${BLANK:0:VW-DW}$N"
    fi
  done
}

render() {
  local out="" t0=${EPOCHREALTIME/[.,]/}
  if (( SMALL )); then
    printf '\e[H\e[2J\e[0m  shellmmorpg needs at least 100x30 characters (now %sx%s).\n  Enlarge the window, or press Q to quit.' "$COLS" "$ROWS"
    NEED_FULL=1; return
  fi
  (( NEED_FULL )) && { draw_frame; NEED_FULL=0; MAP_DIRTY=1; }
  (( NOW - ${SCR_T:-0} > 5000 )) && { SCR=(); SCR_T=$NOW; }    # now and then resend everything
  clock_now; weather_now
  render_header
  if [[ -n $UI ]]; then          # the world map is slow to draw: background changes refresh it twice a second
    if (( MAP_DIRTY )) && { (( KEYD )) || [[ $UI != map ]] || (( NOW - UI_T >= 500 )); }; then
      MAP_DIRTY=0 KEYD=0 UI_T=$NOW; render_ui
    fi
  elif (( MAP_DIRTY || NOW >= next_mapdraw )); then
    render_map; MAP_DIRTY=0; next_mapdraw=$(( NOW + 250 ))
    [[ -n $CW ]] && next_mapdraw=$(( NOW + 120 ))
  fi
  render_panel; render_log; render_input
  if [[ -n $SHELLMMO_DEBUG ]]; then
    local t1=${EPOCHREALTIME/[.,]/}; RT_SUM=$(( RT_SUM + t1 - t0 )) RT_N=$(( RT_N + 1 ))
    (( RT_N >= 20 )) && { RT_AVG=$(( RT_SUM / RT_N / 1000 )); RT_SUM=0 RT_N=0; }
    out+=$'\e[1;'"$(( COLS - 14 ))H${K_SYS}frame ${RT_AVG:-?}ms$N"
  fi
  [[ -n $out ]] && printf '%s' "$out"
}

# ---------------------------------------------------------------------------
#  Input & main loop
# ---------------------------------------------------------------------------
handle_key() {
  local k=$1 rest
  KEYD=1
  if (( CHATTING )); then
    chat_key "$k"
    while (( CHATTING )) && read -t 0; do IFS= read -rsn1 k; chat_key "$k"; done
    return
  fi
  if [[ $k == $'\e' ]]; then
    rest=""; read -rsn2 -t 0.01 rest
    case $rest in
      '[A'|OA) k=UP ;; '[B'|OB) k=DOWN ;; '[C'|OC) k=RIGHT ;; '[D'|OD) k=LEFT ;;
      '') k=ESC ;;
      *) read -rsn6 -t 0.01 rest; return ;;
    esac
  fi
  if [[ -n $UI ]]; then
    MAP_DIRTY=1
    if [[ $UI == trade ]]; then trade_key "$k"; return; fi
    if [[ $UI == bank ]]; then bank_key "$k"; [[ -z $UI ]] && NEED_FULL=1; return; fi
    if [[ $UI == story ]]; then [[ $k == @(|$'\r'|' '|ESC|q) ]] && { UI="" NEED_FULL=1; }; return; fi
    case $k in ESC|q) [[ $UI == inv ]] && inv_leave_tab; UI="" NEED_FULL=1; return ;; esac
    case $UI in
      shop)  shop_key "$k" ;;
      talk)  talk_key "$k" ;;
      inv)   if [[ $k == i ]]; then inv_leave_tab; UI=""; else inv_key "$k"; fi ;;
      quest) quest_key "$k" ;;
      map)   wm_key "$k"; [[ -z $UI ]] && NEED_FULL=1 ;;
      way)   [[ $k == [1-9] ]] && way_travel $(( k - 1 )); [[ $k == 0 ]] && way_travel 9 ;;
      help)  case $k in '?') UI="" ;; RIGHT|'>'|.|d|l|' ') (( HELP_PG < 3 )) && HELP_PG=$(( HELP_PG + 1 )) ;; LEFT|'<'|,|a|h) (( HELP_PG > 0 )) && HELP_PG=$(( HELP_PG - 1 )) ;; esac ;;
      beasts)  case $k in
                 b) UI="" ;;
                 RIGHT|'>'|.|d|l|' ') BEAST_PG=$(( BEAST_PG + 1 )) ;;
                 LEFT|'<'|,|a|h)      (( BEAST_PG > 0 )) && BEAST_PG=$(( BEAST_PG - 1 )) ;;
               esac ;;
      chatlog) [[ $k == c ]] && UI="" ;;
      prof)    [[ $k == p ]] && UI="" ;;
      craft)   craft_key "$k" ;;
      allies)  if [[ $k == y ]]; then UI=""; else aly_key "$k"; fi ;;
      allyshop) ally_shop_key "$k" ;;
      talents) if [[ $k == x ]]; then UI=""
               elif [[ $k == [pt] ]]; then TL_PAGE=$(( ! TL_PAGE ))
               elif (( TL_PAGE )); then [[ $k == [1-6] ]] && para_learn $(( k - 1 ))
               else tal_key "$k"; fi ;;
      dgate)   dgate_key "$k" ;;
      stable)  stable_key "$k" ;;
      valor)   valor_key "$k" ;;
      ach)     if [[ $k == o ]]; then UI=""; else ach_key "$k"; fi ;;
      inn)     inn_key "$k" ;;
      visit)   visit_key "$k" ;;
      dsp)     dsp_key "$k" ;;
      book)    if [[ $k == H ]]; then UI=""; else book_key "$k"; fi ;;
      jewel)   jewel_key "$k" ;;
      wares)   wares_key "$k" ;;
      qchoice) case $k in 1|a) ql_choose a ;; 2|b) ql_choose b ;; esac ;;
      qlog)    case $k in 1|2|3|4) QLOG_TAB=$(( k - 1 )) ;; LEFT) QLOG_TAB=$(( (QLOG_TAB + 3) % 4 )) ;; RIGHT|' '|$'\t') QLOG_TAB=$(( (QLOG_TAB + 1) % 4 )) ;; esac ;;
    esac
    [[ -z $UI ]] && NEED_FULL=1
    return
  fi
  if (( FISH_ST )) && [[ $k == [\ gf] ]]; then fish_strike; return; fi
  case $k in
    w|k|UP)    try_move 0 -1 ;;
    s|j|DOWN)  try_move 0 1 ;;
    a|h|LEFT)  try_move -1 0 ;;
    d|l|RIGHT) try_move 1 0 ;;
    1|2|3)     cast $(( k - 1 )) ;;
    f|' ')     melee_any ;;
    e)         use_item h ;;
    r)         use_item m ;;
    i)         UI=inv MAP_DIRTY=1 ;;
    m)         wm_open; UI=map MAP_DIRTY=1 ;;
    q)         UI=qlog MAP_DIRTY=1 ;;
    b)         UI=beasts MAP_DIRTY=1 ;;
    c)         UI=chatlog MAP_DIRTY=1 ;;
    n)         TAGS_ON=$(( ! TAGS_ON )) MAP_DIRTY=1 ;;
    v)         toggle_gfx ;;
    g)         gather_key ;;
    p)         UI=prof MAP_DIRTY=1 ;;
    u)         eat ;;
    y)         UI=allies MAP_DIRTY=1 ;;
    x)         UI=talents MAP_DIRTY=1 ;;
    z)         mount_toggle ;;
    Z)         STABLE_SRC=keys UI=stable MAP_DIRTY=1 ;;
    o)         UI=ach MAP_DIRTY=1 ;;
    H)         BOOK_PG=0 UI=book MAP_DIRTY=1 ;;
    '?')       UI=help MAP_DIRTY=1 ;;
    ''|$'\r'|t) CHATTING=1 CHAT_BUF="" ;;
    /)         CHATTING=1 CHAT_BUF="/" ;;
    Q)         exit 0 ;;
  esac
}

regen() {
  local rh rm id
  for id in "${!OP_SEEN[@]}"; do (( NOW - OP_SEEN[$id] > 10000 )) && op_del "$id"; done
  trade_tick
  (( DEAD )) && return
  weather_hazard
  v3_tick; v45_tick; v50_tick; (( DEAD )) && return
  rh=$(( MAXHP / 100 + 1 )) rm=$(( MAXMP * 3 / 100 + 1 ))
  (( NOW - last_hurt > 6000 )) && rh=$(( MAXHP * 4 / 100 + 1 ))
  if [[ $CUR_MAP == H* ]] || { [[ $CUR_MAP == W ]] && in_safe_xy "$PX" "$PY"; }; then rh=$(( rh * 3 )) rm=$(( rm * 2 )); fi   # towns and rooms
  (( NOW < fed_until )) && { rh=$(( rh * 2 )) rm=$(( rm * 2 )); }
  (( TB_REGEN )) && { rh=$(( rh * (100 + TB_REGEN) / 100 )) rm=$(( rm * (100 + TB_REGEN) / 100 )); }
  if (( HP < MAXHP || MP < MAXMP )); then
    HP=$(( HP + rh )) MP=$(( MP + rm )); (( HP > MAXHP )) && HP=$MAXHP; (( MP > MAXMP )) && MP=$MAXMP
    POS_DIRTY=1
  fi
}

choose_class() {
  local k i
  printf '\e[0m\e[2J\e[H'
  print_logo
  printf '\n   A new hero awakens. Welcome, \e[1m%s\e[0m. Choose your class:\n\n' "$MY_NAME"
  local rows=40 keys=1234567890; rows=$(stty size 2>/dev/null); rows=${rows%% *}; [[ $rows =~ ^[0-9]+$ ]] || rows=40
  for (( i = 0; i < NCLS; i++ )); do
    printf '   \e[1;38;5;226m[%s]\e[0m %s \e[1m%-11s\e[0m %s\n' "${keys:i:1}" "${CEMO[i]}" "${C_NAME[i]}" "${C_DESC[i]}"
    (( rows >= 12 + NCLS * 2 )) && printf '                   \e[38;5;245mHP %d+%d/lvl  MP %d+%d/lvl  %s / %s / %s\e[0m\n' \
      "${C_HP0[i]}" "${C_HPL[i]}" "${C_MP0[i]}" "${C_MPL[i]}" "${S_NAME[i*3]}" "${S_NAME[i*3+1]}" "${S_NAME[i*3+2]}"
  done
  printf '\n   \e[38;5;245mYour character is saved as %s\e[0m\n' "$CHAR_FILE"
  while :; do
    IFS= read -rsn1 k
    [[ -n $k && $keys == *"$k"* ]] && { k=${keys%%"$k"*}; (( ${#k} < NCLS )) && { new_char "${#k}"; return; }; }
    [[ $k == [Qq] ]] && exit 0
  done
}

choose_look() {
  local k i keys="123456789abc"
  SYM="@"; name_color "$MY_NAME"; COLR=$NCI
  printf '\e[0m\e[2J\e[H'; print_logo
  printf '\n   How should the world see you?\n\n'
  printf '   Press the key of the \e[1msymbol\e[0m you want on the map (any letter, digit or sign).\n'
  printf '   Enter keeps the classic @\n\n   '
  while :; do
    IFS= read -rsn1 k
    if [[ -z $k ]]; then break; fi
    valid_sym "$k" && { SYM=$k; break; }
  done
  printf 'Symbol: \e[1m%s\e[0m\n\n   Now pick your \e[1mcolor\e[0m:\n\n' "$SYM"
  for i in "${!P_COLC[@]}"; do
    printf '   \e[1;38;5;226m[%s]\e[0m \e[1;38;5;%sm%s %-8s\e[0m' "${keys:i:1}" "${P_COLC[i]}" "$SYM" "${P_COLN[i]}"
    (( i % 4 == 3 )) && printf '\n'
  done
  printf '\n   Enter keeps \e[1;38;5;%sm%s\e[0m\n' "${P_COLC[COLR]}" "${P_COLN[COLR]}"
  while :; do
    IFS= read -rsn1 k
    [[ -z $k ]] && break
    i=${keys%%"$k"*}; [[ ${#i} -lt ${#keys} && -n $k ]] && { COLR=${#i}; break; }
  done
  save_char
}

lan_ip() {
  local ip
  ip=$(hostname -I 2>/dev/null); ip=${ip%% *}
  [[ -n $ip ]] || ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i+1)}')
  LANIP=${ip:-<your-ip>}
}

cleanup() {
  save_char
  (( net_up )) && send BYE "$MY_ID" "$MY_NAME"
  [[ $MODE == host ]] && sleep 0.2
  exec 7>&- 2>/dev/null
  [[ $MODE == host ]] && stop_all
  [[ -n $old_stty ]] && stty "$old_stty" 2>/dev/null
  printf '\e[0m\e[?7h\e[?25h\e[?1049l'
  [[ -n $CLS ]] && echo "shellmmorpg: $MY_NAME (level $LVL ${C_NAME[CLS]}) saved. See you in Hearthmoor!"
}

client_main() {
  local key tries=0 next_frame=0 next_sec=0 next_save next_reconnect=0
  trap '' PIPE
  mkdir -p "$DATA_DIR" || die "cannot create $DATA_DIR"
  load_world
  if [[ $MODE == host ]]; then
    pick_hub_tool || die "hosting needs ncat, python3 or socat (joining works with plain bash)"
    echo "Starting the world on port $NET_PORT (hub: $HUB_TOOL)..."
    start_hub || { stop_all; die "could not open port $NET_PORT - already in use? Try --port"; }
    start_world_server
  fi
  echo "Connecting to $NET_HOST:$NET_PORT..."
  until net_connect; do
    tries=$(( tries + 1 ))
    if (( tries > 10 )) || [[ $MODE == join ]]; then
      stop_all; die "could not connect to $NET_HOST:$NET_PORT - is the world running? Firewall?"
    fi
    sleep 0.3
  done
  on_line() { cli_line "$1"; }
  net_lost() {
    (( net_up )) || return
    net_up=0; exec 7>&- 2>/dev/null
    local id; for id in "${!OP_NAME[@]}"; do op_del "$id"; done
    logm "Lost connection to the world server - retrying..." "$K_HURT"
  }
  old_stty=$(stty -g)
  stty -echo -icanon
  set_gfx
  printf '\e[?1049h\e[?25l\e[?7l'
  trap cleanup EXIT
  trap 'exit 0' INT TERM HUP
  trap 'RESIZED=1' WINCH
  if load_char; then
    logm "Welcome back, $MY_NAME the ${C_NAME[CLS]}!" "$K_ANN"
  else
    choose_class; choose_look
    logm "Welcome to Hearthmoor, $MY_NAME the ${C_NAME[CLS]}! Press [?] for help." "$K_ANN"
    logm "Walk into people to talk. The quest board (!) is on the plaza." "$K_SYS"
  fi
  p_walk W "$WX" "$WY" || { WX=$SPAWN_X WY=$SPAWN_Y; }
  CUR_MAP=W PX=$WX PY=$WY
  if (( GFX_NEW )); then
    save_gfx
    logm "NEW: HD graphics with emoji sprites are on. Tiles look broken or shifted? Press [v] for classic ASCII." "$K_ANN"
  fi
  init_where; init_explore; explore_here; init_lights
  now_ms
  (( ALLY >= 0 )) && aly_place
  story_intro
  send HELLO "$MY_ID" "$MY_NAME" "$CLS" "$LVL"; send_pos
  if [[ $MODE == host ]]; then
    lan_ip
    logm "Your world is online. Friends join with: ./shellmmorpg.sh --join $LANIP:$NET_PORT" "$K_PARTY"
  fi
  next_save=$(( NOW + 30000 ))
  layout
  while :; do
    now_ms
    if (( net_up )); then
      net_poll 300
    elif (( NOW >= next_reconnect )); then
      next_reconnect=$(( NOW + 5000 ))
      if net_connect; then
        [[ $CUR_MAP != W ]] && leave_instance quiet
        [[ -n $MY_PARTY ]] && { MY_PARTY="" PARTY_LEADER="" PARTY_IDS=(); pq_to_personal; }
        WANTED_UNTIL=0
        send HELLO "$MY_ID" "$MY_NAME" "$CLS" "$LVL"; send_pos; send SYNC "$MY_ID" W
        logm "Reconnected to the world." "$K_GOOD"
      fi
    fi
    (( ${#DOT_M[@]} )) && dot_tick
    [[ -n $GATH_MID ]] && gather_tick
    (( FISH_ST )) && fish_tick
    (( ALLY >= 0 )) && aly_tick
    if (( NOW >= next_sec )); then next_sec=$(( NOW + 1000 )); regen; fi
    (( DEAD && NOW >= dead_until )) && respawn
    (( clear_until && NOW >= clear_until )) && { clear_until=0; leave_instance; }
    if (( net_up )) && { (( POS_DIRTY && NOW - last_pos >= 60 )) || (( NOW - last_pos >= 2000 )); }; then send_pos; fi
    (( NOW >= next_save )) && { save_char; next_save=$(( NOW + 30000 )); }
    (( RESIZED )) && { RESIZED=0; layout; }
    if (( NOW >= next_frame )); then render; next_frame=$(( NOW + 80 )); fi
    if IFS= read -rsn1 -t 0.03 key; then now_ms; handle_key "$key"; fi
  done
}

dedicated_main() {
  trap '' PIPE
  pick_hub_tool || die "the server needs ncat, python3 or socat"
  echo "shellmmorpg dedicated server - starting hub ($HUB_TOOL) on port $NET_PORT..."
  start_hub || { stop_all; die "could not open port $NET_PORT"; }
  trap 'kill_tree "$HUB_PID"; [[ -n $HUB_DIR ]] && rm -rf "$HUB_DIR"' EXIT
  lan_ip
  echo "Players join with: ./shellmmorpg.sh --join $LANIP:$NET_PORT   (Ctrl+C stops the server)"
  server_main
}
