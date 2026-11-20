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

acct_login() {  # talks to the world server: loads the hero into CHAR_TEXT ("" = a new hero)
  local tries=0 n total txt="" again
  CHAR_TEXT="" ar_buf=""
  while :; do
    if [[ -z $ACC_PASS ]]; then
      if [[ -n $SHELLMMO_PASS ]]; then ACC_PASS=$SHELLMMO_PASS
      else acct_ask "Password for $MY_NAME: "; ACC_PASS=$ACC_IN; fi
    fi
    if ! acct_pass_ok "$ACC_PASS"; then
      echo "The password needs 4-32 characters (not |)." >&2
      [[ -n $SHELLMMO_PASS ]] && die "bad SHELLMMO_PASS"
      ACC_PASS=""; continue
    fi
    for (( n = 0; n < 5; n++ )); do                 # the world server may still be starting up
      send ALOAD "$MY_ID" "$MY_NAME" "$ACC_PASS" || die "lost the connection"
      acct_wait 3000 && break
      (( n == 0 )) && echo "Waiting for the world server..." >&2
    done
    (( n < 5 )) || die "the world server did not answer - is it running, or older than 6.2?"
    case $AR_K in
      NONE)
        if [[ -z $SHELLMMO_PASS ]]; then
          echo "New hero: $MY_NAME - this name is free." >&2
          acct_ask "Repeat the password: "
          if [[ $ACC_IN != "$ACC_PASS" ]]; then echo "The passwords differ." >&2; ACC_PASS=""; continue; fi
        fi
        if [[ -r $CHAR_FILE ]]; then                  # a hero saved on this computer before 6.2: move it to the server
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

acct_flush() {  # on quit: wait (at most 2 s) until the server confirmed our last saves
  local end
  (( CHAR_REMOTE && net_up && ACK_PEND > 0 )) || return 0
  now_ms; end=$(( NOW + 2000 ))
  while (( ACK_PEND > 0 && NOW < end )); do
    net_poll 50; (( ACK_PEND > 0 )) && sleep 0.05; now_ms
  done
}
