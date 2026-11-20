# ---------------------------------------------------------------------------
#  Test helpers: load the built game as a library and count assertions.
#  Usage in a test file:   source "$(dirname "$0")/lib.sh"; ...; t_end
# ---------------------------------------------------------------------------
T_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
GAME=${GAME:-$T_ROOT/shellmmorpg.sh}
T_NAME=${0##*/}; T_NAME=${T_NAME%.sh}
T_PASS=0 T_FAIL=0
T_TMP=$(mktemp -d)
export SHELLMMO_DIR=$T_TMP/data
mkdir -p "$SHELLMMO_DIR"

[[ -r $GAME ]] || { echo "$T_NAME: $GAME not found - run ./build.sh first"; exit 2; }
T_ARGS=("$@"); set --                      # the game parses "$@" when it loads
SHELLMMO_LIB=1 source "$GAME" </dev/null
set -- "${T_ARGS[@]}"
set +f

ok()   { T_PASS=$(( T_PASS + 1 )); }
fail() { T_FAIL=$(( T_FAIL + 1 )); (( T_FAIL <= 40 )) && echo "  FAIL [$T_NAME] $*"; }
# check "description" command args...   (passes when the command succeeds)
check() { local d=$1; shift; if "$@"; then ok; else fail "$d"; fi; }
# eq "description" actual expected
eq() { if [[ $2 == "$3" ]]; then ok; else fail "$1: expected '$3', got '$2'"; fi; }
# le / ge "description" a b
le() { if (( $2 <= $3 )); then ok; else fail "$1: $2 > $3"; fi; }
ge() { if (( $2 >= $3 )); then ok; else fail "$1: $2 < $3"; fi; }
gt() { if (( $2 > $3 )); then ok; else fail "$1: $2 <= $3"; fi; }

t_end() {
  rm -rf "$T_TMP"
  printf '%-14s %4d passed  %d failed\n' "$T_NAME" "$T_PASS" "$T_FAIL"
  (( T_FAIL == 0 ))
}

# A quiet client: no network, logs go to an array, nothing is drawn.
LOGS=()
stub_client() {
  send() { SENT+=("$*"); return 0; }
  logm() { LOGS+=("$1"); }
  chatm() { LOGS+=("$1"); }
  ft_add() { :; }
  printf_bell() { :; }
  SENT=() net_up=1 MY_ID=abc123 MY_NAME=tester
  load_world; init_where
  now_ms
}

# A fresh level-N hero of class C standing in Hearthmoor
new_hero() {  # cls [lvl]
  new_char "$1"; LVL=${2:-1} STORY_SEEN=1
  CUR_MAP=W CUR_DT=-1 PX=$SPAWN_X PY=$SPAWN_Y
  CHAR_FILE=$SHELLMMO_DIR/$MY_NAME.char
  calc_stats; HP=$MAXHP MP=$MAXMP
}
