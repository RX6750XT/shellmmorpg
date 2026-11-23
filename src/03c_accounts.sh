# ---------------------------------------------------------------------------
#  Module 03c - heroes live on the server (v6.2). A client logs in with
#  ALOAD name password; the server answers privately (AR<id>) with the saved
#  hero in chunks (DATA) or NONE (a new hero: it is created by the first
#  ASAVE). ASAVE sends the hero's save text in chunks of at most 1400
#  characters, newlines written as the unit separator (\x1f).
#  The hub delivers ALOAD/ASAVE to the world server only and AR<id> to the
#  player <id> only.
# ---------------------------------------------------------------------------
#  v8.1: passwords are stored as PBKDF2-SHA256 (python3, salt from /dev/urandom):
#  "pbkdf2-sha256:ITERATIONS:SALT HASH Name" in <name>.pw. Older files ("SALT HASH Name",
#  one sha256) still log in and are rewritten with the new hash on the next login.
#  New heroes need 8 characters (older heroes keep their shorter passwords); wrong
#  passwords lock a hero for 1, 2, 4 ... at most 30 minutes.
ACC_DIR="$DATA_DIR/chars" ACCT_ON=0 ACC_HASHER="" ACC_CHUNK=1400 ACC_MAXCH=60 ACC_STALE=8000
ACC_KDF=0 ACC_ITER=${SHELLMMO_PBKDF2_ITER:-200000} ACC_MINNEW=8 ACC_HW=0 ACC_HN=0
[[ $ACC_ITER =~ ^[1-9][0-9]{0,7}$ ]] || ACC_ITER=200000
declare -A ACC_NAME=() ACC_NEW=() ACC_PASS=() ACC_BUF=() ACC_NS=() ACC_SEEN=() ACC_FAIL=() ACC_LOCK=() ACC_RATE=() ACC_SVN=() ACC_SVT=() ACC_LOCKS=()
US=$'\x1f'

acc_init() {
  mkdir -p "$ACC_DIR" && chmod 700 "$ACC_DIR" 2>/dev/null
  if command -v sha256sum >/dev/null 2>&1; then ACC_HASHER="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then ACC_HASHER="shasum -a 256"
  else ACC_HASHER="cksum"; fi
  ACC_KDF=0
  if command -v python3 >/dev/null 2>&1; then          # (the gate needs python3 anyway)
    acc_kdf 00 x 1 && [[ $AH =~ ^[0-9a-f]{64}$ ]] && ACC_KDF=1
  fi
  (( ACC_KDF )) || slog "! no python3 for PBKDF2 - passwords are stored as one salted sha256"
}

