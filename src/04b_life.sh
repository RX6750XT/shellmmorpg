# ---------------------------------------------------------------------------
#  Module 04b - world life (since v1.3): day & night, light, weather, world
#  bosses, professions (fishing, mining, herbalism), crafting and trading
# ---------------------------------------------------------------------------
CLK_OFF="" GM=480 DAYPH="" CW="" CW_I=-1 NR=0 WR=0 LITMODE=0 LITR="" PZ=0 ASH_HINT=0
WTH_K=() WTH_E=() LGX=() LGY=() LGR=() SRX1=() SRY1=() SRX2=() SRY2=() LIT=() SRCX=() SRCY=() SRCR=()
WB_CID="" WB_CT=0 WB_CX=0 WB_CY=0
PROF_LV=(1 1 1) PROF_XP=(0 0 0) MATS=()
MEAL1=0 MEAL2=0 TON_FROST=0 TON_FIRE=0 TON_VEIL=0
fed_until=0 fed_lvl=0 frost_until=0 fireward_until=0 veil_until=0 ash_next=0
GATH_MID="" GATH_END=0 GATH_T0=0 CRAFT=""
FISH_ST=0 FISH_BITE=0 FISH_T0=0 FISH_END=0 FISH_MAT=0 FISH_REQ=1 FISH_ZS=0 FISH_ZW=3 FISH_P=1500 FISH_POOL="" FISH_W=27 FPOS=0
TR_WITH="" TR_OUT="" TR_OUT_T=0 TR_PG=0 TR_MYI=() TR_MYG=0 TR_THI=() TR_THG=0 TR_MYSEQ=0 TR_THSEQ=0 TR_MYOK=0 TR_THOK=0
TR_INPUT="" TR_BUF=""
declare -A TR_IN=() TR_MYM=() TR_THM=() SPANC=() WEA_IDX=()
for i in "${!WEA_REG[@]}"; do WEA_IDX[${WEA_REG[i]//_/ }]=$i; done
mats_zero() { local i; MATS=(); for (( i = 0; i < NMAT; i++ )); do MATS[i]=0; done; }
mats_zero

FXG[warn]=$'\e[0;1;5;38;5;196;48;5;52m!' FXG[bolt]=$'\e[0;1;38;5;229;48;5;61m|'
declare -A FXD=([warn]=1500 [bolt]=380) FXP=([warn]=7)
GLY[fwarn]=${FXG[warn]} GLY[fbolt]=${FXG[bolt]}
GLY[zrain]=$'\e[0;38;5;75m'"'" GLY[zstorm]=$'\e[0;38;5;111m/' GLY[zsnow]=$'\e[0;1;38;5;231m*'
GLY[zsand]=$'\e[0;38;5;180m~' GLY[zash]=$'\e[0;38;5;209m.'
PSX=() PSY=()
for (( i = 0; i < 48; i++ )); do PSX[i]=$(( RANDOM % 997 )) PSY[i]=$(( RANDOM % 991 )); done

# --- clock & light ----------------------------------------------------------------
clock_now() {  # -> GM (game minute 0..1439), NR (night sight radius, 0 = daylight)
  local ph
  if [[ -z $CLK_OFF ]]; then GM=480; else GM=$(( ((NOW + CLK_OFF) % DAYLEN + DAYLEN) % DAYLEN / GMIN )); fi
  if (( GM >= 420 && GM < 1140 )); then NR=0 ph=day
  elif (( GM >= 1140 && GM < 1260 )); then NR=$(( 22 - (GM - 1140) * 16 / 120 )) ph=dusk
  elif (( GM >= 300 && GM < 420 )); then NR=$(( 6 + (GM - 300) * 16 / 120 )) ph=dawn
  else NR=6 ph=night; fi
  [[ $ph == "$DAYPH" ]] && return
  if [[ -n $DAYPH ]]; then
    case $ph in
      dusk)  logm "The sun sets. Torches are lit in the towns." "$K_SYS" ;;
      night) logm "Night falls. The dead grow restless - undead hit harder, but give more XP." "$K_HURT" ;;
      dawn)  logm "Dawn breaks over the land." "$K_GOOD" ;;
    esac
  fi
  DAYPH=$ph
}

clock_txt() {  # -> CLKT "☀ 14:20"
  local ic="☀"
  (( NR > 0 )) && ic="☾"
  if (( TW2 )); then ic="🌞"; (( NR > 0 )) && ic="🌙"; fi
  printf -v CLKT '%s %02d:%02d' "$ic" $(( GM / 60 )) $(( GM % 60 ))
}

weather_now() {  # -> CW (weather where I stand), WR (sight radius it leaves me, 0 = clear)
  CW="" WR=0 CW_I=-1
  [[ $CUR_MAP == W ]] || return
  RNAME=""; region_of "$PX" "$PY" nosafe
  local i=${WEA_IDX[$RNAME]}
  [[ -n $i ]] && (( ${WTH_E[i]:-0} > NOW )) || return
  CW=${WTH_K[i]} CW_I=$i
  case $CW in fog) WR=8 ;; sand) WR=4 ;; snow) WR=9 ;; esac
  (( WR && NOW < veil_until )) && WR=$(( WR * 2 ))
}

