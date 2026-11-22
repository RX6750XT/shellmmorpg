#!/usr/bin/env bash
# v7.1: comfort - special keys, the chat line (cursor, history, Tab, ctrl keys, /r, /bell), the chat log
# (times, wrapping, tabs, scrolling), panels taller than the window scroll, every recipe and every waystone
# can be picked, Q asks first
source "$(dirname "$0")/lib.sh"
stub_client
new_hero 0 40
T_ROWS=30 T_COLS=100
stty() { echo "$T_ROWS $T_COLS"; }
layout; init_explore; init_lights
save_char() { :; }

# --- special keys ---------------------------------------------------------------------------------------
kd() { if [[ -n $1 ]]; then key_esc <<< "$1"; else key_esc < /dev/null; fi; printf '%s' "$KEY"; }
eq "arrow up" "$(kd '[A')" UP; eq "arrow (application mode)" "$(kd 'OB')" DOWN
eq "ctrl+arrow" "$(kd '[1;5C')" RIGHT; eq "page up" "$(kd '[5~')" PGUP; eq "page down" "$(kd '[6~')" PGDN
eq "home" "$(kd '[H')" HOME; eq "home (vt)" "$(kd '[1~')" HOME; eq "end" "$(kd '[F')" END; eq "end (vt)" "$(kd '[4~')" END
eq "delete" "$(kd '[3~')" DEL; eq "a lone escape" "$(kd '')" ESC; eq "alt+x does nothing" "$(kd 'x')" ""
eq "an unknown sequence does nothing" "$(kd '[99~')" ""

