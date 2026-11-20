# ---------------------------------------------------------------------------
#  Module 05b - inventory (since v1.7): four tabs (gear, items, materials,
#  hero), a cursor, item cards that show what changes if you wear something,
#  a power score, locks, sorting and a best-gear button
# ---------------------------------------------------------------------------
INV_TAB=0 INV_CUR=(1 1 1 0) INV_TOP=(0 0 0 0) INV_CONF=-1 SORT_M=0 LR_FAST=0
MAT_NEW=(); declare -A NEWG=()
INV_TABN=(Gear Items Materials Hero) INV_TABE=(🎒 🧪 💎 👤)
SORT_NAME=(type rarity value)
MAT_I=(🥉 🔩 🥈 🥇 💎 🔮 🌼 🌿 🍀 🌹 🌷 🍁 🐟 🐠 🐡 🦑 🦐 🐬 🦈 🎏 🐋 🐍)
for (( _i = GEM0; _i < NMAT; _i++ )); do gem_kq "$_i" && MAT_I[_i]=${GEM_E[GKI]}; done; unset _i   # v3.0 gems (and v4.5's perfect ones)
MAT_I[M45]=💠 MAT_I[M45+1]=⭐ MAT_I[M45+2]=🌺 MAT_I[M45+3]=🌻 MAT_I[M45+4]=🐍 MAT_I[M45+5]=🐟 MAT_I[M45+6]=🐠 MAT_I[M45+7]=🌟
MAT_RN=(common uncommon rare) MAT_RC=("38;5;252" "1;38;5;120" "1;38;5;171")
TIER_FL=("" "It has seen better days." "Plain, solid and dependable." "Fine work from a good smithy."
         "Light as a feather, hard as stone." "Runes hum quietly along it." "Still warm from dragonfire."
         "Forged from a fallen star." "Sings softly when the stars come out." "Made from the dark between worlds."
         "Hammered on the anvils of the old titans." "Cold and dark as the sun's own shadow." "Nobody remembers who made it. Probably nobody did.")
CON_L=(h m gh gm - str iron swift brew recall - meal1 meal2 - tfrost tfire tveil)   # "-" starts the next section
CON_SEC=(POTIONS "ELIXIRS & SCROLLS" FOOD TONICS)
declare -A CON_VAR=([h]=POT_H [m]=POT_M [gh]=POT_GH [gm]=POT_GM [str]=EL_STR [iron]=EL_IRON [swift]=EL_SWIFT
                    [recall]=SCROLL [brew]=BREW [meal1]=MEAL1 [meal2]=MEAL2 [tfrost]=TON_FROST [tfire]=TON_FIRE [tveil]=TON_VEIL)
declare -A CON_KEY=([h]=e [m]=r [gh]=a [gm]=b [str]=c [iron]=d [swift]=f [recall]=g [brew]=h
                    [meal1]=j [meal2]=k [tfrost]=l [tfire]=m [tveil]=n)
declare -A CON_NM=([h]="Health potion" [m]="Mana potion" [gh]="Greater health potion" [gm]="Greater mana potion"
                   [str]="Elixir of Strength" [iron]="Elixir of Iron Skin" [swift]="Elixir of Swiftness"
                   [recall]="Scroll of Recall" [brew]="Hermit's Brew" [meal1]="Grilled Fish" [meal2]="Fisherman's Feast"
                   [tfrost]="Frost Tonic" [tfire]="Fire Ward Tonic" [tveil]="Sand Veil")
declare -A CON_FX=([h]="Restores 40% of your HP. [e] on the map drinks one."
                   [m]="Restores 50% of your MP. [r] on the map drinks one."
                   [gh]="Restores 80% of your HP. [e] picks it when you are out of small ones."
                   [gm]="Restores 80% of your MP. [r] picks it when you are out of small ones."
                   [str]="+30% damage for 90 seconds." [iron]="+50% armor for 90 seconds."
                   [swift]="You move much faster for 60 seconds." [recall]="Teleports you home to Hearthmoor."
                   [brew]="Full HP and MP at once and +30% damage for 2 minutes."
                   [meal1]="Heals 35% HP. Well Fed: double regeneration for 5 minutes. [u] eats."
                   [meal2]="Heals 70% HP and 40% MP. Well Fed+: double regeneration and +10% damage for 10 minutes."
                   [tfrost]="Blizzards can't slow you down for 5 minutes."
                   [tfire]="Burning ash can't hurt you for 5 minutes."
                   [tveil]="Your eyes pierce storms and darkness for 5 minutes.")
declare -A CON_GET=([h]="Mara (Hearthmoor), most shops. Alchemy: 2 Peacebloom." [m]="Mara (Hearthmoor), most shops. Alchemy: 2 Silverleaf."
                    [gh]="Ysolde, Garrick, Nadia. Alchemy: 2 Bog Myrtle + 1 Peacebloom." [gm]="Ysolde, Orwin. Alchemy: 2 Bog Myrtle + 1 Silverleaf."
                    [str]="Ysolde. Alchemy: 3 Desert Rose." [iron]="Ysolde. Alchemy: 2 Frost Lotus + 1 Bog Myrtle."
                    [swift]="Ysolde, Orwin, Nadia. Alchemy: Emberroot, Silverleaf, Peacebloom."
                    [recall]="Mara, Garrick." [brew]="Orwin the hermit, deep in the wilds."
                    [meal1]="Cook common fish at a campfire (*) or an inn." [meal2]="Cook a rare fish at a campfire (*) or an inn."
                    [tfrost]="Nadia and the north. Alchemy: 2 Frost Lotus." [tfire]="Nadia and the ash lands. Alchemy: 2 Emberroot."
                    [tveil]="Nadia and the desert. Alchemy: 2 Desert Rose + 1 Silverleaf.")
CON_E[bag]=🎒

