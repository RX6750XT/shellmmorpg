# ---------------------------------------------------------------------------
#  Module 04g - v3.0 client mechanics: talents, elements and resistances,
#  status effects, champions, gems and sockets, reputation, and quests 2.0
#  (collect / deliver / scout / bounty objectives and the town questlines).
# ---------------------------------------------------------------------------

# === talents ==================================================================================
TAL=000000000000 CASTK=-1 DEAL_EL=0
tal_fix() { [[ $TAL =~ ^[0-5]{12}$ ]] || TAL=000000000000; }
TP_K=""
tal_points() {  # -> TSPENT TFREE TTREE[0..2] (cached: the panel asks every frame)
  [[ $TP_K == "$TAL.$LVL" ]] && return
  TP_K="$TAL.$LVL"
  local i r
  TSPENT=0 TTREE=(0 0 0)
  for (( i = 0; i < 12; i++ )); do r=${TAL:i:1}; TSPENT=$(( TSPENT + r )); TTREE[i/4]=$(( TTREE[i/4] + r )); done
  TFREE=$(( LVL - 1 - TSPENT )); (( TFREE < 0 )) && TFREE=0
  (( TFREE > 36 - TSPENT )) && TFREE=$(( 36 - TSPENT ))      # v4.0: level 40 has more points than talents
}
tal_can() {  # i -> 0 if a point can go there; TWHY says why not
  local i=$1 r=${TAL:$1:1}
  tal_points; TWHY=""
  if (( TFREE <= 0 )); then TWHY="no free points - you get one every level"
  elif (( r >= TL_MAX[i % 4] )); then TWHY="already mastered"
  elif (( TTREE[i / 4] - r < TL_REQ[i % 4] )); then TWHY="needs ${TL_REQ[i % 4]} points in ${TL_TREE[CLS * 3 + i / 4]}"
  fi
  [[ -z $TWHY ]]
}
tal_learn() {  # i
  tal_can "$1" || { logm "Can't learn that: $TWHY." "$K_SYS"; return 1; }
  TAL="${TAL:0:$1}$(( ${TAL:$1:1} + 1 ))${TAL:$1+1}"
  calc_stats
  logm "You learn ${TL_NAME[CLS * 12 + $1]} (rank ${TAL:$1:1})." "$K_GOOD"
}
tal_reset_cost() { TRC=$(( 30 * LVL * LVL / 4 + 50 )); }
tal_reset() {
  tal_reset_cost
  (( GOLD >= TRC )) || { TALK_LINE="Unlearning costs $TRC gold. Come back when your purse is heavier."; return; }
  GOLD=$(( GOLD - TRC )); TAL=000000000000 PARA_P="0 0 0 0 0 0"; calc_stats
  TALK_LINE="A good night's sleep and a strong drink: your talents are forgotten. ($TRC gold)"
  logm "Your talents are reset - spend your points again with [x]." "$K_GOOD"
}
tal_desc() {  # i -> TD (what one rank does)
  local fx=${TL_FX[CLS * 12 + $1]} k v
  k=${fx%%:*} v=${fx#*:}
  case $k in
    dmg) TD="+$v% damage" ;; crit) TD="+$v% critical chance" ;; cdmg) TD="+$v% critical damage" ;;
    hp) TD="+$v% max HP" ;; mp) TD="+$v% max MP" ;; arm) TD="+$v armor" ;; res) TD="+$v% all resistances" ;;
    dodge) TD="+$v% dodge" ;; block) TD="+$v% block (with a shield)" ;; regen) TD="+$v% regeneration" ;;
    ls) TD="$v% of your damage heals you" ;; melee) TD="+$v% attack damage" ;;
    sk[0-2]) TD="+$v% ${S_NAME[CLS * 3 + ${k:2}]} damage" ;; cd[0-2]) TD="-$v% ${S_NAME[CLS * 3 + ${k:2}]} cooldown" ;;
    cdall) TD="-$v% all cooldowns" ;; mpc) TD="-$v% mana cost" ;; el[0-6]) TD="+$v% ${EL_NAME[${k:2}]} damage" ;;
    dot) TD="+$v% damage over time" ;; heal) TD="+$v% healing" ;; aly) TD="+$v% ally damage" ;;
    speed) TD="+$v% move speed" ;; pot) TD="+$v% potion strength" ;; thorns) TD="$v% of melee damage reflected" ;;
    cap) TD=${CAP_DESC[$v]} ;; *) TD=$fx ;;
  esac
}
TC_K=""
tal_calc() {  # -> TB_* bonuses and CAPS from the learned talents (cached per class and talents)
  [[ $TC_K == "$CLS.$TAL.$PARA_P" ]] && return
  tal_fix; TC_K="$CLS.$TAL.$PARA_P"
  local i r fx k v
  TB_DMG=0 TB_CRIT=0 TB_CDMG=0 TB_HP=0 TB_MP=0 TB_ARM=0 TB_RES=0 TB_DODGE=0 TB_BLOCK=0 TB_REGEN=0 TB_LS=0
  TB_SK=(0 0 0) TB_CD=(0 0 0) TB_CDALL=0 TB_MPC=0 TB_MELEE=0 TB_EL=(0 0 0 0 0 0 0) TB_DOT=0 TB_HEAL=0 TB_ALY=0
  TB_SPEED=0 TB_POT=0 TB_THORNS=0 CAPS=" "
  tal_fix
  for (( i = 0; i < 12; i++ )); do
    r=${TAL:i:1}; (( r )) || continue
    fx=${TL_FX[CLS * 12 + i]}; k=${fx%%:*} v=${fx#*:}
    case $k in
      cap) CAPS+="$v " ;;
      sk[0-2]) TB_SK[${k:2}]=$(( TB_SK[${k:2}] + v * r )) ;;
      cd[0-2]) TB_CD[${k:2}]=$(( TB_CD[${k:2}] + v * r )) ;;
      el[0-6]) TB_EL[${k:2}]=$(( TB_EL[${k:2}] + v * r )) ;;
      dmg) TB_DMG=$(( TB_DMG + v * r )) ;; crit) TB_CRIT=$(( TB_CRIT + v * r )) ;; cdmg) TB_CDMG=$(( TB_CDMG + v * r )) ;;
      hp) TB_HP=$(( TB_HP + v * r )) ;; mp) TB_MP=$(( TB_MP + v * r )) ;; arm) TB_ARM=$(( TB_ARM + v * r )) ;;
      res) TB_RES=$(( TB_RES + v * r )) ;; dodge) TB_DODGE=$(( TB_DODGE + v * r )) ;; block) TB_BLOCK=$(( TB_BLOCK + v * r )) ;;
      regen) TB_REGEN=$(( TB_REGEN + v * r )) ;; ls) TB_LS=$(( TB_LS + v * r )) ;; cdall) TB_CDALL=$(( TB_CDALL + v * r )) ;;
      mpc) TB_MPC=$(( TB_MPC + v * r )) ;; melee) TB_MELEE=$(( TB_MELEE + v * r )) ;; dot) TB_DOT=$(( TB_DOT + v * r )) ;;
      heal) TB_HEAL=$(( TB_HEAL + v * r )) ;; aly) TB_ALY=$(( TB_ALY + v * r )) ;; speed) TB_SPEED=$(( TB_SPEED + v * r )) ;;
      pot) TB_POT=$(( TB_POT + v * r )) ;; thorns) TB_THORNS=$(( TB_THORNS + v * r )) ;;
    esac
  done
  has_cap pack && TB_ALY=$(( TB_ALY + 50 ))
  has_cap evasion && TB_DODGE=$(( TB_DODGE + 10 ))
  has_cap thorns && TB_THORNS=$(( TB_THORNS + 30 ))
  has_cap lifelink && TB_LS=$(( TB_LS + 8 ))
  para_bonus                                                     # v4.5: paragon points
  TB_DMG=$(( TB_DMG + PB_DMG )) TB_HP=$(( TB_HP + PB_HP )) TB_CRIT=$(( TB_CRIT + PB_CRIT ))
  TB_RES=$(( TB_RES + PB_RES )) TB_MP=$(( TB_MP + PB_MP )) TB_CDALL=$(( TB_CDALL + PB_CD ))
}
has_cap() { [[ $CAPS == *" $1 "* ]]; }

