# ---------------------------------------------------------------------------
#  Module 04k - your hero lives on the server (v6.2): log in, load, save.
#  Nothing is stored on the player's computer. See 03c_accounts.sh and
#  docs/PROTOCOL.md for the messages.
# ---------------------------------------------------------------------------
CHAR_REMOTE=0 CHAR_TEXT="" ACC_PASS="" ACK_PEND=0 SAVE_LOST=0 MIGRATE_FILE="" AR_K="" AR_A="" AR_B="" AR_C="" ar_buf=""
US=$'\x1f'

acct_wait() {  # ms -> waits for one private answer (AR<my id>) into AR_K AR_A AR_B AR_C; 1 = silence, 2 = connection lost
  local end line rc tag typ from
  now_ms; end=$(( NOW + $1 ))
  while now_ms; (( NOW < end )); do
    IFS= read -r -t 0.2 -u 7 line 2>/dev/null; rc=$?
    if (( rc == 0 )); then
      line=$ar_buf$line; ar_buf=""
      [[ $line == "SM1|AR$MY_ID|srv|"* ]] || continue
      IFS='|' read -r tag typ from AR_K AR_A AR_B AR_C <<< "$line"
      return 0
    elif (( rc > 128 )); then ar_buf+=$line
    else return 2; fi
  done
  return 1
}

acct_pass_ok() { valid_pass "$1"; }

acct_ask() {  # prompt -> ACC_IN (not echoed)
  local old=""
  printf '%s' "$1" >&2
  [[ -t 0 ]] || die "no terminal to ask for the password - set SHELLMMO_PASS"
  IFS= read -rs ACC_IN; printf '\n' >&2
}

acct_ask_name() {  # v7.2 (the shared ssh account): who are you? -> MY_NAME
  local tries=0
  while :; do
    printf '%s' "Hero name (new name = new hero): " >&2
    IFS= read -r ACC_IN || die "bye"
    ACC_IN=${ACC_IN//[$'\r\t ']/}
    if [[ $ACC_IN =~ ^[A-Za-z0-9_-]{1,12}$ ]]; then MY_NAME=$ACC_IN; acct_named; return 0; fi
    [[ -n $ACC_IN ]] && echo "Names are 1-12 letters, digits, _ or -." >&2
    (( ++tries < 20 )) || die "no name - bye"
  done
}

acct_named() {  # the name is known now (v7.2: asked after start): what depends on it
  local g
  CHAR_FILE="$DATA_DIR/$MY_NAME.char"
  [[ $MODE == session ]] || return 0
  GFX_FILE="$DATA_DIR/prefs/${MY_NAME,,}.gfx"
  [[ -f $GFX_FILE ]] || return 0
  if [[ -z $SHELLMMO_GFX ]]; then
    g=$(sed -n 's/^GFX=//p' "$GFX_FILE" 2>/dev/null | head -n1)
    [[ $g == @(hd|ascii) ]] && GFX=$g GFX_NEW=0
  fi
  [[ $'\n'$(<"$GFX_FILE") == *$'\n'BELL=0* ]] && BELL_ON=0
  return 0
}

acct_login() {  # talks to the world server: loads the hero into CHAR_TEXT ("" = a new hero)
  local tries=0 n total txt="" again=0
  CHAR_TEXT="" ar_buf=""
  if [[ -n $ASK_NAME ]]; then
    printf '\n  \e[1mshellmmorpg\e[0m - log in with your hero, or type a new name to create one.\n\n' >&2
    [[ -n $MY_NAME ]] && acct_named || acct_ask_name
  fi
  while :; do
    if [[ -z $MY_NAME ]]; then acct_ask_name; tries=0; fi
    if [[ -z $ACC_PASS ]]; then
      if [[ -n $SHELLMMO_PASS && $MODE != session ]]; then ACC_PASS=$SHELLMMO_PASS
      else acct_ask "Password for $MY_NAME: "; ACC_PASS=$ACC_IN; fi
    fi
    if ! acct_pass_ok "$ACC_PASS"; then
      echo "The password needs 4-32 characters (not |)." >&2
      [[ -n $SHELLMMO_PASS ]] && die "bad SHELLMMO_PASS"
      ACC_PASS=""; continue
    fi
    for (( n = 0; n < 5; n++ )); do                 # the world server may still be starting up
      now_ms; (( NOW - ${ACC_SENT:-0} < 800 )) && sleep 0.8     # (the server takes one try per 0.7 s)
      send ALOAD "$MY_ID" "$MY_NAME" "$ACC_PASS" || die "lost the connection"
      now_ms; ACC_SENT=$NOW
      acct_wait 3000 && break
      (( n == 0 )) && echo "Waiting for the world server..." >&2
    done
    (( n < 5 )) || die "the world server did not answer - is it running, or older than 6.2?"
    case $AR_K in
      NONE)
        if [[ -n $ASK_NAME ]]; then                     # (a typo must not quietly make a second hero)
          printf '%s' "There is no hero called $MY_NAME yet. Create $MY_NAME? [y/n] " >&2
          IFS= read -r ACC_IN || die "bye"
          if [[ ${ACC_IN,,} != @(y|yes|j|ja) ]]; then MY_NAME="" ACC_PASS=""; continue; fi
        fi
        if [[ -z $SHELLMMO_PASS ]]; then
          echo "New hero: $MY_NAME - this name is free." >&2
          acct_ask "Repeat the password: "
          if [[ $ACC_IN != "$ACC_PASS" ]]; then echo "The passwords differ." >&2; ACC_PASS=""; continue; fi
        fi
        if [[ $MODE == host && -r $CHAR_FILE ]]; then  # a hero saved on this computer before 6.2: move it to the server (v7.0: only the host's own)
          CHAR_TEXT=$(<"$CHAR_FILE"); MIGRATE_FILE=$CHAR_FILE
          echo "Found your old local hero - it moves to the server." >&2
        fi
        return 0 ;;
      DATA)
        txt=""; n=$AR_A total=$AR_B txt=$AR_C
        while [[ $n =~ ^[0-9]+$ && $total =~ ^[0-9]+$ ]] && (( n < total )); do
          acct_wait 5000 || die "the server stopped answering while sending your hero"
          [[ $AR_K == DATA ]] || continue
          n=$AR_A total=$AR_B txt+=$AR_C
        done
        CHAR_TEXT=${txt//$US/$'\n'}
        return 0 ;;
      DENY)
        echo "Login refused: $AR_B" >&2
        if [[ $AR_A == PASS && -z $SHELLMMO_PASS ]] && (( ++tries < 3 )); then ACC_PASS=""; continue; fi
        if [[ -n $ASK_NAME ]]; then                     # v7.2: back to "who are you?" instead of ending the session
          if [[ $AR_A == NAME && $AR_B =~ ^That\ hero\ is\ called\ ([A-Za-z0-9_-]{1,12})\.$ ]]; then
            MY_NAME=${BASH_REMATCH[1]}; acct_named; continue          # (sid -> Sid: same hero, same password)
          fi
          (( ++again < 10 )) || die "could not log in - bye"
          [[ $AR_A == LOCK ]] && sleep 1
          MY_NAME="" ACC_PASS=""; echo >&2; continue
        fi
        die "could not log in as $MY_NAME" ;;
      *) die "unexpected answer from the server ($AR_K)" ;;
    esac
  done
}

