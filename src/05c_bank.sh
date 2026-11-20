# ---------------------------------------------------------------------------
#  Module 05c - bags and banks (since v1.8): bags in six sizes; bankers in
#  every town open the same personal vault; the shared chest is one for all
#  heroes on this computer.
# ---------------------------------------------------------------------------
SC_FILE="$DATA_DIR/shared.chest" SC_CAP=24 SC_ITEMS=() SC_G=0 SC_M=()
BK_TAB=0 BK_SIDE=0 BK_CUR=(0 0) BK_TOP=(0 0) BK_INPUT="" BK_BUF="" BK_NPC=""
VAULT_UP=(30 40 50 60) VAULT_COST=(1500 4000 9000)
BAGEQ=(- - -) BAGS=10 BANK=() BANKG=0 BANKCAP=30 BANKM=()

ivl() { if [[ $IK == B ]]; then IVL="$IVAL slots"; else IVL="+$IVAL"; fi; }       # after item_stats
bag_cap() { local b; BAGS=10; for b in "${BAGEQ[@]}"; do [[ $b == [0-5] ]] && BAGS=$(( BAGS + BAG_SZ[b] )); done; }

bag_gain() {  # kind -> BG (slots won by wearing it) BGJ (bag slot it goes to, -1 = no use)
  local j s min=99 mj=-1
  BG=0 BGJ=-1
  for j in 0 1 2; do
    if [[ ${BAGEQ[j]} != [0-5] ]]; then BG=${BAG_SZ[$1]} BGJ=$j; return; fi
    s=${BAG_SZ[${BAGEQ[j]}]}; (( s < min )) && { min=$s mj=$j; }
  done
  (( BAG_SZ[$1] > min )) && { BG=$(( BAG_SZ[$1] - min )) BGJ=$mj; }
}