# === gems and sockets ===============================================================================
sock_info() {  # code -> SN sockets, SF filled, SGEMS "r1 s2 __"
  local g=${1%!} i
  g=${g#*.*.*.*.}; [[ $g == "${1%!}" || $1 == U.* || $1 == B.* ]] && g=""
  SN=$(( ${#g} / 2 )) SF=0 SGEMS=""
  for (( i = 0; i < SN; i++ )); do SGEMS+="${g:i*2:2} "; [[ ${g:i*2:1} != _ ]] && SF=$(( SF + 1 )); done
}
gem_of() {  # "r2" -> GK (kind index) GQ (grade) GV (value) GFXK (effect)
  local i
  GK=-1 GQ=${1:1:1} GV=0 GFXK=""
  for (( i = 0; i < 6; i++ )); do [[ ${GEM_L[i]} == "${1:0:1}" ]] && GK=$i; done
  (( GK >= 0 )) || return 1
  local v=(${GEM_V[GK]}); GV=${v[GQ-1]} GFXK=${GEM_FX[GK]}
}
gems_txt() {  # code -> GTX: the sockets as icons (empty: ◇)
  local s
  sock_info "$1"; GTX=""
  for s in $SGEMS; do if [[ $s == __ ]]; then GTX+="◇"; else gem_of "$s"; GTX+=${GEM_E[GK]}; fi; done
}
gems_plain() {  # code -> GPL: "+6% dmg, +4 crit" for item cards
  local s
  sock_info "$1"; GPL=""
  for s in $SGEMS; do
    [[ $s == __ ]] && continue
    gem_of "$s"
    case $GFXK in dmg) GPL+="+$GV% dmg, " ;; mp) GPL+="+$GV% MP, " ;; crit) GPL+="+$GV% crit, " ;;
      arm) GPL+="+$GV armor, " ;; hp) GPL+="+$GV% HP, " ;; res) GPL+="+$GV% resist, " ;; esac
  done
  GPL=${GPL%, }
}
gem_bonus() {  # gear worn -> G_DMG G_MP G_CRIT G_ARM G_HP G_RES
  local c s
  G_DMG=0 G_MP=0 G_CRIT=0 G_ARM=0 G_HP=0 G_RES=0
  for c in "$EQW" "$EQA" "$EQO" "$EQH" "$EQJ"; do
    [[ $c == *.*.*.*.* ]] || continue
    item_stats "$c"; [[ $ICLS == *"$CLS"* ]] || continue
    sock_info "$c"
    for s in $SGEMS; do
      [[ $s == __ ]] && continue
      gem_of "$s" || continue
      case $GFXK in dmg) G_DMG=$(( G_DMG + GV )) ;; mp) G_MP=$(( G_MP + GV )) ;; crit) G_CRIT=$(( G_CRIT + GV )) ;;
        arm) G_ARM=$(( G_ARM + GV )) ;; hp) G_HP=$(( G_HP + GV )) ;; res) G_RES=$(( G_RES + GV )) ;; esac
    done
  done
}
sock_set() {  # code index gem|__ -> CODE2: the code with that socket changed
  local c=${1%!} lock="" g pre
  [[ $1 == *! ]] && lock="!"
  g=${c#*.*.*.*.}; pre=${c%".$g"}
  g="${g:0:$2*2}$3${g:$2*2+2}"
  CODE2="$pre.$g$lock"
}
sock_add() {  # code -> CODE2 with one more empty socket
  local c=${1%!} lock=""
  [[ $1 == *! ]] && lock="!"
  if [[ $c == *.*.*.*.* ]]; then CODE2="$c""__$lock"; else CODE2="$c.__$lock"; fi
}
sock_cost() {  # code -> SKC gold for the next socket (0 = not possible)
  item_stats "$1"; sock_info "$1"; SKC=0
  [[ -n $IUQ || $IK == B ]] && return
  (( SN < SOCK_MAX[IRR] )) || return
  SKC=$(( (IT * IT * 40 + 200) * (SN + 1) ))
}

# === elements, damage and status effects ==========================================================
mname() {  # mid -> MN: "Vampiric Wolf" for champions
  local t=${CM_T[$1]}
  [[ -n $t ]] || { MN="Something"; return; }                     # (a monster this client does not know about yet)
  MN=${N_FULL[$t]:-${M_NAME[t]}}
  (( ${CM_CH[$1]:-0} )) && MN="${CHP_NAME[CM_CH[$1]-1]} $MN"
}
el_mult() {  # monster-type element -> EM (% damage the monster takes)
  EM=100
  (( M_WK[$1] == $2 )) && EM=150
  (( M_RS[$1] == $2 )) && EM=50
}
# PS_UNTIL[i] for poisoned bleeding burning chilled stunned weakened; PS_DMG[i] per tick
PS_UNTIL=(0 0 0 0 0 0) PS_DMG=(0 0 0 0 0 0) PS_IMM=0 LS_READY=0 BARRIER=0 BARRIER_T=0 EVPROC=0 FRENZY=0 FRENZY_T=0 SMH=0
declare -A FROZEN=()
pst_apply() {  # effect source-dmg
  local i r=$(( RES / 2 ))
  case $1 in poison) i=0 ;; bleed) i=1 ;; burn) i=2 ;; chill) i=3 ;; stun) i=4 ;; weaken) i=5 ;; *) return ;; esac
  (( RANDOM % 100 < r )) && { logm "You shrug off being ${PS_NAME[i]}." "$K_GOOD"; return; }
  case $i in
    0) PS_UNTIL[0]=$(( NOW + 5000 )) PS_DMG[0]=$(( $2 * 22 / 100 + 1 )) ;;
    1) PS_UNTIL[1]=$(( NOW + 4000 )) PS_DMG[1]=$(( $2 * 28 / 100 + 1 )) ;;
    2) PS_UNTIL[2]=$(( NOW + 3000 )) PS_DMG[2]=$(( $2 * 35 / 100 + 1 )) ;;
    3) PS_UNTIL[3]=$(( NOW + 3000 )) ;;
    4) (( NOW < PS_IMM )) && return
       PS_UNTIL[4]=$(( NOW + 1200 )) PS_IMM=$(( NOW + 7000 )) ;;
    5) PS_UNTIL[5]=$(( NOW + 6000 )) ;;
  esac
  (( i < 3 )) && PS_DMG[i]=$(( PS_DMG[i] * (100 - RES) / 100 + 1 ))
  logm "You are ${PS_NAME[i]}!" "$K_HURT"
}
pst_tick() {  # once a second: damage over time on me
  local i d=0
  for i in 0 1 2; do (( NOW < PS_UNTIL[i] )) && d=$(( d + PS_DMG[i] )); done
  (( d )) || return
  HP=$(( HP - d )); POS_DIRTY=1 MAP_DIRTY=1
  ft_add "$PX" "$PY" "-$d" $'\e[0;38;5;141;48;5;234m'
  (( HP <= 0 )) && die_now "your wounds"
}
pst_clear() {  # [all|poison] cure
  if [[ $1 == all ]]; then PS_UNTIL=(0 0 0 0 0 0); else PS_UNTIL[0]=0 PS_UNTIL[1]=0; fi
}
stunned() { (( NOW < PS_UNTIL[4] )) && { (( NOW - ${STUN_MSG:-0} > 700 )) && { logm "You are stunned!" "$K_HURT"; STUN_MSG=$NOW; }; return 0; }; return 1; }
die_now() {  # killer: shared by blows and damage over time
  (( DEAD )) && return
  (( ADM_GOD )) && { HP=$MAXHP; return; }                  # v6.4: admin god mode
  if has_cap laststand && (( NOW >= LS_READY )); then
    HP=1 LS_READY=$(( NOW + 90000 )) immune_until=$(( NOW + 3000 ))
    logm "LAST STAND! You refuse to fall." "$K_GOOD"; return
  fi
  HP=0 DEAD=1 dead_until=$(( NOW + 5000 )); DEATHS=$(( DEATHS + 1 )) UI=""
  PS_UNTIL=(0 0 0 0 0 0)
  local lost=$(( GOLD / 10 )); GOLD=$(( GOLD - lost ))
  logm "${EMJ[death]}You were slain by $1! You lose $lost gold. Respawning in town..." "$K_HURT"
  send EVT "$MY_ID" "$MY_NAME" "was slain by $1."
  MAP_DIRTY=1
}
v3_tick() {  # once a second
  pst_tick
  if has_cap barrier && (( NOW >= BARRIER_T )); then BARRIER=$(( MAXHP * 15 / 100 )) BARRIER_T=$(( NOW + 20000 )); fi
  if has_cap aura || has_cap deathaura; then
    local m el=5; has_cap deathaura && el=4
    mons_within 1
    for m in "${MLIST[@]}"; do DEAL_EL=$el; deal "$m" 15 0 q; done; DEAL_EL=0
  fi
  [[ $CUR_MAP == W ]] && ql_explore
  chain_npcs
}

