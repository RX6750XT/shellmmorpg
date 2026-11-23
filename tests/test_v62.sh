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
# --- v8.1: PBKDF2, old hashes move over, 8 characters for new heroes, longer lock-outs, a hash budget ----------
if command -v python3 >/dev/null; then
  eq "python3 is used for PBKDF2" "$ACC_KDF" 1
  read -r salt hsh nm < "$ACC_DIR/tester.pw"
  check "the hero's password is pbkdf2-sha256 with a long salt" test "${salt%:*}" == "pbkdf2-sha256:$ACC_ITER" -a "${#salt}" -ge 40
  eq "...and the hash is 64 hex digits" "${#hsh}" 64
  acc_kdf 000102030405060708090a0b0c0d0e0f "pass1234" 1000
  eq "PBKDF2 is the real thing" "$AH" "$(python3 -c 'import hashlib; print(hashlib.pbkdf2_hmac("sha256", b"pass1234", bytes(range(16)), 1000).hex())')"
  acc_store_pw salty Salty pass1234; read -r s1 _ < "$ACC_DIR/salty.pw"; acc_store_pw salty Salty pass1234; read -r s2 _ < "$ACC_DIR/salty.pw"
  check "every password gets its own salt" test "$s1" != "$s2"
  eq "the password file is private" "$(stat -c %a "$ACC_DIR/salty.pw")" 600
  # a hero from before 8.1: one sha256, a 4-character password
  osalt=0a1b2c3d4e5f; oh=$(printf '%s:%s' "$osalt" "abcd" | sha256sum); printf '%s %s %s\n' "$osalt" "${oh%% *}" Oldie > "$ACC_DIR/oldie.pw"
  printf 'version=2\nCLS=1\nLVL=7\n' > "$ACC_DIR/oldie.char"
  NOW=$(( NOW + 5000 )); SENT=()
  srv_line "SM1|ALOAD|01d001|Oldie|abcd"; eq "an old hero logs in with the old (short) password" "${SENT[0]:0:24}" "AR01d001 srv DATA 1 1 ve"
  read -r salt hsh nm < "$ACC_DIR/oldie.pw"
  check "...and the password is pbkdf2 now" test "${salt%%:*}" == pbkdf2-sha256
  eq "...for the same hero" "$nm" Oldie
  srv_drop 01d001; acc_forget 01d001; NOW=$(( NOW + 5000 )); SENT=()
  srv_line "SM1|ALOAD|01d002|Oldie|abcd"; eq "...and it still logs in" "${SENT[0]:0:20}" "AR01d002 srv DATA 1 "
  srv_drop 01d002; acc_forget 01d002
fi
NOW=$(( NOW + 5000 )); SENT=()
srv_line "SM1|ALOAD|5e0001|shorty|abc1234"; eq "a new hero needs 8 characters" "${SENT[-1]}" "AR5e0001 srv DENY PASS A new hero needs a password of 8-32 characters."
NOW=$(( NOW + 1000 ))
srv_line "SM1|ALOAD|5e0001|shorty|abcd1234"; eq "...8 are fine" "${SENT[-1]}" "AR5e0001 srv NONE"
check "...and nothing is stored before the first save" test ! -e "$ACC_DIR/shorty.pw"
# lock-outs: 5 wrong passwords lock for a minute, the next 5 for two
lockout() {  # -> SENT[-1] after five wrong passwords
  local i
  for (( i = 0; i < 5; i++ )); do NOW=$(( NOW + 1000 )); srv_line "SM1|ALOAD|bad00$i|tester|wrong$i"; done
}
NOW=$(( NOW + 5000 )); lockout; SENT=()
NOW=$(( NOW + 1000 )); srv_line "SM1|ALOAD|bad010|tester|pass1234"; eq "five wrong passwords: locked for a minute" "${SENT[-1]}" "ARbad010 srv DENY LOCK Too many wrong passwords - try again in 1 minute(s)."
NOW=$(( NOW + 60000 )); lockout; SENT=()
NOW=$(( NOW + 1000 )); srv_line "SM1|ALOAD|bad011|tester|pass1234"; eq "the next lock-out lasts two" "${SENT[-1]}" "ARbad011 srv DENY LOCK Too many wrong passwords - try again in 2 minute(s)."
for (( k = 0; k < 8; k++ )); do NOW=$(( NOW + 1800000 )); lockout; done; SENT=()
NOW=$(( NOW + 1000 )); srv_line "SM1|ALOAD|bad012|tester|pass1234"; eq "...never more than 30" "${SENT[-1]}" "ARbad012 srv DENY LOCK Too many wrong passwords - try again in 30 minute(s)."
NOW=$(( NOW + 1800000 )); SENT=()
srv_line "SM1|ALOAD|bad013|tester|pass1234"; eq "the right password after the lock" "${SENT[0]:0:20}" "ARbad013 srv DATA 1 "
srv_drop bad013; acc_forget bad013
NOW=$(( NOW + 5000 )); lockout; SENT=()
NOW=$(( NOW + 1000 )); srv_line "SM1|ALOAD|bad014|tester|pass1234"; eq "...starts over at a minute" "${SENT[-1]:0:68}" "ARbad014 srv DENY LOCK Too many wrong passwords - try again in 1 min"
# at most 5 hashes a second (a hash takes the world server ~50 ms)
NOW=$(( NOW + 60000 )); SENT=()
for i in 1 2 3 4 5 6; do h=tester; (( i % 2 )) || h=salty; srv_line "SM1|ALOAD|b0b00$i|$h|nope$i"; done
eq "five password checks in a second" "${SENT[4]}" "ARb0b005 srv DENY PASS Wrong password."
eq "...the sixth waits (BUSY)" "${SENT[5]}" "ARb0b006 srv DENY BUSY The server is busy - one moment."
t_end