acct_resume() {  # after a lost connection: log in again without loading, then store what happened meanwhile
  send ALOAD "$MY_ID" "$MY_NAME" "$ACC_PASS" keep
  if acct_wait 5000 && [[ $AR_K == OK ]]; then return 0; fi
  [[ $AR_K == DENY ]] && logm "Could not log in again: $AR_B" "$K_HURT"
  net_up=0; exec 7>&- 2>/dev/null
  return 1
}

acct_send_save() {  # text on stdin of $1
  local txt=${1//$'\n'/$US} n total
  total=$(( (${#txt} + 1399) / 1400 ))
  (( total >= 1 && total <= 60 )) || { logm "Your hero is too big to save (${#txt} characters)!" "$K_HURT"; return 1; }
  for (( n = 1; n <= total; n++ )); do
    send ASAVE "$MY_ID" "$n" "$total" "${txt:(n-1)*1400:1400}" || return 1
  done
  ACK_PEND=$(( ACK_PEND + 1 ))
}

acct_acked() {
  (( ACK_PEND > 0 )) && ACK_PEND=$(( ACK_PEND - 1 ))
  if [[ -n $MIGRATE_FILE && -e $MIGRATE_FILE ]]; then
    mv -f "$MIGRATE_FILE" "$MIGRATE_FILE.moved-to-server" 2>/dev/null && logm "Your old local hero file is now $MIGRATE_FILE.moved-to-server (the server has your hero)." "$K_SYS"
    MIGRATE_FILE=""
  fi
}

acct_flush() {  # on quit: wait (at most 4 s) until the server confirmed our last saves
  local end
  (( CHAR_REMOTE && net_up && ACK_PEND > 0 )) || return 0
  now_ms; end=$(( NOW + 4000 ))
  while (( ACK_PEND > 0 && NOW < end )); do
    net_poll 50; (( ACK_PEND > 0 )) && sleep 0.05; now_ms
  done
}

# v6.3: the world server restarted under us (or dropped our session): log in again without blocking -
# AUTH asks for it, OK (the answer to "keep") brings us back into the world
acct_nudged() {
  (( CHAR_REMOTE )) || return
  (( NOW - ${ACC_NUDGED:-0} >= 3000 )) || return
  ACC_NUDGED=$NOW
  send ALOAD "$MY_ID" "$MY_NAME" "$ACC_PASS" keep
}
acct_back() {
  (( CHAR_REMOTE )) || return
  [[ $CUR_MAP != W ]] && leave_instance quiet
  [[ -n $MY_PARTY ]] && { MY_PARTY="" PARTY_LEADER="" PARTY_IDS=(); pq_to_personal; }
  send HELLO "$MY_ID" "$MY_NAME" "$CLS" "$LVL"; send_pos; send SYNC "$MY_ID" W
  ACK_PEND=0 ADM_GOD=0; save_char                     # (a new server forgot the god mode; it sends ADMIN again)
  logm "The world server is back - you are in the world again." "$K_GOOD"
}
acct_kicked() {  # our hero logged in somewhere else: stop at once, and do not save over the new session
  CLS=""                                   # (save_char does nothing without a class)
  KICKED=$1
  exit 0
}