# === reputation ==================================================================================
REP=(0 0 0 0 0 0 0 0)
rep_fix() { local i; for (( i = 0; i < NFAC; i++ )); do [[ ${REP[i]} =~ ^-?[0-9]+$ ]] || REP[i]=0; done; }   # v4.0: eight factions
rep_rank() {  # faction -> RR (-1 unfriendly, 0 neutral ... 4 exalted)
  local v=${REP[$1]} i
  RR=0; (( v < 0 )) && { RR=-1; return; }
  for i in 1 2 3 4; do (( v >= REP_RANK[i] )) && RR=$i; done
}
rep_add() {  # faction amount
  local f=$1 a=$2 old
  [[ $f =~ ^[0-9]$ ]] && (( f < NFAC )) || return
  rep_rank "$f"; old=$RR
  REP[f]=$(( REP[f] + a )); (( REP[f] < -6000 )) && REP[f]=-6000; (( REP[f] > 21000 )) && REP[f]=21000
  local fe=""; (( TW2 )) && fe="${FAC_E[f]} "
  if (( a >= 0 )); then logm "$fe${FAC_NAME[f]}: +$a reputation" $'\e['"${FAC_COL[f]}m"
  else logm "$fe${FAC_NAME[f]}: $a reputation" "$K_HURT"; fi
  rep_rank "$f"
  if (( RR > old )); then logm "${fe}You are now ${REP_NAME[RR]} with the ${FAC_NAME[f]}!" "$K_ANN"
  elif (( RR < old )); then logm "${fe}The ${FAC_NAME[f]} think less of you." "$K_HURT"; fi
}
fac_at() {  # x y -> FA (faction of that place)
  region_of "$1" "$2"
  FA=${TOWN_FAC[$RNAME]:-${REGION_FAC[$RNAME]:-}}
  [[ -n $FA ]] && return
  case $RNAME in
    "Greenfield Meadows"|Whisperwood|Silverlake) FA=0 ;; "Mirefen Swamp"|"Stormcrag Foothills"|"Stormcrag Peaks"|"Ashen Wastes") FA=1 ;;
    "Saltwind Coast"|"Sunscorch Desert"|"Scorched Badlands") FA=2 ;; "Frostfang Tundra"|"Crystal Highlands") FA=3 ;;
    "Sapphire Isles"|"Emerald Jungle") FA=4 ;; *) FA=5 ;;
  esac
}
fac_of_npc() { [[ -n $1 ]] || { FA=-1; return; }; local h=${N_HOME[$1]:-${MW_NAME[$1]}}; FA=${TOWN_FAC[$h]:--1}; }   # npc type -> FA
rep_disc() {  # npc type -> DISC (% off in its shop)
  DISC=0; fac_of_npc "$1"; (( FA >= 0 )) || return
  rep_rank "$FA"; DISC=$(( RR * 5 ))
}