acc_kdf() {  # salt(hex) password iterations -> AH (the password goes through stdin, never the command line)
  AH=$(printf '%s' "$2" | python3 -I -c 'import hashlib, sys
print(hashlib.pbkdf2_hmac("sha256", sys.stdin.buffer.read(), bytes.fromhex(sys.argv[1]), int(sys.argv[2])).hex())' "$1" "$3" 2>/dev/null)
  [[ -n $AH ]] || { AH=none; return 1; }
}

acc_hash() {  # stored-salt password -> AH (the salt field says how: "pbkdf2-sha256:ITER:SALT" or an old plain salt)
  if [[ $1 =~ ^pbkdf2-sha256:([0-9]{1,8}):([0-9a-f]{16,64})$ ]]; then
    acc_kdf "${BASH_REMATCH[2]}" "$2" "${BASH_REMATCH[1]}" || AH=none
    return
  fi
  AH=$(printf '%s:%s' "$1" "$2" | $ACC_HASHER 2>/dev/null); AH=${AH%% *}
  [[ -n $AH ]] || AH=none
}

acc_store_pw() {  # key name password: writes <key>.pw with a fresh salt (PBKDF2 if python3 is there)
  local salt
  new_token; salt=$TOK
  if (( ACC_KDF )); then salt="pbkdf2-sha256:$ACC_ITER:$salt"; fi
  acc_hash "$salt" "$3"
  [[ $AH != none ]] || return 1
  printf '%s %s %s\n' "$salt" "$AH" "$2" > "$ACC_DIR/$1.pw.tmp" && chmod 600 "$ACC_DIR/$1.pw.tmp" && mv -f "$ACC_DIR/$1.pw.tmp" "$ACC_DIR/$1.pw"
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

acc_forget() { unset "ADM_GOD[$1]" "ADM_RATE[$1]" "ACC_NAME[$1]" "ACC_NEW[$1]" "ACC_PASS[$1]" "ACC_BUF[$1]" "ACC_NS[$1]" "ACC_SEEN[$1]" "ACC_RATE[$1]" "ACC_SVN[$1]" "ACC_SVT[$1]"; }

srv_aload() {  # id name password [keep]
  local id=$1 name=$2 pw=$3 keep=$4 key salt hsh nm n total i txt chunk
  [[ $name =~ ^[A-Za-z0-9_-]{1,12}$ ]] || { acc_reply "$id" DENY NAME "Names are 1-12 letters, digits, _ or -."; return; }
  valid_pass "$pw" || { acc_reply "$id" DENY PASS "The password needs 4-32 characters (not |)."; return; }
  key=${name,,}
  (( NOW - ${ACC_RATE[$id]:-0} >= 700 )) || { acc_reply "$id" DENY LOCK "Slow down."; return; }
  ACC_RATE[$id]=$NOW
  if (( NOW < ${ACC_LOCK[$key]:-0} )); then
    acc_reply "$id" DENY LOCK "Too many wrong passwords - try again in $(( (ACC_LOCK[$key] - NOW + 59999) / 60000 )) minute(s)."; return
  fi
  if [[ ! -r $ACC_DIR/$key.pw ]] && acc_online "$name" "$id"; then acc_reply "$id" DENY ONLINE "Somebody is creating $name right now."; return; fi
  ACC_SEEN[$id]=$NOW
  if [[ -r $ACC_DIR/$key.pw ]]; then
    (( NOW - ACC_HW >= 1000 )) && ACC_HW=$NOW ACC_HN=0     # v8.1: a hash costs the server ~50 ms - at most 5 a second
    (( ++ACC_HN <= 5 )) || { acc_reply "$id" DENY BUSY "The server is busy - one moment."; return; }
    read -r salt hsh nm < "$ACC_DIR/$key.pw"
    acc_hash "$salt" "$pw"
    if [[ $AH != "$hsh" ]]; then
      ACC_FAIL[$key]=$(( ${ACC_FAIL[$key]:-0} + 1 ))
      if (( ACC_FAIL[$key] >= 5 )); then              # v8.1: every lock-out in a row lasts twice as long (1, 2, 4 ... 30 min)
        n=${ACC_LOCKS[$key]:-0}; (( n < 5 )) && ACC_LOCKS[$key]=$(( n + 1 ))
        n=$(( 60000 << n )); (( n > 1800000 )) && n=1800000
        ACC_LOCK[$key]=$(( NOW + n )) ACC_FAIL[$key]=0
        slog "! too many wrong passwords for $name ($id) - locked for $(( n / 60000 )) min"
      fi
      acc_reply "$id" DENY PASS "Wrong password."; return
    fi
    unset "ACC_FAIL[$key]" "ACC_LOCKS[$key]"
    if (( ACC_KDF )) && [[ $salt != pbkdf2-sha256:"$ACC_ITER":* && $nm == "$name" ]]; then   # an old hash: store the new kind now
      acc_store_pw "$key" "$nm" "$pw" && slog "password of $name moved to pbkdf2"
    fi
    [[ $nm == "$name" ]] || { acc_reply "$id" DENY NAME "That hero is called $nm."; return; }
    if acc_online "$name" "$id"; then                # v6.3: the right password takes the hero over (quit and came straight back,
      if [[ $keep == keep ]]; then                    # or a session hanging somewhere) - but a reconnect never kicks anybody
        acc_reply "$id" DENY ONLINE "$name is playing somewhere else."; return
      fi
      acc_kick "$name" "$id"
    fi
    ACC_NAME[$id]=$name; unset "ACC_NEW[$id]" "ACC_PASS[$id]"
    slog "login: $name ($id)"
    if [[ $keep == keep ]]; then acc_reply "$id" OK; adm_status "$id"; return; fi
    if [[ -r $ACC_DIR/$key.char ]]; then
      txt=$(<"$ACC_DIR/$key.char"); txt=${txt//$'\n'/$US}
      total=$(( (${#txt} + ACC_CHUNK - 1) / ACC_CHUNK ))
      for (( n = 1; n <= total; n++ )); do acc_reply "$id" DATA "$n" "$total" "${txt:(n-1)*ACC_CHUNK:ACC_CHUNK}"; done
      adm_status "$id"; return                    # (v6.4: after the hero - the client reads the login answer first)
    fi
    ACC_NEW[$id]=0                               # the password exists but the hero never got saved: create it
    acc_reply "$id" NONE; adm_status "$id"; return
  fi
  if (( ${#pw} < ACC_MINNEW )); then acc_reply "$id" DENY PASS "A new hero needs a password of $ACC_MINNEW-32 characters."; return; fi
  ACC_NAME[$id]=$name ACC_NEW[$id]=1 ACC_PASS[$id]=$pw
  slog "new hero: $name ($id)"
  acc_reply "$id" NONE; adm_status "$id"
}

srv_asave() {  # id n total chunk
  local id=$1 n=$2 total=$3 chunk=$4 key text tmp
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
    acc_store_pw "$key" "${ACC_NAME[$id]}" "${ACC_PASS[$id]}"
  fi
  [[ -r $ACC_DIR/$key.pw ]] || { acc_reply "$id" BAD "no such hero"; return; }
  unset "ACC_NEW[$id]" "ACC_PASS[$id]"
  tmp="$ACC_DIR/$key.char.tmp"
  if printf '%s\n' "$text" > "$tmp" && mv -f "$tmp" "$ACC_DIR/$key.char"; then acc_reply "$id" ACK
  else acc_reply "$id" BAD "the server could not write"; slog "! cannot write $ACC_DIR/$key.char"; fi
}
