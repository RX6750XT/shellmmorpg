# ---------------------------------------------------------------------------
#  Module 03c - heroes live on the server (v6.2). A client logs in with
#  ALOAD name password; the server answers privately (AR<id>) with the saved
#  hero in chunks (DATA) or NONE (a new hero: it is created by the first
#  ASAVE). ASAVE sends the hero's save text in chunks of at most 1400
#  characters, newlines written as the unit separator (\x1f).
#  The hub delivers ALOAD/ASAVE to the world server only and AR<id> to the
#  player <id> only (python3 and socat hubs).
# ---------------------------------------------------------------------------
ACC_DIR="$DATA_DIR/chars" ACCT_ON=0 ACC_HASHER="" ACC_CHUNK=1400 ACC_MAXCH=60 ACC_STALE=8000
declare -A ACC_NAME=() ACC_NEW=() ACC_PASS=() ACC_BUF=() ACC_NS=() ACC_SEEN=() ACC_FAIL=() ACC_LOCK=() ACC_RATE=() ACC_SVN=() ACC_SVT=()
US=$'\x1f'

acc_init() {
  mkdir -p "$ACC_DIR" && chmod 700 "$ACC_DIR" 2>/dev/null
  if command -v sha256sum >/dev/null 2>&1; then ACC_HASHER="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then ACC_HASHER="shasum -a 256"
  else ACC_HASHER="cksum"; fi
}

acc_hash() {  # salt password -> AH
  AH=$(printf '%s:%s' "$1" "$2" | $ACC_HASHER 2>/dev/null); AH=${AH%% *}
  [[ -n $AH ]] || AH=none
}