# === quests 2.0 ===================================================================================
qobj_parse() {  # "K.5.6" -> OT OA ON
  local r=${1#*.}
  OT=${1%%.*} OA=${r%%.*} ON=1; [[ $r == *.* ]] && ON=${r#*.}
}
qitem() { QIN=${QI_NAME[$1]:-${M_NAME[$1]} Trophy}; }       # monster type -> QIN
obj_text() {  # type target need have -> OTX (what to do) OWX OWY (where)
  local t=$1 a=$2 n=$3 h=$4
  OWX="" OWY=""
  case $t in
    K) OTX="Slay $n ${M_NAME[a]}s ($h/$n)" OWX=${MW_X[a]} OWY=${MW_Y[a]} ;;
    C) qitem "$a"; OTX="Collect $n ${QIN}s from ${M_NAME[a]}s ($h/$n)" OWX=${MW_X[a]} OWY=${MW_Y[a]} ;;
    B) OTX="Bounty: slay ${M_NAME[a]}" OWX=${MW_X[a]} OWY=${MW_Y[a]} ;;
    G) OTX="Bring $n ${MAT_NAME[a]} (${MATS[a]}/$n)" ;;
    E) OTX="Scout ${SPT_NAME[a]}" OWX=${SPT_X[a]} OWY=${SPT_Y[a]} ;;
    D) OTX="Clear the ${D_NAME[a]}" OWX=${D_ENTX[a]} OWY=${D_ENTY[a]} ;;
    T) OTX="Talk to ${N_FULL[$a]}" OWX=${MW_X[a]} OWY=${MW_Y[a]} ;;
  esac
}

