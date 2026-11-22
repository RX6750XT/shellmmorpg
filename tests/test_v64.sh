#!/usr/bin/env bash
# v6.4: admin tools on the client - only the world server's private lines do anything; the effects
# themselves (god mode, teleport, level, gold, items, heal); the /admin command
source "$(dirname "$0")/lib.sh"
stub_client
new_hero 0 5
save_char() { :; }

# --- nothing without the server -------------------------------------------------------------------------------
eq "not an admin to begin with" "$IS_ADMIN" 0
SENT=(); CHAT_BUF="/admin gold 100"; chat_submit
eq "/admin is not sent by a non-admin" "${#SENT[@]}" 0
g=$GOLD
cli_line "SM1|ARabc123|f00f00|ADM|gold|5000"; eq "a player cannot send admin effects" "$GOLD" "$g"
cli_line "SM1|ARabc123|f00f00|ADMIN|1"; eq "...nor make you an admin" "$IS_ADMIN" 0
cli_line "SM1|ARdef456|srv|ADMIN|1"; eq "somebody else's admin flag is not mine" "$IS_ADMIN" 0

cli_line "SM1|ARabc123|srv|ADMIN|1"; eq "the server makes you an admin" "$IS_ADMIN" 1
SENT=(); CHAT_BUF="/admin level 30 pleb"; chat_submit
eq "/admin goes to the server" "${SENT[0]}" "ADM abc123 level 30 pleb"
SENT=(); CHAT_BUF="/admin ann hello   world"; chat_submit
eq "...with the rest as one field" "${SENT[0]}" "ADM abc123 ann hello   world"
SENT=(); LOGS=(); CHAT_BUF="/admin"; chat_submit
eq "/admin alone: help, nothing sent" "${#SENT[@]}" 0; ge "...the help has lines" "${#LOGS[@]}" 10
SENT=(); CHAT_BUF='/admin $(id)'; chat_submit; eq "garbage commands are not sent" "${#SENT[@]}" 0

# --- the effects -------------------------------------------------------------------------------------------------
g=$GOLD; cli_line "SM1|ARabc123|srv|ADM|gold|5000"; eq "gold" "$GOLD" $(( g + 5000 ))
cli_line "SM1|ARabc123|srv|ADM|gold|1+1"; eq "...only numbers" "$GOLD" $(( g + 5000 ))
cli_line "SM1|ARabc123|srv|ADM|level|30"; eq "level" "$LVL" 30; eq "...full health" "$HP" "$MAXHP"
cli_line "SM1|ARabc123|srv|ADM|level|99"; eq "...never above the cap" "$LVL" 30
x=$XP; cli_line "SM1|ARabc123|srv|ADM|xp|100"; eq "xp" "$XP" $(( x + 100 ))
n=${#INV[@]}; cli_line "SM1|ARabc123|srv|ADM|item|W.6.12.3"; eq "an item" "${INV[-1]}" "W.6.12.3"
cli_line "SM1|ARabc123|srv|ADM|item|a[\$(id)]"; eq "...only valid items" "${#INV[@]}" $(( n + 1 ))
HP=1; cli_line "SM1|ARabc123|srv|ADM|heal"; eq "heal" "$HP" "$MAXHP"
cli_line "SM1|ARabc123|srv|ADM|tp|W|130|50"; eq "teleport" "$PX,$PY,$CUR_MAP" "130,50,W"
cli_line "SM1|ARabc123|srv|ADM|tp|W|9999|50"; eq "...only onto the map" "$PX,$PY" "130,50"
enter_instance D1 0 12345; cli_line "SM1|ARabc123|srv|ADM|tp|W|100|40"; eq "...out of a dungeon" "$CUR_MAP $PX,$PY" "W 100,40"

cli_line "SM1|ARabc123|srv|ADM|god|1"; eq "god mode" "$ADM_GOD" 1
HP=50; take_damage 10000 Dragon; eq "...no damage" "$HP" 50; eq "...alive" "$DEAD" 0
PS_UNTIL[0]=$(( NOW + 5000 )) PS_DMG[0]=10000; pst_tick; eq "...not even from poison" "$DEAD" 0
cli_line "SM1|ARabc123|srv|ADM|god|0"; eq "god mode off" "$ADM_GOD" 0
HP=50 immune_until=0 DODGE=0; take_damage 10000 Dragon; eq "...hurts again" "$DEAD" 1

cli_line "SM1|ARabc123|srv|ADMIN|0"; eq "the server takes it away" "$IS_ADMIN" 0
SENT=(); CHAT_BUF="/admin heal"; chat_submit; eq "...and /admin is not sent any more" "${#SENT[@]}" 0

# --- the server's list ---------------------------------------------------------------------------------------------
ADM_FILE=$T_TMP/admins
adm_is Bob && fail "nobody is in an empty list" || ok
adm_set add Bob; check "add" adm_is bob
adm_set add bob && fail "no duplicates" || ok
printf '# comment\n  Carol  \n' >> "$ADM_FILE"; check "comments and blanks in the file" adm_is carol
adm_set remove BOB; adm_is Bob && fail "remove" || ok; check "...keeps the others" adm_is Carol
adm_set add 'x;y' && fail "names are checked" || ok
SHELLMMO_ADMIN_NAME=Host; check "the host is an admin" adm_is host

t_end