# --- small helpers ---------------------------------------------------------------------
mat_icon() { MI=""; (( TW2 )) && MI=${MAT_I[$1]}; }
ico() { IC=""; (( TW2 )) && IC="$1 "; }                       # emoji + space (HD only)
mat_prof() { if (( $1 < 6 )); then MP_K=1; elif (( $1 < 12 )); then MP_K=2; elif (( $1 < NFISHE )); then MP_K=0; else MP_K=3; fi; }
# rows and card lines: RC is colored ("§" marks where a row background goes), RP its plain twin
rb() { RC="" RP=""; }
rt() { RC+=$'\e[0§'"${2:+;$2}m$1"; RP+=$1; }
rpad() { dispw "$RP"; (( DW < $1 )) && { RC+=$'\e[0§m'"${BLANK:0:$1-DW}"; RP+=${BLANK:0:$1-DW}; }; }
lr() { LR_C+=("$RC"); LR_P+=("$RP"); LR_S+=("$1"); LR_ID+=("${2:-}"); }
lh() { rb; rt "$1" "${2:-1;38;5;220}"; [[ -n $3 ]] && rt "$3" "38;5;245"; lr 0; }
cc() { CD_C+=("$RC"); CD_P+=("$RP"); }
uxs() { dispw "$RP"; if (( DW > MW )); then padt "$RP" "$MW"; uix "$K_SYS$PADS$N" "$PADS"; else uix "${RC//§/}$N" "$RP"; fi; }   # emit, never wider than the frame
cblank() { RC="" RP=""; cc; }
wrapt() {  # plain text width -> WRL (lines)
  local t=$1 w=$2 cut
  WRL=()
  while (( ${#t} > w )); do
    cut=${t:0:w+1}; cut=${cut% *}; (( ${#cut} < w / 2 )) && cut=${t:0:w}
    WRL+=("$cut"); t=${t:${#cut}}; t=${t# }
  done
  [[ -n $t ]] && WRL+=("$t")
}
ctext() { local l; wrapt "$1" "$CDW"; for l in "${WRL[@]}"; do rb; rt "$l" "${2:-38;5;250}"; cc; done; }   # wrapped card text
secs() { local s=$(( $1 / 1000 )); if (( s >= 60 )); then TS="$(( s / 60 ))m$(( s % 60 ))s"; else TS="${s}s"; fi; }

set_eq() { case $1 in W) EQW=$2 ;; A) EQA=$2 ;; O) EQO=$2 ;; H) EQH=$2 ;; *) EQJ=$2 ;; esac; }
power() { POW=$(( ATK * 3 + ARMOR * 2 + (CRIT - 10) * 4 + MAXHP / 4 + MAXMP / 8 + B_LIGHT * 5 )); }
declare -A PVC=()
pv_slot() {  # slot code -> PV_ATK PV_ARM PV_CRIT PV_HP PV_MP PV_POW: my stats if <code> was worn there ("" = nothing)
  local hp=$HP mp=$MP o key="$1|$2|$EQW|$EQA|$EQO|$EQH|$EQJ|$LVL|$CLS"
  if [[ -n ${PVC[$key]} ]]; then
    set -- ${PVC[$key]}; PV_ATK=$1 PV_ARM=$2 PV_CRIT=$3 PV_HP=$4 PV_MP=$5 PV_POW=$6; power; return
  fi
  (( ${#PVC[@]} > 600 )) && PVC=()
  eq_of "$1"; o=$EQC
  set_eq "$1" "$2"; calc_stats; power
  PV_ATK=$ATK PV_ARM=$ARMOR PV_CRIT=$CRIT PV_HP=$MAXHP PV_MP=$MAXMP PV_POW=$POW
  set_eq "$1" "$o"; calc_stats; power; HP=$hp MP=$mp
  PVC[$key]="$PV_ATK $PV_ARM $PV_CRIT $PV_HP $PV_MP $PV_POW"
}
pv_delta() {  # -> DLC DLP: colored / plain power change of the last pv_slot
  local d=$(( PV_POW - POW ))
  if (( d > 0 )); then DLC="1;38;5;84" DLP="▲$d"; elif (( d < 0 )); then DLC="38;5;203" DLP="▼${d#-}"; else DLC="38;5;242" DLP="="; fi
}

active_fx() {  # -> AFX_E AFX_N AFX_T: buffs running right now
  AFX_E=() AFX_N=() AFX_T=()
  afx() { (( NOW < $1 )) || return; secs $(( $1 - NOW )); AFX_E+=("$2"); AFX_N+=("$3"); AFX_T+=("$TS"); }
  afx "$str_until" 💪 "Strength +30% dmg"; afx "$iron_until" 🐢 "Iron Skin +50% armor"
  afx "$swift_until" 🐇 "Swiftness"; afx "$buff_until" 📣 "Battle Cry +40% dmg"; afx "$anthem_until" 🎺 "Anthem"
  if (( fed_lvl == 2 )); then afx "$fed_until" 🍲 "Well Fed+ +10% dmg"; else afx "$fed_until" 🍢 "Well Fed"; fi
  afx "$frost_until" 🧊 "Frost Tonic"; afx "$fireward_until" 🧯 "Fire Ward"; afx "$veil_until" 🥽 "Sand Veil"
}

# --- tab contents: list rows (LR_*) ------------------------------------------------------------
inv_rows_gear() {  # width
  local W=$1 s i j c key nm nw lk nn d ok P0
  power; P0=$POW
  lh "EQUIPPED" "1;38;5;220" "   power $P0"
  for s in W A O H J; do
    eq_of "$s"; rb
    printf -v PF '%-8s' "${SLOT_LABEL[$s]}"; rt "$PF" "38;5;245"
    if [[ -n $EQC ]]; then
      item_name "$EQC" "$CLS"; item_icon "$EQC" "$CLS"
      nm=$INAME; (( TW2 )) && nm=$INSHORT
      lk="  "; [[ $EQC == *! ]] && { lk="* "; (( TW2 )) && lk=🔒; }
      nw=$(( W - 8 - (TW2 ? 7 : 0) - 2 - 6 ))
      rt "$lk" "38;5;220"; [[ -n $II ]] && rt "$II "
      padt "$nm" "$nw"; rt "$PADS" "$ICOL"
      if (( IVAL )); then printf -v PF '%5s' "+$IVAL"; rt "$PF" "1;38;5;231"; fi
    else
      rt "·  empty" "38;5;240"
    fi
    lr 1 "e:$s"
  done
  lh "BAG SLOTS" "1;38;5;220" "   your bags hold $BAGS"
  rb; printf -v PF '%-8s' Starter; rt "$PF" "38;5;245"; (( TW2 )) && rt "🎒🧵   "
  padt "Backpack" $(( W - 8 - (TW2 ? 7 : 0) - 6 )); rt "$PADS" "38;5;242"; rt "  +10" "38;5;242"; lr 0
  for j in 0 1 2; do
    rb; printf -v PF '%-8s' "Bag $(( j + 1 ))"; rt "$PF" "38;5;245"
    if [[ ${BAGEQ[j]} == [0-5] ]]; then
      item_name "B.${BAGEQ[j]}" "$CLS"; item_icon "B.${BAGEQ[j]}" "$CLS"
      [[ -n $II ]] && rt "$II "
      padt "$INAME" $(( W - 8 - (TW2 ? 7 : 0) - 6 )); rt "$PADS" "$ICOL"
      printf -v PF '%5s' "+$IVAL"; rt "$PF" "1;38;5;231"
    else
      rt "·  empty" "38;5;240"
    fi
    lr 1 "q:$j"
  done
  lh "BAGS ${#INV[@]}/$BAGS" "1;38;5;220" "   sorted by ${SORT_NAME[SORT_M]}"
  (( ${#INV[@]} )) || { rb; rt "  empty - slay monsters for loot" "38;5;242"; lr 0; }
  for i in "${!INV[@]}"; do
    c=${INV[i]}; rb
    key=" "; (( i < 10 )) && key=$(( (i + 1) % 10 ))
    rt "$key " "38;5;245"
    item_name "$c" "$CLS"; item_icon "$c" "$CLS"
    ok=0; [[ $ICLS == *"$CLS"* ]] && ok=1
    nm=$INAME; (( TW2 )) && nm=$INSHORT
    lk="  "; [[ $c == *! ]] && { lk="* "; (( TW2 )) && lk=🔒; }
    nn="  "; [[ -n ${NEWG[${c%!}]} ]] && { nn="+ "; (( TW2 )) && nn=✨; }
    nw=$(( W - 2 - 2 - (TW2 ? 7 : 0) - 6 - 2 ))
    rt "$lk" "38;5;220"
    [[ -n $II ]] && rt "$II "
    padt "$nm" "$nw"
    if [[ $IK == B ]]; then
      rt "$PADS" "$ICOL"
      bag_gain "$IKD"; if (( BG > 0 )); then padr " ▲$BG" 6; rt "$PADS" "1;38;5;84"; else rt " =    " "38;5;242"; fi
    elif (( ok )); then
      rt "$PADS" "$ICOL"
      if (( LR_FAST )); then rt "      "
      else pv_slot "$IK" "$c"; pv_delta; padr " $DLP" 6; rt "$PADS" "$DLC"; fi
    else
      rt "$PADS" "38;5;242"; rt " ✖    " "38;5;203"
    fi
    rt "$nn" "1;38;5;226"
    lr 1 "b:$i"
  done
  (( ${#INV[@]} < BAGS )) && { rb; rt "  $(( BAGS - ${#INV[@]} )) free slots" "38;5;240"; lr 0; }
}

inv_rows_items() {  # width
  local W=$1 e sec=0 n v col nw
  lh "${CON_SEC[0]}"
  for e in "${CON_L[@]}"; do
    if [[ $e == - ]]; then sec=$(( sec + 1 )); lh "${CON_SEC[sec]}"; continue; fi
    v=${CON_VAR[$e]}; n=${!v}; rb
    rt "[${CON_KEY[$e]}] " "38;5;245"
    ci "$e"; [[ -n $CI ]] && rt "$CI"
    col="38;5;252"; (( n > 0 )) || col="38;5;242"
    nw=$(( W - 4 - (TW2 ? 3 : 0) - 6 ))
    padt "${CON_NM[$e]}" "$nw"; rt "$PADS" "$col"
    if (( n > 0 )); then printf -v PF '%6s' "x$n"; rt "$PF" "1;38;5;231"; else rt "    x0" "38;5;240"; fi
    lr 1 "c:$e"
  done
  lh "ACTIVE EFFECTS"
  active_fx
  (( ${#AFX_N[@]} )) || { rb; rt "  none - drink something!" "38;5;242"; lr 0; }
  for n in "${!AFX_N[@]}"; do
    rb; ico "${AFX_E[n]}"; [[ -n $IC ]] && rt "$IC"
    padt "${AFX_N[n]}" $(( W - (TW2 ? 3 : 0) - 7 )); rt "$PADS" "38;5;120"; printf -v PF '%7s' "${AFX_T[n]}"; rt "$PF" "1;38;5;231"
    lr 0
  done
}

inv_rows_mats() {  # width
  local W=$1 p k a b nw col tot=0 g
  for p in 1 2 0 3; do
    case $p in 1) g=🔨 ;; 2) g=🌿 ;; 0) g=🎣 ;; 3) g=💎 ;; esac
    rb; ico "$g"; [[ -n $IC ]] && rt "$IC" "1"
    if (( p == 3 )); then rt "GEMS" "1;38;5;213"; rt "  set them in at any smith" "38;5;245"
    else
    prof_next "${PROF_LV[p]}"
    printf -v PF '%-10s' "${PROF_NAME[p]^^}"; rt "$PF" "1;38;5;220"; printf -v PF '%-3d' "${PROF_LV[p]}"; rt "Lv $PF" "1;38;5;231"
    if (( PROF_LV[p] >= PROF_MAX )); then rt "MASTER" "1;38;5;84"
    else pbar "${PROF_XP[p]}" "$PN" 10 $'\e[38;5;220m'; RC+="$PB"; RP+=${BLANK:0:10}; fi
    fi
    lr 0
    for k in ${MAT_GRP[p]}; do
      rb; mat_icon "$k"; [[ -n $MI ]] && rt "$MI "
      col=${MAT_RC[${MAT_RARE[k]}]}; (( MATS[k] > 0 )) || col="38;5;242"
      nw=$(( W - (TW2 ? 3 : 0) - 6 - 5 - 1 ))
      padt "${MAT_NAME[k]}" "$nw"; rt "$PADS" "$col"
      if (( MATS[k] > 0 )); then printf -v PF '%6s' "${MATS[k]}"; rt "$PF" "1;38;5;231"; else rt "     0" "38;5;240"; fi
      if (( ${MAT_NEW[k]:-0} > 0 )); then printf -v PF ' %-4s' "+${MAT_NEW[k]}"; rt "$PF" "1;38;5;84"; else rt "     "; fi
      tot=$(( tot + MATS[k] * MAT_VAL[k] ))
      lr 1 "m:$k"
    done
  done
  rb; rt "worth about ${tot}g in total" "38;5;245"; lr 0
}

inv_rows_hero() {  # width
  local W=$1 s i pad=$(( ($1 - 2) / 2 - 9 )) e c t
  (( pad < 0 )) && pad=0
  dollc() { eq_of "$1"; if [[ -n $EQC ]]; then item_stats "$EQC"; DC=$IKE; else DC="··"; fi; }
  if (( TW2 )); then
    rb; lr 0
    dollc H; rb; rt "${BLANK:0:pad+8}"; rt "$DC"; lr 0
    dollc W; local dw=$DC; dollc O; rb; rt "${BLANK:0:pad}"; rt "$dw" ; rt "      "; rt "${CEMO[CLS]}"; rt "      "; rt "$DC"; lr 0
    dollc A; rb; rt "${BLANK:0:pad+8}"; rt "$DC"; lr 0
    dollc J; rb; rt "${BLANK:0:pad+8}"; rt "$DC"; lr 0
    rb; lr 0
  fi
  rb; rt "$MY_NAME" "1;38;5;${P_COLC[COLR]}"; rt "  Level $LVL ${C_NAME[CLS]}" "1;38;5;231"; lr 0
  rb; rt "XP " "38;5;245"; pbar "$XP" "$XPNEXT" 16 $'\e[38;5;220m'; RC+="$PB"; RP+=${BLANK:0:16}
  rt " $XP/$XPNEXT" "38;5;245"; lr 0
  rb; rt "HP " "38;5;245"; hp_col "$HP" "$MAXHP"; pbar "$HP" "$MAXHP" 16 "$HC"; RC+="$PB"; RP+=${BLANK:0:16}; rt " $HP/$MAXHP" "38;5;245"; lr 0
  rb; rt "MP " "38;5;245"; pbar "$MP" "$MAXMP" 16 $'\e[38;5;33m'; RC+="$PB"; RP+=${BLANK:0:16}; rt " $MP/$MAXMP" "38;5;245"; lr 0
  rb; lr 0
  rb; ico 💰; rt "$IC" ; rt "$GOLD gold" "1;38;5;220"; rt "   "; ico 🎒; rt "$IC"; rt "bags ${#INV[@]}/$BAGS" "38;5;252"; lr 0
  rb; ico 💀; rt "$IC"; rt "$KILLS kills" "38;5;252"; rt "   "; ico 👻; rt "$IC"; rt "$DEATHS deaths" "38;5;252"; lr 0
  rb; ico 📜; rt "$IC"; rt "${#QUESTS[@]}/3 quests" "38;5;252"; lr 0
  rb; lr 0
  lh "PROFESSIONS"
  for i in 0 1 2; do
    prof_next "${PROF_LV[i]}"; rb
    case $i in 0) e=🎣 ;; 1) e=🔨 ;; 2) e=🌿 ;; esac
    ico "$e"; rt "$IC"; printf -v PF '%-10s Lv %-3d' "${PROF_NAME[i]}" "${PROF_LV[i]}"; rt "$PF" "38;5;252"
    if (( PROF_LV[i] >= PROF_MAX )); then rt "MASTER" "1;38;5;84"
    else pbar "${PROF_XP[i]}" "$PN" 10 $'\e[38;5;220m'; RC+="$PB"; RP+=${BLANK:0:10}; fi
    lr 0
  done
}

inv_build() {  # width -> LR_* for the current tab
  LR_C=() LR_P=() LR_S=() LR_ID=()
  case $INV_TAB in 0) inv_rows_gear "$1" ;; 1) inv_rows_items "$1" ;; 2) inv_rows_mats "$1" ;; 3) inv_rows_hero "$1" ;; esac
}

inv_fixcur() {  # keep the cursor on a row that can be selected
  local n=${#LR_S[@]} c=${INV_CUR[INV_TAB]} j
  (( c >= n )) && c=$(( n - 1 )); (( c < 0 )) && c=0
  if (( ! ${LR_S[c]:-0} )); then
    for (( j = c; j < n; j++ )); do (( LR_S[j] )) && break; done
    if (( j >= n )); then for (( j = c; j >= 0; j-- )); do (( LR_S[j] )) && break; done; fi
    c=$j
  fi
  INV_CUR[INV_TAB]=$c
}

# --- the card on the right ----------------------------------------------------------------
cmp_row() {  # label old new [suffix]
  local d=$(( $3 - $2 )) col="38;5;242" t="" sx=${4:-}
  (( d > 0 )) && { col="1;38;5;84" t="▲$d"; }; (( d < 0 )) && { col="38;5;203" t="▼${d#-}"; }
  (( d )) || return
  rb; printf -v PF '%-8s%5s →%5s ' "$1" "$2$sx" "$3$sx"; rt "$PF" "38;5;250"; rt "$t" "$col"; cc
}

inv_card_bag() {  # code worn-slot ("" = in your bags)
  local c=$1 j=$2 k nb
  item_name "$c" "$CLS"; item_icon "$c" "$CLS"; k=$IKD
  rb; [[ -n $II ]] && rt "$II "; rt "$INAME" "$ICOL"; cc
  rb; rt "${RAR_NAME[IRR]} bag · $IVAL slots" "38;5;245"; cc
  ctext "${BAG_FL[k]}" "3;38;5;244"
  cblank
  rb; ico 🎒; rt "$IC"; rt "+$IVAL bag slots" "1;38;5;231"; cc
  rb; ico 💰; rt "$IC"; rt "sells for ${ISELL}g" "38;5;220"; cc
  [[ $c == *! ]] && { rb; ico 🔒; rt "$IC"; rt "locked - shops won't buy it" "38;5;220"; cc; }
  cblank
  if [[ -n $j ]]; then
    nb=$(( BAGS - IVAL ))
    rb; rt "Take it off: " "38;5;250"; rt "$BAGS → $nb slots" "1;38;5;203"; cc
    (( ${#INV[@]} + 1 > nb )) && ctext "Make room first: you carry ${#INV[@]} items." "38;5;203"
  else
    bag_gain "$k"
    if (( BG > 0 )); then
      rb; rt "Put it on: " "38;5;250"; rt "$BAGS → $(( BAGS + BG )) slots" "1;38;5;84"; cc
      [[ ${BAGEQ[BGJ]} == [0-5] ]] && ctext "It replaces your ${BAG_NAME[${BAGEQ[BGJ]}]}." "38;5;245"
    else
      ctext "All 3 bag slots already hold bags at least this big. Sell it, store it at a banker or trade it." "38;5;245"
    fi
  fi
}

inv_card_gear() {  # id
  local id=$1 c worn=0 s nm col k kn t r v bt cl sell ok l uq fl
  case $id in
    q:*) s=${id#q:}
         if [[ ${BAGEQ[s]} == [0-5] ]]; then inv_card_bag "B.${BAGEQ[s]}" "$s"
         else
           rb; rt "Empty bag slot" "1;38;5;231"; cc; cblank
           ctext "Put a bag on with [enter] in your bags. Mara, Garrick, Nadia, Jarl Hrolf and Ser Kael sell them; bosses drop the big ones." "38;5;250"
         fi
         return ;;
    b:*) c=${INV[${id#b:}]}; [[ $c == B.* ]] && { inv_card_bag "$c" ""; return; } ;;
    e:*) s=${id#e:}; eq_of "$s"; c=$EQC; worn=1 ;;
    *) return ;;
  esac
  if [[ -z $c ]]; then
    rb; rt "Empty ${SLOT_LABEL[$s],,} slot" "1;38;5;231"; cc; cblank
    ctext "Monsters drop gear for every slot. Smiths and traders sell some, and other players trade it."
    return
  fi
  item_name "$c" "$CLS"; item_icon "$c" "$CLS"; bonus_txt
  nm=$INAME col=$ICOL k=$IK kn=$IKN t=$IT r=$IRR v=$IVAL bt=$BTX cl=$ICLS sell=$ISELL uq=$IUQ fl=${TIER_FL[IT]}
  if [[ -n $uq ]]; then                       # uniques: say what kind of thing it is, tell its own story
    case $k in W) kn=${WK_NAME[IKD]} ;; A) kn=${AK_NAME[IKD]} ;; O) kn=${OK_NAME[IKD]} ;; H) kn=${HK_NAME[IKD]} ;; *) kn=${JK_NAME[IKD]} ;; esac
    fl=${U_FL[uq]}
  fi
  ok=0; [[ $cl == *"$CLS"* ]] && ok=1
  wrapt "$nm" $(( CDW - (TW2 ? 7 : 0) ))
  rb; [[ -n $II ]] && rt "$II "; rt "${WRL[0]}" "$col"; cc
  for l in "${WRL[@]:1}"; do rb; rt "$l" "$col"; cc; done
  rb; rt "${RAR_NAME[r]} ${SLOT_LABEL[$k],,} · $kn" "38;5;245"; cc
  ctext "$fl" "3;38;5;244"
  [[ -n $uq ]] && ctext "${TIER_Q[t]} tier - the only one of its kind." "38;5;208"
  cblank
  if (( v )); then
    rb; if [[ $k == W ]]; then ico 💥; rt "$IC"; rt "+$v damage" "1;38;5;231"; else ico 🔰; rt "$IC"; rt "+$v armor" "1;38;5;231"; fi; cc
  fi
  [[ -n $bt ]] && { rb; ico ✨; rt "$IC"; rt "$bt" "1;38;5;117"; cc; }
  sock_info "$c"
  if (( SN )); then                           # v3.0: sockets and gems
    gems_txt "$c"; gems_plain "$c"
    rb; ico 💎; rt "$IC"; (( TW2 )) && rt "$GTX " "1"; rt "$SF/$SN sockets${GPL:+: $GPL}" "1;38;5;213"; cc
  fi
  cls_list "$cl"
  if (( ok )); then rb; ico 👥; rt "$IC"; rt "✔ " "1;38;5;84"; rt "$CLT" "38;5;250"; cc
  else rb; ico 👥; rt "$IC"; rt "✖ " "1;38;5;203"; rt "only $CLT" "38;5;203"; cc; fi
  rb; ico 💰; rt "$IC"; rt "sells for ${sell}g" "38;5;220"; cc
  [[ $c == *! ]] && { rb; ico 🔒; rt "$IC"; rt "locked - shops won't buy it" "38;5;220"; cc; }
  cblank
  if (( worn )); then
    if [[ $k == [WA] ]]; then ctext "You are wearing it. Equip another ${SLOT_LABEL[$k],,} from your bags to swap." "38;5;245"
    else
      pv_slot "$k" ""; rb; rt "If you take it off:" "1;38;5;231"; cc
      cmp_row Power "$POW" "$PV_POW"; cmp_row Attack "$ATK" "$PV_ATK"; cmp_row Armor "$ARMOR" "$PV_ARM"
      cmp_row Crit "$CRIT" "$PV_CRIT" %; cmp_row "Max HP" "$MAXHP" "$PV_HP"; cmp_row "Max MP" "$MAXMP" "$PV_MP"
    fi
  elif (( ok )); then
    pv_slot "$k" "$c"
    eq_of "$k"
    if [[ -n $EQC ]]; then item_name "$EQC" "$CLS"; rb; rt "Instead of your " "1;38;5;231"; padt "$IKN:" $(( CDW - 16 )); rt "$PADS" "1;$ICOL"; cc
    else ctext "Fills your empty ${SLOT_LABEL[$k],,} slot:" "1;38;5;231"; fi
    local n0=${#CD_C[@]}
    cmp_row Power "$POW" "$PV_POW"; cmp_row Attack "$ATK" "$PV_ATK"; cmp_row Armor "$ARMOR" "$PV_ARM"
    cmp_row Crit "$CRIT" "$PV_CRIT" %; cmp_row "Max HP" "$MAXHP" "$PV_HP"; cmp_row "Max MP" "$MAXMP" "$PV_MP"
    (( ${#CD_C[@]} > n0 )) || { rb; rt "no change at all" "38;5;242"; cc; }
  else
    ctext "A ${C_NAME[CLS]} can't use this. Sell it, or /trade it to someone who can." "38;5;203"
  fi
}

inv_card_items() {  # id
  local e=${1#c:} v n
  [[ $1 == c:* ]] || return
  v=${CON_VAR[$e]}; n=${!v}
  rb; ci "$e"; [[ -n $CI ]] && rt "$CI"; rt "${CON_NM[$e]}" "1;38;5;231"; cc
  if (( n > 0 )); then rb; rt "You have $n" "1;38;5;84"; cc; else rb; rt "You have none" "38;5;203"; cc; fi
  cblank
  ctext "${CON_FX[$e]}" "38;5;252"
  cblank
  rb; rt "WHERE TO GET IT" "1;38;5;220"; cc
  ctext "${CON_GET[$e]}" "38;5;245"
  cblank
  if (( n > 0 )); then rb; rt "[enter]" "1;38;5;226"; rt " or " "38;5;245"; rt "[${CON_KEY[$e]}]" "1;38;5;226"; rt " use it now" "38;5;245"; cc; fi
}

mat_found() {  # material -> MF (where it comes from)
  local k=$1 t kind e f rq rr cond z zones="" req=1 night=""
  if mat_node "$k"; then
    t=$MNT_T; node_prof "$t"
    MF="${M_NAME[t]}, ${PROF_NAME[NPK]} ${M_LVL[t]}+. ${MW_NAME[t]}."
    return
  fi
  for kind in "${!FISHW[@]}"; do
    for e in ${FISHW[$kind]}; do
      IFS=: read -r f rq rr cond <<< "$e"
      (( f == k )) || continue
      req=$rq; [[ $cond == night ]] && night=" Only bites at night."
      for z in "${!WATER_OF[@]}"; do [[ ${WATER_OF[$z]} == "$kind" ]] && zones+="${z//_/ }, "; done
      [[ $kind == fresh ]] && zones+="rivers and ponds, "
    done
  done
  MF="Fishing $req+. ${zones%, }.$night"
}

mat_uses() {  # material -> MU (lines)
  local k=$1 i t TW2=0 sv=$CRAFT
  MU=()
  if gem_kq "$k"; then
    local g=$GKI q=$(( GQI - 1 )) v=(${GEM_V[GKI]})
    MU+=("In a socket: +${v[q]}${GEM_TXT[g]}." "Jewelcrafting at any smith sets it into gear with sockets.")
    (( q < 2 )) && MU+=("Three of them make one ${GEM_GRADE[q+1]} ${GEM_NAME[g]}.")
    return
  fi
  if (( k < 6 )); then
    t=$(( k + 2 )); MU+=("Forge (Brom): ${TIER_Q[t]} weapons and armor - 6 ore + $(( 15 * t * t ))g, often Rare or better.")
  elif (( k < 12 )); then
    CRAFT=alch; craft_build
    for i in "${!RC_ID[@]}"; do
      [[ " ${RC_NEED[i]} " == *" $k:"* ]] || continue
      t=" ${RC_NEED[i]}"; t=${t#* $k:}; t=${t%% *}
      MU+=("Alchemy: ${RC_LAB[i]%% (*} ($t)")
    done
    CRAFT=$sv
  else
    if (( MAT_RARE[k] == 2 )); then MU+=("Cooking: Fisherman's Feast"); else MU+=("Cooking: Grilled Fish"); fi
    MU+=("Mara, Garrick and Nadia buy fish.")
  fi
}

inv_card_mats() {  # id
  local k=${1#m:} l
  [[ $1 == m:* ]] || return
  mat_prof "$k"; mat_icon "$k"
  rb; [[ -n $MI ]] && rt "$MI "; rt "${MAT_NAME[k]}" "${MAT_RC[${MAT_RARE[k]}]}"; cc
  rb; rt "${PROF_NAME[MP_K]:-Jewelcrafting} · ${MAT_RN[${MAT_RARE[k]}]}" "38;5;245"; cc
  cblank
  rb; rt "You have " "38;5;250"; rt "${MATS[k]}" "1;38;5;231"
  (( ${MAT_NEW[k]:-0} > 0 )) && rt "  (+${MAT_NEW[k]} new)" "1;38;5;84"
  cc
  rb; ico 💰; rt "$IC"; rt "${MAT_VAL[k]}g each, $(( MATS[k] * MAT_VAL[k] ))g for all" "38;5;220"; cc
  cblank
  rb; rt "FOUND" "1;38;5;220"; cc
  mat_found "$k"; ctext "$MF" "38;5;250"
  cblank
  rb; rt "USED FOR" "1;38;5;220"; cc
  mat_uses "$k"; for l in "${MU[@]}"; do ctext "$l" "38;5;250"; done
}

inv_card_hero() {
  local s n
  power
  rb; rt "COMBAT" "1;38;5;220"; cc
  rb; ico ⚡; rt "$IC"; rt "Power  " "38;5;245"; rt "$POW" "1;38;5;226"; cc
  rb; ico 💥; rt "$IC"; rt "Attack " "38;5;245"; rt "$ATK" "1;38;5;231"; cc
  rb; ico 🔰; rt "$IC"; rt "Armor  " "38;5;245"; rt "$ARMOR" "1;38;5;231"; cc
  rb; ico 🎯; rt "$IC"; rt "Crit   " "38;5;245"; rt "$CRIT%" "1;38;5;231"; cc
  cblank
  rb; rt "FROM YOUR GEAR" "1;38;5;220"; cc
  rb; rt "+$B_HP% HP  +$B_MP% MP  +$B_DMG% dmg" "38;5;117"; cc
  rb; rt "+$B_ARM armor  +$B_LIGHT light" "38;5;117"; cc
  cblank
  rb; rt "ACTIVE EFFECTS" "1;38;5;220"; cc
  active_fx
  (( ${#AFX_N[@]} )) || { rb; rt "none" "38;5;242"; cc; }
  for n in "${!AFX_N[@]}"; do rb; ico "${AFX_E[n]}"; rt "$IC"; rt "${AFX_N[n]} " "38;5;120"; rt "${AFX_T[n]}" "1;38;5;231"; cc; done
  (( NOW < WANTED_UNTIL )) && { cblank; rb; rt "WANTED by the guards!" "1;38;5;203"; cc; }
}

inv_card() {  # id
  CD_C=() CD_P=()
  case $INV_TAB in 0) inv_card_gear "$1" ;; 1) inv_card_items "$1" ;; 2) inv_card_mats "$1" ;; 3) inv_card_hero ;; esac
}

# --- drawing ---------------------------------------------------------------------------
ui_inv() {
  local lw rw H r li top cur n bg mk lc lp line plain i id narrow=0 nl nc foot1 foot2 badge t
  lw=$(( MW * 54 / 100 )); (( lw > 46 )) && lw=46; (( lw < 36 )) && lw=36
  rw=$(( MW - lw - 3 ))
  (( rw < 26 )) && { narrow=1 lw=$(( MW - 2 )) rw=$(( MW - 2 )); }
  CDW=$(( rw - 4 ))
  # tab bar
  rb; rt " "
  for i in 0 1 2 3; do
    badge=""; (( i == 0 && ${#NEWG[@]} )) && badge=" •${#NEWG[@]}"
    if (( i == 2 )); then n=0; for t in "${MAT_NEW[@]}"; do n=$(( n + t )); done; (( n )) && badge=" •$n"; fi
    ico "${INV_TABE[i]}"
    if (( i == INV_TAB )); then rt " $IC${INV_TABN[i]}$badge " "1;38;5;16;48;5;220"
    else rt " $IC${INV_TABN[i]}" "38;5;250"; [[ -n $badge ]] && rt "$badge" "1;38;5;84"; rt " "; fi
    rt " "
  done
  ico 💰; t="$IC$GOLD"; dispw "$RP$t"; (( DW < MW - 2 )) && rt "${BLANK:0:MW-2-DW}"; rt "$t" "1;38;5;220"
  uxs
  # stats
  power; rb
  rt " Power " "38;5;245"; rt "$POW" "1;38;5;226"; rt "   Attack " "38;5;245"; rt "$ATK" "1;38;5;231"
  rt "  Armor " "38;5;245"; rt "$ARMOR" "1;38;5;231"; rt "  Crit " "38;5;245"; rt "$CRIT%" "1;38;5;231"
  rt "  HP " "38;5;245"; rt "$MAXHP" "1;38;5;231"; rt "  MP " "38;5;245"; rt "$MAXMP" "1;38;5;231"
  dispw "$RP"; (( DW <= MW )) || { rb; rt " Power $POW  Atk $ATK  Arm $ARMOR  Crit $CRIT%" "38;5;250"; }
  uxs
  t=${BLANK:0:MW}; uix "$K_FRAME${t// /─}$N" "$t"
  # list + card
  LR_FAST=0; inv_build $(( lw - 2 )); inv_fixcur
  cur=${INV_CUR[INV_TAB]}; id=${LR_ID[cur]:-}
  inv_card "$id"
  nc=${#CD_C[@]} n=${#LR_C[@]}
  H=$(( VH - 5 ))
  if (( narrow )); then (( nc > H / 2 )) && nc=$(( H / 2 )); else (( nc > H - 2 )) && nc=$(( H - 2 )); fi
  nl=$H; (( narrow && nc )) && { nl=$(( H - nc - 2 )); (( nl < 6 )) && nl=6; }
  top=${INV_TOP[INV_TAB]}
  (( cur >= 0 && cur < top )) && top=$cur
  (( cur >= top + nl )) && top=$(( cur - nl + 1 ))
  (( top > n - nl )) && top=$(( n - nl )); (( top < 0 )) && top=0
  INV_TOP[INV_TAB]=$top
  for (( r = 0; r < H; r++ )); do
    lc="" lp=""
    if (( r < nl )); then
      li=$(( top + r ))
      if (( li < n )); then
        bg="" mk="  "
        if (( li == cur )); then bg=";48;5;237"; mk=$'\e[0;1;38;5;226;48;5;237m▶ '
        elif (( r == 0 && top > 0 )); then mk=$'\e[0;38;5;245m▲ '
        elif (( r == nl - 1 && li < n - 1 )); then mk=$'\e[0;38;5;245m▼ '; fi
        lc="$mk${LR_C[li]//§/$bg}" lp="  ${LR_P[li]}"
        dispw "$lp"; (( DW < lw )) && { lc+=$'\e[0'"${bg}m${BLANK:0:lw-DW}"; lp+=${BLANK:0:lw-DW}; }
        lc+=$N
      else
        lc=${BLANK:0:lw} lp=$lc
      fi
    fi
    if (( narrow )); then
      (( r < nl )) || { i=$(( r - nl - 1 )); inv_cardline "$i" "$nc"; lc=$CLC lp=$CLP; }
      uix " $lc" " $lp"
    else
      inv_cardline $(( r - 1 )) "$nc"
      uix " $lc $CLC" " $lp $CLP"
    fi
  done
  # footer
  case $INV_TAB in
    0) foot1="[↑↓] select  [enter] equip/put on  [l] lock  [x] destroy  [o] sort: ${SORT_NAME[SORT_M]}"
       foot2="[1-0] quick equip  [b] best gear  [←→/tab] tabs  [esc] close" ;;
    1) foot1="[↑↓] select  [enter] use  [a-n] quick use  [e/r] potions"
       foot2="[←→/tab] tabs  [esc] close   - [u] eats on the map" ;;
    2) foot1="Gather: [g] at veins, herbs and water. Forge/brew/cook at NPCs."
       foot2="[↑↓] select  [←→/tab] tabs  [esc] close" ;;
    3) foot1="Power: what your gear and level are worth in a fight."
       foot2="[←→/tab] tabs  [esc] close" ;;
  esac
  if (( INV_CONF >= 0 )) && [[ -n ${INV[INV_CONF]} ]]; then item_name "${INV[INV_CONF]}" "$CLS"; ui "  Press [x] again to destroy $INAME - it will be gone for good." "$K_HURT"
  else ui "  $foot1" "$K_SYS"; fi
  ui "  $foot2" "$K_SYS"
}

inv_cardline() {  # row count -> CLC CLP: one line of the bordered card (row -1 = top border)
  local r=$1 n=$2 t
  CLC="" CLP=""
  (( n )) || return
  if (( r == -1 )); then t=${BLANK:0:rw-2}; CLC="$K_FRAME╭${t// /─}╮$N" CLP="╭${t}╮"
  elif (( r == n )); then t=${BLANK:0:rw-2}; CLC="$K_FRAME╰${t// /─}╯$N" CLP="╰${t}╯"
  elif (( r >= 0 && r < n )); then
    t=${CD_P[r]}; dispw "$t"
    if (( DW > CDW )); then padt "$t" "$CDW"; CLC="$K_FRAME│$N $PADS $K_FRAME│$N" CLP="│ $PADS │"
    else CLC="$K_FRAME│$N ${CD_C[r]//§/}$N${BLANK:0:CDW-DW} $K_FRAME│$N" CLP="│ $t${BLANK:0:CDW-DW} │"; fi
  fi
}

# --- keys ------------------------------------------------------------------------------
inv_leave_tab() { case $INV_TAB in 0) NEWG=() ;; 2) MAT_NEW=() ;; esac; INV_CONF=-1; }

inv_tab() { inv_leave_tab; INV_TAB=$(( (INV_TAB + $1 + 4) % 4 )); }

inv_move() {  # -1 | 1 | -10 | 10
  local c n j step=1
  LR_FAST=1; inv_build 40; LR_FAST=0; inv_fixcur
  c=${INV_CUR[INV_TAB]} n=${#LR_S[@]}
  (( $1 < 0 )) && step=-1
  for (( j = c + step; j >= 0 && j < n; j += step )); do (( LR_S[j] )) && { c=$j; (( ${1#-} == 1 )) && break; }; done
  INV_CUR[INV_TAB]=$c
}

inv_key() {
  local k=$1 id conf=$INV_CONF
  INV_CONF=-1
  case $k in
    LEFT|'[') inv_tab -1; return ;;
    RIGHT|']'|$'\t') inv_tab 1; return ;;
    UP|w) inv_move -1; return ;;
    DOWN|s) inv_move 1; return ;;
  esac
  LR_FAST=1; inv_build 40; LR_FAST=0; inv_fixcur
  id=${LR_ID[${INV_CUR[INV_TAB]}]:-}
  case $INV_TAB in
    0) case $k in
         ''|$'\r'|' '|e) case $id in b:*) inv_equip "${id#b:}" ;; e:*) inv_unequip "${id#e:}" ;; q:*) bag_unequip "${id#q:}" ;; esac ;;
         [1-9]) inv_equip $(( k - 1 )) ;;
         0) inv_equip 9 ;;
         l|L) inv_lock "$id" ;;
         x|X) inv_destroy "$id" "$conf" ;;
         o|O) SORT_M=$(( (SORT_M + 1) % 3 )); inv_sort ;;
         b|B) inv_best ;;
       esac ;;
    1) case $k in
         ''|$'\r'|' ') [[ $id == c:* ]] && use_item "${id#c:}" ;;
         e) use_item h ;; r) use_item m ;;
         a) use_item gh ;; b) use_item gm ;; c) use_item str ;; d) use_item iron ;;
         f) use_item swift ;; g) use_item recall ;; h) use_item brew ;;
         j) use_item meal1 ;; k) use_item meal2 ;; l) use_item tfrost ;;
         m) use_item tfire ;; n) use_item tveil ;;
       esac ;;
  esac
}