# --- questlines: QLS one char per line (0 not started, 1-9 the step you are on, x done),
#     QLP progress per line, QLC the choices you made (- none, a, b)
QLS="" QLP=() QLC=""
ql_fix() {
  local i
  [[ $QLS =~ ^[0-9x]{$NQL}$ ]] || QLS=$(printf '%*s' "$NQL" '' | tr ' ' 0)
  [[ $QLC =~ ^[-ab]{$NQL}$ ]] || QLC=$(printf '%*s' "$NQL" '' | tr ' ' -)
  for (( i = 0; i < NQL; i++ )); do [[ ${QLP[i]} =~ ^[0-9]{1,4}$ ]] || QLP[i]=0; done
}
ql_step() {  # line -> QST (step index into QS_*, -1 if none active) QSI (1-based step)
  local c=${QLS:$1:1}
  QST=-1 QSI=0
  [[ $c == [1-9] ]] || return 1
  QSI=$c QST=$(( QL_S0[$1] + c - 1 ))
}
ql_ready() {  # line -> 0 if the active objective is done (talk to the turn-in person)
  ql_step "$1" || return 1
  qobj_parse "${QS_OBJ[QST]}"
  case $OT in
    G) (( MATS[OA] >= ON )) ;;
    T) return 1 ;;
    *) (( QLP[$1] >= ON )) ;;
  esac
}
ql_turnin_npc() {  # line -> QTN: who takes the active step
  ql_step "$1"; qobj_parse "${QS_OBJ[QST]}"
  QTN=${QL_NPC[$1]}; [[ $OT == T ]] && QTN=$OA
}
ql_reward_lvl() { QRL=$(( QL_LVL[$1] + QSI )); QRX=$(( (30 * QRL * QRL + 70 * QRL) * 18 / 100 )) QRG=$(( 20 * QRL + 40 )); }
ql_start() {  # line: begin with step 1
  QLS="${QLS:0:$1}1${QLS:$1+1}"; QLP[$1]=0
  ql_step "$1"; qobj_parse "${QS_OBJ[QST]}"; obj_text "$OT" "$OA" "$ON" 0
  logm "${EMJ[quest]}NEW QUESTLINE: ${QL_NAME[$1]} - $OTX" "$K_ANN"
  TALK_LINE=${QS_TXT[QST]}
}
ql_complete() {  # line: finish the active step (rewards), then a choice or the next step
  local l=$1
  ql_step "$l"; qobj_parse "${QS_OBJ[QST]}"
  [[ $OT == G ]] && MATS[OA]=$(( MATS[OA] - ON ))
  ql_reward_lvl "$l"
  logm "${EMJ[quest]}${QL_NAME[l]} ($QSI/${QL_N[l]}) COMPLETE - +$QRX XP +$QRG gold" "$K_ANN"
  TALK_LINE=${QS_DONE[QST]}
  GOLD=$(( GOLD + QRG )); gain_xp "$QRX"
  rep_add "${QL_FAC[l]}" "${QS_REP[QST]}"
  if [[ -n ${QS_CH[QST]} ]]; then QCH_L=$l UI=qchoice MAP_DIRTY=1; return; fi
  ql_next "$l"
}
ql_choose() {  # a|b
  local l=$QCH_L i=0 opt rew txt r
  [[ $1 == b ]] && i=1
  ql_step "$l"
  IFS='|' read -r -a opt <<< "${QS_CHR[QST]}"; rew=${opt[i]}
  IFS='|' read -r -a opt <<< "${QS_CHT[QST]}"; txt=${opt[i]}
  QLC="${QLC:0:$l}$1${QLC:$l+1}"
  logm "$txt" "$K_CHAT"
  for r in ${rew//,/ }; do grant "$r"; done
  UI=talk TALK_LINE=$txt
  [[ -n ${CM_T[$TALK_MID]} ]] || UI=""
  ql_next "$l"
}
grant() {  # one reward: rep:f:n gold:n gem:n pot:n epic:S uq:n
  local a=(${1//:/ }) i g
  case ${a[0]} in
    rep)  rep_add "${a[1]}" "${a[2]}" ;;
    gold) GOLD=$(( GOLD + a[1] )); logm "+${a[1]} gold" "$K_LOOT" ;;
    pot)  POT_H=$(( POT_H + a[1] )); logm "+${a[1]} health potions" "$K_LOOT" ;;
    gem)  for (( i = 0; i < a[1]; i++ )); do g=1; (( LVL >= 12 )) && g=2; (( LVL >= 22 )) && g=3; gem_mat $(( RANDOM % 6 )) "$g"; gem_get "$GM"; done ;;
    epic) epic_item "${a[1]}" 2 1; add_item "$ITEM" ;;
    uq)   valid_item "U.${a[1]}" && add_item "U.${a[1]}" ;;
  esac
}
epic_item() {  # slot rarity sockets [tier] -> ITEM: gear of your class at your level
  local s=$1 t=$4 k=0 i cls n
  [[ -n $t ]] || { tier_for "$LVL"; t=$TF; }
  case $s in W) n=${#WK_NAME[@]} ;; A) n=${#AK_NAME[@]} ;; O) n=${#OK_NAME[@]} ;; H) n=${#HK_NAME[@]} ;; *) n=${#JK_NAME[@]} ;; esac
  for (( i = 0; i < 40; i++ )); do
    k=$(( RANDOM % n ))
    case $s in W) cls=${WK_CLS[k]} ;; A) cls=${AK_CLS[k]} ;; O) cls=${OK_CLS[k]} ;; H) cls=${HK_CLS[k]} ;; *) cls=${JK_CLS[k]} ;; esac
    [[ $cls == *"$CLS"* ]] && break
  done
  ITEM="$s.$k.$t.$2"
  (( $3 > 0 )) && { ITEM+="."; for (( i = 0; i < $3; i++ )); do ITEM+="__"; done; }
}
gem_get() {  # material index: a gem goes into your materials
  MATS[$1]=$(( MATS[$1] + 1 )); MAT_NEW[$1]=$(( ${MAT_NEW[$1]:-0} + 1 ))
  mat_icon "$1"
  logm "${EMJ[loot]}Gem: $MI${MI:+ }${MAT_NAME[$1]} - set it into a socket at any smith" $'\e[1;38;5;213m'
}
ql_next() {  # line: move on to the next step (or finish the line)
  local l=$1 s
  s=$(( ${QLS:$l:1} + 1 ))
  if (( s > QL_N[l] )); then
    QLS="${QLS:0:$l}x${QLS:$l+1}"
    logm "${EMJ[quest]}QUESTLINE COMPLETE: ${QL_NAME[l]}!" "$K_ANN"
    send EVT "$MY_ID" "$MY_NAME" "completed the questline ${QL_NAME[l]}."
    return
  fi
  QLS="${QLS:0:$l}$s${QLS:$l+1}"; QLP[l]=0
  ql_step "$l"; qobj_parse "${QS_OBJ[QST]}"; obj_text "$OT" "$OA" "$ON" 0
  logm "${EMJ[quest]}${QL_NAME[l]} ($s/${QL_N[l]}): $OTX" "$K_LOOT"
  [[ $UI == qchoice ]] || TALK_LINE="${TALK_LINE} ${QS_TXT[QST]}"
}
ql_for_npc() {  # npc type -> QLN: the line this person gives (-1 none)
  local i
  QLN=-1; for (( i = 0; i < NQL; i++ )); do (( QL_NPC[i] == $1 )) && { QLN=$i; return 0; }; done
  return 1
}
chain_npc() { [[ $CHN == *" $1 "* ]]; }       # npc type -> questline business here (see chain_npcs)
ql_talk() {  # npc type: questline business when you talk to someone (T objectives complete here)
  local i
  for (( i = 0; i < NQL; i++ )); do
    ql_step "$i" || continue
    [[ ${QS_OBJ[QST]} == "T.$1" ]] && { ql_complete "$i"; return 0; }
  done
  return 1
}
ql_key() {  # [5] in a conversation with a questline giver
  local l
  ql_for_npc "$TALK_T" || return
  l=$QLN
  case ${QLS:l:1} in
    x) TALK_LINE="You have done more for us than anyone. Thank you, friend." ;;
    0) if (( LVL >= QL_LVL[l] )); then ql_start "$l"; else TALK_LINE="I may have work for you one day - come back at level ${QL_LVL[l]}."; fi ;;
    *) if ql_ready "$l"; then ql_complete "$l"
       else
         ql_step "$l"; qobj_parse "${QS_OBJ[QST]}"; obj_text "$OT" "$OA" "$ON" "${QLP[l]}"
         TALK_LINE="${QS_TXT[QST]} ($OTX)"
         [[ $OT == T ]] && TALK_LINE="Have you spoken to ${N_FULL[$OA]} yet?"
       fi ;;
  esac
}
ql_explore() {  # scouting objectives: are we there yet?
  local i q f
  for (( i = 0; i < NQL; i++ )); do
    ql_step "$i" || continue
    [[ ${QS_OBJ[QST]} == E.* ]] || continue
    (( QLP[i] )) && continue
    qobj_parse "${QS_OBJ[QST]}"
    cheb $(( SPT_X[OA] - PX )) $(( SPT_Y[OA] - PY )); (( D <= 3 )) || continue
    QLP[i]=1; logm "${EMJ[quest]}You found ${SPT_NAME[OA]}. Return to ${N_FULL[${QL_NPC[i]}]}." "$K_ANN"
  done
  for i in "${!QUESTS[@]}"; do
    q=${QUESTS[i]}; [[ $q == E.* ]] || continue
    IFS=. read -r -a f <<< "$q"
    cheb $(( SPT_X[f[1]] - PX )) $(( SPT_Y[f[1]] - PY )); (( D <= 3 )) || continue
    quest_done "$i"; return
  done
}
qev_kill() {  # monster type: kills, drops and bounties for quests and questlines
  local t=$1 i f q done=() n
  for (( i = 0; i < NQL; i++ )); do
    ql_step "$i" || continue
    qobj_parse "${QS_OBJ[QST]}"
    [[ $OA == "$t" && $OT == [KCB] ]] || continue
    (( QLP[i] >= ON )) && continue
    if [[ $OT == C ]] && (( RANDOM % 100 >= (M_BOSS[t] ? 100 : 50) )); then continue; fi
    QLP[i]=$(( QLP[i] + 1 ))
    if [[ $OT == C ]]; then qitem "$t"; logm "${EMJ[loot]}Quest item: $QIN (${QLP[i]}/$ON)" "$K_LOOT"; fi
    (( QLP[i] >= ON )) && logm "${EMJ[quest]}${QL_NAME[i]}: done - return to ${N_FULL[${QL_NPC[i]}]}." "$K_ANN"
  done
  for i in "${!QUESTS[@]}"; do
    IFS=. read -r -a f <<< "${QUESTS[i]}"
    [[ ${f[1]} == "$t" && ${f[0]} == [CB] ]] || continue
    if [[ ${f[0]} == C ]]; then
      (( RANDOM % 100 < (M_BOSS[t] ? 100 : 45) )) || continue
      qitem "$t"; f[3]=$(( f[3] + 1 )); logm "${EMJ[loot]}Quest item: $QIN (${f[3]}/${f[2]})" "$K_LOOT"
    else f[3]=1; fi
    QUESTS[i]="${f[0]}.${f[1]}.${f[2]}.${f[3]}.${f[4]}.${f[5]}"
    (( f[3] >= f[2] )) && done=("$i" "${done[@]}")
  done
  for i in "${done[@]}"; do quest_done "$i"; done
}
qev_dungeon() {  # dungeon type cleared
  local i
  for (( i = 0; i < NQL; i++ )); do
    ql_step "$i" || continue
    [[ ${QS_OBJ[QST]} == "D.$1" ]] || continue
    QLP[i]=1; logm "${EMJ[quest]}${QL_NAME[i]}: done - return to ${N_FULL[${QL_NPC[i]}]}." "$K_ANN"
  done
}
qev_board() {  # at a quest board: hand in materials for delivery quests
  local i f done=()
  for i in "${!QUESTS[@]}"; do
    [[ ${QUESTS[i]} == G.* ]] || continue
    IFS=. read -r -a f <<< "${QUESTS[i]}"
    (( MATS[f[1]] >= f[2] )) || continue
    MATS[f[1]]=$(( MATS[f[1]] - f[2] )); done=("$i" "${done[@]}")
  done
  for i in "${done[@]}"; do quest_done "$i"; done
}
quest_rep() {  # quest code: the faction of the place it helps gets reputation
  local f x="" y=""
  IFS=. read -r -a f <<< "$1"
  case ${f[0]} in
    K|C|B) x=${MW_X[f[1]]} y=${MW_Y[f[1]]} ;;
    D) x=${D_ENTX[f[1]]} y=${D_ENTY[f[1]]} ;;
    E) x=${SPT_X[f[1]]} y=${SPT_Y[f[1]]} ;;
    T) fac_of_npc "${f[1]}"; (( FA >= 0 )) && rep_add "$FA" $(( 60 + LVL * 8 )); return ;;
    G) x=$PX y=$PY ;;
  esac
  [[ -n $x ]] || return
  fac_at "$x" "$y"; rep_add "$FA" $(( 60 + LVL * 8 ))
}