# --- the chat line ------------------------------------------------------------------------------------------
typ() { local s=$1 i; for (( i = 0; i < ${#s}; i++ )); do chat_key "${s:i:1}"; done; }
chat_open ""; typ "helo world"
chat_key LEFT; chat_key LEFT; chat_key LEFT; chat_key LEFT; chat_key LEFT; chat_key LEFT; chat_key LEFT; typ "l"
eq "the cursor moves, typing inserts" "$CHAT_BUF" "hello world"
chat_key HOME; chat_key DEL; typ "H"; eq "home + delete" "$CHAT_BUF" "Hello world"
chat_key END; chat_key $'\x17'; eq "ctrl+w deletes a word" "$CHAT_BUF" "Hello "
chat_key $'\x7f'; eq "backspace" "$CHAT_BUF" "Hello"
chat_key HOME; chat_key RIGHT; chat_key $'\x0b'; eq "ctrl+k: the rest of the line" "$CHAT_BUF" "H"
chat_key $'\x15'; eq "ctrl+u: the start of the line" "$CHAT_BUF" ""
SENT=(); typ "first"; chat_key ''; chat_open ""; typ "second"; chat_key ''
eq "enter sends" "${SENT[-1]}" "CHAT abc123 tester second"
chat_open ""; typ "draft"; chat_key UP; eq "up: the last line" "$CHAT_BUF" "second"
chat_key UP; eq "up again: the one before" "$CHAT_BUF" "first"
chat_key UP; eq "...and stops at the oldest" "$CHAT_BUF" "first"
chat_key DOWN; chat_key DOWN; eq "down past the newest: back to the draft" "$CHAT_BUF" "draft"
chat_key ESC; eq "escape closes" "$CHATTING" 0
OP_NAME[beefed]=Mirabel OP_NAME[cafe01]=Mira OP_NAME[cafe02]=Bob
chat_open ""; typ "hi bo"; chat_key $'\t'; eq "tab completes a name" "$CHAT_BUF" "hi Bob "
CHAT_BUF="" CHAT_POS=0; typ "mir"; chat_key $'\t'; eq "several names: as far as they agree" "$CHAT_BUF" "Mira"
LOGS=(); chat_key $'\t'; eq "...(and still Mira, the names are listed)" "$CHAT_BUF" "Mira"
CHAT_BUF="" CHAT_POS=0; typ "/inv"; chat_key $'\t'; eq "tab completes a command" "$CHAT_BUF" "/invite "
chat_key ESC
SENT=(); CHAT_BUF="/r hi"; chat_submit; eq "/r without a whisper: nothing sent" "${#SENT[@]}" 0
cli_line "SM1|WHISP|beefed|Mirabel|tester|psst"; SENT=(); CHAT_BUF="/r hello back"; chat_submit
eq "/r answers the last whisper" "${SENT[0]}" "WHISP abc123 tester Mirabel hello back"
chat_open ""; typ "$(printf 'x%.0s' {1..300})"; eq "the line has a limit" "${#CHAT_BUF}" 180; chat_key ESC
chat_open ""; typ "$(printf 'y%.0s' {1..150})"; out=""; render_input
check "a long line: the cursor stays on screen" test "${out//[^y]/}" != ""; chat_key ESC

# --- the bell ---------------------------------------------------------------------------------------------------
GFX_FILE=$T_TMP/prefs/tester.gfx
BELL_ON=1; CHAT_BUF="/bell"; chat_submit; eq "/bell switches it off" "$BELL_ON" 0
eq "...and it is remembered" "$(grep BELL "$GFX_FILE")" "BELL=0"
eq "no bell rings" "$(bell)" ""
CHAT_BUF="/bell"; chat_submit; eq "/bell again: on" "$(bell)" $'\a'

# --- the chat log -------------------------------------------------------------------------------------------------
source <(sed -n '/^logm() {/,/^}/p; /^chatm() {/,/^}/p' "$T_ROOT/src/04_client.sh")     # (the stubs keep nothing)
LOG_T=() LOG_C=() LOG_TM=() LOG_S=() CHL_T=() CHL_C=() CHL_TM=() CHL_S=()
for i in $(seq 120); do logm "event $i"; chatm "Mira: chat $i"; done
chatm "Mira: $(printf 'word%s ' {1..60})the end"
eq "more is kept than before (400)" "${#CHL_T[@]}" 121
check "every line has a time" test -n "${CHL_TM[-1]}"
UI=chatlog CL_TAB=0 CL_OFF=0; out=""; render_ui
check "the chat tab ends with the newest line" grep -q "the end" <<< "${UIT[*]}"
long=0; for l in "${UIT[@]:1}"; do dispw "$l"; (( DW > MW - 1 )) && long=1; done; eq "long lines are wrapped, not cut (and the hints fit)" "$long" 0
handle_key $'\e' <<< '[5~'
ge "page up (the real key) scrolls back" "$CL_OFF" 1
out=""; render_ui; check "...older lines show" grep -q "chat 1[0-9][0-9]\|chat [0-9][0-9]" <<< "${UIT[*]}"
CL_OFF=999999; out=""; render_ui; check "home: the oldest line" grep -q "chat 1$" <<< "$(printf '%s\n' "${UIT[@]}")"
o=$CL_OFF; chatm "Mira: something new"; out=""; render_ui; eq "scrolled back: new lines do not move the view" "$CL_OFF" $(( o + 1 ))
chatlog_key END; eq "end: back to the newest" "$CL_OFF" 0
chatlog_key 2; out=""; render_ui; check "the events tab" grep -q "event 120" <<< "${UIT[*]}"
chatlog_key 3; out=""; render_ui; check "everything: chat and events together" grep -q "event 120" <<< "${UIT[*]}"
chatlog_key ''; eq "enter in the log starts chatting" "$CHATTING" 1; chat_key ESC
chatlog_key c; eq "c closes it" "$UI" ""

# --- panels taller than the window scroll ------------------------------------------------------------------
PROF_LV=(40 40 40); UI=prof; out=""; render_ui
le "the professions page fits the window" "${#UIT[@]}" "$VH"
check "...and says there is more" grep -q "PgDn" <<< "${UIT[-1]}"
first=${UIT[0]}; handle_key $'\e' <<< '[6~'; out=""; render_ui
check "page down shows other lines" test "${UIT[0]}" != "$first"
UI_SCR=999999; out=""; render_ui; check "...down to the end" grep -q " of " <<< "${UIT[-1]}"
UI=qlog QLOG_TAB=1; out=""; render_ui; le "the quest log fits" "${#UIT[@]}" "$VH"; QLOG_TAB=0

# --- every recipe and every waystone can be picked --------------------------------------------------------------
for (( i = 0; i < NMAT; i++ )); do MATS[i]=50; done; GOLD=999999999
CRAFT=forge UI=craft; out=""; render_ui; craft_build
ge "the forge has more recipes than letters" "${#RC_ID[@]}" 13
craft_do() { DONE=$1; }
for (( i = 0; i < ${#RC_ID[@]} + 3; i++ )); do craft_key DOWN; done
craft_key ''; eq "the last recipe can be forged" "$DONE" $(( ${#RC_ID[@]} - 1 ))
out=""; render_ui; check "...and its line is on screen" grep -q "▶" <<< "${UIT[*]}"
craft_key HOME; craft_key ''; eq "home: the first" "$DONE" 0
craft_key c; eq "letters still work" "$DONE" 2
WAYS=$(printf '1%.0s' $(seq ${#WAYSTONES[@]}))
ge "more waystones than number keys" "${#WAYSTONES[@]}" 11
way_travel() { WENT=$1; }
UI=way; out=""; render_ui
for (( i = 0; i < ${#WAYSTONES[@]}; i++ )); do way_key DOWN; done; way_key ''
eq "the last waystone can be reached" "$WENT" $(( ${#WAYSTONES[@]} - 1 ))
way_key 0; eq "0: the tenth" "$WENT" 9
labels=$(printf '%s\n' "${UIT[@]}" | grep -o '\[[0-9]\]' | sort | uniq -d)
eq "no number is shown twice" "$labels" ""

# --- Q asks first ----------------------------------------------------------------------------------------------
UI=""; handle_key Q; eq "Q asks" "$QUIT_ASK" 1
out=""; render_input; check "...on the input line" grep -q "Quit the game" <<< "$out"
handle_key n; eq "any other key: keep playing" "$QUIT_ASK" 0
( handle_key Q; handle_key y; echo alive ) > "$T_TMP/q" 2>&1; eq "y quits" "$(cat "$T_TMP/q")" ""

t_end