init_lights() {  # campfires and waystones glow at night -> LGX LGY LGR; lit streets -> SRX1 SRY1 SRX2 SRY2
  local y x row a s
  LGX=() LGY=() LGR=()
  for (( y = 0; y < MAPH[W]; y++ )); do
    row=${MAPROW[W:$y]}
    [[ $row == *[FZ]* ]] || continue
    for (( x = 0; x < ${#row}; x++ )); do
      case ${row:x:1} in F) LGX+=("$x") LGY+=("$y") LGR+=(5) ;; Z) LGX+=("$x") LGY+=("$y") LGR+=(2) ;; esac
    done
  done
  SRX1=() SRY1=() SRX2=() SRY2=()
  for s in "${SAFE_RECTS[@]}"; do a=($s); SRX1+=("${a[0]}") SRY1+=("${a[1]}") SRX2+=("${a[2]}") SRY2+=("${a[3]}"); done
}

span() {  # r dy -> SP: half width of a light ellipse (ASCII cells are twice as high as wide), -1 outside
  local k="$1:$2"
  SP=${SPANC[$k]}
  [[ -n $SP ]] && return
  if (( $2 * $2 > $1 * $1 )); then SP=-1
  elif (( TW == 2 )); then isqrt $(( $1 * $1 + $1 - $2 * $2 )); SP=$R
  else isqrt $(( 4 * ($1 * $1 + $1 - $2 * $2) )); SP=$R; fi
  SPANC[$k]=$SP
}

build_lit() {  # cx0 cy0 -> LIT[ry]: lit spans "a:b ..." of every view row (sorted, merged)
  local cx0=$1 cy0=$2 n=0 i j p s a x y ry dy lst t o lo hi cl ch wl=0 wh=-1 nr=$NR
  LIT=() SRCX=() SRCY=() SRCR=()
  if (( NR > 0 )); then
    (( NOW < veil_until )) && nr=$(( NR * 3 / 2 ))
    nr=$(( nr + ${B_LIGHT:-0} ))                  # lanterns
    SRCX[0]=$(( PX - cx0 )) SRCY[0]=$(( PY - cy0 )) SRCR[0]=$nr; n=1
    for p in "${!OP_MAP[@]}"; do                  # everybody carries a torch
      [[ ${OP_MAP[$p]} == W ]] || continue
      x=$(( ${OP_X[$p]} - cx0 )) y=$(( ${OP_Y[$p]} - cy0 ))
      (( x > -12 && x < VW + 12 && y > -6 && y < VH + 6 )) && { SRCX[n]=$x SRCY[n]=$y SRCR[n]=5; n=$(( n + 1 )); }
    done
    for (( i = 0; i < ${#LGX[@]}; i++ )); do
      x=$(( LGX[i] - cx0 )) y=$(( LGY[i] - cy0 ))
      (( x > -12 && x < VW + 12 && y > -6 && y < VH + 6 )) && { SRCX[n]=$x SRCY[n]=$y SRCR[n]=${LGR[i]}; n=$(( n + 1 )); }
    done
  fi
  for (( ry = 0; ry < VH; ry++ )); do
    lst=()
    if (( NR > 0 )); then
      for (( i = 0; i < n; i++ )); do
        dy=$(( ry - SRCY[i] )); (( dy <= SRCR[i] && -dy <= SRCR[i] )) || continue
        span "${SRCR[i]}" "$dy"; (( SP >= 0 )) && lst+=("$(( SRCX[i] - SP )) $(( SRCX[i] + SP ))")
      done
      y=$(( cy0 + ry ))
      for (( j = 0; j < ${#SRX1[@]}; j++ )); do    # streets are lit
        (( y >= SRY1[j] && y <= SRY2[j] && SRX2[j] >= cx0 && SRX1[j] < cx0 + VW )) && lst+=("$(( SRX1[j] - cx0 )) $(( SRX2[j] - cx0 ))")
      done
    else
      lst=("0 $(( VW - 1 ))")
    fi
    if (( WR > 0 )); then                         # storms only let you see close around you
      dy=$(( ry - PY + cy0 )); wl=0 wh=-1
      if (( dy <= WR && -dy <= WR )); then span "$WR" "$dy"; wl=$(( PX - cx0 - SP )) wh=$(( PX - cx0 + SP )); fi
    fi
    for (( i = 1; i < ${#lst[@]}; i++ )); do       # sort by start
      t=${lst[i]}; j=$(( i - 1 ))
      while (( j >= 0 && ${lst[j]% *} > ${t% *} )); do lst[j+1]=${lst[j]}; j=$(( j - 1 )); done
      lst[j+1]=$t
    done
    o="" cl=0 ch=0 p=0
    for t in "${lst[@]}" "99999 99999"; do
      lo=${t% *} hi=${t#* }
      if (( p && lo <= ch + 1 )); then (( hi > ch )) && ch=$hi; continue; fi
      if (( p )); then
        (( cl < 0 )) && cl=0; (( ch > VW - 1 )) && ch=$(( VW - 1 ))
        if (( WR > 0 )); then (( cl < wl )) && cl=$wl; (( ch > wh )) && ch=$wh; fi
        (( cl <= ch )) && o+="$cl:$ch "
      fi
      cl=$lo ch=$hi p=1
    done
    LIT[ry]=$o
  done
  if (( NR > 0 )); then Z_DARK=$'\e[0;38;5;60m' Z_DARKBG=$'\e[0;48;5;233m'
  else case $CW in
    sand) Z_DARK=$'\e[0;38;5;94m' Z_DARKBG=$'\e[0;48;5;58m' ;;
    snow) Z_DARK=$'\e[0;38;5;250m' Z_DARKBG=$'\e[0;48;5;245m' ;;
    *)    Z_DARK=$'\e[0;38;5;243m' Z_DARKBG=$'\e[0;48;5;238m' ;;
  esac; fi
  (( TW == 2 )) && Z_DARK="${Z_DARK%m}${Z_DARKBG#$'\e[0'}"
}

is_lit() {  # x (screen) -> 0 if inside a lit span of the current row
  local iv
  for iv in $LITR; do (( $1 >= ${iv%:*} && $1 <= ${iv#*:} )) && return 0; done
  return 1
}


add_particles() {  # weather drifting over the view (behind everything else)
  local i n=0 x y k
  case $CW in
    rain) n=30 k=zrain ;; storm) n=44 k=zstorm ;; snow) n=34 k=zsnow ;; sand) n=42 k=zsand ;; ash) n=26 k=zash ;; *) return ;;
  esac
  (( TW2 )) && n=$(( n / 3 ))                    # emoji particles are big - fewer of them
  for (( i = 0; i < n; i++ )); do
    case $CW in
      rain)  x=$(( (PSX[i] + NOW / 500) % VW )) y=$(( (PSY[i] + NOW / 55) % VH )) ;;
      storm) x=$(( (PSX[i] + NOW / 70) % VW )) y=$(( (PSY[i] + NOW / 45) % VH )) ;;
      snow)  x=$(( (PSX[i] + NOW / 900 + (NOW / 400 + i) % 3) % VW )) y=$(( (PSY[i] + NOW / 260) % VH )) ;;
      sand)  x=$(( (PSX[i] + NOW / 30) % VW )) y=$(( (PSY[i] + NOW / 600) % VH )) ;;
      ash)   x=$(( (PSX[i] - NOW / 700 % VW + VW) % VW )) y=$(( (PSY[i] + NOW / 380) % VH )) ;;
    esac
    RI[y]+="$(( x * 10 + 8 )):1:$k "
  done
}

weather_hazard() {  # every second: ash burns, lightning flashes
  [[ -n $CW ]] && (( ! DEAD )) || return
  case $CW in
    ash)
      in_safe_xy "$PX" "$PY" && return
      (( NOW >= fireward_until && NOW >= ash_next )) || return
      ash_next=$(( NOW + 2000 ))
      (( ASH_HINT )) || { ASH_HINT=1; logm "The burning ash sears your skin! A Fire Ward Tonic protects you (alchemists, Ser Kael, Nadia)." "$K_HURT"; }
      take_damage $(( MAXHP * 4 / 100 + 3 )) "Burning ash" ;;
    storm)
      (( RANDOM % 4 == 0 )) || return
      local x=$(( PX + RANDOM % 41 - 20 )) y=$(( PY - 3 - RANDOM % 5 )) c="" i
      for (( i = 0; i < 4; i++ )); do c+="$(( x + (RANDOM % 3) - 1 )),$(( y + i )) "; done
      add_fx bolt "$c" ;;
  esac
}

# --- professions ------------------------------------------------------------------
prof_next() { PN=$(( 6 * $1 + 10 )); }

prof_gain() {  # kind xp
  local k=$1
  (( PROF_LV[k] >= PROF_MAX )) && return
  PROF_XP[k]=$(( PROF_XP[k] + $2 ))
  prof_next "${PROF_LV[k]}"
  while (( PROF_XP[k] >= PN && PROF_LV[k] < PROF_MAX )); do
    PROF_XP[k]=$(( PROF_XP[k] - PN )); PROF_LV[k]=$(( PROF_LV[k] + 1 ))
    logm "Your ${PROF_NAME[k]} skill rises to ${PROF_LV[k]}!" "$K_ANN"
    prof_next "${PROF_LV[k]}"
  done
  (( PROF_LV[k] >= PROF_MAX )) && PROF_XP[k]=0
}