bag_equip() {  # bag index in INV
  local i=$1 c k old
  c=${INV[i]%!}; k=${c#B.}
  bag_gain "$k"
  if (( BGJ < 0 )); then logm "All 3 bag slots already hold bags at least this big." "$K_SYS"; return 1; fi
  old=${BAGEQ[BGJ]}
  BAGEQ[BGJ]=$k
  if [[ $old == [0-5] ]]; then INV[i]="B.$old"; else unset "INV[i]"; INV=("${INV[@]}"); fi
  unset "NEWG[$c]"
  bag_cap
  if [[ $old == [0-5] ]]; then logm "${BAG_E[k]} You swap your ${BAG_NAME[old]} for the ${BAG_NAME[k]}. Your bags now hold $BAGS items." "$K_GOOD"
  else logm "${BAG_E[k]} You put on the ${BAG_NAME[k]}. Your bags now hold $BAGS items." "$K_GOOD"; fi
}

bag_unequip() {  # bag slot 0-2
  local j=$1 k=${BAGEQ[$1]}
  [[ $k == [0-5] ]] || return
  if (( ${#INV[@]} + 1 > BAGS - BAG_SZ[k] )); then
    logm "Make room first - without the ${BAG_NAME[k]} your bags would only hold $(( BAGS - BAG_SZ[k] )) items." "$K_HURT"; return
  fi
  BAGEQ[j]=-; bag_cap; INV+=("B.$k")
  logm "You take off the ${BAG_NAME[k]}. Your bags now hold $BAGS items." "$K_SYS"
}

bag_buy() {  # B.k -> 1 if there is no room for it
  local k=${1#B.}
  bag_gain "$k"
  if (( BGJ >= 0 )) && [[ ${BAGEQ[BGJ]} != [0-5] ]]; then
    BAGEQ[BGJ]=$k; bag_cap
    logm "${BAG_E[k]} You buy a ${BAG_NAME[k]} and strap it on. Your bags now hold $BAGS items!" "$K_ANN"; return 0
  fi
  (( ${#INV[@]} < BAGS )) || { logm "Your bags are full - sell something first." "$K_HURT"; return 1; }
  INV+=("$1"); NEWG[$1]=1
  logm "${BAG_E[k]} Bought a ${BAG_NAME[k]}. Swap it for a smaller bag in your inventory [i]." "$K_LOOT"
}

# --- the shared chest (a file every hero on this computer can reach) ------------------
sc_load() {
  local k v x i
  SC_ITEMS=() SC_G=0 SC_M=()
  for (( i = 0; i < NMAT; i++ )); do SC_M[i]=0; done
  [[ -r $SC_FILE ]] || return 0
  while IFS='=' read -r k v; do
    case $k in
      ITEMS) for x in $v; do valid_item "${x%!}" && SC_ITEMS+=("$x"); done ;;
      GOLD)  [[ $v =~ ^[0-9]{1,12}$ ]] && SC_G=$(( 10#$v )) ;;
      MATS)  i=0; for x in $v; do [[ $x =~ ^[0-9]{1,6}$ ]] && (( i < NMAT )) && SC_M[i]=$(( 10#$x )); i=$(( i + 1 )); done ;;
    esac
  done < "$SC_FILE"
  SC_ITEMS=("${SC_ITEMS[@]:0:SC_CAP}")
}

sc_save() {
  local IFS=$' \t\n' tmp="$SC_FILE.tmp.$$"
  mkdir -p "$DATA_DIR" 2>/dev/null
  { echo "ITEMS=${SC_ITEMS[*]}"; echo "GOLD=$SC_G"; echo "MATS=${SC_M[*]}"; } > "$tmp" 2>/dev/null && mv -f "$tmp" "$SC_FILE"
}

bk_store() {  # BK_TAB -> ST SG SM (variable names) SCAP SNAME
  if (( BK_TAB == 0 )); then ST=BANK SG=BANKG SM=BANKM SCAP=$BANKCAP SNAME=vault
  else ST=SC_ITEMS SG=SC_G SM=SC_M SCAP=$SC_CAP SNAME="shared chest"; fi
}
bk_fresh() { (( BK_TAB == 1 )) && sc_load; bk_store; }            # always work on the newest chest
bk_commit() { save_char; (( BK_TAB == 1 )) && sc_save; MAP_DIRTY=1; }

bank_open() {
  BK_NPC=$TALK_T BK_INPUT="" BK_SIDE=0 BK_CUR=(0 0) BK_TOP=(0 0)
  (( ${#BANKM[@]} )) || { local i; for (( i = 0; i < NMAT; i++ )); do BANKM[i]=0; done; }
  sc_load; UI=bank MAP_DIRTY=1
}

# --- moving things -----------------------------------------------------------------
bk_transfer() {
  local i c new=() j
  bk_fresh; local -n st=$ST
  i=${BK_CUR[BK_SIDE]}
  if (( BK_SIDE == 0 )); then
    c=${INV[i]}; [[ -n $c ]] || return
    (( ${#st[@]} < SCAP )) || { logm "The $SNAME is full ($SCAP)." "$K_HURT"; return; }
    unset "INV[i]"; INV=("${INV[@]}"); st+=("$c")
    item_name "$c" "$CLS"; logm "Stored $INAME in the $SNAME." "$K_LOOT"
  else
    c=${st[i]}; [[ -n $c ]] || return
    (( ${#INV[@]} < BAGS )) || { logm "Your bags are full ($BAGS)." "$K_HURT"; return; }
    for j in "${!st[@]}"; do (( j == i )) || new+=("${st[j]}"); done
    st=("${new[@]}"); INV+=("$c")
    item_name "$c" "$CLS"; logm "Took $INAME from the $SNAME." "$K_LOOT"
  fi
  bk_commit
}

bk_gold() {  # dep|wd amount ("" = all of it)
  local a=${2:-} have
  bk_fresh; have=${!SG}
  [[ -n $a ]] && a=$(( 10#$a ))
  if [[ $1 == dep ]]; then
    [[ -z $a ]] && a=$GOLD; (( a > GOLD )) && a=$GOLD; (( a > 0 )) || { logm "You have no gold to put in."; return; }
    GOLD=$(( GOLD - a )); printf -v "$SG" '%d' $(( have + a ))
    logm "${EMJ[gold]}Deposited $a gold. In the $SNAME: ${!SG}." "$K_LOOT"
  else
    [[ -z $a ]] && a=$have; (( a > have )) && a=$have; (( a > 0 )) || { logm "There is no gold in the $SNAME."; return; }
    GOLD=$(( GOLD + a )); printf -v "$SG" '%d' $(( have - a ))
    logm "${EMJ[gold]}Took $a gold. In the $SNAME: ${!SG}." "$K_LOOT"
  fi
  bk_commit
}

bk_mats() {  # in|out: all materials into the store or back into your bags
  local k n=0 kinds=0
  bk_fresh; local -n sm=$SM
  for (( k = 0; k < NMAT; k++ )); do
    if [[ $1 == in ]]; then
      (( MATS[k] > 0 )) || continue
      n=$(( n + MATS[k] )) kinds=$(( kinds + 1 )); sm[k]=$(( ${sm[k]:-0} + MATS[k] )); MATS[k]=0
    else
      (( ${sm[k]:-0} > 0 )) || continue
      n=$(( n + sm[k] )) kinds=$(( kinds + 1 )); MATS[k]=$(( MATS[k] + sm[k] )); sm[k]=0
    fi
  done
  (( n )) || { if [[ $1 == in ]]; then logm "You carry no materials."; else logm "No materials in the $SNAME."; fi; return; }
  if [[ $1 == in ]]; then logm "Stored $n materials ($kinds kinds) in the $SNAME." "$K_LOOT"
  else logm "Took $n materials ($kinds kinds) from the $SNAME." "$K_LOOT"; fi
  bk_commit
}

bk_lock() {
  local i=${BK_CUR[BK_SIDE]} c
  if (( BK_SIDE == 0 )); then inv_lock "b:$i"; save_char; return; fi
  bk_fresh; local -n st=$ST
  c=${st[i]}; [[ -n $c ]] || return
  if [[ $c == *! ]]; then st[i]=${c%!}; else st[i]="$c!"; fi
  item_name "$c" "$CLS"; logm "$([[ $c == *! ]] && echo Unlocked || echo Locked) $INAME." "$K_SYS"
  bk_commit
}

bk_sort() {
  if (( BK_SIDE == 0 )); then inv_sort; save_char; return; fi
  bk_fresh; sort_items "$ST"; logm "Sorted the $SNAME by ${SORT_NAME[SORT_M]}." "$K_SYS"; bk_commit
}

bk_upgrade() {
  local i cost
  (( BK_TAB == 0 )) || { logm "The shared chest always holds $SC_CAP items."; return; }
  for (( i = 0; i < 3; i++ )); do (( BANKCAP == VAULT_UP[i] )) && break; done
  (( i < 3 )) || { logm "Your vault is as big as it gets ($BANKCAP)."; return; }
  cost=${VAULT_COST[i]}
  (( GOLD >= cost )) || { logm "More vault space costs $cost gold." "$K_HURT"; return; }
  GOLD=$(( GOLD - cost )) BANKCAP=${VAULT_UP[i+1]}
  logm "${EMJ[gold]}You rent more vault space: it now holds $BANKCAP items." "$K_ANN"
  save_char
}

bk_move() {  # -1|1
  local n c
  bk_store; local -n st=$ST
  if (( BK_SIDE == 0 )); then n=${#INV[@]}; else n=${#st[@]}; fi
  c=$(( BK_CUR[BK_SIDE] + $1 )); (( c >= n )) && c=$(( n - 1 )); (( c < 0 )) && c=0
  BK_CUR[BK_SIDE]=$c
}

bank_key() {
  local k=$1
  MAP_DIRTY=1
  if [[ -n $BK_INPUT ]]; then
    case $k in
      ''|$'\r') bk_gold "$BK_INPUT" "$BK_BUF"; BK_INPUT="" ;;
      ESC) BK_INPUT="" ;;
      $'\x7f'|$'\b') BK_BUF=${BK_BUF%?} ;;
      [0-9]) (( ${#BK_BUF} < 9 )) && BK_BUF+=$k ;;
    esac
    return
  fi
  case $k in
    ESC|q) UI="" ;;
    LEFT|RIGHT|$'\t'|a|d) BK_SIDE=$(( 1 - BK_SIDE )) ;;
    UP|w) bk_move -1 ;;
    DOWN|s) bk_move 1 ;;
    1) BK_TAB=0 BK_CUR[1]=0 ;;
    2) BK_TAB=1 BK_CUR[1]=0; sc_load ;;
    ''|$'\r'|' '|e) bk_transfer ;;
    g) BK_INPUT=dep BK_BUF="" ;;
    t) BK_INPUT=wd BK_BUF="" ;;
    m) bk_mats in ;;
    n) bk_mats out ;;
    l) bk_lock ;;
    o) SORT_M=$(( (SORT_M + 1) % 3 )); bk_sort ;;
    u) bk_upgrade ;;
  esac
}

# --- drawing -----------------------------------------------------------------------
bk_row() {  # code width -> RC RP (one cell of a column; narrow columns drop the icons)
  local c=$1 w=$2 nm lk ok col TW2=$TW2
  (( w < 30 )) && TW2=0
  rb
  item_name "$c" "$CLS"; item_icon "$c" "$CLS"
  ok=0; [[ $ICLS == *"$CLS"* ]] && ok=1
  lk="  "; [[ $c == *! ]] && { lk="* "; (( TW2 )) && lk=🔒; }
  nm=$INAME; (( TW2 || w < 30 )) && nm=$INSHORT
  rt "$lk" "38;5;220"; [[ -n $II ]] && rt "$II "
  col=$ICOL; (( ok )) || col="38;5;242"
  padt "$nm" $(( w - 2 - (TW2 ? 7 : 0) - 5 )); rt "$PADS" "$col"
  ivl; [[ $IK == B ]] && IVL="+$IVAL"
  (( IVAL )) || IVL=""
  printf -v PF '%5s' "$IVL"; if (( ok )); then rt "$PF" "38;5;250"; else rt "    ✖" "38;5;203"; fi
}

ui_bank() {
  local cw H n0 n1 r i li c top lc lp rc rp bg mk side t g nm k carried=0 stored=0 ck=0 sk=0
  [[ -n ${CM_T[$TALK_MID]} ]] || { UI=""; return; }
  (( BK_TAB == 1 )) && sc_load
  bk_store; local -n st=$ST sm=$SM
  g=${!SG}
  cw=$(( (MW - 5) / 2 ))
  # title + tabs
  rb; ico 🏦; rt " $IC" "1"; rt "${N_FULL[$BK_NPC]^^}" "1;38;5;220"
  rt " · ${N_HOME[$BK_NPC]:-}" "38;5;245"; rt "   "
  for i in 0 1; do
    if (( i == 0 )); then ico 🔐; t="[1] ${IC}Vault"; else ico 👥; t="[2] ${IC}Shared chest"; fi
    if (( i == BK_TAB )); then rt " $t " "1;38;5;16;48;5;220"; else rt " $t " "38;5;250"; fi
    rt " "
  done
  dispw "$RP"; (( DW > MW )) && { rb; rt " ${N_FULL[$BK_NPC]^^}   [1] Vault  [2] Shared chest" "1;38;5;220"; }
  uix "${RC//§/}$N" "$RP"
  rb; ico 💰; rt " $IC" ; rt "carried " "38;5;245"; rt "$GOLD" "1;38;5;220"
  rt "   in the $SNAME " "38;5;245"; rt "$g" "1;38;5;220"
  if (( BK_TAB == 0 )); then rt "   - safe when you die" "38;5;242"; else rt "   - every hero on this computer" "38;5;242"; fi
  uxs
  t=${BLANK:0:MW}; uix "$K_FRAME${t// /─}$N" "$t"
  # column heads
  rb; rt " YOUR BAGS ${#INV[@]}/$BAGS" "1;38;5;220"; rpad $(( cw + 4 )); rt " ${SNAME^^} ${#st[@]}/$SCAP" "1;38;5;220"
  uix "${RC//§/}$N" "$RP"
  H=$(( VH - 10 )); (( H < 4 )) && H=4
  n0=${#INV[@]} n1=${#st[@]}
  for side in 0 1; do
    if (( side == 0 )); then n=$n0; else n=$n1; fi
    (( BK_CUR[side] >= n )) && BK_CUR[side]=$(( n - 1 )); (( BK_CUR[side] < 0 )) && BK_CUR[side]=0
    top=${BK_TOP[side]}
    (( BK_CUR[side] < top )) && top=${BK_CUR[side]}
    (( BK_CUR[side] >= top + H )) && top=$(( BK_CUR[side] - H + 1 ))
    (( top > n - H )) && top=$(( n - H )); (( top < 0 )) && top=0
    BK_TOP[side]=$top
  done
  for (( r = 0; r < H; r++ )); do
    lc="" lp="" rc="" rp=""
    for side in 0 1; do
      li=$(( BK_TOP[side] + r ))
      if (( side == 0 )); then c=${INV[li]:-}; n=$n0; else c=${st[li]:-}; n=$n1; fi
      if [[ -n $c ]]; then
        bk_row "$c" $(( cw - 2 ))
        bg="" mk="  "
        if (( li == BK_CUR[side] )); then
          if (( side == BK_SIDE )); then bg=";48;5;237"; mk=$'\e[0;1;38;5;226;48;5;237m▶ '; else mk=$'\e[0;38;5;242m› '; fi
        elif (( r == 0 && BK_TOP[side] > 0 )); then mk=$'\e[0;38;5;245m▲ '
        elif (( r == H - 1 && li < n - 1 )); then mk=$'\e[0;38;5;245m▼ '; fi
        t="$mk${RC//§/$bg}" k="  $RP"
        dispw "$k"; (( DW < cw )) && { t+=$'\e[0'"${bg}m${BLANK:0:cw-DW}"; k+=${BLANK:0:cw-DW}; }
        t+=$N
      elif (( r == 0 && li == 0 )); then
        if (( side == 0 )); then k="  (nothing in your bags)"; else k="  (empty)"; fi
        padr "$k" "$cw"; k=$PADS t="$K_SYS$k$N"
      else
        t=${BLANK:0:cw} k=$t
      fi
      if (( side == 0 )); then lc=$t lp=$k; else rc=$t rp=$k; fi
    done
    uix " $lc $K_FRAME│$N $rc" " $lp │ $rp"
  done
  t=${BLANK:0:MW}; uix "$K_FRAME${t// /─}$N" "$t"
  # what is selected
  if (( BK_SIDE == 0 )); then c=${INV[BK_CUR[0]]:-}; else c=${st[BK_CUR[1]]:-}; fi
  if [[ -n $c ]]; then
    item_name "$c" "$CLS"; item_icon "$c" "$CLS"; bonus_txt
    rb; rt " "; [[ -n $II ]] && rt "$II "; rt "$INAME" "$ICOL"
    if [[ $IK == B ]]; then rt "  bag, $IVAL slots" "38;5;250"
    else
      (( IVAL )) && { if [[ $IK == W ]]; then rt "  +$IVAL dmg" "38;5;250"; else rt "  +$IVAL armor" "38;5;250"; fi; }
      [[ -n $BTX ]] && rt "  $BTX" "38;5;117"
      cls_list "$ICLS"
      if [[ $ICLS == *"$CLS"* ]]; then rt "  ✔ ${CLT}" "38;5;120"; else rt "  ✖ only $CLT" "38;5;203"; fi
    fi
    rt "  ${ISELL}g" "38;5;220"
    uxs
  else
    ui ""
  fi
  # materials
  for (( k = 0; k < NMAT; k++ )); do
    (( MATS[k] > 0 )) && { carried=$(( carried + MATS[k] )) ck=$(( ck + 1 )); }
    (( ${sm[k]:-0} > 0 )) && { stored=$(( stored + sm[k] )) sk=$(( sk + 1 )); }
  done
  rb; ico 🧺; rt " $IC"; rt "Materials " "38;5;245"; rt "carried $carried ($ck kinds)" "38;5;252"
  rt "   in the $SNAME $stored ($sk kinds)" "38;5;252"
  uxs
  # keys
  ui "  [↑↓] select  [←→] side  [enter] move it across  [l] lock  [o] sort: ${SORT_NAME[SORT_M]}" "$K_SYS"
  if [[ -n $BK_INPUT ]]; then
    if [[ $BK_INPUT == dep ]]; then t="Deposit how much gold?"; else t="Take how much gold?"; fi
    ui "  $t > ${BK_BUF}_     (enter = all, esc = cancel)" "$K_LOOT$B"
  else
    t=""
    if (( BK_TAB == 0 )); then
      for (( i = 0; i < 3; i++ )); do (( BANKCAP == VAULT_UP[i] )) && { t="  [u] +10: ${VAULT_COST[i]}g"; break; }; done
    fi
    ui "  [g/t] gold in/out  [m/n] materials in/out$t  [esc] leave" "$K_SYS"
  fi
}