valid_pass() { local LC_ALL=C; [[ ${#1} -ge 4 && ${#1} -le 32 && $1 != *[^\ -{}-~]* ]]; }   # printable ASCII, no |

acc_reply() { send "AR$1" srv "${@:2}"; }

acc_valid_text() {  # a hero's save text: version line, KEY=printable lines, sane size
  local LC_ALL=C line n=0
  (( ${#1} > 0 && ${#1} <= 60000 )) || return 1
  [[ $1 == version=2* ]] || return 1
  while IFS= read -r line; do
    n=$(( n + 1 ))
    [[ $line =~ ^[A-Za-z][A-Za-z0-9_]*=[\ -~]*$ ]] || return 1
  done <<< "$1"
  (( n <= 400 )) && [[ $1 == *$'\n'CLS=[0-9]* ]]
}

acc_online() {  # name id -> 0 if somebody else is logged in as that name right now (stale sessions are dropped)
  local i
  for i in "${!ACC_NAME[@]}"; do
    [[ $i != "$2" && ${ACC_NAME[$i],,} == "${1,,}" ]] || continue
    if (( NOW - ${ACC_SEEN[$i]:-0} > ACC_STALE )); then srv_drop "$i"; acc_forget "$i"; continue; fi
    return 0
  done
  return 1
}

declare -A ACC_NUDGE=()
acc_nudge() {  # a player we do not know (the server restarted, or the session timed out): please log in again
  (( NOW - ${ACC_NUDGE[$1]:-0} >= 5000 )) || return
  ACC_NUDGE[$1]=$NOW
  (( ${#ACC_NUDGE[@]} > 500 )) && ACC_NUDGE=()
  acc_reply "$1" AUTH
}

acc_kick() {  # name new-id: end every other session of that hero
  local i
  for i in "${!ACC_NAME[@]}"; do
    [[ $i != "$2" && ${ACC_NAME[$i],,} == "${1,,}" ]] || continue
    acc_reply "$i" DENY KICK "$1 logged in somewhere else."
    slog "! $1 ($i) taken over by $2"
    srv_drop "$i"; acc_forget "$i"
  done
}

acc_forget() { unset "ACC_NAME[$1]" "ACC_NEW[$1]" "ACC_PASS[$1]" "ACC_BUF[$1]" "ACC_NS[$1]" "ACC_SEEN[$1]" "ACC_RATE[$1]" "ACC_SVN[$1]" "ACC_SVT[$1]"; }

srv_aload() {  # id name password [keep]
  local id=$1 name=$2 pw=$3 keep=$4 key salt hsh nm n total i txt chunk
  [[ $name =~ ^[A-Za-z0-9_-]{1,12}$ ]] || { acc_reply "$id" DENY NAME "Names are 1-12 letters, digits, _ or -."; return; }
  valid_pass "$pw" || { acc_reply "$id" DENY PASS "The password needs 4-32 characters (not |)."; return; }
  key=${name,,}
  (( NOW - ${ACC_RATE[$id]:-0} >= 700 )) || { acc_reply "$id" DENY LOCK "Slow down."; return; }
  ACC_RATE[$id]=$NOW
  (( NOW >= ${ACC_LOCK[$key]:-0} )) || { acc_reply "$id" DENY LOCK "Too many wrong passwords - try again in a minute."; return; }
  if [[ ! -r $ACC_DIR/$key.pw ]] && acc_online "$name" "$id"; then acc_reply "$id" DENY ONLINE "Somebody is creating $name right now."; return; fi
  ACC_SEEN[$id]=$NOW
  if [[ -r $ACC_DIR/$key.pw ]]; then
    read -r salt hsh nm < "$ACC_DIR/$key.pw"
    acc_hash "$salt" "$pw"
    if [[ $AH != "$hsh" ]]; then
      ACC_FAIL[$key]=$(( ${ACC_FAIL[$key]:-0} + 1 ))
      (( ACC_FAIL[$key] >= 5 )) && { ACC_LOCK[$key]=$(( NOW + 60000 )) ACC_FAIL[$key]=0; slog "! too many wrong passwords for $name ($id)"; }
      acc_reply "$id" DENY PASS "Wrong password."; return
    fi
    ACC_FAIL[$key]=0
    [[ $nm == "$name" ]] || { acc_reply "$id" DENY NAME "That hero is called $nm."; return; }
    if acc_online "$name" "$id"; then                # v6.3: the right password takes the hero over (quit and came straight back,
      if [[ $keep == keep ]]; then                    # or a session hanging somewhere) - but a reconnect never kicks anybody
        acc_reply "$id" DENY ONLINE "$name is playing somewhere else."; return
      fi
      acc_kick "$name" "$id"
    fi
    ACC_NAME[$id]=$name; unset "ACC_NEW[$id]" "ACC_PASS[$id]"
    slog "login: $name ($id)"
    if [[ $keep == keep ]]; then acc_reply "$id" OK; return; fi
    if [[ -r $ACC_DIR/$key.char ]]; then
      txt=$(<"$ACC_DIR/$key.char"); txt=${txt//$'\n'/$US}
      total=$(( (${#txt} + ACC_CHUNK - 1) / ACC_CHUNK ))
      for (( n = 1; n <= total; n++ )); do acc_reply "$id" DATA "$n" "$total" "${txt:(n-1)*ACC_CHUNK:ACC_CHUNK}"; done
      return
    fi
    ACC_NEW[$id]=0                               # the password exists but the hero never got saved: create it
    acc_reply "$id" NONE; return
  fi
  ACC_NAME[$id]=$name ACC_NEW[$id]=1 ACC_PASS[$id]=$pw
  slog "new hero: $name ($id)"
  acc_reply "$id" NONE
}

srv_asave() {  # id n total chunk
  local id=$1 n=$2 total=$3 chunk=$4 key text salt tmp
  [[ -n ${ACC_NAME[$id]} ]] || return
  isnum "$n" && isnum "$total" && (( n >= 1 && n <= total && total <= ACC_MAXCH && ${#chunk} <= ACC_CHUNK + 20 )) || return
  local LC_ALL=C
  [[ $chunk == *[^\ -~"$US"]* ]] && return
  ACC_SEEN[$id]=$NOW
  if (( n == 1 )); then ACC_BUF[$id]=$chunk ACC_NS[$id]=1
  elif (( ${ACC_NS[$id]:-0} == n - 1 )); then ACC_BUF[$id]+=$chunk ACC_NS[$id]=$n
  else unset "ACC_BUF[$id]" "ACC_NS[$id]"; return; fi
  (( n == total )) || return
  text=${ACC_BUF[$id]//$US/$'\n'}; unset "ACC_BUF[$id]" "ACC_NS[$id]"
  if (( NOW - ${ACC_SVT[$id]:-0} > 10000 )); then ACC_SVT[$id]=$NOW ACC_SVN[$id]=0; fi
  (( ++ACC_SVN[$id] <= 30 )) || { acc_reply "$id" BAD "saving too often"; return; }
  acc_valid_text "$text" || { acc_reply "$id" BAD "not a hero"; slog "! bad save from ${ACC_NAME[$id]} ($id)"; return; }
  key=${ACC_NAME[$id],,}
  if [[ -n ${ACC_NEW[$id]} && ! -r $ACC_DIR/$key.pw ]]; then
    printf -v salt '%04x%04x%04x' $RANDOM $RANDOM $RANDOM
    acc_hash "$salt" "${ACC_PASS[$id]}"
    printf '%s %s %s\n' "$salt" "$AH" "${ACC_NAME[$id]}" > "$ACC_DIR/$key.pw.tmp" && mv -f "$ACC_DIR/$key.pw.tmp" "$ACC_DIR/$key.pw" && chmod 600 "$ACC_DIR/$key.pw"
  fi
  [[ -r $ACC_DIR/$key.pw ]] || { acc_reply "$id" BAD "no such hero"; return; }
  unset "ACC_NEW[$id]" "ACC_PASS[$id]"
  tmp="$ACC_DIR/$key.char.tmp"
  if printf '%s\n' "$text" > "$tmp" && mv -f "$tmp" "$ACC_DIR/$key.char"; then acc_reply "$id" ACK
  else acc_reply "$id" BAD "the server could not write"; slog "! cannot write $ACC_DIR/$key.char"; fi
}