node_prof() { if (( $1 < NODE0 + 6 )); then NPK=1; else NPK=2; fi; }   # type -> NPK (1 mining, 2 herbalism)

gather_start() {  # mid
  local m=$1 t=${CM_T[$1]}
  [[ $GATH_MID == "$m" ]] && return
  node_prof "$t"
  if (( PROF_LV[NPK] < M_LVL[t] )); then
    logm "You need ${PROF_NAME[NPK]} ${M_LVL[t]} for ${M_NAME[t]} (you have ${PROF_LV[NPK]})." "$K_HURT"
    next_move=$(( NOW + 400 )); return
  fi
  fish_stop quiet
  GATH_MID=$m GATH_T0=$NOW GATH_END=$(( NOW + 1700 - PROF_LV[NPK] * 25 ))
  MAP_DIRTY=1
}

gather_tick() {
  local m=$GATH_MID t mat n=1 xp
  [[ -n $m ]] || return
  t=${CM_T[$m]}
  if [[ -z $t ]]; then GATH_MID=""; logm "Someone else got there first."; return; fi
  cheb $(( CM_X[m] - PX )) $(( CM_Y[m] - PY )); (( D <= 1 )) || { GATH_MID=""; return; }
  MAP_DIRTY=1
  (( NOW >= GATH_END )) || return
  GATH_MID=""
  node_prof "$t"; mat=${NODE_MAT[$t]:-$(( t - NODE0 ))}
  (( PROF_LV[NPK] >= M_LVL[t] + 6 && RANDOM % 3 == 0 )) && n=2
  MATS[mat]=$(( MATS[mat] + n )); MAT_NEW[mat]=$(( ${MAT_NEW[mat]:-0} + n ))
  xp=${M_XP[t]}; (( PROF_LV[NPK] >= M_LVL[t] + 10 )) && xp=$(( xp / 4 + 1 ))
  send HIT "$MY_ID" "$CUR_MAP" "$m" 1 0
  mat_icon "$mat"
  logm "+$n $MI${MI:+ }${MAT_NAME[mat]}   (${PROF_NAME[NPK]} ${PROF_LV[NPK]}, ${MATS[mat]} in your bag)" "$K_LOOT"
  prof_gain "$NPK" "$xp"; dly_ev gath; col_find 4
}

fish_stop() { (( FISH_ST )) || return; FISH_ST=0 MAP_DIRTY=1; [[ $1 == quiet ]] || logm "You reel in your line."; }