inv_equip() {  # bag index [quiet]
  local i=$1 old c pl
  (( i < ${#INV[@]} )) || return 1
  c=${INV[i]}; item_name "$c" "$CLS"
  if [[ $IK == B ]]; then [[ $2 == quiet ]] && return 1; bag_equip "$i"; return; fi
  if [[ $ICLS != *"$CLS"* ]]; then
    pl=${IKN}s; [[ $IKN == *s ]] && pl=$IKN
    cls_list "$ICLS"; logm "A ${C_NAME[CLS]} can't use $pl - only $CLT. Sell or trade it." "$K_HURT"; return 1
  fi
  eq_of "$IK"; old=$EQC
  set_eq "$IK" "$c"
  if [[ -n $old ]]; then INV[i]=$old; else unset "INV[i]"; INV=("${INV[@]}"); fi
  unset "NEWG[${c%!}]"
  calc_stats
  [[ $2 == quiet ]] || logm "Equipped $INAME. Attack $ATK, armor $ARMOR, crit $CRIT%." "$K_GOOD"
  POS_DIRTY=1
}

inv_unequip() {  # slot
  local s=$1
  if [[ $s == [WA] ]]; then logm "You always keep a weapon and armor on - equip another one to swap." "$K_SYS"; return; fi
  eq_of "$s"; [[ -n $EQC ]] || return
  (( ${#INV[@]} < BAGS )) || { logm "Your bags are full." "$K_HURT"; return; }
  item_name "$EQC" "$CLS"
  INV+=("$EQC"); set_eq "$s" ""; calc_stats
  logm "You take off $INAME." "$K_SYS"
}

inv_lock() {  # id
  local id=$1 i c s
  case $id in
    b:*) i=${id#b:}; c=${INV[i]}; [[ -n $c ]] || return
         if [[ $c == *! ]]; then INV[i]=${c%!}; else INV[i]="$c!"; fi; c=${INV[i]} ;;
    e:*) s=${id#e:}; eq_of "$s"; c=$EQC; [[ -n $c ]] || return
         if [[ $c == *! ]]; then c=${c%!}; else c="$c!"; fi; set_eq "$s" "$c" ;;
    *) return ;;
  esac
  item_name "$c" "$CLS"
  if [[ $c == *! ]]; then logm "Locked $INAME - shops won't buy it and it can't be destroyed." "$K_LOOT"
  else logm "Unlocked $INAME." "$K_SYS"; fi
}

inv_destroy() {  # id confirmed-index
  local i
  [[ $1 == b:* ]] || { [[ $1 == e:* ]] && logm "Take it off first." "$K_SYS"; return; }
  i=${1#b:}; [[ -n ${INV[i]} ]] || return
  if [[ ${INV[i]} == *! ]]; then logm "That one is locked - unlock it with [l] first." "$K_HURT"; return; fi
  if (( $2 == i )); then
    item_name "${INV[i]}" "$CLS"; unset "INV[i]"; INV=("${INV[@]}")
    logm "You smash the $INAME to pieces." "$K_HURT"
  else
    INV_CONF=$i
  fi
}

inv_sort() { sort_items INV; logm "Bags sorted by ${SORT_NAME[SORT_M]}." "$K_SYS"; }

sort_items() {  # array name: by SORT_M (type, rarity or value) - things you can use first
  local -n sarr=$1
  local c k u si ord=WAOHJB lines=() l
  for c in "${sarr[@]}"; do
    item_stats "$c"; u=1; [[ $ICLS == *"$CLS"* ]] && u=0
    si=${ord%%"$IK"*}; si=${#si}
    case $SORT_M in
      0) k=$(( u * 10000000 + si * 1000000 + 999999 - IVAL * 100 - IBV )) ;;
      1) k=$(( u * 10000000 + (4 - IRR) * 1000000 + (9 - IT) * 100000 + si * 10000 + 9999 - IVAL )) ;;
      *) l=$ISELL; (( l > 999999 )) && l=999999; k=$(( u * 10000000 + 999999 - l )) ;;
    esac
    printf -v l '%08d %s' "$k" "$c"; lines+=("$l")
  done
  (( ${#lines[@]} )) && mapfile -t "$1" < <(printf '%s\n' "${lines[@]}" | sort | cut -d' ' -f2)
}

inv_best() {  # wear the strongest thing you have for every slot
  local s i c bi bp n=0 names=""
  for s in W A O H J; do
    power; bp=$POW bi=-1
    for i in "${!INV[@]}"; do
      c=${INV[i]}; item_stats "$c"
      [[ $IK == "$s" && $ICLS == *"$CLS"* ]] || continue
      pv_slot "$s" "$c"; (( PV_POW > bp )) && { bp=$PV_POW bi=$i; }
    done
    if (( bi >= 0 )); then item_name "${INV[bi]}" "$CLS"; names+="$IKN, "; inv_equip "$bi" quiet; n=$(( n + 1 )); fi
  done
  power
  if (( n )); then logm "Equipped ${names%, }. Power is now $POW." "$K_GOOD"
  else logm "You already wear your best gear (power $POW)." "$K_SYS"; fi
}
