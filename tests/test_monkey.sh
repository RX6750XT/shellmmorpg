#!/usr/bin/env bash
# The monkey: thousands of random keys in every screen, random network lines from friends and strangers,
# time passing - and after every step the hero must still make sense. Any bash error is a bug.
#   bash tests/test_monkey.sh [steps] [seed]
source "$(dirname "$0")/lib.sh"
stub_client
STEPS=${T_ARGS[0]:-1500} RANDOM=${T_ARGS[1]:-4711}
T_ROWS=40 T_COLS=120
stty() { echo "$T_ROWS $T_COLS"; }
exit() { MONKEY_EXIT=1; }                                 # (Q quits the game: not here)
init_explore; init_lights
ERR=$T_TMP/err
declare -A ARROW=([UP]='[A' [DOWN]='[B' [RIGHT]='[C' [LEFT]='[D')
KEYS=(w a s d w a s d w a s d UP DOWN LEFT RIGHT ESC $'\r' ' ' $'\t' $'\x7f' 1 2 3 4 5 6 7 8 9 0 - =
      e r u g i m q b c n v p y x z Z o H f t j k l h '?' '<' '>' , . '[' ']' '+' A B C D E F G I J K L M N O P R S T U V W X Y '/' '!' '#')
UIS=("" inv shop talk quest map way help beasts chatlog prof craft bank allies allyshop talents jewel wares qlog dgate stable valor ach inn visit book guest)
ids=(beefed c0ffee abc123 000000 ffffff 151add 9e1715 0123ab)
garbage=('a[$(touch /tmp/monkey_pwned)]' '-1' '99999999999' '' 'x' '08' '1.5' '$((1/0))' '*' '|' "$(printf '%0400d' 0)" 'C.5' 'U.3' 'W.0.12.3.r4__' 'H1' 'D3' 'W')
pick() { local -n arr=$1; PICK=${arr[RANDOM % ${#arr[@]}]}; }

setup() {
  new_hero $(( RANDOM % NCLS )) $(( 1 + RANDOM % 40 )); GOLD=$(( RANDOM * 10 ))
  INV=(W.0.9.3 U.1 B.5 A.1.4.1! H.2.3.0 J.1.9.2 C.5 C.40 C.$(( NCOL - 1 )) O.0.2.0.__ W.6.5.1.r2__)
  BAGEQ=(4 2 -); bag_cap; BANK=(U.2 W.1.7.3 C.7) BANKG=5000
  for (( i = 0; i < NMAT; i++ )); do MATS[i]=$(( RANDOM % 12 )); done
  POT_H=5 POT_M=5 POT_GH=2 EL_STR=1 SCROLL=3 STORY=$(( RANDOM % NST )) ALLIES=111111111111
  QUESTS=(K.5.10.3.100.50 D.2.1.0.500.300 E.3.1.0.80.40)
  WAYS=$(printf '1%.0s' $(seq ${#WAYSTONES[@]})) SEEN=; for (( i = 0; i < NM; i++ )); do SEEN+=1; done
  ROOM_T=$(( RANDOM % 5 )); v50_fix; rent_week; ROOM_PAID=$RWK; ROOMD[0]=C.9
  CUR_MAP=W PX=88 PY=32
  CM_T=() CM_X=() CM_Y=() CM_HP=() CM_MAX=() CM_POS=() CMR=()
  cm_set 900 2 90 33 20 34; cm_set 901 19 86 33 900 900; cm_set 902 23 89 32 900 900; cm_set 903 $BANK0 87 31 900 900
  cm_set 904 21 89 31 900 900; cm_set 905 $Q_HESK 88 30 900 900; cm_set 906 $NPC45 87 33 900 900; cm_set 907 $NODE0 90 31 3 3
  OP_NAME[beefed]=Mira OP_MAP[beefed]=W OP_X[beefed]=87 OP_Y[beefed]=32 OP_CLS[beefed]=3 OP_LVL[beefed]=24
  OP_HP[beefed]=50 OP_MAX[beefed]=300 OP_DEAD[beefed]=0 OP_SEEN[beefed]=$NOW OP_SYM[beefed]=M OP_COL[beefed]=3
  player_glyph beefed M 3 0
  explore_here; layout
}

sane() {  # the hero must still make sense
  local c why=""
  for c in "${INV[@]}" "${BANK[@]}" "${ROOMC[@]}"; do valid_item "${c%!}" || why+="bad item '$c' "; done
  for c in "${ROOMD[@]}"; do [[ $c == - ]] || valid_item "$c" || why+="bad display '$c' "; done
  for c in EQW EQA; do valid_item "${!c%!}" || why+="$c='${!c}' "; done
  (( GOLD >= 0 && BANKG >= 0 )) || why+="gold $GOLD/$BANKG "
  (( HP <= MAXHP && MP <= MAXMP && MP >= 0 )) || why+="hp $HP/$MAXHP mp $MP/$MAXMP "
  for c in "${!MATS[@]}"; do (( MATS[c] >= 0 )) || why+="mats[$c]=${MATS[c]} "; done
  (( POT_H >= 0 && POT_M >= 0 && POT_GH >= 0 && POT_GM >= 0 && SCROLL >= 0 )) || why+="potions "
  [[ $CUR_MAP =~ ^(W|D[0-9]+|H[0-9]{1,8})$ ]] || why+="map '$CUR_MAP' "
  if [[ $CUR_MAP == W ]] && ! p_walk W "$PX" "$PY"; then why+="standing in '$T' at $PX,$PY "; fi
  (( ${#QUESTS[@]} <= 3 )) || why+="${#QUESTS[@]} quests "
  (( ${#INV[@]} <= BAGS + 4 )) || why+="bags ${#INV[@]}/$BAGS "
  [[ -z $why ]] || { fail "step $1 ($2): $why"; return 1; }
}

netline() {  # a random line from a friend, a stranger or the server
  local typ from f=() i
  pick ids; from=$PICK
  case $(( RANDOM % 4 )) in
    0) from=srv; pick SRVT; typ=$PICK ;;
    *) pick CLIT; typ=$PICK ;;
  esac
  for (( i = 0; i < 9; i++ )); do
    case $(( RANDOM % 5 )) in
      0) pick garbage; f+=("$PICK") ;;
      1) f+=("$MY_ID") ;; 2) f+=("$CUR_MAP") ;;
      *) f+=("$(( RANDOM % 120 ))") ;;
    esac
  done
  local IFS='|'; LINE="SM1|$typ|$from|${f[*]}"
}
SRVT=(MON MMOV MHP MDIE MATK LOOT REW MDONE EVREW PARTY PQUEST QDONE PINFO WANTED PINV INFO DSTART DCLEAR DEND ANN BOSS CLOCK WEATHER WBOSS FX)
CLIT=(HELLO POS BYE CHAT PCHAT WHISP EMOTE EVT FX HEAL BUFF GIVE TREQ TACC TCAN TOFF TOK RASK RHAS RREQ ROOM RNO RSIGN)

for g in ascii hd; do
  GFX=$g; set_gfx; setup
  : > "$ERR"
  for (( s = 0; s < STEPS; s++ )); do
    NOW=$(( NOW + RANDOM % 400 ))
    r=$(( RANDOM % 100 ))
    if (( r < 6 )); then pick UIS; UI=$PICK; [[ $UI == talk || $UI == shop ]] && { TALK_MID=902 TALK_T=23 SHOP=general; }
      [[ $UI == bank ]] && { TALK_MID=903 TALK_T=$BANK0; bank_open; }
      what="open $UI"
    elif (( r < 20 )); then netline; what="net $LINE"; cli_line "$LINE" 2>> "$ERR"
    elif (( r < 22 )); then what="room"; [[ $CUR_MAP == W ]] && ROOM_T=$(( 1 + RANDOM % 4 )) && v50_fix && room_home 2>> "$ERR"
    elif (( r < 23 )); then what="dungeon"; d=$(( RANDOM % NDT )); [[ $CUR_MAP == W ]] && enter_instance D$(( 900 + s )) "$d" "$RANDOM" 2>> "$ERR"
    elif (( r < 24 )); then what="leave"; [[ $CUR_MAP != W ]] && leave_instance 2>> "$ERR"
    else
      pick KEYS; k=$PICK; what="key '$k' in '${UI:-map}'"
      if [[ -n ${ARROW[$k]} ]]; then handle_key $'\e' <<< "${ARROW[$k]}" 2>> "$ERR"
      elif [[ $k == ESC ]]; then handle_key $'\e' < /dev/null 2>> "$ERR"
      else handle_key "$k" < /dev/null 2>> "$ERR"; fi
    fi
    if (( NOW >= ${next_sec:-0} )); then next_sec=$(( NOW + 1000 )); regen 2>> "$ERR"; fi
    (( DEAD && NOW >= dead_until )) && respawn 2>> "$ERR"
    (( clear_until && NOW >= clear_until )) && { clear_until=0; leave_instance 2>> "$ERR"; }
    (( ALLY >= 0 )) && aly_tick 2>> "$ERR"
    (( ${#DOT_M[@]} )) && dot_tick 2>> "$ERR"
    [[ -n $GATH_MID ]] && gather_tick 2>> "$ERR"
    (( FISH_ST )) && fish_tick 2>> "$ERR"
    (( s % 7 == 0 )) && { NEED_FULL=1 MAP_DIRTY=1; render > /dev/null 2>> "$ERR"; }
    (( s % 200 == 0 )) && { SENT=(); LOGS=(); CHL_T=() CHL_C=(); }
    if [[ -s $ERR ]]; then fail "step $s ($what, $g): $(head -c 400 "$ERR")"; : > "$ERR"; fi
    sane "$s" "$what" || break
    MONKEY_EXIT=0
  done
  eq "the monkey made all its steps ($g)" "$s" "$STEPS"
done
[[ -e /tmp/monkey_pwned ]] && { fail "a network line ran code"; rm -f /tmp/monkey_pwned; } || ok
t_end