# === faction quartermasters =========================================================================
wares_build() {  # npc type -> WR_* (what the faction sells), WR_F
  local f t
  fac_of_npc "$1"; WR_F=$FA
  WR_NAME=() WR_RANK=() WR_PRICE=() WR_CODE=()
  (( WR_F >= 0 )) || return
  tier_for "$LVL"; f=$WR_F t=$TF
  WR_NAME+=("Gem pouch (2 gems for your level)") WR_RANK+=(1) WR_PRICE+=($(( 300 + 40 * LVL ))) WR_CODE+=(gems)
  WR_NAME+=("${FAC_NAME[f]} armor (epic, 2 sockets)") WR_RANK+=(2) WR_PRICE+=($(( 2000 + 160 * LVL ))) WR_CODE+=(A)
  WR_NAME+=("${FAC_NAME[f]} weapon (epic, 1 socket)") WR_RANK+=(2) WR_PRICE+=($(( 2400 + 180 * LVL ))) WR_CODE+=(W)
  WR_NAME+=("${U_NAME[FAC_UQ0 + f]} (unique)") WR_RANK+=(3) WR_PRICE+=(12000) WR_CODE+=("U.$(( FAC_UQ0 + f ))")
  WR_NAME+=("Champion's weapon (legendary, 3 sockets)") WR_RANK+=(4) WR_PRICE+=(25000) WR_CODE+=(LW)
}
wares_buy() {  # index
  local i=$1
  wares_build "$TALK_T"
  (( i < ${#WR_NAME[@]} )) || return
  rep_rank "$WR_F"
  (( RR >= WR_RANK[i] )) || { logm "The ${FAC_NAME[WR_F]} only sell that to those they call ${REP_NAME[WR_RANK[i]]}." "$K_HURT"; return; }
  (( GOLD >= WR_PRICE[i] )) || { logm "Not enough gold." "$K_HURT"; return; }
  if [[ ${WR_CODE[i]} != gems ]] && (( ${#INV[@]} >= BAGS )); then logm "Your bags are full." "$K_HURT"; return; fi
  GOLD=$(( GOLD - WR_PRICE[i] ))
  case ${WR_CODE[i]} in
    gems) grant gem:2 ;;
    A) epic_item A 2 2; add_item "$ITEM" ;;
    W) epic_item W 2 1; add_item "$ITEM" ;;
    LW) epic_item W 3 3 9; add_item "$ITEM" ;;
    *) add_item "${WR_CODE[i]}" ;;
  esac
}