gather_key() {  # [g]: gather the node next to me, or fish
  local d x y
  (( DEAD )) && return
  for d in "$FDX,$FDY" "0,1" "0,-1" "1,0" "-1,0"; do
    x=$(( PX + ${d%,*} )) y=$(( PY + ${d#*,} ))
    if mon_at "$x" "$y" && (( M_KIND[${CM_T[$MID]}] == 3 )); then gather_start "$MID"; return; fi
  done
  fish_start
}

fish_start() {
  local x y d e f req rar cond pool="" minr=99 kind wt=""
  [[ $CUR_MAP == W ]] || { logm "There is nothing to fish down here."; return; }
  for d in "$FDX,$FDY" "0,1" "0,-1" "1,0" "-1,0" "0,0"; do
    x=$(( PX + ${d%,*} )) y=$(( PY + ${d#*,} ))
    tile W "$x" "$y"; [[ $T == [~LI] ]] && { wt=$T; break; }
  done
  if [[ -z $wt ]]; then logm "Stand next to water (~) to fish - or walk into an ore vein ◆ or herb ♣ to gather it."; return; fi
  if [[ $wt == L ]]; then kind=lava; elif [[ $wt == I ]]; then kind=ice
  else RNAME=""; region_of "$x" "$y" nosafe; kind=${WATER_OF[${RNAME// /_}]:-fresh}; fi
  for e in ${FISHW[$kind]}; do
    IFS=: read -r f req rar cond <<< "$e"
    (( req < minr )) && minr=$req
    (( PROF_LV[0] >= req )) || continue
    [[ $cond == night ]] && (( NR == 0 )) && continue
    pool+="$f:$rar:$req "
  done
  [[ -n $pool ]] || { logm "The fish here are too wily for you - you need Fishing $minr." "$K_HURT"; return; }
  GATH_MID=""
  FISH_POOL=$pool FISH_ST=1 FISH_BITE=$(( NOW + 1800 + RANDOM % 4000 ))
  [[ $CW == @(rain|storm) ]] && FISH_BITE=$(( NOW + 900 + RANDOM % 2200 ))
  [[ $kind == lava ]] && logm "You cast a fireproof line into the lava..." || logm "You cast your line... strike with [space] when it bites."
  MAP_DIRTY=1
}

fish_tick() {
  (( FISH_ST )) || return
  MAP_DIRTY=1
  if (( FISH_ST == 1 && NOW >= FISH_BITE )); then
    local e w tot=0 r rar mul=1 pick=""
    [[ $CW == @(rain|storm) ]] && mul=3
    for e in $FISH_POOL; do rar=${e#*:}; rar=${rar%:*}; w=$(( rar == 0 ? 70 : (rar == 1 ? 25 : 7 * mul) )); tot=$(( tot + w )); done
    r=$(( RANDOM % tot ))
    for e in $FISH_POOL; do
      rar=${e#*:}; rar=${rar%:*}; w=$(( rar == 0 ? 70 : (rar == 1 ? 25 : 7 * mul) ))
      (( r < w )) && { pick=$e; break; }; r=$(( r - w ))
    done
    [[ -n $pick ]] || pick=${FISH_POOL%% *}
    FISH_MAT=${pick%%:*} FISH_REQ=${pick##*:} rar=${MAT_RARE[${pick%%:*}]}
    FISH_ZW=$(( 4 + PROF_LV[0] / 6 - rar )); (( FISH_ZW < 2 )) && FISH_ZW=2
    FISH_ZS=$(( RANDOM % (FISH_W - FISH_ZW) ))
    FISH_P=$(( 1500 - rar * 250 ))
    FISH_ST=2 FISH_T0=$NOW FISH_END=$(( NOW + 4500 ))
    bell
  elif (( FISH_ST == 2 && NOW >= FISH_END )); then
    FISH_ST=0; logm "The fish got away..." "$K_HURT"
  fi
}

fish_pos() {
  local p=$(( (NOW - FISH_T0) % (2 * FISH_P) ))
  if (( p < FISH_P )); then FPOS=$(( p * (FISH_W - 1) / FISH_P )); else FPOS=$(( (2 * FISH_P - p) * (FISH_W - 1) / FISH_P )); fi
}

fish_strike() {
  if (( FISH_ST == 1 )); then FISH_ST=0; logm "Too early - you yanked the hook out of the water." "$K_HURT"; return; fi
  fish_pos
  local f=$FISH_MAT rar=${MAT_RARE[$FISH_MAT]}
  FISH_ST=0 MAP_DIRTY=1
  if (( FPOS >= FISH_ZS && FPOS < FISH_ZS + FISH_ZW )); then
    MATS[f]=$(( MATS[f] + 1 )); MAT_NEW[f]=$(( ${MAT_NEW[f]:-0} + 1 )); mat_icon "$f"
    if (( rar == 2 )); then logm "You caught a $MI${MI:+ }${MAT_NAME[f]}! A rare catch!" "$K_ANN"; else logm "You caught a $MI${MI:+ }${MAT_NAME[f]}." "$K_LOOT"; fi
    prof_gain 0 $(( (rar == 0 ? 8 : (rar == 1 ? 13 : 26)) + FISH_REQ )); dly_ev fish; col_find 3
  else
    logm "Missed! The ${MAT_NAME[f]} slips off the hook." "$K_HURT"
  fi
}

draw_overlay() {  # fishing / gathering box at the bottom of the map
  local msg plain bar i c r=$(( VH + 1 )) t tot
  if [[ -n $GATH_MID && -n ${CM_T[$GATH_MID]} ]]; then
    t=${CM_T[$GATH_MID]}; node_prof "$t"; tot=$(( GATH_END - GATH_T0 ))
    pbar $(( NOW - GATH_T0 )) "$tot" 16 $'\e[38;5;220m'
    plain=" ${PROF_NAME[NPK]}: ${M_NAME[t]}  "
    out+=$'\e['"$r;$(( 2 + (MW - ${#plain} - 17) / 2 ))H"$'\e[0;1;38;5;231;48;5;236m'"$plain$PB"$'\e[48;5;236m '"$N"
  fi
  (( FISH_ST )) || return
  if (( FISH_ST == 1 )); then
    plain="  ~  your float bobs on the water...  ~  "
    out+=$'\e['"$r;$(( 2 + (MW - ${#plain}) / 2 ))H"$'\e[0;38;5;153;48;5;24m'"$plain$N"
    return
  fi
  fish_pos; bar=""
  for (( i = 0; i < FISH_W; i++ )); do
    if (( i >= FISH_ZS && i < FISH_ZS + FISH_ZW )); then c=$'\e[48;5;34m'; else c=$'\e[48;5;24m'; fi
    if (( i == FPOS )); then bar+="$c"$'\e[1;38;5;231m▲'; else bar+="$c "; fi
  done
  plain=" BITE! [space] when ▲ is in the green "
  out+=$'\e['"$(( r - 1 ));$(( 2 + (MW - ${#plain}) / 2 ))H"$'\e[0;1;5;38;5;16;48;5;226m'"$plain$N"
  out+=$'\e['"$r;$(( 2 + (MW - FISH_W - 2) / 2 ))H"$'\e[0;38;5;231;48;5;236m['"$bar"$'\e[0;38;5;231;48;5;236m]'"$N"
}

# --- crafting -----------------------------------------------------------------------
craft_build() {  # CRAFT (forge|alch|cook) -> RC_ID RC_LAB RC_NEED RC_GOLD
  local o t f
  RC_ID=() RC_LAB=() RC_NEED=() RC_GOLD=()
  rc() { RC_ID+=("$1"); RC_LAB+=("$2"); RC_NEED+=("$3"); RC_GOLD+=("${4:-0}"); }
  case $CRAFT in
    forge)
      forge_kinds
      for (( o = 0; o < 6; o++ )); do
        t=$(( o + 2 ))
        item_name "W.$FWK.$t.0" "$CLS"; item_icon "W.$FWK.$t.0" "$CLS"; rc "W.$FWK.$t" "${II:0:2}${II:+ }$INAME" "$o:6" $(( 15 * t * t ))
        item_name "A.$FAK.$t.0" "$CLS"; item_icon "A.$FAK.$t.0" "$CLS"; rc "A.$FAK.$t" "${II:0:2}${II:+ }$INAME" "$o:6" $(( 15 * t * t ))
      done
      local fr                                              # v4.5: titanite and starmetal, tiers 8-12
      for fr in "${FORGE_X[@]}" "8:$M45:4 5:4" "9:$M45:6" "10:$M45:8 5:6" "11:$(( M45 + 1 )):6 $M45:4" "12:$(( M45 + 1 )):10 $M45:6"; do
        t=${fr%%:*}
        item_name "W.$FWK.$t.0" "$CLS"; item_icon "W.$FWK.$t.0" "$CLS"; rc "W.$FWK.$t" "${II:0:2}${II:+ }$INAME" "${fr#*:}" $(( 15 * t * t ))
        item_name "A.$FAK.$t.0" "$CLS"; item_icon "A.$FAK.$t.0" "$CLS"; rc "A.$FAK.$t" "${II:0:2}${II:+ }$INAME" "${fr#*:}" $(( 15 * t * t ))
      done ;;
    alch)
      local e I_hp2 I_mp2 I_gh I_gm I_str I_iron I_swift I_tfrost I_tfire I_tveil       # consumable icons
      for e in hp2 mp2 gh gm str iron swift tfrost tfire tveil; do ci "$e"; printf -v "I_$e" '%s' "$CI"; done
      rc hp2 "${I_hp2}2x Health potion" "6:2"; rc mp2 "${I_mp2}2x Mana potion" "7:2"
      rc gh "${I_gh}Greater health potion" "8:2 6:1"; rc gm "${I_gm}Greater mana potion" "8:2 7:1"
      rc str "${I_str}Elixir of Strength" "9:3"; rc iron "${I_iron}Elixir of Iron Skin" "10:2 8:1"
      rc swift "${I_swift}Elixir of Swiftness" "11:1 7:1 6:1"
      rc tfrost "${I_tfrost}Frost Tonic (no blizzard slow)" "10:2"
      rc tfire "${I_tfire}Fire Ward Tonic (ash immunity)" "11:2"
      rc tveil "${I_tveil}Sand Veil (see far in storms/night)" "9:2 7:1"
      rc gh3 "${I_gh}3x Greater health potion" "$(( M45 + 2 )):2"; rc gm3 "${I_gm}3x Greater mana potion" "$(( M45 + 2 )):1 $(( M45 + 3 )):1"
      rc grand "${I_str}Grand Elixir (Strength + Iron Skin + Swiftness)" "$(( M45 + 3 )):3 $(( M45 + 2 )):1"
      local x xi xl xn                                      # v6.0: cobalt-era herbs
      for x in "${ALCH_X[@]}"; do IFS=: read -r xi xl xn <<< "$x"; ci "$xi"; rc "$xi" "$CI$xl" "$xn"; done ;;
    cook)
      for f in ${MAT_GRP[0]}; do                            # (only fish - v4.5 fix: gems were "cookable")
        if (( MAT_RARE[f] == 2 )); then ci meal2; rc "c$f" "${MAT_NAME[f]} -> $CI${CI:+ }Fisherman's Feast" "$f:1"
        else ci meal1; rc "c$f" "${MAT_NAME[f]} -> $CI${CI:+ }Grilled Fish" "$f:1"; fi
      done ;;
  esac
}

craft_can() {  # index -> 0 if I have everything; NEEDC (colored) NEEDP (plain)
  local i=$1 e mat cnt ok=0 col
  NEEDC="" NEEDP=""
  for e in ${RC_NEED[i]}; do
    mat=${e%:*} cnt=${e#*:}
    if (( MATS[mat] >= cnt )); then col=$K_GOOD; else col=$K_HURT; ok=1; fi
    local mg=""; (( TW2 )) && mg=${MAT_I[mat]}
    NEEDC+="$col$cnt $mg$col${MAT_NAME[mat]} (${MATS[mat]})$N " NEEDP+="$cnt $mg${MAT_NAME[mat]} (${MATS[mat]}) "
  done
  if (( RC_GOLD[i] > 0 )); then
    if (( GOLD >= RC_GOLD[i] )); then col=$K_LOOT; else col=$K_HURT; ok=1; fi
    NEEDC+="$col${RC_GOLD[i]}g$N" NEEDP+="${RC_GOLD[i]}g"
  fi
  return $ok
}

craft_do() {  # index
  local i=$1 id e r k t
  (( i >= 0 && i < ${#RC_ID[@]} )) || return
  craft_can "$i" || { logm "You are missing something for ${RC_LAB[i]%% (*}." "$K_HURT"; return; }
  id=${RC_ID[i]}
  if [[ $id == [WAOHJ].* ]] && (( ${#INV[@]} >= BAGS )); then logm "Your bags are full - make room first." "$K_HURT"; return; fi
  for e in ${RC_NEED[i]}; do MATS[${e%:*}]=$(( MATS[${e%:*}] - ${e#*:} )); done
  GOLD=$(( GOLD - RC_GOLD[i] ))
  case $id in
    [WAOHJ].*)
      r=$(( RANDOM % 100 )); if (( r < 60 )); then r=1; elif (( r < 92 )); then r=2; else r=3; fi
      INV+=("$id.$r"); NEWG[$id.$r]=1; item_name "$id.$r" "$CLS"
      logm "The anvil rings - you forged a $INAME! (+$IVAL)  Equip it with [i]." $'\e['"${ICOL}m" ;;
    hp2) POT_H=$(( POT_H + 2 )) ;; mp2) POT_M=$(( POT_M + 2 )) ;; gh) POT_GH=$(( POT_GH + 1 )) ;; gm) POT_GM=$(( POT_GM + 1 )) ;;
    str) EL_STR=$(( EL_STR + 1 )) ;; iron) EL_IRON=$(( EL_IRON + 1 )) ;; swift) EL_SWIFT=$(( EL_SWIFT + 1 )) ;;
    tfrost) TON_FROST=$(( TON_FROST + 1 )) ;; tfire) TON_FIRE=$(( TON_FIRE + 1 )) ;; tveil) TON_VEIL=$(( TON_VEIL + 1 )) ;;
    gh3) POT_GH=$(( POT_GH + 3 )) ;; gm3) POT_GM=$(( POT_GM + 3 )) ;;
    grand) EL_STR=$(( EL_STR + 1 )) EL_IRON=$(( EL_IRON + 1 )) EL_SWIFT=$(( EL_SWIFT + 1 )) ;;
    c*) if (( MAT_RARE[${id#c}] == 2 )); then MEAL2=$(( MEAL2 + 1 )); else MEAL1=$(( MEAL1 + 1 )); fi ;;
  esac
  [[ $id == [WAOHJ].* ]] || logm "Made: ${RC_LAB[i]%% (*}" "$K_LOOT"
}

forge_kinds() {  # FWK / FAK: weapon and armor kind the forge makes (only what my class can use)
  [[ -n $FWK && ${WK_CLS[FWK]} == *"$CLS"* ]] || FWK=${DEFW[CLS]}
  [[ -n $FAK && ${AK_CLS[FAK]} == *"$CLS"* ]] || FAK=${DEFA[CLS]}
}

forge_cycle() {  # W|A: next kind my class may use
  local n i k
  forge_kinds
  if [[ $1 == W ]]; then n=${#WK_NAME[@]} k=$FWK; else n=${#AK_NAME[@]} k=$FAK; fi
  for (( i = 1; i <= n; i++ )); do
    k=$(( (k + 1) % n ))
    if [[ $1 == W ]]; then [[ ${WK_CLS[k]} == *"$CLS"* ]] && { FWK=$k; return; }
    else [[ ${AK_CLS[k]} == *"$CLS"* ]] && { FAK=$k; return; }; fi
  done
}

craft_key() {
  local keys=abcdefghijkl i n=0 f
  if [[ $CRAFT == forge ]]; then
    case $1 in x|X) forge_cycle W; return ;; y|Y) forge_cycle A; return ;; esac
  fi
  craft_build
  if [[ $1 == z && $CRAFT == cook ]]; then
    for (( f = 12; f < NMAT; f++ )); do
      while (( MATS[f] > 0 )); do
        MATS[f]=$(( MATS[f] - 1 )) n=$(( n + 1 ))
        if (( MAT_RARE[f] == 2 )); then MEAL2=$(( MEAL2 + 1 )); else MEAL1=$(( MEAL1 + 1 )); fi
      done
    done
    if (( n )); then logm "You cook $n fish. Food: $MEAL1 Grilled Fish, $MEAL2 Fisherman's Feast - eat with [u]." "$K_LOOT"
    else logm "You have no fish. Press [g] next to water to fish."; fi
    return
  fi
  craft_vis
  local p=-1; for i in "${!CR_VIS[@]}"; do (( CR_VIS[i] == CRAFT_CUR )) && p=$i; done
  case $1 in                                    # v7.1: a cursor - there are more recipes than letters
    UP)        (( p > 0 )) && CRAFT_CUR=${CR_VIS[p-1]} ;;
    DOWN)      (( p >= 0 && p < ${#CR_VIS[@]} - 1 )) && CRAFT_CUR=${CR_VIS[p+1]} ;;
    PGUP|HOME) CRAFT_CUR=${CR_VIS[0]:-0} ;;
    PGDN|END)  CRAFT_CUR=${CR_VIS[-1]:-0} ;;
    ''|$'\r'|' ') (( p >= 0 )) && craft_do "$CRAFT_CUR" ;;
    [a-l])     i=${keys%%"$1"*}; (( ${#i} < ${#RC_ID[@]} )) && { CRAFT_CUR=${#i}; craft_do "${#i}"; } ;;
  esac
}

CRAFT_CUR=0 CR_LAST=""
craft_vis() {  # -> CR_VIS: the recipes shown (at the campfire only the fish you have); the cursor stays on one
  local i
  CR_VIS=()
  for i in "${!RC_ID[@]}"; do
    [[ $CRAFT == cook ]] && (( MATS[${RC_ID[i]#c}] <= 0 )) && continue
    CR_VIS+=("$i")
  done
  [[ $CR_LAST == "$CRAFT" ]] || { CR_LAST=$CRAFT; CRAFT_CUR=${CR_VIS[0]:-0}; }
  for i in "${CR_VIS[@]}"; do (( i == CRAFT_CUR )) && return; done
  CRAFT_CUR=${CR_VIS[0]:-0}
}

ui_craft() {
  local i keys=abcdefghijkl title t lw k sel
  craft_build; craft_vis
  case $CRAFT in
    forge) title="FORGE - turn 6 ore into Rare, Epic or Legendary gear" ;;
    alch)  title="ALCHEMY - brew potions and tonics from herbs" ;;
    cook)  title="CAMPFIRE - cook your fish" ;;
  esac
  ui "  $title" "$K_LOOT$B"
  ui "  You have ${EMJ[gold]}$GOLD gold." "$K_SYS"
  ui ""
  local mxn=0
  for i in "${!RC_ID[@]}"; do craft_can "$i"; dispw "$NEEDP"; (( DW > mxn )) && mxn=$DW; done
  for i in "${CR_VIS[@]}"; do
    craft_can "$i"
    k="   "; (( i < ${#keys} )) && k="[${keys:i:1}]"
    sel="  "; (( i == CRAFT_CUR )) && { sel=$'\e[1;38;5;226m▶\e[0m '; UI_FOCUS=${#UIT[@]}; }
    if [[ $CRAFT == cook ]]; then
      uix "$sel$k ${RC_LAB[i]}   ${K_SYS}x${MATS[${RC_ID[i]#c}]}$N" "  [x] ${RC_LAB[i]}   x${MATS[${RC_ID[i]#c}]}"
    else
      lw=$(( VW - 8 - mxn )); (( lw > 38 )) && lw=38; (( lw < 16 )) && lw=16
      t=${RC_LAB[i]}; dispw "$t"; while (( DW > lw )); do t=${t:0:${#t}-1}; dispw "$t"; done
      padr "$t" "$lw"; t=$PADS
      uix "$sel$k $t $NEEDC" "  [x] $t $NEEDP"
    fi
  done
  ui ""
  case $CRAFT in
    cook)  ui "  Grilled Fish: heals 35%, Well Fed 5 min (double regeneration)." "$K_SYS"
           ui "  Fisherman's Feast: heals 70%, Well Fed+ 10 min (+10% damage)." "$K_SYS"
           ui "  [↑↓] [enter] cook one  [z] cook all  [esc] close" "$K_SYS" ;;
    forge) ui "  [x] weapon type: ${WK_NAME[FWK]}   [y] armor type: ${AK_NAME[FAK]}   (what a ${C_NAME[CLS]} can use)" "$K_LOOT"
           ui "  Ore comes from veins (◆) next to mountains - see [p] professions." "$K_SYS"
           ui "  [↑↓] [enter] forge   [a-l] quick   [esc] close" "$K_SYS" ;;
    alch)  ui "  Herbs (♣) grow in the wild - see [p] professions." "$K_SYS"
           ui "  [↑↓] [enter] brew   [a-l] quick   [esc] close" "$K_SYS" ;;
  esac
}

ui_prof() {
  local k i c line plain cols=3 rows w nm g t idx x
  ui "  PROFESSIONS" "$K_LOOT$B"
  for k in 0 1 2; do
    prof_next "${PROF_LV[k]}"; pbar "${PROF_XP[k]}" "$PN" 12 $'\e[38;5;220m'
    case $k in 0) t="[g] next to water ~" ;; 1) t="walk into ore veins ◆" ;; 2) t="walk into herbs ♣" ;; esac
    printf -v line '  %-10s Lv %-2d ' "${PROF_NAME[k]}" "${PROF_LV[k]}"
    if (( PROF_LV[k] >= PROF_MAX )); then uix "$line${K_GOOD}MASTER$N         ${K_SYS}$t$N" "$line MASTER         $t"
    else uix "$line$PB $(printf '%3d/%-3d' "${PROF_XP[k]}" "$PN") ${K_SYS}$t$N" "$line############ 000/000 $t"; fi
  done
  ui ""
  ui "  MATERIALS" "$B"
  local ml=(${MAT_GRP[1]} ${MAT_GRP[2]} ${MAT_GRP[0]}) nml
  nml=${#ml[@]}; rows=$(( (nml + cols - 1) / cols )); w=$(( (VW - 4) / cols ))
  for (( i = 0; i < rows; i++ )); do
    line="  " plain="  "
    for (( c = 0; c < cols; c++ )); do
      x=$(( c * rows + i )); (( x < nml )) || continue; idx=${ml[x]}
      if (( TW2 )); then g=${MAT_I[idx]}; elif mat_node "$idx"; then g="${GLYP[m$MNT_T]}$N"; else g="$FISHG$N"; fi
      printf -v nm '%-*s' $(( w - 1 - ${#PLX} )) "${MAT_NAME[idx]:0:w-7} ${MATS[idx]}"
      if (( MATS[idx] > 0 )); then line+="$g $nm"; else line+="$g ${K_SYS}$nm$N"; fi
      plain+="$PLX $nm"
    done
    uix "$line" "$plain"
  done
  ui "  Food: $MEAL1 grilled fish, $MEAL2 feasts   Tonics: $TON_FROST frost, $TON_FIRE fire ward, $TON_VEIL veil" "$K_SYS"
  ui ""
  ui "  Cook fish at campfires (*) and inns, forge ore at smiths, brew herbs at" "$K_SYS"
  ui "  alchemists. Rain makes fish bite faster and rare fish more common." "$K_SYS"
  ui "  WHERE TO FIND" "$B"
  w=$(( (VW - 4) / 2 ))
  local half=$(( (${#NODE_T[@]} + 1) / 2 ))
  for (( i = 0; i < half; i++ )); do
    line="  " plain="  "
    for c in 0 "$half"; do
      t=${NODE_T[i + c]}; [[ -n $t ]] || continue; node_prof "$t"
      printf -v nm '%-*s' $(( w - 2 - ${#PLX} )) "${M_NAME[t]} ${PROF_NAME[NPK]:0:1}${M_LVL[t]} - ${MW_NAME[t]}"
      nm="${nm:0:w-2-${#PLX}} "
      line+="${GLYP[m$t]}$N $nm" plain+="$PLX $nm"
    done
    uix "$line" "$plain"
  done
  ui "  Fish: Minnow/Trout in rivers, Silverscale in forests and Silverlake, Moonfin" "$K_SYS"
  ui "  (Silverlake, night), Mudfish (swamp), Sea Bass/Swordfish (coast), Golden" "$K_SYS"
  ui "  Koi (oasis), Ice Pike (frozen lakes), Lava Eel (lava!). From 30: Abyssal Eel" "$K_SYS"
  ui "  (sea, swamp), Storm Trout (ice), Magma Carp (lava), Starfish of Ys (sea, night)  [esc]" "$K_SYS"
}

# --- food & tonics --------------------------------------------------------------------
eat() {  # best food first
  (( DEAD )) && return
  if (( MEAL2 > 0 )); then
    MEAL2=$(( MEAL2 - 1 )); heal_self $(( MAXHP * 70 / 100 )); MP=$(( MP + MAXMP * 40 / 100 ))
    fed_until=$(( NOW + 600000 )) fed_lvl=2
    logm "A Fisherman's Feast! Well Fed: double regeneration and +10% damage for 10 min." "$K_GOOD"
  elif (( MEAL1 > 0 )); then
    MEAL1=$(( MEAL1 - 1 )); heal_self $(( MAXHP * 35 / 100 )); MP=$(( MP + MAXMP * 20 / 100 ))
    (( NOW < fed_until && fed_lvl == 2 )) || { fed_until=$(( NOW + 300000 )) fed_lvl=1; }
    logm "Grilled fish! Well Fed: double regeneration for 5 min." "$K_GOOD"
  else
    logm "No food. Fish with [g] next to water, then cook at a campfire (*) or inn."
  fi
  (( MP > MAXMP )) && MP=$MAXMP
  POS_DIRTY=1
}

# --- trading ----------------------------------------------------------------------------
trade_cmd() {  # /trade name
  local a=$1
  [[ -n $a ]] || { [[ -n $TR_WITH ]] && UI=trade MAP_DIRTY=1 || logm "Usage: /trade <name>"; return; }
  find_player "$a"
  [[ -n $FOUND ]] || { logm "Nobody called '$a' is online."; return; }
  [[ -z $TR_WITH ]] || { logm "You are already trading with ${OP_NAME[$TR_WITH]}."; UI=trade MAP_DIRTY=1; return; }
  cheb $(( ${OP_X[$FOUND]:-999} - PX )) $(( ${OP_Y[$FOUND]:-999} - PY ))
  [[ ${OP_MAP[$FOUND]} == "$CUR_MAP" ]] && (( D <= 6 )) || { logm "${OP_NAME[$FOUND]} is too far away to trade (max 6 steps)."; return; }
  if (( NOW - ${TR_IN[$FOUND]:-0} < 60000 )); then
    unset "TR_IN[$FOUND]"
    send TACC "$MY_ID" "$MY_NAME" "$FOUND"
    trade_open "$FOUND"
  else
    TR_OUT=$FOUND TR_OUT_T=$NOW
    send TREQ "$MY_ID" "$MY_NAME" "$FOUND"
    logm "You ask ${OP_NAME[$FOUND]} to trade..." "$K_SYS"
  fi
}

trade_open() {
  TR_WITH=$1 TR_OUT="" TR_PG=0 TR_MYI=() TR_MYG=0 TR_THI=() TR_THG=0 TR_MYSEQ=0 TR_THSEQ=0 TR_MYOK=0 TR_THOK=0 TR_INPUT="" TR_BUF=""
  TR_MYM=() TR_THM=()
  fish_stop quiet; GATH_MID=""
  UI=trade MAP_DIRTY=1
  logm "Trade opened with ${OP_NAME[$1]}. Both sides must accept with [y]." "$K_LOOT"
}

trade_close() {  # [msg]
  [[ -n $TR_WITH ]] || return
  [[ -n $1 ]] && logm "$1" "$K_SYS"
  TR_WITH="" TR_INPUT=""
  [[ $UI == trade ]] && { UI=""; NEED_FULL=1; }
  MAP_DIRTY=1
}

trade_send() {  # my offer changed
  local i items="" mats="" k
  TR_MYSEQ=$(( TR_MYSEQ + 1 )) TR_MYOK=0 TR_THOK=0
  for i in "${TR_MYI[@]}"; do items+="${INV[i]%!},"; done
  for k in "${!TR_MYM[@]}"; do mats+="$k:${TR_MYM[$k]},"; done
  send TOFF "$MY_ID" "$MY_NAME" "$TR_WITH" "$TR_MYSEQ" "$TR_MYG" "${items%,}" "${mats%,}"
  MAP_DIRTY=1
}

trade_toggle() {  # inventory index
  local i=$1 j new=() had=0
  (( i < ${#INV[@]} )) || return
  for j in "${TR_MYI[@]}"; do if (( j == i )); then had=1; else new+=("$j"); fi; done
  if (( ! had )); then
    (( ${#new[@]} < 10 )) || { logm "You can offer at most 10 items per trade." "$K_HURT"; return; }
    new+=("$i")
  fi
  TR_MYI=("${new[@]}")
  trade_send
}

trade_input() {  # finished text of the gold / material prompt
  local t=${TR_BUF,,} n name k best=""
  if [[ $TR_INPUT == gold ]]; then
    isnum "$t" || { logm "Type a number."; return; }
    (( t > GOLD )) && t=$GOLD
    TR_MYG=$t; trade_send; return
  fi
  t=${t#"${t%%[![:space:]]*}"}
  if [[ $t =~ ^([0-9]+)\ +(.+)$ ]]; then n=${BASH_REMATCH[1]} name=${BASH_REMATCH[2]}
  elif [[ $t =~ ^(.+[^0-9\ ])\ +([0-9]+)$ ]]; then name=${BASH_REMATCH[1]} n=${BASH_REMATCH[2]}
  else logm "Type an amount and a material, e.g.  5 iron"; return; fi
  for (( k = 0; k < NMAT; k++ )); do [[ ${MAT_NAME[k],,} == *"$name"* ]] && { best=$k; break; }; done
  [[ -n $best ]] || { logm "No material called '$name'."; return; }
  n=$(( 10#$n )); (( n > MATS[best] )) && n=${MATS[best]}
  if (( n > 0 )); then TR_MYM[$best]=$n; else unset "TR_MYM[$best]"; fi
  trade_send
}

trade_key() {
  local k=$1 i
  if [[ -n $TR_INPUT ]]; then
    case $k in
      ''|$'\r') trade_input; TR_INPUT="" ;;
      ESC) TR_INPUT="" ;;
      $'\x7f'|$'\b') TR_BUF=${TR_BUF%?} ;;
      *) [[ ${#k} == 1 && $k == [[:print:]] ]] && (( ${#TR_BUF} < 30 )) && TR_BUF+=$k ;;
    esac
    return
  fi
  case $k in
    ESC|x|X) send TCAN "$MY_ID" "$MY_NAME" "$TR_WITH"; trade_close "You cancel the trade." ;;
    [1-9]) trade_toggle $(( TR_PG * 10 + k - 1 )) ;;
    0) trade_toggle $(( TR_PG * 10 + 9 )) ;;
    '<'|,|LEFT)  (( TR_PG > 0 )) && TR_PG=$(( TR_PG - 1 )) ;;
    '>'|.|RIGHT) (( (TR_PG + 1) * 10 < ${#INV[@]} )) && TR_PG=$(( TR_PG + 1 )) ;;
    g|G) TR_INPUT=gold TR_BUF="" ;;
    m|M) TR_INPUT=mat TR_BUF="" ;;
    y|Y)
      local mine=${#TR_MYI[@]} theirs=${#TR_THI[@]}
      if (( ${#INV[@]} - mine + theirs > BAGS )); then logm "Not enough room in your bags for their items." "$K_HURT"; return; fi
      TR_MYOK=1
      send TOK "$MY_ID" "$MY_NAME" "$TR_WITH" "$TR_MYSEQ" "$TR_THSEQ"
      trade_check ;;
  esac
}

trade_check() { (( TR_MYOK && TR_THOK )) && trade_exec; }

trade_exec() {
  local i j k c ok=1 idx=() got="" gave="" nm=${OP_NAME[$TR_WITH]:-?}
  for i in "${TR_MYI[@]}"; do [[ -n ${INV[i]} ]] || ok=0; done
  (( TR_MYG <= GOLD )) || ok=0
  for k in "${!TR_MYM[@]}"; do (( MATS[k] >= TR_MYM[$k] )) || ok=0; done
  if (( ! ok )); then send TCAN "$MY_ID" "$MY_NAME" "$TR_WITH"; trade_close "Trade failed - your offer changed."; return; fi
  idx=($(printf '%s\n' "${TR_MYI[@]}" | sort -rn))
  for i in "${idx[@]}"; do item_name "${INV[i]}" "$CLS"; gave+="$INAME, "; unset "INV[i]"; done
  INV=("${INV[@]}")
  GOLD=$(( GOLD - TR_MYG + TR_THG ))
  (( TR_MYG )) && gave+="${TR_MYG} gold, "; (( TR_THG )) && got+="${TR_THG} gold, "
  for k in "${!TR_MYM[@]}"; do MATS[k]=$(( MATS[k] - TR_MYM[$k] )); gave+="${TR_MYM[$k]} ${MAT_NAME[k]}, "; done
  for k in "${!TR_THM[@]}"; do MATS[k]=$(( MATS[k] + TR_THM[$k] )); MAT_NEW[k]=$(( ${MAT_NEW[k]:-0} + TR_THM[$k] )); got+="${TR_THM[$k]} ${MAT_NAME[k]}, "; done
  for c in "${TR_THI[@]}"; do item_name "$c" "$CLS"; got+="$INAME, "; INV+=("$c"); NEWG[$c]=1; done
  INV=("${INV[@]:0:BAGS}")
  gave=${gave%, } got=${got%, }
  logm "Trade with $nm complete. You gave: ${gave:-nothing}. You got: ${got:-nothing}." "$K_LOOT"
  save_char
  trade_close
}

trade_tick() {  # once a second: partner gone or walked off?
  [[ -n $TR_WITH ]] || return
  if [[ -z ${OP_NAME[$TR_WITH]} || ${OP_MAP[$TR_WITH]} != "$CUR_MAP" ]]; then trade_close "The trade was cancelled."; return; fi
  cheb $(( ${OP_X[$TR_WITH]} - PX )) $(( ${OP_Y[$TR_WITH]} - PY ))
  (( D <= 10 )) || { send TCAN "$MY_ID" "$MY_NAME" "$TR_WITH"; trade_close "You are too far apart - trade cancelled."; }
}

trade_msg() {  # typ from name target fields...
  local typ=$1 from=$2 nm=$3 i e list=() n
  [[ $4 == "$MY_ID" ]] || return
  case $typ in
    TREQ)
      if [[ $TR_OUT == "$from" && -z $TR_WITH ]]; then send TACC "$MY_ID" "$MY_NAME" "$from"; trade_open "$from"; return; fi
      TR_IN[$from]=$NOW
      logm "$nm wants to trade with you - type /trade $nm to accept." "$K_LOOT"; bell ;;
    TACC)
      [[ $TR_OUT == "$from" && -z $TR_WITH ]] && (( NOW - TR_OUT_T < 60000 )) && trade_open "$from" ;;
    TCAN)
      [[ $TR_WITH == "$from" ]] && trade_close "$nm cancelled the trade." ;;
    TOFF)  # seq gold items mats
      [[ $TR_WITH == "$from" ]] && isnum "$5" && isnum "$6" && (( $6 <= 10000000 )) || return
      TR_THI=() TR_THM=()
      IFS=, read -r -a list <<< "$7"
      for e in "${list[@]}"; do valid_item "$e" && TR_THI+=("$e"); done
      TR_THI=("${TR_THI[@]:0:10}")
      IFS=, read -r -a list <<< "$8"
      for e in "${list[@]}"; do
        [[ $e =~ ^(0|[1-9][0-9]?):([1-9][0-9]{0,4})$ ]] || continue
        n=${BASH_REMATCH[1]}; (( n < NMAT )) && TR_THM[$n]=${BASH_REMATCH[2]}
      done
      TR_THSEQ=$5 TR_THG=$6 TR_MYOK=0 TR_THOK=0 MAP_DIRTY=1 ;;
    TOK)   # their seq, my seq as they saw it
      [[ $TR_WITH == "$from" ]] || return
      if [[ $5 == "$TR_THSEQ" && $6 == "$TR_MYSEQ" ]]; then TR_THOK=1 MAP_DIRTY=1; trade_check; fi ;;
  esac
}

ui_trade() {
  local nm=${OP_NAME[$TR_WITH]:-?} w=$(( (VW - 6) / 2 )) L=() Rr=() i k n c line key mk
  ui "  TRADE WITH ${nm^^}" "$K_LOOT$B"
  ui ""
  local mg
  matg() { mg=""; (( TW2 )) && mg=${MAT_I[$1]}; }
  for i in "${TR_MYI[@]}"; do item_name "${INV[i]}" "$CLS"; item_icon "${INV[i]}" "$CLS"; ivl; L+=("$II${II:+ }$INAME ($IVL)"); done
  for k in "${!TR_MYM[@]}"; do matg "$k"; L+=("${TR_MYM[$k]} $mg${MAT_NAME[k]}"); done
  (( TR_MYG )) && L+=("${EMJ[gold]}$TR_MYG gold")
  for c in "${TR_THI[@]}"; do item_name "$c" "$CLS"; item_icon "$c" "$CLS"; ivl; Rr+=("$II${II:+ }$INAME ($IVL)"); done
  for k in "${!TR_THM[@]}"; do matg "$k"; Rr+=("${TR_THM[$k]} $mg${MAT_NAME[k]}"); done
  (( TR_THG )) && Rr+=("${EMJ[gold]}$TR_THG gold")
  (( ${#L[@]} )) || L=("(nothing)"); (( ${#Rr[@]} )) || Rr=("(nothing)")
  printf -v line "  %-*s  %s" "$w" "YOU OFFER" "${nm^^} OFFERS"; ui "$line" "$B"
  n=${#L[@]}; (( ${#Rr[@]} > n )) && n=${#Rr[@]}
  for (( i = 0; i < n; i++ )); do padr "${L[i]}" "$w"; ui "  $PADS  ${Rr[i]}" "$K_CHAT"; done
  local s1="waiting" s2="waiting"
  (( TR_MYOK )) && s1="ACCEPTED"; (( TR_THOK )) && s2="ACCEPTED"
  printf -v line "  %-*s  %s" "$w" "[$s1]" "[$s2]"; ui "$line" "$K_GOOD"
  ui ""
  local pages=$(( (${#INV[@]} + 9) / 10 )) p0
  (( TR_PG >= pages && pages > 0 )) && TR_PG=$(( pages - 1 ))
  p0=$(( TR_PG * 10 ))
  if (( pages > 1 )); then ui "  Your bags (page $(( TR_PG + 1 ))/$pages, [<] [>] turn) - toggle with [1-0]:" "$B"
  else ui "  Your bags - toggle with [1-0]:" "$B"; fi
  for i in "${!INV[@]}"; do
    (( i < p0 )) && continue
    (( i >= p0 + 10 )) && break
    key=$(( (i - p0 + 1) % 10 )) mk=" "
    for k in "${TR_MYI[@]}"; do (( k == i )) && mk="*"; done
    item_name "${INV[i]}" "$CLS"; item_icon "${INV[i]}" "$CLS"
    ivl; ui "   [$key]$mk $II${II:+ }$INAME ($IVL)" $'\e['"${ICOL}m"
  done
  (( ${#INV[@]} )) || ui "   (empty)" "$K_SYS"
  ui ""
  case $TR_INPUT in
    gold) ui "  Gold to offer (you have $GOLD): ${TR_BUF}_" "$K_LOOT" ;;
    mat)  ui "  Material and amount, e.g. '5 iron':  ${TR_BUF}_" "$K_LOOT" ;;
    *)    ui "  [g] gold  [m] materials  [y] accept  [esc] cancel" "$K_SYS"
          ui "  Any change to an offer resets both acceptances." "$K_SYS" ;;
  esac
}
