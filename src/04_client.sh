# ---------------------------------------------------------------------------
#  Module 04 - client: character (save/load), combat, skills, items, NPCs,
#  shops, quests, parties and the handlers for everything the network sends
# ---------------------------------------------------------------------------
declare -A OP_NAME=() OP_MAP=() OP_X=() OP_Y=() OP_CLS=() OP_LVL=() OP_HP=() OP_MAX=() OP_DEAD=() OP_SEEN=()
declare -A OP_MNT=() OP_SYM=() OP_COL=() OP_SAY=() OP_SAYT=() OP_WANTED=() CM_POS=() EXPL=() ATK_NPC=() GLY=()
CM_T=() CM_X=() CM_Y=() CM_HP=() CM_MAX=()
LOG_T=() LOG_C=() CHL_T=() CHL_C=() FX_X=() FX_Y=() FX_K=() FX_E=() INV=() QUESTS=() OFFERS=() PQ_CODES=()
PARTY_IDS=() SKCD=(0 0 0) DOT_M=() DOT_D=() DOT_N=() DOT_T=()
printf -v MY_ID '%06x' $(( ((RANDOM << 15) | RANDOM) & 0xffffff ))
CUR_MAP=W CUR_DT=-1 PX=$SPAWN_X PY=$SPAWN_Y FDX=0 FDY=1 DEAD=0 TARGET="" MY_PARTY="" PARTY_LEADER=""
next_move=0 next_attack=0 buff_until=0 anthem_until=0 str_until=0 iron_until=0 swift_until=0 immune_until=0
last_hurt=0 dead_until=0 clear_until=0 dreq_until=0 home_ready=0 last_pos=0 WANTED_UNTIL=0 MY_SAYT=0 MY_SAY=""
POS_DIRTY=1 MAP_DIRTY=1 NEED_FULL=1 UI="" SHOP="" CHATTING=0 CHAT_BUF="" WX=$SPAWN_X WY=$SPAWN_Y TAGS_ON=1
LRX=12 LRY=6 OFFER_LVL=0 LASTDMG=0 QSRC=board OFFER_SRC="" EXPW="" SEEN="" WAYS="" LAST_CHUNK=-1 WM_Z=0 WM_X=0 WM_Y=0
ARW=(↑ ↗ → ↘ ↓ ↙ ← ↖)

# colors
N=$'\e[0m' B=$'\e[1m' DIM=$'\e[2m'
K_SYS=$'\e[38;5;245m' K_CHAT=$'\e[38;5;255m' K_PARTY=$'\e[38;5;84m' K_WHISP=$'\e[38;5;213m'
K_HIT=$'\e[38;5;223m' K_HURT=$'\e[38;5;203m' K_LOOT=$'\e[38;5;220m' K_ANN=$'\e[1;38;5;214m' K_GOOD=$'\e[38;5;120m'
K_FRAME=$'\e[38;5;240m' K_NPC=$'\e[38;5;117m'

# terrain palette (every tile resets attributes so backgrounds never bleed)
Z_DOT=$'\e[0;38;5;22m.' Z_COM=$'\e[0;38;5;28m,' Z_TG=$'\e[0;38;5;64m"' Z_FLW=$'\e[0;38;5;211m*'
Z_TREE=$'\e[0;38;5;35mT' Z_WAT=$'\e[0;38;5;45;48;5;18m~' Z_MTN=$'\e[0;38;5;250m^' Z_ROAD=$'\e[0;38;5;137m.'
Z_BRG=$'\e[0;38;5;130m=' Z_SWP=$'\e[0;38;5;100m%' Z_ENT=$'\e[0;1;38;5;196m>' Z_EXT=$'\e[0;1;38;5;201m<'
Z_QST=$'\e[0;1;38;5;226m!' Z_FTN=$'\e[0;1;38;5;51mo' Z_FIRE=$'\e[0;1;38;5;202m*' Z_MEM=$'\e[0;38;5;237m'
Z_SAND=$'\e[0;38;5;180m.' Z_DUNE=$'\e[0;38;5;179m,' Z_CACT=$'\e[0;38;5;71mY' Z_SNOW=$'\e[0;38;5;255m.'
Z_DRIFT=$'\e[0;38;5;252m,' Z_PINE=$'\e[0;38;5;30mT' Z_ICE=$'\e[0;38;5;195;48;5;31m.' Z_ASH=$'\e[0;38;5;242m.'
Z_LAVA=$'\e[0;1;38;5;214;48;5;124m~' Z_ROCK=$'\e[0;38;5;238m^' Z_WAY=$'\e[0;1;38;5;201m&' Z_FOG=$'\e[0;38;5;238m' COMP_DIM=0
Z_CRYF=$'\e[0;38;5;183m.' Z_CRYS=$'\e[0;1;38;5;141m^' Z_JUNG=$'\e[0;38;5;34m,' Z_JTREE=$'\e[0;1;38;5;40mT'
Z_BAD=$'\e[0;38;5;166m.' Z_MESA=$'\e[0;38;5;130m^' Z_VOIDF=$'\e[0;38;5;97m.' Z_CHASM=$'\e[0;38;5;201;48;5;53m~'   # v2.0 lands
Z_AUT=$'\e[0;38;5;172m.' Z_ATREE=$'\e[0;1;38;5;166mT' Z_MYC=$'\e[0;38;5;139m,' Z_SHROOM=$'\e[0;1;38;5;170mT'          # v4.0 lands
Z_HGT=$'\e[0;38;5;109m.' Z_CRAG=$'\e[0;1;38;5;67m^' Z_BONE=$'\e[0;38;5;187m.'
set_palette() {  # dungeon type, -1 for the open world, -2 for a room at the inn (v5.0)
  Z_EXT=$'\e[0;1;38;5;201m<' Z2_EXT=$'\e[0;48;5;53m🌀'
  if (( $1 == -2 )); then
    Z_WALL=$'\e[0;38;5;137m#' Z_FLR=$'\e[0;38;5;94m.' Z_EXT=$'\e[0;1;38;5;180m<'
    Z2_WALL=$'\e[0;48;5;58m🟫' Z2_FLR=$'\e[0;48;5;94m  ' Z2_EXT=$'\e[0;48;5;94m🚪'
  elif (( $1 < 0 )); then
    Z_WALL=$'\e[0;38;5;244m#' Z_FLR=$'\e[0;38;5;239m.'
    Z2_WALL=$'\e[0;48;5;94m🧱' Z2_FLR=$'\e[0;48;5;102m  '
  else
    Z_WALL=$'\e[0;'"${D_WALL[$1]}m#" Z_FLR=$'\e[0;'"${D_FLOOR[$1]}m."
    Z2_WALL=$'\e[0;48;5;235m'"${D_WE[$1]:-🧱}" Z2_FLR=$'\e[0;'"${D_FLOOR[$1]/38;5/48;5}m  "
    Z2_z=$'\e[0;'"${D_FLOOR[$1]/38;5/48;5}m🦴"
  fi
  Z_FURN=$Z_FLR Z2_FURN=$Z2_FLR                  # "+": furniture stands here (rooms only), drawn on top
  declare -F tbg_build >/dev/null && tbg_build
  declare -F tiles_init >/dev/null && tiles_init
}
set_palette -1

