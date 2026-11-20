#!/usr/bin/env bash
# Fuzzing the world server: a real world, players wandering, and a flood of lines - valid ones,
# nearly valid ones and garbage - from honest players and liars. Any bash error is a bug.
#   bash tests/test_fuzz.sh [lines] [seed]
source "$(dirname "$0")/lib.sh"
LINES=${T_ARGS[0]:-3000} RANDOM=${T_ARGS[1]:-99}
send() { SENT_N=$(( ${SENT_N:-0} + 1 )); return 0; }; slog() { :; }
load_world; now_ms; spawn_world; WH_LAST=$(( NOW / 150 - 1 ))
ERR=$T_TMP/err; : > "$ERR"
ids=(aaaaaa bbbbbb cccccc dddddd eeeeee 000000 ffffff)
pick() { local -n arr=$1; PICK=${arr[RANDOM % ${#arr[@]}]}; }
TYPES=(HELLO POS POS POS HIT HIT HIT DREQ SYNC INV PACC PLEAVE QADD QTALK BYE CHAT AUTH)
garbage=('a[$(touch /tmp/fuzz_pwned)]' '-1' '99999999999' '' 'x' '08' '$((1/0))' '*' 'W' 'D1' 'D99999' 'H123' 'K.5.10.0.100.50'
         'K.999.1.0.1.1' 'D.18.1.0.1.1' "$(printf '%0300d' 0)" '1e3' ' 5' '5 ' '+3')
field() {  # a field that is often almost right
  local mid
  case $(( RANDOM % 8 )) in
    0|1) pick garbage; F=$PICK ;;
    2) F=$(( RANDOM % 500 )) ;;
    3) mid=("${!AL[@]}"); (( ${#mid[@]} )) && F=${mid[RANDOM % ${#mid[@]}]} || F=1 ;;
    4) F=W ;; 5) F=D$(( RANDOM % 45 )) ;; 6) pick ids; F=$PICK ;;
    *) F=$(( RANDOM % 40 )) ;;
  esac
}
for (( n = 0; n < LINES; n++ )); do
  NOW=$(( NOW + RANDOM % 200 ))
  pick ids; from=$PICK; pick TYPES; typ=$PICK; f=()
  if [[ $typ == POS && $(( RANDOM % 2 )) == 0 ]]; then         # an honest position near monsters
    f=("p$from" $(( RANDOM % 10 )) $(( 1 + RANDOM % 40 )) W $(( 60 + RANDOM % 360 )) $(( 10 + RANDOM % 180 )) 100 100 0 @ 1)
  else for (( i = 0; i < 8; i++ )); do field; f+=("$F"); done; fi
  IFS='|'; line="SM1|$typ|$from|${f[*]}"; unset IFS
  srv_line "$line" 2>> "$ERR"
  (( n % 3 == 0 )) && { ai_tick 2>> "$ERR"; (( ${#SYNC_PEND[@]} )) && sync_flush 2>> "$ERR"; }
  (( n % 20 == 0 )) && srv_second 2>> "$ERR"
  if [[ -s $ERR ]]; then fail "line $n: $line -> $(head -c 300 "$ERR")"; : > "$ERR"; fi
done
ok
[[ -e /tmp/fuzz_pwned ]] && { fail "a line ran code"; rm -f /tmp/fuzz_pwned; } || ok
gt "the server answered" "${SENT_N:-0}" 100
t_end
