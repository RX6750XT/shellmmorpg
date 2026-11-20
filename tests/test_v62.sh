#!/usr/bin/env bash
# v6.2: heroes live on the server - save text through the protocol, the server's storage, hostile data
source "$(dirname "$0")/lib.sh"
stub_client
new_hero 3 25
INV=(W.0.3.0 U.3); GOLD=4242; SYM=';'; SC_ITEMS=(W.1.2.1); SC_G=77
CHAR_REMOTE=1 ACK_PEND=0

# --- the client sends its hero in chunks, nothing touches the disk --------------------------------------------
rm -f "$CHAR_FILE"; SENT=(); save_char
check "no local file is written" test ! -e "$CHAR_FILE"
n=${#SENT[@]}; ge "at least one ASAVE" "$n" 1; eq "one acknowledgement is awaited" "$ACK_PEND" 1
txt=""; i=0
for l in "${SENT[@]}"; do
  IFS=' ' read -r typ id k total chunk <<< "$l"
  [[ $typ == ASAVE && $id == "$MY_ID" ]] || fail "bad line $l"
  (( ${#l} < 1500 )) || fail "line too long (${#l})"
  i=$(( i + 1 )); eq "chunk $i is numbered" "$k/$total" "$i/$n"
  txt+=$chunk
done
CHAR_TEXT=${txt//$US/$'\n'}
GOLD=0 INV=() SC_ITEMS=() SC_G=0 SYM=@; load_char
eq "gold survives the trip" "$GOLD" 4242; eq "inventory" "${INV[*]}" "W.0.3.0 U.3"; eq "symbol" "$SYM" ";"
eq "the shared chest is part of the hero" "${SC_ITEMS[*]}/$SC_G" "W.1.2.1/77"

# --- the server accepts it exactly like that ------------------------------------------------------------------
ACCT_ON=1; acc_init; ACC_DIR=$T_TMP/chars; mkdir -p "$ACC_DIR"; slog() { :; }
SENT=(); now_ms
srv_line "SM1|ALOAD|abc123|tester|pass1234"; eq "a free name" "${SENT[-1]}" "ARabc123 srv NONE"
SENT=()
t=${CHAR_TEXT//$'\n'/$US}; total=$(( (${#t} + 1399) / 1400 ))
for (( k = 1; k <= total; k++ )); do srv_line "SM1|ASAVE|abc123|$k|$total|${t:(k-1)*1400:1400}"; done
eq "the server acknowledges" "${SENT[-1]}" "ARabc123 srv ACK"
eq "...and stores exactly the text" "$(<"$ACC_DIR/tester.char")" "$CHAR_TEXT"
check "...with a hashed password" test -s "$ACC_DIR/tester.pw"
grep -q pass1234 "$ACC_DIR/tester.pw" && fail "the password is stored in the clear" || ok
srv_drop abc123; NOW=$(( NOW + 5000 )); SENT=()
srv_line "SM1|ALOAD|def456|tester|pass1234"; eq "login sends the hero back (DATA 1/$total)" "${SENT[0]:0:$(( 20 + ${#total} ))}" "ARdef456 srv DATA 1 $total"
NOW=$(( NOW + 5000 )); srv_drop def456; SENT=()
srv_line "SM1|ALOAD|def456|tester|badpass"; eq "wrong password" "${SENT[-1]}" "ARdef456 srv DENY PASS Wrong password."

# --- hostile saves ------------------------------------------------------------------------------------------
srv_line "SM1|ALOAD|aaa111|mallory|pass1234"; SENT=()
for bad in 'x' 'version=2' $'version=2\nCLS=1\n$(touch /tmp/pwned)' $'version=2\nLVL=1' $'version=2\nCLS=1\nA=b\x01c'; do
  srv_line "SM1|ASAVE|aaa111|1|1|${bad//$'\n'/$US}"
  eq "refused: ${bad:0:20}" "${SENT[-1]}" "ARaaa111 srv BAD not a hero"
done
check "nothing was written for mallory" test ! -e "$ACC_DIR/mallory.char"
srv_line "SM1|ASAVE|bbb222|1|1|version=2${US}CLS=1"; check "no session, no save" test ! -e "$ACC_DIR/bbb222.char"
srv_line "SM1|ALOAD|ccc333|../etc|pass1234"; eq "names cannot be paths" "${SENT[-1]:0:22}" "ARccc333 srv DENY NAME"
srv_line "SM1|ALOAD|ccc333|x|a|b"; eq "bad passwords are refused" "${SENT[-1]:0:22}" "ARccc333 srv DENY PASS"
t_end