colorize1() {   # CZ in place (classic ASCII, 1 column per tile)
  CZ=${CZ//'.'/$Z_DOT};  CZ=${CZ//','/$Z_COM};  CZ=${CZ//'"'/$Z_TG};   CZ=${CZ//'*'/$Z_FLW}
  CZ=${CZ//'T'/$Z_TREE}; CZ=${CZ//'~'/$Z_WAT};  CZ=${CZ//'^'/$Z_MTN};  CZ=${CZ//'#'/$Z_WALL}
  CZ=${CZ//'_'/$Z_FLR};  CZ=${CZ//':'/$Z_ROAD}; CZ=${CZ//'='/$Z_BRG};  CZ=${CZ//'%'/$Z_SWP}
  CZ=${CZ//'>'/$Z_ENT};  CZ=${CZ//'<'/$Z_EXT};  CZ=${CZ//'Q'/$Z_QST};  CZ=${CZ//'O'/$Z_FTN}
  CZ=${CZ//'F'/$Z_FIRE}
  CZ=${CZ//'S'/$Z_SAND}; CZ=${CZ//'s'/$Z_DUNE}; CZ=${CZ//'Y'/$Z_CACT}; CZ=${CZ//'N'/$Z_SNOW}
  CZ=${CZ//'n'/$Z_DRIFT}; CZ=${CZ//'P'/$Z_PINE}; CZ=${CZ//'I'/$Z_ICE};  CZ=${CZ//'A'/$Z_ASH}
  CZ=${CZ//'L'/$Z_LAVA}; CZ=${CZ//'R'/$Z_ROCK}; CZ=${CZ//'Z'/$Z_WAY}
  CZ=${CZ//K/$Z_CRYF}; CZ=${CZ//C/$Z_CRYS}; CZ=${CZ//J/$Z_JUNG}; CZ=${CZ//W/$Z_JTREE}
  CZ=${CZ//D/$Z_BAD}; CZ=${CZ//V/$Z_MESA}; CZ=${CZ//E/$Z_VOIDF}; CZ=${CZ//G/$Z_CHASM}
  CZ=${CZ//q/$Z_AUT}; CZ=${CZ//y/$Z_ATREE}; CZ=${CZ//M/$Z_MYC}; CZ=${CZ//U/$Z_SHROOM}
  CZ=${CZ//H/$Z_HGT}; CZ=${CZ//X/$Z_CRAG}; CZ=${CZ//B/$Z_BONE}; CZ=${CZ//'+'/$Z_FURN}
}

# glyphs for everything that moves (spliced between colorized terrain segments)
for (( t = 0; t < NM; t++ )); do GLY[m$t]=$'\e[0;'"${M_COL[t]}m${M_GLY[t]}"; done
declare -A FXG=([fire]=$'\e[0;1;38;5;202m*' [frost]=$'\e[0;1;38;5;117m*' [holy]=$'\e[0;1;38;5;228m+'
                [slash]=$'\e[0;1;38;5;231mx' [poison]=$'\e[0;1;38;5;118m%' [bone]=$'\e[0;1;38;5;255m/'
                [sound]=$'\e[0;1;38;5;213m~')
for k in "${!FXG[@]}"; do GLY[f$k]=${FXG[$k]}; done

LSPAN=()
for (( dy = -LRY; dy <= LRY; dy++ )); do isqrt $(( LRX * LRX * (LRY * LRY - dy * dy) / (LRY * LRY) )); LSPAN[dy+LRY]=$R; done

logm() {  # v7.1: with the time and a sequence number (the chat log [c] shows both, in order); 400 kept
  local tm; printf -v tm '%(%H:%M)T' -1
  LSEQ=$(( LSEQ + 1 ))
  LOG_T+=("$1"); LOG_C+=("${2:-$K_SYS}"); LOG_TM+=("$tm"); LOG_S+=("$LSEQ")
  if (( ${#LOG_T[@]} > 400 )); then LOG_T=("${LOG_T[@]:100}"); LOG_C=("${LOG_C[@]:100}"); LOG_TM=("${LOG_TM[@]:100}"); LOG_S=("${LOG_S[@]:100}"); fi
}
chatm() {
  local tm; printf -v tm '%(%H:%M)T' -1
  LSEQ=$(( LSEQ + 1 ))
  CHL_T+=("$1"); CHL_C+=("${2:-$K_CHAT}"); CHL_TM+=("$tm"); CHL_S+=("$LSEQ")
  if (( ${#CHL_T[@]} > 400 )); then CHL_T=("${CHL_T[@]:100}"); CHL_C=("${CHL_C[@]:100}"); CHL_TM=("${CHL_TM[@]:100}"); CHL_S=("${CHL_S[@]:100}"); fi
}

valid_sym() {  # single printable ASCII char, not the protocol separator
  local c
  [[ ${#1} == 1 ]] || return 1
  printf -v c '%d' "'$1"
  (( c >= 33 && c <= 126 && c != 124 ))
}

player_glyph() {  # id sym col dead   (HD: class sprite on the player's own color)
  if [[ $4 == 1 ]]; then GLY[p$1]=$'\e[0;38;5;240m'"$2" GLYH[p$1]=$'\e[0;48;5;238m💀'
  else GLY[p$1]=$'\e[0;1;38;5;'"${P_COLC[$3]}m$2" GLYH[p$1]=$'\e[0;48;5;'"${P_COLC[$3]}m"
    if [[ -n ${OP_MNT[$1]} ]]; then GLYH[p$1]+=${MNT_E[${OP_MNT[$1]}]}; else GLYH[p$1]+=${CEMO[${OP_CLS[$1]:-0}]}; fi; fi
}

# --- character ---------------------------------------------------------------
CHAR_VARS=(CLS LVL XP GOLD HP MP POT_H POT_M POT_GH POT_GM EL_STR EL_IRON EL_SWIFT SCROLL BREW EQW EQA EQO EQH EQJ WX WY KILLS DEATHS COLR
           MEAL1 MEAL2 TON_FROST TON_FIRE TON_VEIL BANKG BANKCAP STORY STORY_P STORY_SEEN ALLYN ALLIES)
CHAR_FILE="$DATA_DIR/$MY_NAME.char"

migrate_gear() {  # pre-1.6 saves: W.t.r / A.t.r become the class' own weapon and armor kind
  local i c p
  up() { local IFS=.; p=($1); if (( ${#p[@]} == 3 )); then if [[ ${p[0]} == W ]]; then c="W.${DEFW[CLS]}.${p[1]}.${p[2]}"; else c="A.${DEFA[CLS]}.${p[1]}.${p[2]}"; fi; else c=$1; fi; }
  [[ -n $EQW ]] && { up "$EQW"; EQW=$c; }
  [[ -n $EQA ]] && { up "$EQA"; EQA=$c; }
  for i in "${!INV[@]}"; do up "${INV[i]}"; INV[i]=$c; done
}

calc_stats() {  # base stats of the class + everything worn (gear your class can't use does nothing) + talents + gems
  local w=0 a=0 c shield=0
  B_CRIT=0 B_HP=0 B_MP=0 B_ARM=0 B_DMG=0 B_LIGHT=0
  for c in "$EQW" "$EQA" "$EQO" "$EQH" "$EQJ"; do
    [[ -n $c ]] || continue
    item_stats "$c"; [[ $ICLS == *"$CLS"* ]] || continue
    if [[ $IK == W ]]; then w=$IVAL; else a=$(( a + IVAL )); fi
    case $IBT in
      crit) B_CRIT=$(( B_CRIT + IBV )) ;; hp) B_HP=$(( B_HP + IBV )) ;; mp) B_MP=$(( B_MP + IBV )) ;;
      arm) B_ARM=$(( B_ARM + IBV )) ;; dmg) B_DMG=$(( B_DMG + IBV )) ;; light) B_LIGHT=$(( B_LIGHT + IBV )) ;;
    esac
  done
  tal_calc; gem_bonus
  B_HP=$(( B_HP + TB_HP + G_HP )) B_MP=$(( B_MP + TB_MP + G_MP )) B_CRIT=$(( B_CRIT + TB_CRIT + G_CRIT ))
  B_DMG=$(( B_DMG + TB_DMG + G_DMG )) B_ARM=$(( B_ARM + TB_ARM + G_ARM ))
  [[ $EQO == O.0.* ]] && { item_stats "$EQO"; [[ $ICLS == *"$CLS"* ]] && shield=1; }
  RES=$(( TB_RES + G_RES )); (( RES > 60 )) && RES=60
  DODGE=$(( 3 + TB_DODGE )); (( DODGE > 35 )) && DODGE=35
  BLOCK=0; (( shield )) && BLOCK=$(( 10 + TB_BLOCK ))
  CDMG=$(( 200 + TB_CDMG ))
  MAXHP=$(( (C_HP0[CLS] + C_HPL[CLS] * LVL) * (100 + B_HP) / 100 ))
  MAXMP=$(( (C_MP0[CLS] + C_MPL[CLS] * LVL) * (100 + B_MP) / 100 ))
  ATK=$(( (w + 4 + LVL * 2) * C_DMG[CLS] / 100 * (100 + B_DMG) / 100 ))
  ARMOR=$(( a + B_ARM + C_ARM[CLS] + LVL / 2 ))
  CRIT=$(( 10 + B_CRIT )); (( CRIT > 75 )) && CRIT=75
  XPNEXT=$(( 30 * LVL * LVL + 70 * LVL ))
  (( LVL >= MAXLVL )) && { para_next "$PARA"; XPNEXT=$PNX; }   # v4.5: paragon
  (( HP > MAXHP )) && HP=$MAXHP; (( MP > MAXMP )) && MP=$MAXMP
}

new_char() {
  CLS=$1 LVL=1 XP=0 GOLD=25 POT_H=3 POT_M=2 POT_GH=0 POT_GM=0 EL_STR=0 EL_IRON=0 EL_SWIFT=0 SCROLL=0 BREW=0
  EQW="W.${DEFW[CLS]}.1.0" EQA="A.${DEFA[CLS]}.1.0" EQO="" EQH="" EQJ="" KILLS=0 DEATHS=0 WX=$SPAWN_X WY=$SPAWN_Y
  STORY=0 STORY_P=0 STORY_SEEN=0 ALLYN=0 ALLIES="" ALLY=-1; aly_fix
  TAL=000000000000 QLS="" QLP=() QLC="" REP=(); rep_fix; ql_fix; v45_reset
  INV=() QUESTS=() BAGS=10 BAGEQ=(- - -) BANK=() BANKG=0 BANKCAP=30 MEAL1=1 MEAL2=0 TON_FROST=0 TON_FIRE=0 TON_VEIL=0 PROF_LV=(1 1 1) PROF_XP=(0 0 0); mats_zero
  calc_stats; HP=$MAXHP MP=$MAXMP
}

char_text() {   # the hero as save text (what is stored: a file in tests, on the server in the game)
  local k
  echo "version=2"
  for k in "${CHAR_VARS[@]}"; do echo "$k=${!k}"; done
  echo "SYM=$SYM"
  echo "EXPW=$EXPW"
  echo "SEEN=$SEEN"
  echo "WAYS=$WAYS"
  echo "INV=${INV[*]}"
  echo "BAGEQ=${BAGEQ[*]}"
  echo "BANK=${BANK[*]}"
  echo "BANKM=${BANKM[*]}"
  echo "QUESTS=${QUESTS[*]}"
  echo "PROF=${PROF_LV[0]} ${PROF_XP[0]} ${PROF_LV[1]} ${PROF_XP[1]} ${PROF_LV[2]} ${PROF_XP[2]}"
  echo "MATS=${MATS[*]}"
  echo "TAL=$TAL"
  echo "QLS=$QLS"
  echo "QLP=${QLP[*]}"
  echo "QLC=$QLC"
  echo "REP=${REP[*]}"
  v45_save
  if (( CHAR_REMOTE )); then echo "SCI=${SC_ITEMS[*]}"; echo "SCG=$SC_G"; echo "SCM=${SC_M[*]}"; fi
}

save_char() {
  local tmp="$CHAR_FILE.tmp" IFS=$' \t\n' text   # traps can fire inside "IFS= read" - never join with empty IFS
  [[ -n $CLS ]] || return
  if [[ $CUR_MAP == W ]]; then WX=$PX WY=$PY; fi
  ALLYN=$(( ALLY + 1 ))
  if (( CHAR_REMOTE )); then                                # v6.2: heroes live on the server
    if (( net_up )); then text=$(char_text); acct_send_save "$text" && SAVE_LOST=0 || SAVE_LOST=1; else SAVE_LOST=1; fi
    return
  fi
  char_text > "$tmp" 2>/dev/null && mv -f "$tmp" "$CHAR_FILE"
}

load_char() {
  local k v x ok=0 text
  if (( CHAR_REMOTE )); then text=$CHAR_TEXT; [[ -n $text ]] || return 1
  else [[ -r $CHAR_FILE ]] || return 1; text=$(<"$CHAR_FILE"); fi
  SC_ITEMS=() SC_G=0 SC_M=(); for (( x = 0; x < NMAT; x++ )); do SC_M[x]=0; done
  CLS="" EQW="" EQA="" EQO="" EQH="" EQJ="" INV=() QUESTS=() SYM="@" COLR="" EXPW="" SEEN="" WAYS=""
  POT_GH=0 POT_GM=0 EL_STR=0 EL_IRON=0 EL_SWIFT=0 SCROLL=0 BREW=0 BAGS=10 BAGEQ=(- - -) BANK=() BANKG=0 BANKCAP=30
  BANKM=(); for (( x = 0; x < NMAT; x++ )); do BANKM[x]=0; done
  local bageq=""
  STORY=0 STORY_P=0 STORY_SEEN=0 ALLYN=0 ALLIES="" ALLY=-1 TAL=000000000000 QLS="" QLP=() QLC="" REP=(); v45_reset
  MEAL1=0 MEAL2=0 TON_FROST=0 TON_FIRE=0 TON_VEIL=0 PROF_LV=(1 1 1) PROF_XP=(0 0 0); mats_zero
  while IFS='=' read -r k v; do
    case $k in
      version) ok=1 ;;
      SYM)    valid_sym "$v" && SYM=$v ;;
      EXPW|SEEN|WAYS) [[ $v =~ ^[01]{1,2000}$ ]] && printf -v "$k" '%s' "$v" ;;
      ALLIES) [[ $v =~ ^[01]{1,16}$ ]] && ALLIES=$v ;;
      EQW|EQA|EQO|EQH|EQJ) { valid_item "${v%!}" || [[ $v =~ ^[WA]\.[1-7]\.[0-3]$ ]]; } && printf -v "$k" '%s' "$v" ;;
      INV)    for x in $v; do { valid_item "${x%!}" || [[ $x =~ ^[WA]\.[1-7]\.[0-3]$ ]]; } && INV+=("$x"); done ;;
      BAGEQ)  bageq=$v ;;
      BANK)   for x in $v; do valid_item "${x%!}" && BANK+=("$x"); done ;;
      BANKM)  x=0; for k in $v; do [[ $k =~ ^[0-9]{1,6}$ ]] && (( x < NMAT )) && BANKM[x]=$(( 10#$k )); x=$(( x + 1 )); done ;;
      QUESTS) for x in $v; do [[ $x =~ ^[KDTCGEB](\.(0|[1-9][0-9]{0,8})){5}$ ]] && QUESTS+=("$x"); done ;;
      TAL)    [[ $v =~ ^[0-5]{12}$ ]] && TAL=$v ;;
      QLS)    [[ $v =~ ^[0-9x]{1,64}$ ]] && QLS=$v ;;
      QLC)    [[ $v =~ ^[-ab]{1,64}$ ]] && QLC=$v ;;
      QLP)    x=0; for k in $v; do [[ $k =~ ^[0-9]{1,4}$ ]] && QLP[x]=$(( 10#$k )); x=$(( x + 1 )); done ;;
      REP)    x=0; for k in $v; do [[ $k =~ ^-?[0-9]{1,5}$ ]] && (( x < NFAC )) && { if [[ $k == -* ]]; then REP[x]=$(( -10#${k#-} )); else REP[x]=$(( 10#$k )); fi; }; x=$(( x + 1 )); done ;;
      PROF)   if [[ $v =~ ^([0-9]{1,2})\ ([0-9]{1,4})\ ([0-9]{1,2})\ ([0-9]{1,4})\ ([0-9]{1,2})\ ([0-9]{1,4})$ ]]; then
                for x in 0 1 2; do
                  PROF_LV[x]=$(( 10#${BASH_REMATCH[x * 2 + 1]} )) PROF_XP[x]=$(( 10#${BASH_REMATCH[x * 2 + 2]} ))
                  (( PROF_LV[x] >= 1 && PROF_LV[x] <= PROF_MAX )) || PROF_LV[x]=1
                done
              fi ;;
      MATS)   x=0; for k in $v; do [[ $k =~ ^[0-9]{1,5}$ ]] && (( x < NMAT )) && MATS[x]=$(( 10#$k )); x=$(( x + 1 )); done ;;
      CLS|LVL|XP|GOLD|HP|MP|POT_H|POT_M|POT_GH|POT_GM|EL_STR|EL_IRON|EL_SWIFT|SCROLL|BREW|WX|WY|KILLS|DEATHS|COLR|MEAL1|MEAL2|TON_FROST|TON_FIRE|TON_VEIL|BAGS|BANKG|BANKCAP|STORY|STORY_P|STORY_SEEN|ALLYN)
        [[ $v =~ ^[0-9]{1,12}$ ]] && printf -v "$k" '%d' "$(( 10#$v ))" ;;
      SCI)    SC_ITEMS=(); for x in $v; do valid_item "${x%!}" && SC_ITEMS+=("$x"); done; SC_ITEMS=("${SC_ITEMS[@]:0:SC_CAP}") ;;
      SCG)    [[ $v =~ ^[0-9]{1,12}$ ]] && SC_G=$(( 10#$v )) ;;
      SCM)    x=0; for k in $v; do [[ $k =~ ^[0-9]{1,6}$ ]] && (( x < NMAT )) && SC_M[x]=$(( 10#$k )); x=$(( x + 1 )); done ;;
      *) v45_load_kv "$k" "$v" ;;
    esac
  done <<< "$text"
  (( ok )) && [[ $CLS =~ ^[0-9]$ ]] && (( CLS < NCLS )) || return 1
  (( LVL >= 1 && LVL <= 50 )) || LVL=1
  if [[ -z $COLR ]] || (( COLR >= ${#P_COLC[@]} )); then name_color "$MY_NAME"; COLR=$NCI; fi
  if [[ -n $bageq ]]; then           # v1.8 bag slots
    BAGEQ=($bageq); BAGEQ=("${BAGEQ[@]:0:3}")
    for x in 0 1 2; do [[ ${BAGEQ[x]} == [0-5] ]] || BAGEQ[x]=-; done
  elif (( BAGS == 15 )); then BAGEQ=(2 - -)   # v1.7 backpack upgrades become real bags
  elif (( BAGS == 20 )); then BAGEQ=(3 - -); fi
  bag_cap
  aly_fix; (( STORY <= NST )) || STORY=$NST; ALLY=$(( ALLYN - 1 )); { (( ALLY >= 0 )) && aly_has "$ALLY"; } || ALLY=-1
  (( BANKCAP == 30 || BANKCAP == 40 || BANKCAP == 50 || BANKCAP == 60 )) || BANKCAP=30
  INV=("${INV[@]:0:BAGS}") QUESTS=("${QUESTS[@]:0:3}") BANK=("${BANK[@]:0:BANKCAP}")
  migrate_gear
  QLS=${QLS:0:NQL}; while (( ${#QLS} < NQL )); do QLS+="0"; done        # questlines added later start fresh
  QLC=${QLC:0:NQL}; while (( ${#QLC} < NQL )); do QLC+=-; done
  rep_fix; ql_fix; v45_fix
  calc_stats
  (( HP < 1 )) && HP=$MAXHP
  return 0
}

gain_xp() {
  XP=$(( XP + $1 ))
  while (( XP >= XPNEXT && LVL < MAXLVL )); do
    XP=$(( XP - XPNEXT )); LVL=$(( LVL + 1 )); calc_stats; HP=$MAXHP MP=$MAXMP
    logm "${EMJ[lvl]}*** LEVEL UP! You are now level $LVL. ***" "$K_ANN"
    ft_add "$PX" $(( PY - 2 )) "LEVEL UP!" $'\e[0;1;5;38;5;16;48;5;220m' 
    send EVT "$MY_ID" "$MY_NAME" "reached level $LVL!"
    story_levelup
    save_char
  done
  (( LVL >= MAXLVL )) && para_xp
}

add_item() {  # code
  item_name "$1" "$CLS"
  if (( ${#INV[@]} >= BAGS )) && [[ -z $IUQ && $IK != C ]]; then   # a unique (or a collectable) is too precious to auto-sell: it squeezes in
    GOLD=$(( GOLD + ISELL ))
    logm "Bags full - auto-sold $INAME for ${ISELL}g" "$K_LOOT"
  else
    INV+=("$1"); NEWG[$1]=1
    if [[ -n $IUQ ]]; then
      item_icon "$1" "$CLS"; bonus_txt
      logm "${EMJ[loot]}UNIQUE LOOT: $II${II:+ }$INAME (${IVAL:++$IVAL }$BTX) - there is only one of these!" $'\e['"${ICOL}m"
      send EVT "$MY_ID" "$MY_NAME" "found the unique $INAME!"
      return
    fi
    if [[ $IK == B ]]; then
      item_icon "$1" "$CLS"
      logm "${EMJ[loot]}Loot: $II${II:+ }$INAME - a bag with $IVAL slots! Put it on in [i]." $'\e['"${ICOL}m"
      return
    fi
    if [[ $IK == C ]]; then
      item_icon "$1" "$CLS"; col_mark "$IKD"
      logm "${EMJ[loot]}Collectable: $II${II:+ }$INAME (${CS_NAME[${CL_SET[IKD]}]})" $'\e['"${ICOL}m"
      return
    fi
    local lab=dmg nv=$IVAL nm=$INAME col=$ICOL up="" ok=1 cl=$ICLS; [[ $IK != W ]] && lab=armor
    bonus_txt; local bt=$BTX
    [[ $cl == *"$CLS"* ]] || ok=0
    eq_of "$IK"; local cur=$EQC
    if (( ! ok )); then cls_list "$cl"; up="  (for $CLT)"
    elif [[ -z $cur ]]; then up="  - NEW SLOT! equip it with [i]"
    else item_stats "$cur"; (( nv > IVAL )) && up="  - UPGRADE! equip it with [i]"; fi
    (( nv )) || { lab=""; nv=""; }
    item_icon "$1" "$CLS"
    logm "${EMJ[loot]}Loot: $II${II:+ }$nm (${nv:++$nv $lab }$bt)$up" $'\e['"${col}m"
  fi
}

reward() {  # xp gold item mtype
  local i f done=() xp=$1
  (( NOW < REST_UNTIL )) && xp=$(( xp * (100 + REST_PCT) / 100 ))      # v5.0: Well Rested
  gain_xp "$xp"; GOLD=$(( GOLD + $2 )); KILLS=$(( KILLS + 1 ))
  logm "${EMJ[xp]}+$xp XP  ${EMJ[gold]}+$2 gold" "$K_GOOD"
  ft_add "$PX" $(( PY - 1 )) "+${xp}xp" $'\e[0;1;38;5;220;48;5;234m'
  case $3 in
    H) POT_H=$(( POT_H + 1 )); ci h; logm "${EMJ[loot]}Loot: ${CI}Health Potion" "$K_LOOT" ;;
    M) POT_M=$(( POT_M + 1 )); ci m; logm "${EMJ[loot]}Loot: ${CI}Mana Potion" "$K_LOOT" ;;
    *.*.*.*|B.[0-5]|U.*) valid_item "$3" && add_item "$3" ;;
  esac
  (( M_KIND[$4] == 4 )) && logm "${EMJ[loot]}You open the treasure chest!" "$K_ANN"
  story_event K "$4"
  qev_kill "$4"
  if has_cap onkill; then heal_self $(( MAXHP * 6 / 100 )); MP=$(( MP + MAXMP * 4 / 100 )); (( MP > MAXMP )) && MP=$MAXMP; fi
  has_cap frenzy && { (( FRENZY < 3 )) && FRENZY=$(( FRENZY + 1 )); FRENZY_T=$(( NOW + 6000 )); }
  for i in "${!QUESTS[@]}"; do
    IFS=. read -r -a f <<< "${QUESTS[i]}"
    [[ ${f[0]} == K && ${f[1]} == "$4" ]] || continue
    f[3]=$(( f[3] + 1 ))
    QUESTS[i]="${f[0]}.${f[1]}.${f[2]}.${f[3]}.${f[4]}.${f[5]}"
    (( f[3] >= f[2] )) && done=("$i" "${done[@]}")
  done
  for i in "${done[@]}"; do quest_done "$i"; done
}

init_where() {  # where each monster / NPC lives -> MW_NAME MW_X MW_Y
  local z a t d p
  MW_NAME=() MW_X=() MW_Y=() ZR=()
  for z in "${ZONES[@]}"; do
    a=($z); t=${a[0]}
    ZR[t]+="${a[1]} ${a[2]} ${a[3]} ${a[4]} "                       # v3.0: zone rectangles per monster type
    [[ -n ${MW_NAME[t]} ]] && continue
    MW_X[t]=$(( (a[1] + a[3]) / 2 )) MW_Y[t]=$(( (a[2] + a[4]) / 2 ))
    region_of "${MW_X[t]}" "${MW_Y[t]}" nosafe; MW_NAME[t]=$RNAME
  done
  for (( d = 0; d < NDT; d++ )); do
    for t in ${D_POOL[d]} ${D_BOSS[d]} ${D_ELITE[d]}; do
      [[ -n ${MW_NAME[t]} ]] && continue
      MW_NAME[t]="${D_NAME[d]}" MW_X[t]=${D_ENTX[d]} MW_Y[t]=${D_ENTY[d]}
    done
  done
  for p in "${NPC_SPAWNS[@]}"; do
    a=($p); t=${a[0]}; [[ -n ${MW_NAME[t]} ]] && continue
    region_of "${a[1]}" "${a[2]}"; MW_NAME[t]=$RNAME MW_X[t]=${a[1]} MW_Y[t]=${a[2]}
  done
  for p in "${!WB_LIST[@]}"; do
    t=${WB_LIST[p]} a=(${WB_RECT[p]})
    MW_X[t]=$(( (a[0] + a[2]) / 2 )) MW_Y[t]=$(( (a[1] + a[3]) / 2 ))
    region_of "${MW_X[t]}" "${MW_Y[t]}" nosafe; MW_NAME[t]="$RNAME (world boss)"
  done
}

quest_info() {  # code -> QTXT QSHORT QGLY QWHERE QTX QTY
  local f=(${1//./ }) a i best=999999 d2 cx cy
  QTX="" QTY=""
  case ${f[0]} in
    K) QTXT="Slay ${f[2]} ${M_NAME[f[1]]}s (${f[3]}/${f[2]})" QSHORT="${M_NAME[f[1]]}s ${f[3]}/${f[2]}"
       QGLY="${GLYP[m${f[1]}]}$N" QWHERE=${MW_NAME[f[1]]:-somewhere} QTX=${MW_X[f[1]]} QTY=${MW_Y[f[1]]}
       a=(${ZR[f[1]]})                                                 # nearest zone of that monster (or the one I'm in)
       for (( i = 0; i < ${#a[@]}; i += 4 )); do
         if (( PX >= a[i] && PX <= a[i+2] && PY >= a[i+1] && PY <= a[i+3] )) && [[ $CUR_MAP == W ]]; then QTX=$PX QTY=$PY; break; fi
         cx=$(( (a[i] + a[i+2]) / 2 )) cy=$(( (a[i+1] + a[i+3]) / 2 )) d2=$(( (cx - PX) * (cx - PX) + (cy - PY) * (cy - PY) ))
         (( d2 < best )) && { best=$d2; QTX=$cx QTY=$cy; }
       done ;;
    D) QTXT="Clear the ${D_NAME[f[1]]}" QSHORT="Clear ${D_NAME[f[1]]}" QGLY="$Z_ENT$N"; (( TW2 )) && QGLY=🚪
       QWHERE=${D_WHERE[f[1]]} QTX=${D_ENTX[f[1]]} QTY=${D_ENTY[f[1]]} ;;
    T) QTXT="Bring a letter to ${N_FULL[${f[1]}]}" QSHORT="Letter for ${M_NAME[f[1]]}" QGLY="${GLYP[m${f[1]}]}$N"
       QWHERE=${N_HOME[${f[1]}]:-${MW_NAME[f[1]]}} QTX=${MW_X[f[1]]} QTY=${MW_Y[f[1]]} ;;
    C) qitem "${f[1]}"; QTXT="Collect ${f[2]} ${QIN}s from ${M_NAME[f[1]]}s (${f[3]}/${f[2]})" QSHORT="${QIN}s ${f[3]}/${f[2]}"
       QGLY="${GLYP[m${f[1]}]}$N" QWHERE=${MW_NAME[f[1]]:-somewhere} QTX=${MW_X[f[1]]} QTY=${MW_Y[f[1]]} ;;
    B) QTXT="Bounty: slay ${M_NAME[f[1]]}" QSHORT="Bounty: ${M_NAME[f[1]]}" QGLY="${GLYP[m${f[1]}]}$N"
       QWHERE=${MW_NAME[f[1]]:-somewhere} QTX=${MW_X[f[1]]} QTY=${MW_Y[f[1]]} ;;
    E) QTXT="Scout ${SPT_NAME[f[1]]}" QSHORT="Scout ${SPT_NAME[f[1]]#the }" QGLY="${K_LOOT}x$N"; (( TW2 )) && QGLY=🧭
       region_of "${SPT_X[f[1]]}" "${SPT_Y[f[1]]}" nosafe; QWHERE=$RNAME QTX=${SPT_X[f[1]]} QTY=${SPT_Y[f[1]]} ;;
    G) QTXT="Deliver ${f[2]} ${MAT_NAME[f[1]]} to a quest board (${MATS[f[1]]}/${f[2]})" QSHORT="${MAT_NAME[f[1]]} ${MATS[f[1]]}/${f[2]}"
       mat_icon "${f[1]}"; QGLY=${MI:-$K_LOOT*$N}; QWHERE="any quest board" ;;
  esac
}
quest_text() { quest_info "$1"; }

track() {  # QTX QTY -> TRK: arrow + distance from me (empty inside dungeons)
  local dx dy ax ay ar
  TRK=""
  [[ $CUR_MAP == W && -n $QTX ]] || return
  dx=$(( QTX - PX )) dy=$(( QTY - PY )); ax=${dx#-} ay=${dy#-}
  if (( ax <= 3 && ay <= 3 )); then TRK="here"; return; fi
  if (( ax > 2 * ay )); then ar=$(( dx > 0 ? 2 : 6 ))
  elif (( ay > 2 * ax )); then ar=$(( dy > 0 ? 4 : 0 ))
  elif (( dx > 0 )); then ar=$(( dy > 0 ? 3 : 1 ))
  else ar=$(( dy > 0 ? 5 : 7 )); fi
  cheb "$dx" "$dy"; TRK="${ARW[ar]} ${D}m"
}

con_col() {  # level -> CC (grey/green/yellow/orange/red relative to you)
  local d=$(( $1 - LVL ))
  if (( d <= -5 )); then CC=$'\e[38;5;245m'; elif (( d <= -2 )); then CC=$'\e[38;5;120m'
  elif (( d <= 1 )); then CC=$'\e[38;5;227m'; elif (( d <= 3 )); then CC=$'\e[38;5;214m'; else CC=$'\e[38;5;196m'; fi
}

turnin_for() {  # npc type -> 0 if one of my (party) quests wants a letter delivered there
  local q
  for q in "${QUESTS[@]}" "${PQ_CODES[@]}"; do [[ $q == "T.$1."* ]] && return 0; done
  return 1
}

explore_here() {  # fog of war on the world map + waystone attunement
  [[ $CUR_MAP == W ]] || return
  local cx=$(( PX / 8 )) cy=$(( PY / 8 )) c i j k w a
  for w in "${!WAYSTONES[@]}"; do
    [[ ${WAYS:w:1} == 1 ]] && continue
    a=(${WAYSTONES[w]}); cheb $(( a[1] - PX )) $(( a[2] - PY ))
    if (( D <= 3 )); then
      WAYS="${WAYS:0:w}1${WAYS:w+1}"
      logm "Waystone attuned: ${a[0]//_/ }. Touch any waystone (&) to travel here." "$K_GOOD"
    fi
  done
  c=$(( cy * NCHX + cx )); (( c == LAST_CHUNK )) && return; LAST_CHUNK=$c
  for (( j = cy - 1; j <= cy + 1; j++ )); do for (( i = cx - 1; i <= cx + 1; i++ )); do
    (( i >= 0 && j >= 0 && i < NCHX && j < NCHY )) || continue
    k=$(( j * NCHX + i )); [[ ${EXPW:k:1} == 1 ]] || EXPW="${EXPW:0:k}1${EXPW:k+1}"
  done; done
}

init_explore() {
  local z
  NCHX=$(( (MAPW[W] + 7) / 8 )) NCHY=$(( (MAPH[W] + 7) / 8 ))
  printf -v z '%*s' $(( NCHX * NCHY )) ''; z=${z// /0}
  local ow=0 oh=0                                            # the map grew: keep what was explored
  (( ${#EXPW} == 390 && NCHX * NCHY != 390 )) && ow=30 oh=13   # v2.0: 240x100 -> 360x150
  (( ${#EXPW} == 855 && NCHX * NCHY != 855 )) && ow=45 oh=19   # v4.0: 360x150 -> 480x200
  (( ${#EXPW} == 1500 && NCHX * NCHY != 1500 )) && ow=60 oh=25  # v8.0: 480x200 -> 600x200
  if (( ow )); then
    local i j old=$EXPW; EXPW=$z
    for (( j = 0; j < oh; j++ )); do for (( i = 0; i < ow; i++ )); do
      [[ ${old:j*ow+i:1} == 1 ]] && EXPW="${EXPW:0:j*NCHX+i}1${EXPW:j*NCHX+i+1}"
    done; done
  fi
  (( ${#EXPW} == NCHX * NCHY )) || EXPW=$z
  printf -v z '%*s' "$NM" ''; z=${z// /0}
  (( ${#SEEN} < NM )) && SEEN+=${z:${#SEEN}}          # new creatures: keep what was already discovered
  SEEN=${SEEN:0:NM}
  printf -v z '%*s' "${#WAYSTONES[@]}" ''; z=${z// /0}
  (( ${#WAYS} < ${#WAYSTONES[@]} )) && WAYS+=${z:${#WAYS}}
  WAYS=${WAYS:0:${#WAYSTONES[@]}}
}

way_travel() {  # index
  local i=$1 a cost
  (( i >= 0 && i < ${#WAYSTONES[@]} )) && [[ ${WAYS:i:1} == 1 ]] || return
  cost=$(( 10 + LVL * 3 ))
  (( GOLD >= cost )) || { logm "Travel costs $cost gold." "$K_HURT"; return; }
  a=(${WAYSTONES[i]})
  GOLD=$(( GOLD - cost ))
  PX=${a[1]} PY=$(( a[2] + 1 ))
  p_walk W "$PX" "$PY" || { PX=$(( a[1] + 1 )) PY=${a[2]}; }
  p_walk W "$PX" "$PY" || { PX=$(( a[1] - 1 )) PY=${a[2]}; }
  UI="" POS_DIRTY=1 MAP_DIRTY=1
  logm "The waystone hums - you arrive at ${a[0]//_/ } (-${cost}g)." "$K_GOOD"
  explore_here
}

quest_done() {
  local f; IFS=. read -r -a f <<< "${QUESTS[$1]}"
  quest_text "${QUESTS[$1]}"
  logm "${EMJ[quest]}QUEST COMPLETE: ${QTXT%% (*} - +${f[4]} XP +${f[5]} gold" "$K_ANN"
  unset "QUESTS[$1]"; QUESTS=("${QUESTS[@]}")
  GOLD=$(( GOLD + f[5] )); gain_xp "${f[4]}"
  quest_rep "${f[0]}.${f[1]}"
}

gen_offers() {  # QSRC = board or the NPC type of a quest giver
  local cand=() t i need dt=-1 d tgt=""
  OFFERS=() OFFER_LVL=$LVL OFFER_SRC=$QSRC
  if [[ $QSRC == board ]]; then
    for t in "${WORLD_TYPES[@]}"; do (( M_LVL[t] >= LVL - 2 && M_LVL[t] <= LVL + 2 )) && cand+=("$t"); done
    (( ${#cand[@]} )) || cand=(43)
    for d in 0 1 2; do (( LVL >= D_REQ[d] )) && dt=$d; done
    if (( LVL < 6 )); then tgt=25; elif (( LVL < 10 )); then tgt=26; else tgt=46; fi
  else
    cand=(${N_QK[$QSRC]}); dt=${N_QD[$QSRC]:--1}; tgt=${N_QT[$QSRC]}
    (( ${#cand[@]} )) || cand=(0)
  fi
  for i in 0 1; do
    t=${cand[RANDOM % ${#cand[@]}]}; need=$(( 6 + RANDOM % 9 ))
    OFFERS+=("K.$t.$need.0.$(( need * M_XP[t] * 3 / 2 )).$(( need * M_GOLD[t] * 2 ))")
  done
  if (( dt >= 0 )); then
    t=${D_BOSS[dt]}; OFFERS+=("D.$dt.1.0.$(( M_XP[t] )).$(( M_GOLD[t] ))")
  fi
  [[ -n $tgt ]] && OFFERS+=("T.$tgt.1.0.$(( 60 * LVL + 150 )).$(( 25 * LVL + 40 ))")
  # v3.0: collect, bounty, scout, deliver - one or two of them
  t=${cand[RANDOM % ${#cand[@]}]}; need=$(( 4 + RANDOM % 5 ))
  (( M_BOSS[t] == 0 )) && OFFERS+=("C.$t.$need.0.$(( need * M_XP[t] * 2 )).$(( need * M_GOLD[t] * 3 ))")
  local r best="" bd=99 s
  for r in "${RARE_T[@]}"; do
    d=$(( M_LVL[r] - LVL )); (( d < 0 )) && d=$(( -d * 2 ))
    (( d < bd )) && { bd=$d; best=$r; }
  done
  (( bd <= 6 )) && OFFERS+=("B.$best.1.0.$(( M_XP[best] * 2 )).$(( M_GOLD[best] ))")
  if (( RANDOM % 2 )); then
    best="" bd=999
    for (( s = 0; s < NSPOT; s++ )); do
      region_of "${SPT_X[s]}" "${SPT_Y[s]}" nosafe; r=${RLVL%%-*}; [[ $r =~ ^[0-9]+$ ]] || continue
      d=$(( r - LVL )); (( d < 0 )) && d=$(( -d ))
      (( d * 10 + RANDOM % 10 < bd )) && { bd=$(( d * 10 )); best=$s; }
    done
    [[ -n $best ]] && OFFERS+=("E.$best.1.0.$(( 40 * LVL + 120 )).$(( 15 * LVL + 30 ))")
  else
    r=$(( LVL / 5 )); (( r > 5 )) && r=5
    s=$(( (RANDOM % 2) * 6 + r )); need=$(( 3 + RANDOM % 4 ))
    OFFERS+=("G.$s.$need.0.$(( need * MAT_VAL[s] * 6 + 30 * LVL )).$(( need * MAT_VAL[s] * 3 ))")
  fi
}

pq_to_personal() {
  local q n=0
  for q in "${PQ_CODES[@]}"; do
    (( ${#QUESTS[@]} < 3 )) || break
    QUESTS+=("$q"); n=$(( n + 1 ))
  done
  (( n )) && logm "Your party quests carry on as personal quests." "$K_PARTY"
  PQ_CODES=()
}

# --- monsters & NPCs mirror (current map only) ------------------------------
# CM_POS["x,y"] -> mid, CMR[y] -> " mid  mid " (who is on that row: frames and skills only look at nearby rows)
CMR=()
cm_set() {  # mid type x y hp max
  if [[ -n ${CM_T[$1]} ]]; then unset "CM_POS[${CM_X[$1]},${CM_Y[$1]}]"; CMR[CM_Y[$1]]=${CMR[CM_Y[$1]]/" $1 "/}; fi
  CM_T[$1]=$2 CM_X[$1]=$3 CM_Y[$1]=$4 CM_HP[$1]=$5 CM_MAX[$1]=$6
  CM_POS["$3,$4"]=$1; CMR[$4]+=" $1 "
}
cm_move() {  # mid x y
  unset "CM_POS[${CM_X[$1]},${CM_Y[$1]}]"; CMR[CM_Y[$1]]=${CMR[CM_Y[$1]]/" $1 "/}
  CM_X[$1]=$2 CM_Y[$1]=$3; CM_POS["$2,$3"]=$1; CMR[$3]+=" $1 "
}
cm_del() {
  [[ -n ${CM_T[$1]} ]] || return
  CMR[CM_Y[$1]]=${CMR[CM_Y[$1]]/" $1 "/}
  unset "CM_POS[${CM_X[$1]},${CM_Y[$1]}]" "CM_T[$1]" "CM_X[$1]" "CM_Y[$1]" "CM_HP[$1]" "CM_MAX[$1]" "ATK_NPC[$1]" "CM_CH[$1]" "FROZEN[$1]"
}
mons_rect() {  # x1 y1 x2 y2 -> MR: every monster/NPC inside the rectangle
  local y m
  MR=()
  for (( y = ($2 < 0 ? 0 : $2); y <= $4; y++ )); do
    for m in ${CMR[y]}; do (( CM_X[m] >= $1 && CM_X[m] <= $3 )) && MR+=("$m"); done
  done
}
cm_clear() {
  CM_T=() CM_X=() CM_Y=() CM_HP=() CM_MAX=(); CM_POS=() ATK_NPC=() CMR=() CM_CH=() FROZEN=()
  FX_X=() FX_Y=() FX_K=() FX_E=() DOT_M=() DOT_D=() DOT_N=() DOT_T=(); TARGET=""
}
mon_at() { MID=${CM_POS[$1,$2]}; [[ -n $MID ]]; }
hostile() {  # mid -> 0 if it is fair game
  local t=${CM_T[$1]}
  [[ -n $t ]] || return 1
  (( M_KIND[t] == 0 || M_KIND[t] == 4 )) && return 0
  [[ -n ${ATK_NPC[$1]} ]] && return 0
  (( M_KIND[t] == 2 && NOW < WANTED_UNTIL )) && return 0
  return 1
}

in_party() { local p; for p in "${PARTY_IDS[@]}"; do [[ $p == "$1" ]] && return 0; done; return 1; }

party_near() {  # range -> NEAR ids (party members on my map, alive, in range)
  local p; NEAR=()
  for p in "${PARTY_IDS[@]}"; do
    [[ $p == "$MY_ID" || ${OP_MAP[$p]} != "$CUR_MAP" || ${OP_DEAD[$p]} == 1 ]] && continue
    cheb $(( ${OP_X[$p]:-0} - PX )) $(( ${OP_Y[$p]:-0} - PY )); (( D <= $1 )) && NEAR+=("$p")
  done
}

party_txt() {  # NEAR (party members in reach) -> PTXT " and 2 allies"
  if (( ${#NEAR[@]} == 1 )); then PTXT=" and 1 ally"; elif (( ${#NEAR[@]} > 1 )); then PTXT=" and ${#NEAR[@]} allies"; else PTXT=""; fi
}

# --- combat -------------------------------------------------------------------
add_fx() {  # kind "x,y x,y ..." [broadcast]
  local c
  [[ -n $1 && -n ${FXG[$1]} ]] || return                       # (an empty kind from the network: no bash error)
  for c in $2; do
    [[ $c =~ ^-?(0|[1-9][0-9]{0,3}),-?(0|[1-9][0-9]{0,3})$ ]] || continue
    FX_X+=("${c%,*}"); FX_Y+=("${c#*,}"); FX_K+=("$1"); FX_E+=($(( NOW + ${FXD[$1]:-280} )))
  done
  if (( ${#FX_E[@]} > 120 )); then
    FX_X=("${FX_X[@]:60}"); FX_Y=("${FX_Y[@]:60}"); FX_K=("${FX_K[@]:60}"); FX_E=("${FX_E[@]:60}")
  fi
  [[ $3 == 1 ]] && send FX "$MY_ID" "$CUR_MAP" "$1" "$2"
  MAP_DIRTY=1
}

ring() {  # r -> RING cells around me
  local i j; RING=""
  for (( j = -$1; j <= $1; j++ )); do for (( i = -$1; i <= $1; i++ )); do
    (( i == 0 && j == 0 )) || RING+="$(( PX + i )),$(( PY + j )) "
  done; done
}

dmg_mult() {
  DM=100
  (( NOW < buff_until )) && DM=$(( DM + 40 ))
  (( NOW < anthem_until )) && DM=$(( DM + 20 ))
  (( NOW < str_until )) && DM=$(( DM + 30 ))
  (( NOW < fed_until && fed_lvl == 2 )) && DM=$(( DM + 10 ))
}

deal() {  # mid pct freeze [quiet]   (DEAL_EL element, CASTK skill index or -1)
  local m=$1 d crit="" t=${CM_T[$1]} mul cc=${CRIT:-10} wk=""
  [[ -n $t ]] || return
  dmg_mult
  (( NOW < PS_UNTIL[5] )) && DM=$(( DM * 75 / 100 ))          # weakened
  d=$(( ATK * $2 / 100 * DM / 100 ))
  mul=$(( 100 + ${TB_EL[DEAL_EL]:-0} ))
  if (( CASTK >= 0 )); then mul=$(( mul + ${TB_SK[CASTK]:-0} )); else mul=$(( mul + ${TB_MELEE:-0} )); fi
  has_cap execute && (( CM_HP[m] * 100 < CM_MAX[m] * 30 )) && mul=$(( mul + 60 ))
  has_cap shatter && (( NOW < ${FROZEN[$m]:-0} )) && mul=$(( mul + 50 ))
  d=$(( d * mul / 100 ))
  el_mult "$t" "$DEAL_EL"; d=$(( d * EM / 100 ))
  (( EM > 100 )) && wk=" (weak to ${EL_NAME[DEAL_EL]})"; (( EM < 100 )) && wk=" (resists ${EL_NAME[DEAL_EL]})"
  d=$(( d * (85 + RANDOM % 31) / 100 )); (( d < 1 )) && d=1
  has_cap toxic && [[ " ${DOT_M[*]} " == *" $m "* ]] && cc=$(( cc + 25 ))
  (( EVPROC )) && { cc=100; EVPROC=0; }
  if (( RANDOM % 100 < cc )); then
    d=$(( d * CDMG / 100 )); crit=" - CRITICAL!"
    has_cap critreset && { SKCD[0]=$(( SKCD[0] - 1000 )) SKCD[1]=$(( SKCD[1] - 1000 )) SKCD[2]=$(( SKCD[2] - 1000 )); }
  fi
  (( $3 > 0 )) && FROZEN[$m]=$(( NOW + $3 ))
  (( TB_LS > 0 )) && heal_self $(( d * TB_LS / 100 )) q
  (( CASTK >= 0 )) && has_cap smiteheal && SMH=$(( SMH + d / 5 ))
  has_cap ignite && (( DEAL_EL == 1 && ! DOTK )) && dot_add "$m" $(( d * 30 / 100 )) 3
  has_cap bleed0 && (( CASTK == 0 && ! DOTK )) && dot_add "$m" $(( d * 40 / 100 )) 4
  send HIT "$MY_ID" "$CUR_MAP" "$m" "$d" "$3"
  CM_HP[$m]=$(( CM_HP[$m] - d )); (( CM_HP[$m] < 0 )) && CM_HP[$m]=0
  TARGET=$m LASTDMG=$d HITF[$m]=$NOW
  if [[ -n $crit ]]; then ft_add "${CM_X[$m]}" "${CM_Y[$m]}" "$d!" $'\e[0;1;38;5;226;48;5;52m'
  else ft_add "${CM_X[$m]}" "${CM_Y[$m]}" "$d" $'\e[0;1;38;5;231;48;5;234m'; fi
  [[ $4 == q ]] || { mname "$m"; logm "You hit $MN for $d$crit$wk" "$K_HIT"; }
}

dot_add() { DOT_M+=("$1"); DOT_D+=($(( $2 * (100 + ${TB_DOT:-0}) / 100 ))); DOT_N+=("$3"); DOT_T+=($(( NOW + 1000 ))); }

dot_tick() {
  local i m d
  for i in "${!DOT_M[@]}"; do
    (( NOW >= DOT_T[i] )) || continue
    m=${DOT_M[i]}
    if [[ -n ${CM_T[$m]} ]]; then
      d=${DOT_D[i]}; (( d < 1 )) && d=1
      send HIT "$MY_ID" "$CUR_MAP" "$m" "$d" 0
      CM_HP[$m]=$(( CM_HP[$m] - d )); (( CM_HP[$m] < 0 )) && CM_HP[$m]=0
      add_fx poison "${CM_X[$m]},${CM_Y[$m]}" 1
      ft_add "${CM_X[$m]}" "${CM_Y[$m]}" "$d" $'\e[0;38;5;118;48;5;234m' 
      DOT_N[i]=$(( DOT_N[i] - 1 )); DOT_T[i]=$(( DOT_T[i] + 1000 ))
      (( DOT_N[i] > 0 )) && continue
    fi
    unset "DOT_M[i]" "DOT_D[i]" "DOT_N[i]" "DOT_T[i]"
  done
}

melee() {
  (( NOW < next_attack )) && return
  stunned && return
  mount_off quiet; last_att=$NOW
  next_attack=$(( NOW + 650 - (NOW < FRENZY_T ? FRENZY * 60 : 0) ))
  CASTK=-1 DEAL_EL=0
  deal "$1" 100 0
  add_fx slash "${CM_X[$1]},${CM_Y[$1]}" 1
}

mons_within() {  # r -> MLIST (hostile only) sorted by distance
  local m i j t
  MLIST=() MDIST=()
  mons_rect $(( PX - $1 )) $(( PY - $1 )) $(( PX + $1 )) $(( PY + $1 ))
  for m in "${MR[@]}"; do
    cheb $(( CM_X[m] - PX )) $(( CM_Y[m] - PY ))
    (( D <= $1 )) || continue
    hostile "$m" || continue
    MLIST+=("$m"); MDIST+=("$D")
  done
  for (( i = 1; i < ${#MLIST[@]}; i++ )); do
    for (( j = i; j > 0 && MDIST[j-1] > MDIST[j]; j-- )); do
      t=${MLIST[j]}; MLIST[j]=${MLIST[j-1]}; MLIST[j-1]=$t
      t=${MDIST[j]}; MDIST[j]=${MDIST[j-1]}; MDIST[j-1]=$t
    done
  done
}

trace_line() {  # range [pierce] -> LHIT (first) LHITS (all) LCELLS; friendly NPCs stop shots
  local i x=$PX y=$PY
  LHIT="" LHITS=() LCELLS=""
  for (( i = 1; i <= $1; i++ )); do
    x=$(( x + FDX )) y=$(( y + FDY ))
    blocks_shot "$CUR_MAP" "$x" "$y" && break
    LCELLS+="$x,$y "
    if mon_at "$x" "$y"; then
      hostile "$MID" || break
      [[ -z $LHIT ]] && LHIT=$MID
      LHITS+=("$MID")
      [[ $2 == pierce ]] || break
    fi
  done
}

adj_target() {  # -> ADJ: hostile foe in front of me, else the nearest adjacent one
  local nx=$(( PX + FDX )) ny=$(( PY + FDY ))
  if mon_at "$nx" "$ny" && hostile "$MID"; then ADJ=$MID; return 0; fi
  mons_within 1; (( ${#MLIST[@]} )) || return 1
  ADJ=${MLIST[0]}
}

dash() {  # max dx dy -> moves me, returns steps; stops before monsters
  local i n=0 nx ny
  DASH_HIT=""
  for (( i = 0; i < $1; i++ )); do
    nx=$(( PX + $2 )) ny=$(( PY + $3 ))
    if mon_at "$nx" "$ny"; then hostile "$MID" && DASH_HIT=$MID; break; fi
    p_walk "$CUR_MAP" "$nx" "$ny" || break
    [[ $T == [\<\>] ]] && break
    PX=$nx PY=$ny; n=$(( n + 1 ))
  done
  DSTEPS=$n
  (( n )) && { POS_DIRTY=1; MAP_DIRTY=1; }
}

heal_amount() { HEALV=$(( (18 + LVL * 7) * (100 + TB_HEAL) / 100 )); }
heal_self() {  # amount [q: no floating number]
  local h=$1; (( HP + h > MAXHP )) && h=$(( MAXHP - HP ))
  HP=$(( HP + h )); POS_DIRTY=1
  (( h > 0 )) && [[ $2 != q ]] && ft_add "$PX" "$PY" "+$h" $'\e[0;1;38;5;120;48;5;234m'
}

cast() {  # skill index 0..2
  local k=$1 s=$(( CLS * 3 + $1 )) m p c sx=$PX sy=$PY
  (( DEAD )) && return
  stunned && return
  if (( NOW < SKCD[k] )); then logm "${S_NAME[s]} is not ready yet."; return; fi
  local cost=$(( S_MP[s] * (100 - TB_MPC) / 100 ))
  if (( MP < cost )); then logm "Not enough mana for ${S_NAME[s]} ($cost)."; return; fi
  CASTK=$k DEAL_EL=${S_EL[s]} SMH=0
  mount_off quiet; last_att=$NOW
  case $s in
    0)  mons_within 1; (( ${#MLIST[@]} )) || { logm "Nothing in reach to cleave."; return; }
        for m in "${MLIST[@]}"; do deal "$m" 120 0; done; ring 1; add_fx slash "$RING" 1 ;;
    1)  dash 4 "$FDX" "$FDY"
        c=""; for (( m = 0; m <= DSTEPS; m++ )); do c+="$(( sx + FDX * m )),$(( sy + FDY * m )) "; done
        if [[ -n $DASH_HIT ]]; then deal "$DASH_HIT" 170 1500; c+="${CM_X[$DASH_HIT]},${CM_Y[$DASH_HIT]}"
        elif (( DSTEPS == 0 )); then logm "No room to charge."; return; fi
        add_fx slash "$c" 1 ;;
    2)  buff_until=$(( NOW + 12000 )); party_near 10
        for p in "${NEAR[@]}"; do send BUFF "$MY_ID" "$MY_NAME" "$p" 12000 fury; done
        ring 1; add_fx holy "$RING" 1; party_txt; logm "BATTLE CRY! You$PTXT deal +40% damage." "$K_GOOD" ;;
    3)  trace_line 8; add_fx fire "$LCELLS" 1
        if [[ -n $LHIT ]]; then
          local tx=${CM_X[$LHIT]} ty=${CM_Y[$LHIT]}
          deal "$LHIT" 220 0
          mons_rect $(( tx - 1 )) $(( ty - 1 )) $(( tx + 1 )) $(( ty + 1 ))
          for m in "${MR[@]}"; do
            [[ $m == "$LHIT" ]] && continue
            hostile "$m" || continue
            cheb $(( CM_X[m] - tx )) $(( CM_Y[m] - ty )); (( D <= 1 )) && deal "$m" 60 0
          done
          c=""; for p in -1 0 1; do for m in -1 0 1; do c+="$(( tx + m )),$(( ty + p )) "; done; done; add_fx fire "$c" 1
        fi ;;
    4)  mons_within 2; for m in "${MLIST[@]}"; do deal "$m" 90 3000; done; ring 2; add_fx frost "$RING" 1 ;;
    5)  dash 5 "$FDX" "$FDY"
        (( DSTEPS )) || { logm "Something blocks your blink."; return; }
        add_fx frost "$sx,$sy $PX,$PY" 1 ;;
    6)  trace_line 7; add_fx slash "$LCELLS" 1; [[ -n $LHIT ]] && deal "$LHIT" 115 0 ;;
    7)  mons_within 6; (( ${#MLIST[@]} )) || { logm "No targets for Multishot."; return; }
        c=""; for m in "${MLIST[@]:0:3}"; do deal "$m" 85 0; c+="${CM_X[$m]},${CM_Y[$m]} "; done; add_fx slash "$c" 1 ;;
    8)  dash 3 $(( -FDX )) $(( -FDY )); immune_until=$(( NOW + 2000 ))
        add_fx frost "$sx,$sy $PX,$PY" 1; logm "You leap away - immune for 2s." "$K_GOOD" ;;
    9)  trace_line 5; add_fx holy "$LCELLS" 1; [[ -n $LHIT ]] && deal "$LHIT" 140 0 ;;
    10) heal_amount; heal_self "$HEALV"; party_near 8
        for p in "${NEAR[@]}"; do send HEAL "$MY_ID" "$MY_NAME" "$p" "$HEALV"; done
        ring 1; add_fx holy "$RING" 1; party_txt; logm "You heal yourself$PTXT for $HEALV." "$K_GOOD" ;;
    11) mons_within 3; for m in "${MLIST[@]}"; do deal "$m" 110 0; done
        heal_amount; HEALV=$(( HEALV / 2 )); heal_self "$HEALV"; party_near 6
        for p in "${NEAR[@]}"; do send HEAL "$MY_ID" "$MY_NAME" "$p" "$HEALV"; done
        ring 3; add_fx holy "$RING" 1 ;;
    12) adj_target || { logm "Nobody in reach to backstab."; return; }
        deal "$ADJ" 260 0; add_fx slash "${CM_X[$ADJ]},${CM_Y[$ADJ]}" 1 ;;
    13) adj_target || { logm "Nobody in reach to poison."; return; }
        deal "$ADJ" 80 0; dot_add "$ADJ" $(( ATK * 45 / 100 )) 5
        add_fx poison "${CM_X[$ADJ]},${CM_Y[$ADJ]}" 1; logm "${M_NAME[CM_T[$ADJ]]} is poisoned." "$K_GOOD" ;;
    14) mons_within 7; (( ${#MLIST[@]} )) || { logm "No shadows to step into."; return; }
        m=${MLIST[0]}
        local tx=${CM_X[$m]} ty=${CM_Y[$m]} best="" bx by d2 o
        for o in "1 0" "-1 0" "0 1" "0 -1"; do
          set -- $o; bx=$(( tx + $1 )) by=$(( ty + $2 ))
          p_walk "$CUR_MAP" "$bx" "$by" && [[ $T != [\<\>] ]] && ! mon_at "$bx" "$by" || continue
          d2=$(( (bx - PX) * (bx - PX) + (by - PY) * (by - PY) ))
          [[ -z $best || $d2 -gt ${best%% *} ]] && best="$d2 $bx $by $(( -$1 )) $(( -$2 ))"
        done
        [[ -n $best ]] || { logm "No room behind your target."; return; }
        set -- $best; PX=$2 PY=$3 FDX=$4 FDY=$5 POS_DIRTY=1 MAP_DIRTY=1
        immune_until=$(( NOW + 1000 ))
        add_fx poison "$sx,$sy $PX,$PY" 1; deal "$m" 120 0 ;;
    15) adj_target || { logm "Nothing in reach to strike."; return; }
        deal "$ADJ" 160 0; heal_self $(( MAXHP * 8 / 100 )); add_fx holy "${CM_X[$ADJ]},${CM_Y[$ADJ]}" 1 ;;
    16) immune_until=$(( NOW + 4000 )); ring 1; add_fx holy "$RING" 1
        logm "DIVINE SHIELD - nothing can touch you for 4s." "$K_GOOD" ;;
    17) mons_within 2; for m in "${MLIST[@]}"; do deal "$m" 90 0; done
        HEALV=$(( 10 + LVL * 3 )); heal_self "$HEALV"; party_near 4
        for p in "${NEAR[@]}"; do send HEAL "$MY_ID" "$MY_NAME" "$p" "$HEALV"; done
        ring 2; add_fx holy "$RING" 1 ;;
    18) trace_line 9 pierce; add_fx bone "$LCELLS" 1
        for m in "${LHITS[@]}"; do deal "$m" 140 0; done ;;
    19) trace_line 6; add_fx poison "$LCELLS" 1
        if [[ -n $LHIT ]]; then deal "$LHIT" 150 0; heal_self $(( LASTDMG / 2 )); logm "You drain $(( LASTDMG / 2 )) life." "$K_GOOD"; fi ;;
    20) mons_within 3; (( ${#MLIST[@]} )) || { logm "No one to infect."; return; }
        for m in "${MLIST[@]}"; do dot_add "$m" $(( ATK * 40 / 100 )) 6; done
        ring 3; add_fx poison "$RING" 1; logm "PLAGUE spreads to ${#MLIST[@]} foes." "$K_GOOD" ;;
    21) trace_line 6 pierce; add_fx sound "$LCELLS" 1
        for m in "${LHITS[@]}"; do deal "$m" 110 0; done ;;
    22) mons_within 3; for m in "${MLIST[@]}"; do deal "$m" 40 4000 q; done
        ring 3; add_fx sound "$RING" 1; logm "Your LULLABY puts ${#MLIST[@]} foes to sleep." "$K_GOOD" ;;
    23) anthem_until=$(( NOW + 15000 )); party_near 10
        for p in "${NEAR[@]}"; do send BUFF "$MY_ID" "$MY_NAME" "$p" 15000 anthem; done
        ring 1; add_fx sound "$RING" 1; party_txt; logm "ANTHEM! You$PTXT are faster and deal +20% damage." "$K_GOOD" ;;
    # v4.0: the druid
    24) trace_line 6; add_fx poison "$LCELLS" 1
        [[ -n $LHIT ]] && { deal "$LHIT" 130 0; dot_add "$LHIT" $(( ATK * 30 / 100 )) 4; } ;;
    25) mons_within 3; (( ${#MLIST[@]} )) || { logm "Nothing close enough to entangle."; return; }
        for m in "${MLIST[@]}"; do deal "$m" 60 3500; done
        ring 3; add_fx poison "$RING" 1; logm "Roots hold ${#MLIST[@]} foes fast." "$K_GOOD" ;;
    26) heal_amount; heal_self "$HEALV"; party_near 8
        for p in "${NEAR[@]}"; do send HEAL "$MY_ID" "$MY_NAME" "$p" "$HEALV"; done
        ring 2; add_fx holy "$RING" 1; party_txt; logm "Wild Growth heals you$PTXT for $HEALV." "$K_GOOD" ;;
    # v4.0: the monk
    27) adj_target || { logm "Nobody in reach of your fists."; return; }
        deal "$ADJ" 70 0 q; deal "$ADJ" 70 0 q; deal "$ADJ" 70 0; add_fx slash "${CM_X[$ADJ]},${CM_Y[$ADJ]}" 1 ;;
    28) dash 4 "$FDX" "$FDY"
        c=""; for (( m = 0; m <= DSTEPS; m++ )); do c+="$(( sx + FDX * m )),$(( sy + FDY * m )) "; done
        if [[ -n $DASH_HIT ]]; then deal "$DASH_HIT" 160 1500; c+="${CM_X[$DASH_HIT]},${CM_Y[$DASH_HIT]}"
        elif (( DSTEPS == 0 )); then logm "No room to jump."; return; fi
        add_fx slash "$c" 1 ;;
    29) heal_self $(( MAXHP * 22 / 100 )); immune_until=$(( NOW + 1500 ))
        ring 1; add_fx holy "$RING" 1; logm "Inner peace: you heal, and nothing touches you for 1.5s." "$K_GOOD" ;;
  esac
  # v3.0: talents bend the rules a little
  has_cap clearcast && (( RANDOM % 100 < 20 )) && { cost=0; logm "Clearcasting - that one was free." "$K_GOOD"; }
  MP=$(( MP - cost )); SKCD[k]=$(( NOW + S_CD[s] * (100 - TB_CD[k] - TB_CDALL) / 100 )); POS_DIRTY=1
  (( k == 2 )) && has_cap echo && (( RANDOM % 100 < 30 )) && { SKCD[2]=$NOW; logm "Encore! ${S_NAME[s]} is ready again." "$K_GOOD"; }
  if (( k == 0 )) && has_cap chain && [[ -n $TARGET && -n ${CM_T[$TARGET]} ]]; then
    local cm; mons_within 6
    for cm in "${MLIST[@]}"; do [[ $cm == "$TARGET" ]] && continue; deal "$cm" 60 0; add_fx bone "${CM_X[$cm]},${CM_Y[$cm]}" 1; break; done
  fi
  if (( SMH > 0 )); then
    heal_self "$SMH"; party_near 8; for p in "${NEAR[@]}"; do send HEAL "$MY_ID" "$MY_NAME" "$p" "$SMH"; done
  fi
  case $s in 10|11|15|17|26|29) pst_clear all ;; esac     # holy magic (and nature, and calm) cleanses
  CASTK=-1 DEAL_EL=0
}

take_damage() {  # dmg source [mid] [element] [effect]
  (( DEAD )) && return
  [[ -n $3 ]] && (( M_KIND[${CM_T[$3]:-0}] > 0 )) && ATK_NPC[$3]=1     # fight back against angry NPCs
  [[ -n $3 ]] && ALY_LAST=$3
  (( ADM_GOD )) && return                                                # v6.4: admin god mode
  if (( NOW < immune_until )); then logm "You evade $2's attack!" "$K_GOOD"; return; fi
  (( RIDING )) && { mount_off quiet; logm "You are thrown from your mount!" "$K_HURT"; }
  local a=$ARMOR d el=${4:-0} r=$RES tag=""
  if (( RANDOM % 100 < DODGE )); then
    logm "You dodge $2's attack!" "$K_GOOD"; ft_add "$PX" "$PY" "dodge" $'\e[0;38;5;250;48;5;234m'
    has_cap evasion && EVPROC=1
    return
  fi
  (( NOW < iron_until )) && a=$(( ARMOR * 3 / 2 ))
  if (( el == 0 )); then d=$(( $1 * 100 / (100 + a * 5) ))
  else                                                       # magic: half the armor, resistances count
    (( el == 1 && NOW < fireward_until )) && r=$(( r + 25 ))
    (( el == 2 && NOW < frost_until )) && r=$(( r + 25 ))
    d=$(( $1 * 100 / (100 + a * 5 / 2) * (100 - r) / 100 )); tag=" ${EL_NAME[el]}"
  fi
  if (( BLOCK && RANDOM % 100 < BLOCK )); then d=$(( d / 2 )); tag+=" (blocked)"; fi
  (( d < 1 )) && d=1
  if (( BARRIER > 0 )); then
    if (( BARRIER >= d )); then BARRIER=$(( BARRIER - d )); logm "Your shield absorbs $d." "$K_GOOD"; return; fi
    d=$(( d - BARRIER )); BARRIER=0
  fi
  if [[ -n $3 ]] && (( TB_THORNS > 0 && el == 0 )) && [[ -n ${CM_T[$3]} ]] && hostile "$3"; then
    send HIT "$MY_ID" "$CUR_MAP" "$3" $(( d * TB_THORNS / 100 + 1 )) 0
  fi
  HP=$(( HP - d )); last_hurt=$NOW; POS_DIRTY=1 MAP_DIRTY=1
  logm "$2 hits you for $d$tag" "$K_HURT"
  ft_add "$PX" "$PY" "-$d" $'\e[0;1;38;5;203;48;5;234m' 
  if (( HP <= 0 )); then die_now "$2"; return; fi
  [[ -n $5 ]] && pst_apply "$5" "$1"
}

respawn() {
  DEAD=0 HP=$MAXHP MP=$MAXMP; PS_UNTIL=(0 0 0 0 0 0)
  [[ $CUR_MAP != W ]] && leave_instance quiet
  PX=$SPAWN_X PY=$SPAWN_Y POS_DIRTY=1 MAP_DIRTY=1
  logm "You wake up by the fountain of Hearthmoor." "$K_GOOD"
}

use_item() {  # h m gh gm str iron swift recall brew
  (( DEAD )) && return
  case $1 in
    h)  if (( POT_H > 0 )); then POT_H=$(( POT_H - 1 )); heal_self $(( MAXHP * (40 + TB_POT) / 100 )); pst_clear; logm "You drink a health potion." "$K_GOOD"
        elif (( POT_GH > 0 )); then use_item gh
        else logm "No health potions left. Mara sells them in Hearthmoor."; fi ;;
    m)  if (( POT_M > 0 )); then POT_M=$(( POT_M - 1 )); MP=$(( MP + MAXMP * 50 / 100 )); logm "You drink a mana potion." "$K_GOOD"
        elif (( POT_GM > 0 )); then use_item gm
        else logm "No mana potions left. Mara sells them in Hearthmoor."; fi ;;
    gh) (( POT_GH > 0 )) || return; POT_GH=$(( POT_GH - 1 )); heal_self $(( MAXHP * (80 + TB_POT) / 100 )); pst_clear; logm "You drink a greater health potion." "$K_GOOD" ;;
    gm) (( POT_GM > 0 )) || return; POT_GM=$(( POT_GM - 1 )); MP=$(( MP + MAXMP * 80 / 100 )); logm "You drink a greater mana potion." "$K_GOOD" ;;
    str)   (( EL_STR > 0 )) || return; EL_STR=$(( EL_STR - 1 )); str_until=$(( NOW + 90000 )); logm "Elixir of Strength: +30% damage for 90s." "$K_GOOD" ;;
    iron)  (( EL_IRON > 0 )) || return; EL_IRON=$(( EL_IRON - 1 )); iron_until=$(( NOW + 90000 )); logm "Elixir of Iron Skin: +50% armor for 90s." "$K_GOOD" ;;
    swift) (( EL_SWIFT > 0 )) || return; EL_SWIFT=$(( EL_SWIFT - 1 )); swift_until=$(( NOW + 60000 )); logm "Elixir of Swiftness: you move faster for 60s." "$K_GOOD" ;;
    recall) (( SCROLL > 0 )) || return; SCROLL=$(( SCROLL - 1 )); home_ready=0; recall ;;
    brew)  (( BREW > 0 )) || return; BREW=$(( BREW - 1 )); HP=$MAXHP MP=$MAXMP str_until=$(( NOW + 120000 ))
           logm "Hermit's Brew! Fully restored and +30% damage for 120s." "$K_GOOD" ;;
    meal1) (( MEAL1 > 0 )) || return; local m2=$MEAL2; MEAL2=0; eat; MEAL2=$m2 ;;
    meal2) (( MEAL2 > 0 )) || return; eat ;;
    tfrost) (( TON_FROST > 0 )) || return; TON_FROST=$(( TON_FROST - 1 )); frost_until=$(( NOW + 300000 ))
            logm "Frost Tonic: the cold can't slow you down for 5 minutes." "$K_GOOD" ;;
    tfire)  (( TON_FIRE > 0 )) || return; TON_FIRE=$(( TON_FIRE - 1 )); fireward_until=$(( NOW + 300000 ))
            logm "Fire Ward Tonic: burning ash can't hurt you for 5 minutes." "$K_GOOD" ;;
    tveil)  (( TON_VEIL > 0 )) || return; TON_VEIL=$(( TON_VEIL - 1 )); veil_until=$(( NOW + 300000 ))
            logm "Sand Veil: your eyes pierce storms and darkness for 5 minutes." "$K_GOOD" ;;
  esac
  (( MP > MAXMP )) && MP=$MAXMP
  POS_DIRTY=1
}

# --- moving, dungeons ---------------------------------------------------------
init_fog() {
  local y blank
  printf -v blank '%*s' "${MAPW[$1]}" ''
  for (( y = 0; y < MAPH[$1]; y++ )); do EXPL["$1:$y"]=$blank; done
}

enter_instance() {  # map dt seed
  WX=${D_ENTX[$2]} WY=$(( D_ENTY[$2] + 1 ))
  gen_dungeon "$1" "$2" "$3"
  drop_vrows "$1"
  mount_off quiet
  CUR_MAP=$1 CUR_DT=$2 PX=$DG_SX PY=$DG_SY clear_until=0 UI=""
  cm_clear; init_fog "$1"; set_palette "$2"
  POS_DIRTY=1 MAP_DIRTY=1
  logm "You descend into the ${D_NAME[$2]}. Somewhere in the dark waits its master..." "$K_ANN"
}

leave_instance() {
  local old=$CUR_MAP y
  [[ $old == W ]] && return
  drop_vrows "$old"
  for (( y = 0; y < ${MAPH[$old]:-0}; y++ )); do unset "MAPROW[$old:$y]" "EXPL[$old:$y]"; done
  CUR_MAP=W CUR_DT=-1 PX=$WX PY=$WY clear_until=0
  cm_clear; set_palette -1
  [[ $old == H* ]] && room_left
  send SYNC "$MY_ID" W
  POS_DIRTY=1 MAP_DIRTY=1 NEED_FULL=1
  if [[ $1 != quiet ]]; then
    if [[ $old == H* ]]; then logm "You go back down to the taproom." "$K_SYS"; else logm "You climb back into the daylight." "$K_GOOD"; fi
  fi
}

dungeon_enter() {
  local d
  for (( d = 0; d < NDT; d++ )); do
    (( PX == D_ENTX[d] && PY == D_ENTY[d] )) || continue
    if (( LVL < D_REQ[d] )); then logm "A cold voice whispers: the ${D_NAME[d]} is for level ${D_REQ[d]}+." "$K_HURT"; return; fi
    if (( LVL >= MAXLVL || ${D_RAID[$d]:-0} )); then [[ $UI == dgate ]] || dgate_open "$d"; return; fi   # v4.5: normal or mythic?
    (( NOW < dreq_until )) && return
    dreq_until=$(( NOW + 4000 ))
    send DREQ "$MY_ID" "$d"
    logm "You open the gate to the ${D_NAME[d]}..." "$K_SYS"
  done
}

rest() {
  HP=$MAXHP MP=$MAXMP POS_DIRTY=1; pst_clear all
  logm "$1" "$K_GOOD"
}

try_move() {  # dx dy
  local nx=$(( PX + $1 )) ny=$(( PY + $2 ))
  FDX=$1 FDY=$2
  (( DEAD || NOW < next_move )) && return
  stunned && return
  if mon_at "$nx" "$ny" && (( M_KIND[${CM_T[$MID]}] == 3 )); then gather_start "$MID"; return; fi
  (( FISH_ST )) && fish_stop
  GATH_MID=""
  if mon_at "$nx" "$ny"; then
    if hostile "$MID"; then melee "$MID"; else talk_open "$MID"; fi
    next_move=$(( NOW + 150 )); return
  fi
  if [[ $CUR_MAP == H* && -n ${RM_AT[$nx,$ny]} ]]; then room_use "${RM_AT[$nx,$ny]}"; next_move=$(( NOW + 250 )); return; fi   # v5.0
  tile "$CUR_MAP" "$nx" "$ny"
  case $T in
    Q) qev_board; QSRC=board; [[ ${#OFFERS[@]} -gt 0 && $OFFER_LVL == "$LVL" && $OFFER_SRC == board ]] || gen_offers; UI=quest; MAP_DIRTY=1; return ;;
    Z) UI=way MAP_DIRTY=1; explore_here; return ;;
    O) logm "The fountain glitters. Press [?] for help, [m] for the world map."; next_move=$(( NOW + 500 )); return ;;
    F) CRAFT=cook UI=craft MAP_DIRTY=1; return ;;
  esac
  p_walk "$CUR_MAP" "$nx" "$ny" || return
  local ox=$PX oy=$PY
  PX=$nx PY=$ny POS_DIRTY=1 MAP_DIRTY=1
  aly_follow "$ox" "$oy"
  explore_here
  if (( NOW < anthem_until || NOW < swift_until )); then next_move=$(( NOW + 75 )); else next_move=$(( NOW + 110 )); fi
  [[ $CW == snow ]] && (( NOW >= frost_until )) && next_move=$(( next_move + 120 ))   # wading through the blizzard
  (( NOW < PS_UNTIL[3] )) && next_move=$(( next_move + 110 ))                        # chilled
  (( TB_SPEED || (NOW < FRENZY_T && FRENZY) )) && next_move=$(( NOW + (next_move - NOW) * (100 - TB_SPEED - (NOW < FRENZY_T ? FRENZY * 5 : 0)) / 100 ))
  mount_delay
  if [[ $T == '>' && $CUR_MAP == W ]]; then dungeon_enter
  elif [[ $T == '<' && $CUR_MAP != W ]]; then leave_instance; fi
}

melee_any() {
  adj_target && melee "$ADJ"
}

recall() {
  if (( NOW < home_ready )); then logm "Your hearthstone is still cooling down ($(( (home_ready - NOW) / 1000 ))s)."; return; fi
  (( DEAD )) && return
  home_ready=$(( NOW + 60000 ))
  [[ $CUR_MAP != W ]] && leave_instance quiet
  PX=$SPAWN_X PY=$SPAWN_Y POS_DIRTY=1 MAP_DIRTY=1
  logm "You crush your hearthstone and appear in Hearthmoor." "$K_GOOD"
  explore_here
}

# --- NPCs, shops ------------------------------------------------------------------
pick_line() {  # "a|b|c" -> LINE   (nothing to say: "" - a modulo by zero here once ended the whole game)
  local IFS='|' arr
  arr=($1); LINE=""
  (( ${#arr[@]} )) && LINE=${arr[RANDOM % ${#arr[@]}]}
}

talk_open() {  # mid
  local t=${CM_T[$1]} role
  role=${N_ROLE[$t]}
  TALK_MID=$1 TALK_T=$t TALK_CONFIRM=0 UI=talk MAP_DIRTY=1
  if (( NOW < WANTED_UNTIL )) && [[ $role == @(general|smith|alchemist|inn|guard|villager|merc|bank) ]]; then
    LINE="Murderer! I'll have nothing to do with you. GUARDS!"
  else
    pick_line "${N_SAY[$role]}"
  fi
  if story_npc "$t"; then TALK_LINE=$LINE; story_event T "$t"; return; fi
  TALK_LINE=$LINE
  ql_talk "$t" && return
  if (( STORY < NST )) && [[ ${ST_OBJ[STORY]} == "T.$t" ]]; then LINE="I have something to tell you, friend - but come back when you are level ${ST_LVL[STORY]}."; fi
  local i f q done=()
  for i in "${!QUESTS[@]}"; do
    [[ ${QUESTS[i]} == "T.$t."* ]] && done=("$i" "${done[@]}")
  done
  for i in "${done[@]}"; do quest_done "$i"; LINE="A letter for me? Thank you, friend - here's something for your trouble."; done
  for q in "${PQ_CODES[@]}"; do
    [[ $q == "T.$t."* ]] && { send QTALK "$MY_ID" "$t"; LINE="Ah, the letter your party carries! Many thanks."; break; }
  done
  TALK_LINE=$LINE
}

shop_build() {  # role -> SH_ID SH_LABEL SH_PRICE
  local t r
  SH_ID=() SH_LABEL=() SH_PRICE=()
  tier_for "$LVL"; t=$TF; r=$(( t < MAXTIER ? t + 1 : MAXTIER ))
  shi() { SH_ID+=("$1"); SH_LABEL+=("$2"); SH_PRICE+=("$3"); }
  shg() {  # gear code price
    item_name "$1" "$CLS"; bonus_txt
    if (( IVAL )); then local l=dmg; [[ $IK != W ]] && l=arm; shi "$1" "$INAME  (+$IVAL $l, $BTX)" "$2"
    else shi "$1" "$INAME  ($BTX)" "$2"; fi
  }
  case $1 in
    general)
      shi h "Health potion  (+40% HP)" 20; shi m "Mana potion  (+50% MP)" 20; shi recall "Scroll of Recall  (instant /home)" 40
      shi B.0 "" 150; shi B.1 "" 400 ;;
    smith)
      shg "W.${DEFW[CLS]}.$t.0" $(( 30 * t * t + 20 )); shg "A.${DEFA[CLS]}.$t.0" $(( 30 * t * t + 20 ))
      shg "W.${ALTW[CLS]}.$r.1" $(( 90 * r * r + 60 )); shg "A.${DEFA[CLS]}.$r.1" $(( 90 * r * r + 60 ))
      shg "H.${DEFH[CLS]}.$t.0" $(( 20 * t * t + 15 )); shg "O.${DEFO[CLS]}.$t.0" $(( 20 * t * t + 15 ))
      reforge_info "$EQW"; shi rfw "Reforge your weapon  ($RFTXT)" "$RFCOST"
      reforge_info "$EQA"; shi rfa "Reforge your armor  ($RFTXT)" "$RFCOST" ;;
    alchemist)
      shi gh "Greater health potion  (+80% HP)" 60; shi gm "Greater mana potion  (+80% MP)" 60
      shi str "Elixir of Strength  (+30% dmg, 90s)" 120; shi iron "Elixir of Iron Skin  (+50% armor, 90s)" 120
      shi swift "Elixir of Swiftness  (faster, 60s)" 90; shi h "Health potion" 25; shi m "Mana potion" 25 ;;
    trader)
      shi gh "Greater health potion" 75
      shg "J.0.$t.1" $(( 40 * t * t + 60 )); shg "J.1.$t.1" $(( 40 * t * t + 60 ))
      shg "J.2.$t.1" $(( 40 * t * t + 60 )); shg "J.3.$t.1" $(( 40 * t * t + 60 )); shg "O.3.$t.0" $(( 15 * t * t + 30 ))
      shg "W.${DEFW[CLS]}.$t.0" $(( (30 * t * t + 20) * 13 / 10 )); shi B.1 "" 450; shi B.2 "" 950 ;;
    hermit)
      shi brew "Hermit's Brew  (full restore, +30% dmg 120s)" 150; shi gm "Greater mana potion" 55
      shi swift "Elixir of Swiftness" 80 ;;
    spice)
      shi h "Health potion" 28; shi gh "Greater health potion" 70
      shi tfire "Fire Ward Tonic  (ash rain immunity, 5 min)" 90; shi tfrost "Frost Tonic  (no blizzard slow, 5 min)" 90
      shi tveil "Sand Veil  (see far in storms and at night)" 110; shi swift "Elixir of Swiftness" 95
      shi B.2 "" 950; shi B.3 "" 1900 ;;
    questgiver)
      shi h "Health potion" 30; shi m "Mana potion" 30
      case $TALK_T in
        46) shi tveil "Sand Veil  (see far in storms and at night)" 120; shi recall "Scroll of Recall" 50 ;;
        49) shi tfrost "Frost Tonic  (no blizzard slow, 5 min)" 95; shi gh "Greater health potion" 75; shi B.3 "" 1850 ;;
        52) shi tfire "Fire Ward Tonic  (ash rain immunity, 5 min)" 95; shi gm "Greater mana potion" 75; shi B.4 "" 4200 ;;
        $(( NPC1 + 1 ))) shi gh "Greater health potion" 80; shi gm "Greater mana potion" 80; shi recall "Scroll of Recall" 60; shi B.3 "" 2000 ;;
        $(( NPC1 + 5 ))) shi gm "Greater mana potion" 80; shi tfrost "Frost Tonic  (no blizzard slow, 5 min)" 95
                         shi iron "Elixir of Iron Skin  (+50% armor, 90s)" 130; shi B.4 "" 4500 ;;
        $(( NPC1 + 10 ))) shi gh "Greater health potion" 80; shi str "Elixir of Strength  (+30% dmg, 90s)" 130
                          shi swift "Elixir of Swiftness" 95; shi B.4 "" 4500 ;;
        $(( NPC1 + 14 ))) shi gh "Greater health potion" 80; shi tfire "Fire Ward Tonic  (ash rain immunity, 5 min)" 95
                          shi tveil "Sand Veil  (see far in storms and at night)" 115; shi B.4 "" 4400 ;;
        $(( NPC1 + 19 ))) shi gh "Greater health potion" 90; shi gm "Greater mana potion" 90; shi brew "Hermit's Brew  (full restore, +30% dmg 120s)" 180
                          shi str "Elixir of Strength  (+30% dmg, 90s)" 140; shi B.5 "" 15000 ;;
      esac ;;
  esac
  local i; rep_disc "$TALK_T"                         # v3.0: reputation brings discounts
  (( DISC )) && for i in "${!SH_PRICE[@]}"; do SH_PRICE[i]=$(( SH_PRICE[i] * (100 - DISC) / 100 )); done
}

fish_value() { local f; FISHN=0 FISHV=0; for (( f = 12; f < NMAT; f++ )); do FISHN=$(( FISHN + MATS[f] )) FISHV=$(( FISHV + MATS[f] * MAT_VAL[f] )); done; }

reforge_info() {  # code -> RFCOST RFCHANCE RFTXT
  item_stats "$1"
  if (( IRR >= 3 )); then RFCOST=0 RFCHANCE=0 RFTXT="already legendary"; return; fi
  RFCOST=$(( 60 * IT * IT * (IRR + 1) + 50 ))
  RFCHANCE=$(( IRR == 0 ? 80 : (IRR == 1 ? 55 : 30) ))
  RFTXT="${RAR_NAME[IRR+1]}, ${RFCHANCE}% chance"
}

junk_value() {  # -> JUNK (count) JVAL, items worse or equal to what you wear
  local c cur
  JUNK=0 JVAL=0
  for c in "${INV[@]}"; do
    is_junk "$c" && { JUNK=$(( JUNK + 1 )); JVAL=$(( JVAL + JS )); }
  done
}

eq_of() { case $1 in W) EQC=$EQW ;; A) EQC=$EQA ;; O) EQC=$EQO ;; H) EQC=$EQH ;; *) EQC=$EQJ ;; esac; }   # slot -> EQC

is_junk() {  # code -> 0 if unusable for my class or not better than what I wear there; JS = sell value
  local v b
  item_stats "$1"; JS=$ISELL
  [[ $1 == *! || $IK == [BC] || -n $IUQ ]] && return 1
  [[ $ICLS == *"$CLS"* ]] || return 0
  v=$IVAL b=$IBV; eq_of "$IK"; [[ -n $EQC ]] || return 1
  item_stats "$EQC"
  (( v < IVAL || (v == IVAL && b <= IBV) ))
}

shop_key() {
  local i id price c keep=() total=0 cur
  shop_build "$SHOP"
  case $1 in
    [1-9])
      i=$(( $1 - 1 )); (( i < ${#SH_ID[@]} )) || return
      id=${SH_ID[i]} price=${SH_PRICE[i]}
      if [[ $id == rf? ]]; then
        local code=$EQW; [[ $id == rfa ]] && code=$EQA
        reforge_info "$code"
        (( RFCOST > 0 )) || { logm "That one is already legendary."; return; }
        (( GOLD >= RFCOST )) || { logm "Brom wants $RFCOST gold for that." "$K_HURT"; return; }
        GOLD=$(( GOLD - RFCOST ))
        if (( RANDOM % 100 < RFCHANCE )); then
          code="$IK.$IKD.$IT.$(( IRR + 1 ))"
          if [[ $id == rfw ]]; then EQW=$code; else EQA=$code; fi
          calc_stats; item_name "$code" "$CLS"
          logm "SUCCESS! Brom hands you a $INAME." "$K_ANN"
        else
          logm "The metal cracks... Brom shrugs. Better luck next time." "$K_HURT"
        fi
        return
      fi
      (( GOLD >= price )) || { logm "You need $price gold." "$K_HURT"; return; }
      case $id in
        B.*) bag_buy "$id" || return ;;
        [WAOHJ].*) (( ${#INV[@]} < BAGS )) || { logm "Your bags are full - sell something first." "$K_HURT"; return; }
                INV+=("$id"); NEWG[$id]=1; item_name "$id" "$CLS"; logm "Bought $INAME. Equip it in your inventory [i]." "$K_LOOT" ;;
        h) POT_H=$(( POT_H + 1 )) ;; m) POT_M=$(( POT_M + 1 )) ;; gh) POT_GH=$(( POT_GH + 1 )) ;; gm) POT_GM=$(( POT_GM + 1 )) ;;
        str) EL_STR=$(( EL_STR + 1 )) ;; iron) EL_IRON=$(( EL_IRON + 1 )) ;; swift) EL_SWIFT=$(( EL_SWIFT + 1 )) ;;
        recall) SCROLL=$(( SCROLL + 1 )) ;; brew) BREW=$(( BREW + 1 )) ;;
        tfire) TON_FIRE=$(( TON_FIRE + 1 )) ;; tfrost) TON_FROST=$(( TON_FROST + 1 )) ;; tveil) TON_VEIL=$(( TON_VEIL + 1 )) ;;
      esac
      GOLD=$(( GOLD - price ))
      [[ $id == [WAOHJB].* ]] || logm "Bought: ${SH_LABEL[i]%%  (*} (${price}g)" "$K_LOOT" ;;
    j|J)
      junk_value; (( JUNK )) || { logm "No junk in your bags - everything beats what you wear."; return; }
      for c in "${INV[@]}"; do is_junk "$c" || keep+=("$c"); done
      INV=("${keep[@]}"); GOLD=$(( GOLD + JVAL )); logm "Sold $JUNK junk items for $JVAL gold." "$K_LOOT" ;;
    c|C)                                                         # v5.0: collectables you already own once
      [[ $SHOP == @(general|trader|spice) ]] || return
      col_dupes; (( ${#DUP[@]} )) || { logm "No duplicate collectables in your bags - lock one with [l] to keep it."; return; }
      for c in "${!INV[@]}"; do [[ " ${DUP[*]} " == *" $c "* ]] || keep+=("${INV[c]}"); done
      GOLD=$(( GOLD + DUPV )); logm "Sold ${#DUP[@]} duplicate collectables for $DUPV gold." "$K_LOOT"; INV=("${keep[@]}") ;;
    f|F)
      [[ $SHOP == @(general|trader|spice) ]] || return
      fish_value; (( FISHN )) || { logm "You have no fish to sell."; return; }
      for (( c = 12; c < NMAT; c++ )); do MATS[c]=0; done
      GOLD=$(( GOLD + FISHV )); logm "Sold $FISHN fish for $FISHV gold." "$K_LOOT" ;;
    s|S)
      (( ${#INV[@]} )) || { logm "Nothing to sell."; return; }
      for c in "${INV[@]}"; do if [[ $c == *! || $c == C.* ]]; then keep+=("$c"); else item_stats "$c"; total=$(( total + ISELL )); fi; done
      (( ${#INV[@]} > ${#keep[@]} )) || { logm "Everything in your bags is locked (or a collectable)."; return; }
      GOLD=$(( GOLD + total )); logm "Sold $(( ${#INV[@]} - ${#keep[@]} )) items for $total gold." "$K_LOOT"; INV=("${keep[@]}") ;;
  esac
}

talk_key() {
  local role=${N_ROLE[$TALK_T]} name=${N_FULL[$TALK_T]}
  [[ -n ${CM_T[$TALK_MID]} ]] || { UI=""; return; }
  case $1 in
    1)
      if (( NOW < WANTED_UNTIL )) && [[ $role == @(general|smith|alchemist|inn|guard|villager|bank) ]]; then
        TALK_LINE="I said get lost, murderer!"; return
      fi
      case $role in
        inn)   rest "${N_FULL[$TALK_T]} serves you a hot stew. HP and MP fully restored."; TALK_LINE="There you go. Come back anytime!" ;;
        merc)  UI=allyshop ;;
        stable) STABLE_SRC=talk UI=stable ;;
        valor) UI=valor ;;
        medic) rest "Senna patches you up. HP and MP fully restored."; TALK_LINE="All done. Try not to get stabbed again." ;;
        guard|villager) ;;
        bank) bank_open ;;
        *) SHOP=$role UI=shop ;;
      esac ;;
    2) TALK_LINE=${RUMORS[RANDOM % ${#RUMORS[@]}]} ;;
    4) case $role in
         smith) CRAFT=forge UI=craft ;; alchemist|hermit) CRAFT=alch UI=craft ;; inn) CRAFT=cook UI=craft ;;
       esac ;;
    5) ql_key ;;
    6) ql_for_npc "$TALK_T" && UI=wares ;;
    7) [[ $role == smith ]] && jewel_open ;;
    8) [[ $role == inn ]] && tal_reset ;;
    9) [[ $role == inn ]] || return                             # v5.0: rooms upstairs
       if (( NOW < WANTED_UNTIL )); then TALK_LINE="No rooms for murderers. Out!"; return; fi
       UI=inn ;;
    3) [[ -n ${N_QK[$TALK_T]}${N_QD[$TALK_T]} ]] || return
       QSRC=$TALK_T
       [[ ${#OFFERS[@]} -gt 0 && $OFFER_LVL == "$LVL" && $OFFER_SRC == "$QSRC" ]] || gen_offers
       UI=quest ;;
    x|X)
      if (( TALK_CONFIRM )); then
        ATK_NPC[$TALK_MID]=1; UI=""; next_attack=0; melee "$TALK_MID"
        logm "You attack $name! The guards will hear of this." "$K_HURT"
      else
        TALK_CONFIRM=1
      fi ;;
  esac
}

quest_key() {
  [[ $1 == [1-9] ]] || return
  local i=$(( $1 - 1 )) keep fresh
  (( i >= 0 && i < ${#OFFERS[@]} )) || return
  if [[ -n $MY_PARTY ]]; then
    if [[ $PARTY_LEADER != "$MY_ID" ]]; then
      logm "Only your party leader (${OP_NAME[$PARTY_LEADER]:-?}) can accept quests for the party." "$K_HURT"; return
    fi
    (( ${#PQ_CODES[@]} < 3 )) || { logm "Your party already has 3 quests." "$K_HURT"; return; }
    send QADD "$MY_ID" "${OFFERS[i]}"
  else
    (( ${#QUESTS[@]} < 3 )) || { logm "You can only track 3 quests at once." "$K_HURT"; return; }
    QUESTS+=("${OFFERS[i]}"); quest_text "${OFFERS[i]}"
    logm "Quest accepted: ${QTXT%% (*}" "$K_ANN"
  fi
  keep=("${OFFERS[@]}"); gen_offers; fresh=${OFFERS[i]}; OFFERS=("${keep[@]}"); OFFERS[i]=$fresh
}

# --- chat ---------------------------------------------------------------------
find_player() {  # name -> FOUND id (same map, any distance) or empty
  local id want=${1,,}
  FOUND=""
  for id in "${!OP_NAME[@]}"; do [[ ${OP_NAME[$id],,} == "$want" ]] && FOUND=$id; done
}

chat_submit() {
  clean_text "$CHAT_BUF"; local t=$CLEAN id list="" a b c i
  t=${t#"${t%%[![:space:]]*}"}
  [[ -n $t ]] || return
  case $t in
    "/p "*)  [[ -n $MY_PARTY ]] || { logm "You are not in a party. /invite <name>"; return; }
             send PCHAT "$MY_ID" "$MY_NAME" "${t#/p }"; chatm "[party] $MY_NAME: ${t#/p }" "$K_PARTY" ;;
    "/w "*)  a=${t#/w }; b=${a#* }; a=${a%% *}
             [[ -n $a && $b != "$a" ]] || { logm "Usage: /w <name> <message>"; return; }
             send WHISP "$MY_ID" "$MY_NAME" "$a" "$b"; chatm "[to $a] $b" "$K_WHISP" ;;
    "/r "*)  [[ -n $LAST_WHISP ]] || { logm "Nobody whispered to you yet. /w <name> <message>"; return; }
             b=${t#/r }; send WHISP "$MY_ID" "$MY_NAME" "$LAST_WHISP" "$b"; chatm "[to $LAST_WHISP] $b" "$K_WHISP" ;;
    /bell)   BELL_ON=$(( ! BELL_ON )); save_gfx
             if (( BELL_ON )); then logm "The bell rings again for whispers, invites and your name." "$K_SYS"; else logm "The bell is off. /bell turns it on again." "$K_SYS"; fi ;;
    "/invite "*) send INV "$MY_ID" "$MY_NAME" "${t#/invite }" ;;
    /accept) send PACC "$MY_ID" ;;
    /leave)  send PLEAVE "$MY_ID"; logm "You leave your party." ;;
    "/me "*) send EMOTE "$MY_ID" "$MY_NAME" "${t#/me }"; chatm "* $MY_NAME ${t#/me }" "$K_WHISP" ;;
    /home)   recall ;;
    /trade)  trade_cmd "" ;;
    "/trade "*) a=${t#/trade }; trade_cmd "${a%% *}" ;;
    "/give "*)
      a=${t#/give }; b=${a#* }; a=${a%% *}
      find_player "$a"
      [[ -n $FOUND ]] || { logm "Nobody called '$a' is online."; return; }
      cheb $(( ${OP_X[$FOUND]:-999} - PX )) $(( ${OP_Y[$FOUND]:-999} - PY ))
      [[ ${OP_MAP[$FOUND]} == "$CUR_MAP" ]] && (( D <= 3 )) || { logm "${OP_NAME[$FOUND]} must stand right next to you."; return; }
      if [[ $b =~ ^#([1-9]|1[0-9]|20)$ ]]; then
        i=$(( ${b#\#} - 1 )); (( i < ${#INV[@]} )) || { logm "You have no item #${b#\#}."; return; }
        c=${INV[i]%!}; unset "INV[i]"; INV=("${INV[@]}")
        send GIVE "$MY_ID" "$MY_NAME" "${OP_NAME[$FOUND]}" I "$c"
        item_name "$c" "$CLS"; logm "You hand $INAME to ${OP_NAME[$FOUND]}." "$K_LOOT"
      elif isnum "$b" && (( b > 0 )); then
        (( b <= GOLD )) || { logm "You only have $GOLD gold."; return; }
        GOLD=$(( GOLD - b )); send GIVE "$MY_ID" "$MY_NAME" "${OP_NAME[$FOUND]}" G "$b"
        logm "You give $b gold to ${OP_NAME[$FOUND]}." "$K_LOOT"
      else
        logm "Usage: /give <name> <gold>   or   /give <name> #<item number>"
      fi ;;
    "/symbol "*)
      a=${t#/symbol }
      if valid_sym "$a"; then SYM=$a; POS_DIRTY=1 MAP_DIRTY=1; logm "Your symbol is now $SYM."; else logm "Pick one printable character, e.g. /symbol &"; fi ;;
    "/color "*)
      a=${t#/color }; b=""
      for i in "${!P_COLN[@]}"; do [[ ${P_COLN[i]} == "${a,,}" || $a == "$(( i + 1 ))" ]] && b=$i; done
      if [[ -n $b ]]; then COLR=$b; POS_DIRTY=1 MAP_DIRTY=1; logm "Your color is now ${P_COLN[b]}."
      else logm "Colors: ${P_COLN[*]}  (or 1-${#P_COLN[@]})"; fi ;;
    /who)
      list="$SYM $MY_NAME (${C_NAME[CLS]} $LVL)"
      for id in "${!OP_NAME[@]}"; do list+=", ${OP_SYM[$id]:-@} ${OP_NAME[$id]} (${C_NAME[${OP_CLS[$id]:-0}]} ${OP_LVL[$id]})"; done
      logm "Online: $list" ;;
    /admin|"/admin "*) adm_cmd "${t#/admin}" ;;
    /help)   logm "/p party  /w name msg  /invite /accept /leave  /trade name  /give name gold|#item  /symbol c  /color c  /who  /me  /home  /r reply  /bell${IS_ADMIN/#1/  /admin}  - [tab] names  [↑] last lines" ;;
    /*)      logm "Unknown command ${t%% *} - try /help" ;;
    *)       send CHAT "$MY_ID" "$MY_NAME" "$t"; chatm "$MY_NAME: $t" "$K_CHAT"; MY_SAY=$t MY_SAYT=$(( NOW + 5000 )) MAP_DIRTY=1 ;;
  esac
}


# --- network messages -----------------------------------------------------------
send_pos() {
  local al=-1; (( ALLY >= 0 )) && [[ $ALY_MAP == "$CUR_MAP" ]] && al=$ALLY
  local mt=-; (( RIDING )) && mt=$MNT_CUR
  send POS "$MY_ID" "$MY_NAME" "$CLS" "$LVL" "$CUR_MAP" "$PX" "$PY" "$HP" "$MAXHP" "$DEAD" "$SYM" "$COLR" "$al" "$AX" "$AY" "$mt"
  last_pos=$NOW POS_DIRTY=0
}

op_del() {
  unset "OP_NAME[$1]" "OP_MAP[$1]" "OP_X[$1]" "OP_Y[$1]" "OP_CLS[$1]" "OP_LVL[$1]" "OP_HP[$1]" "OP_MAX[$1]" \
        "OP_DEAD[$1]" "OP_SEEN[$1]" "OP_SYM[$1]" "OP_COL[$1]" "OP_SAY[$1]" "OP_SAYT[$1]" "OP_WANTED[$1]" "GLY[p$1]" \
        "OP_ALY[$1]" "OP_AX[$1]" "OP_AY[$1]" "OP_MNT[$1]" "GLYH[p$1]"
  MAP_DIRTY=1
}

num() { [[ ${#1} -le 9 && $1 == @(0|[1-9]*([0-9])) ]]; }           # = isnum, without a second call

valid_quest() {  # format + range check (K: monster type, D: dungeon, T: known NPC; C B E G: v3.0)
  [[ $1 =~ ^([KDTCBEG])\.(0|[1-9][0-9]{0,8})(\.(0|[1-9][0-9]{0,8})){4}$ ]] || return 1
  local k=${BASH_REMATCH[1]} t=${BASH_REMATCH[2]}
  case $k in
    K|C|B) (( t < NM )) && [[ ${M_KIND[t]} == 0 ]] ;;
    D) (( t < NDT )) ;;
    T) (( t < NM )) && [[ -n ${N_FULL[$t]} ]] ;;
    E) (( t < NSPOT )) ;;
    G) (( t < NFISHE )) ;;
  esac
}

cli_srv() {  # typ fields...
  local typ=$1 a=$2 b=$3 c=$4 d=$5 e=$6 f=$7 g=$8 h=$9 x n old new q list=()
  case $typ in
    "AR$MY_ID") case $a in
                  ACK)  acct_acked ;;
                  AUTH) acct_nudged ;;                                  # v6.3: the server forgot us (it restarted)
                  OK)   acct_back ;;
                  DENY) if [[ $b == KICK ]]; then acct_kicked "$c"; else logm "The server refused the login: $c" "$K_HURT"; fi ;;
                  BAD) ACK_PEND=0; logm "The server did not accept your save: $b" "$K_HURT" ;;
                  ADMIN) adm_flag "$b" ;;                               # v6.4: admin tools (04l_admin.sh)
                  ADM)   adm_effect "$b" "$c" "$d" "$e" ;;
                esac ;;
    MON)  [[ $a == "$CUR_MAP" ]] && num "$b" && num "$c" && num "$d" && num "$e" && num "$f" && num "$g" || return
          (( c < NM )) || return
          [[ ${SEEN:c:1} == 0 ]] && SEEN="${SEEN:0:c}1${SEEN:c+1}"
          cm_set "$b" "$c" "$d" "$e" "$f" "$g"; MAP_DIRTY=1
          CM_CH[$b]=0; [[ $h =~ ^[1-9][0-9]?$ ]] && (( h <= NCHP )) && CM_CH[$b]=$h ;;
    MMOV) num "$b" && [[ $a == "$CUR_MAP" ]] && num "$c" && num "$d" || return
          if [[ -z ${CM_T[$b]} ]]; then                      # v6.3: a monster we have not heard of (it walked into range)
            num "$e" && num "$f" && num "$g" && (( e < NM )) || return
            [[ ${SEEN:e:1} == 0 ]] && SEEN="${SEEN:0:e}1${SEEN:e+1}"
            cm_set "$b" "$e" "$c" "$d" "$f" "$g"
            CM_CH[$b]=0; [[ $h =~ ^[1-9][0-9]?$ ]] && (( h <= NCHP )) && CM_CH[$b]=$h
          else cm_move "$b" "$c" "$d"; fi
          (( c - PX < VW / 2 + 2 && PX - c < VW / 2 + 2 && d - PY < VH / 2 + 2 && PY - d < VH / 2 + 2 )) && MAP_DIRTY=1 ;;
    MHP)  num "$b" && [[ $a == "$CUR_MAP" && -n ${CM_T[$b]} ]] && num "$c" || return
          CM_HP[$b]=$c ;;
    MDIE) num "$b" && [[ $a == "$CUR_MAP" && -n ${CM_T[$b]} ]] || return
          x=${CM_T[$b]}
          if [[ $c != - ]] && (( M_KIND[x] != 3 )) && [[ $c == "$MY_NAME" || $TARGET == "$b" ]]; then logm "${M_NAME[x]} dies." "$K_HIT"; fi
          [[ $TARGET == "$b" ]] && TARGET=""
          [[ $UI == @(talk|shop) && $TALK_MID == "$b" ]] && UI=""
          cm_del "$b"; MAP_DIRTY=1 ;;
    MATK) [[ $a == "$CUR_MAP" && $c == "$MY_ID" ]] && num "$b" && num "$d" || return
          [[ $e =~ ^[0-6]$ ]] || e=0
          [[ $f == @(poison|bleed|burn|chill|stun|weaken) ]] || f=""
          mname "$b"; take_damage "$d" "$MN" "$b" "$e" "$f" ;;
    LOOT) [[ $a == "$MY_ID" ]] || return
          if [[ $b =~ ^g([0-9]{1,3})$ ]]; then x=${BASH_REMATCH[1]}; (( x < NMAT )) && gem_kq "$x" && gem_get "$x"
          elif [[ $b =~ ^i:(.{3,40})$ ]] && x=${BASH_REMATCH[1]} && valid_item "$x"; then   # v4.5: mythic, raid and invasion rewards
            if (( ${#INV[@]} >= BAGS )); then logm "Your bags are full - a reward was lost!" "$K_HURT"
            else INV+=("$x"); NEWG[$x]=1; item_name "$x" "$CLS"; logm "${EMJ[loot]}Reward: $INAME" $'\e['"${ICOL}m"; fi
          fi ;;
    REW)  [[ $a == "$MY_ID" ]] && num "$b" && num "$c" && num "$e" || return
          (( e < NM )) || return
          reward "$b" "$c" "$d" "$e"; dly_kill "$e" "${f:-0}"; col_kill "$e" "${f:-0}" ;;
    MDONE) [[ $a == "$MY_ID" ]] && num "$b" && num "$c" && num "$d" && num "$e" || return
          (( b <= MYTH_MAX && c <= 2 && e <= 5000 )) && myth_done "$b" "$c" "$d" "$e" ;;
    EVREW) [[ $a == "$MY_ID" ]] && num "$b" && num "$c" && num "$d" || return
          (( b <= 500 && c <= 999999 && d <= 99999 )) || return
          INVK=$(( INVK + 1 )); logm "The town is saved - thank you, defender!" "$K_ANN"
          valor_add "$b" invasion; GOLD=$(( GOLD + d )); gain_xp "$c"; dly_ev inv; ach_check ;;
    PARTY)
      [[ $a =~ ^p[0-9]+$ ]] || return
      if [[ ",$c," == *",$MY_ID,"* ]]; then
        [[ $MY_PARTY != "$a" ]] && logm "You are now in a party. Talk with /p, leave with /leave." "$K_PARTY"
        MY_PARTY=$a PARTY_LEADER=$b; IFS=, read -r -a PARTY_IDS <<< "$c"
      elif [[ $MY_PARTY == "$a" ]]; then
        MY_PARTY="" PARTY_LEADER="" PARTY_IDS=()
        logm "You are no longer in a party." "$K_PARTY"
        pq_to_personal
      fi
      MAP_DIRTY=1 ;;
    PQUEST)
      [[ $a == "$MY_PARTY" && -n $a ]] || return
      IFS=, read -r -a list <<< "$b"
      new=()
      for q in "${list[@]}"; do valid_quest "$q" && new+=("$q"); done
      for q in "${new[@]}"; do
        old=0; for x in "${PQ_CODES[@]}"; do [[ ${x%.*.*.*.*} == "${q%.*.*.*.*}" ]] && old=1; done
        (( old )) || { quest_text "$q"; logm "New party quest: ${QTXT%% (*}  (+25% rewards for everyone)" "$K_PARTY"; }
      done
      PQ_CODES=("${new[@]:0:3}") ;;
    QDONE)
      [[ $a == "$MY_PARTY" && -n $a ]] && num "$b" && num "$c" && valid_quest "$d" || return
      old=0; for x in "${PQ_CODES[@]}"; do [[ ${x%.*.*.*.*} == "${d%.*.*.*.*}" ]] && old=1; done
      (( old && b <= 100000 && c <= 100000 )) || return
      for x in "${!PQ_CODES[@]}"; do [[ ${PQ_CODES[x]%.*.*.*.*} == "${d%.*.*.*.*}" ]] && { unset "PQ_CODES[x]"; break; }; done
      PQ_CODES=("${PQ_CODES[@]}")
      quest_text "$d"
      logm "${EMJ[quest]}PARTY QUEST COMPLETE: ${QTXT%% (*} - +$b XP +$c gold" "$K_ANN"
      GOLD=$(( GOLD + c )); gain_xp "$b" ;;
    PINFO) [[ $a == "$MY_PARTY" && -n $a ]] || return; clean_text "$b"; logm "$CLEAN" "$K_PARTY" ;;
    WANTED)
      [[ $a =~ ^[0-9a-f]{6}$ ]] && [[ $b =~ ^-?[0-9]{1,6}$ ]] || return
      n=$(( 10#${b#-} )); [[ $b == -* ]] && n=0
      if [[ $a == "$MY_ID" ]]; then
        if (( n > 0 )); then
          (( NOW >= WANTED_UNTIL )) && logm "You are WANTED! The guards of Hearthmoor will attack you on sight." "$K_HURT"
          WANTED_UNTIL=$(( NOW + n * 1000 ))
        else
          (( WANTED_UNTIL > NOW )) && logm "You are no longer wanted." "$K_GOOD"
          WANTED_UNTIL=0
        fi
      elif (( n > 0 )); then OP_WANTED[$a]=$(( NOW + n * 1000 ))
      else unset "OP_WANTED[$a]"; fi
      MAP_DIRTY=1 ;;
    PINV) [[ $a == "$MY_ID" ]] || return
          logm "${b//[^A-Za-z0-9_-]/} invites you to a party - type /accept to join." "$K_PARTY"; bell ;;
    INFO) [[ $a == "$MY_ID" ]] || return; clean_text "$b"; logm "$CLEAN" "$K_SYS" ;;
    DSTART)
      [[ $a =~ ^D[0-9]+$ && $b =~ ^(0|[1-9][0-9]?)$ ]] && (( b < NDT )) && num "$c" || return
      [[ ",$e," == *",$MY_ID,"* ]] || return
      enter_instance "$a" "$b" "$c"
      IN_MK=0 IN_LIM=0 IN_T0=$NOW                               # v4.5: mythic level, time limit (ms), time already used
      if [[ $f =~ ^(0|[1-9][0-9]?)$ && $g =~ ^(0|[1-9][0-9]{0,6})$ ]] && (( f <= MYTH_MAX )); then   # (no leading zeros: octal)
        IN_MK=$f IN_LIM=$g; [[ $h =~ ^(0|[1-9][0-9]{0,6})$ ]] && IN_T0=$(( NOW - h ))
        (( IN_MK )) && { myth_txt "$IN_MK"; logm "MYTHIC $MYT - the clock is running: $(( IN_LIM / 60000 )) minutes!" "$K_ANN"; }
      fi ;;
    DCLEAR)
      [[ $a == "$CUR_MAP" ]] || return
      logm "VICTORY! ${b//[^A-Za-z ]/} has fallen. You return to the surface in 10 seconds." "$K_ANN"
      DCLR=$(( DCLR + 1 )); dly_ev dungn; (( D_REQ[CUR_DT] >= 30 )) && dly_ev dung
      clear_until=$(( NOW + 10000 ))
      for x in "${!QUESTS[@]}"; do [[ ${QUESTS[x]} == "D.$CUR_DT."* ]] && quest_done "$x" && break; done
      qev_dungeon "$CUR_DT"
      story_event D "$CUR_DT"; v80_dclear "$CUR_DT" ;;
    DEND) [[ $a == "$CUR_MAP" ]] && leave_instance ;;
    ANN)  clean_text "$a"; logm "$CLEAN" "$K_ANN" ;;
    BOSS) [[ $a == "$CUR_MAP" ]] || return
          if num "$c" && num "$d"; then cheb $(( c - PX )) $(( d - PY )); (( D <= 40 )) || return; fi
          clean_text "$b"; logm "$CLEAN" "$K_HURT" ;;
    CLOCK) num "$a" && (( a < DAYLEN )) || return
           [[ -z $CLK_OFF ]] && DAYPH=""
           CLK_OFF=$(( a - NOW )) ;;
    WEATHER)
      [[ $a =~ ^[0-9]$ && $b =~ ^(-|rain|storm|fog|sand|snow|ash)$ ]] && (( a < NCLS )) && num "$c" || return
      local wr=${WEA_REG[a]//_/ } here=0
      [[ $CUR_MAP == W ]] && { RNAME=""; region_of "$PX" "$PY" nosafe; [[ $RNAME == "$wr" ]] && here=1; }
      if [[ $b == - ]]; then
        (( here && ${WTH_E[a]:-0} > NOW )) && logm "The ${WEA_LABEL[${WTH_K[a]}],,} over the $wr clears up." "$K_SYS"
        WTH_K[a]="" WTH_E[a]=0
      else
        (( c > 600 )) && c=600
        (( ${WTH_E[a]:-0} > NOW )) || {
          if (( here )); then logm "${WEA_START[$b]} the $wr!" "$K_ANN"
          elif [[ $b == @(sand|snow|ash|storm) ]]; then logm "${WEA_START[$b]} the $wr." "$K_SYS"; fi
          [[ $b == ash ]] && ASH_HINT=0
        }
        WTH_K[a]=$b WTH_E[a]=$(( NOW + c * 1000 ))
      fi
      MAP_DIRTY=1 ;;
    WBOSS)
      if num "$a" && num "$b" && num "$c" && num "$d" && (( b < NM )); then WB_CID=$a WB_CT=$b WB_CX=$c WB_CY=$d
      else WB_CID=""; fi ;;
    FX)   [[ $a == "$CUR_MAP" ]] && add_fx "$b" "$c" ;;
  esac
}

cli_line() {
  local line=$1 tag typ from a b c d e f g h i j k l q r nm
  (( ${#line} <= 2048 )) || return
  if [[ $line == SM1\|@(MON|MMOV|MHP|MDIE|MATK)\|srv\|* ]]; then   # most of what the server says is about other maps:
    r=${line#SM1|*|srv|}; [[ ${r%%|*} == "$CUR_MAP" ]] || return     # drop it before parsing (v6.0: ~10x faster)
  fi
  IFS='|' read -r tag typ from a b c d e f g h i j k l q r <<< "$line"
  [[ $tag == SM1 && $from != "$MY_ID" ]] || return
  if [[ $from == srv ]]; then LAST_SRV=$NOW; cli_srv "$typ" "$a" "$b" "$c" "$d" "$e" "$f" "$g" "$h"; return; fi
  [[ $from =~ ^[0-9a-f]{6}$ ]] || return
  nm=${a//[^A-Za-z0-9_-]/}; nm=${nm:0:12}; [[ -n $nm ]] || nm=anon
  case $typ in
    HELLO) [[ -z ${OP_NAME[$from]} ]] && logm "$nm has entered the world." "$K_SYS"
           OP_NAME[$from]=$nm OP_SEEN[$from]=$NOW ;;
    POS)   # name cls lvl map x y hp max dead sym col ally ax ay|mount
      [[ $b =~ ^[0-9]$ && $d =~ ^(W|D[0-9]+|H[0-9]{1,8})$ ]] && (( b < NCLS )) && num "$c" && num "$e" && num "$f" && num "$g" && num "$h" || return
      [[ -z ${OP_NAME[$from]} ]] && logm "$nm is here." "$K_SYS"
      valid_sym "$j" || j=@
      if isnum "$k" && (( k < ${#P_COLC[@]} )); then :; else name_color "$nm"; k=$NCI; fi
      OP_NAME[$from]=$nm OP_CLS[$from]=$b OP_LVL[$from]=$c OP_MAP[$from]=$d OP_X[$from]=$e OP_Y[$from]=$f
      OP_HP[$from]=$g OP_MAX[$from]=$h OP_DEAD[$from]=${i:0:1} OP_SEEN[$from]=$NOW OP_SYM[$from]=$j OP_COL[$from]=$k
      if [[ $l =~ ^(0|[1-9][0-9]?)$ ]] && (( l < NALY )) && num "$q" && num "${r%%|*}"; then OP_ALY[$from]=$l OP_AX[$from]=$q OP_AY[$from]=${r%%|*}
      else unset "OP_ALY[$from]"; fi
      x=""; [[ $r == *"|"* ]] && { x=${r#*|}; x=${x%%|*}; }
      if [[ $x =~ ^[0-9]$ ]] && (( x < NMNT )); then OP_MNT[$from]=$x; else unset "OP_MNT[$from]"; fi
      player_glyph "$from" "$j" "$k" "${i:0:1}"
      [[ $d == "$CUR_MAP" ]] && MAP_DIRTY=1 ;;
    BYE)   [[ -n ${OP_NAME[$from]} ]] && logm "$nm has left the world." "$K_SYS"; op_del "$from" ;;
    CHAT)  clean_text "$b"; [[ -n $CLEAN ]] || return
           chatm "$nm: $CLEAN" "$K_CHAT"; OP_SAY[$from]=$CLEAN OP_SAYT[$from]=$(( NOW + 5000 )) MAP_DIRTY=1
           [[ ${CLEAN,,} == *"${MY_NAME,,}"* ]] && bell ;;
    PCHAT) in_party "$from" || return; clean_text "$b"; chatm "[party] $nm: $CLEAN" "$K_PARTY" ;;
    WHISP) [[ ${b,,} == "${MY_NAME,,}" ]] || return; clean_text "$c"; chatm "[$nm whispers] $CLEAN" "$K_WHISP"; LAST_WHISP=$nm; bell ;;
    EMOTE) clean_text "$b"; chatm "* $nm $CLEAN" "$K_WHISP" ;;
    EVT)   clean_text "$b"; logm "* $nm $CLEAN" "$K_SYS" ;;
    HEAL)  [[ $b == "$MY_ID" ]] && num "$c" && (( ! DEAD )) || return
           (( c > 2000 )) && c=2000
           heal_self "$c"; logm "$nm heals you for $c." "$K_GOOD" ;;
    BUFF)  [[ $b == "$MY_ID" ]] && num "$c" || return
           (( c > 16000 )) && c=16000
           if [[ $d == anthem ]]; then anthem_until=$(( NOW + c )); logm "$nm's anthem quickens your step! (faster, +20% damage)" "$K_GOOD"
           else buff_until=$(( NOW + c )); logm "$nm's battle cry fills you with fury! (+40% damage)" "$K_GOOD"; fi ;;
    GIVE)  [[ ${b,,} == "${MY_NAME,,}" ]] || return
           if [[ $c == G ]] && num "$d" && (( d <= 10000000 )); then GOLD=$(( GOLD + d )); logm "$nm gives you $d gold." "$K_LOOT"
           elif [[ $c == I ]] && valid_item "$d"; then logm "$nm hands you something." "$K_LOOT"; add_item "$d"; fi ;;
    FX)    [[ $a == "$CUR_MAP" ]] && add_fx "$b" "$c" ;;
    TREQ|TACC|TOFF|TOK|TCAN) trade_msg "$typ" "$from" "$nm" "$b" "$c" "$d" "$e" "$f" ;;
    RASK|RHAS|RREQ|ROOM|RNO|RSIGN) room_msg "$typ" "$from" "$nm" "$b" "$c" "$d" "$e" ;;     # v5.0: visiting rooms
  esac
}
