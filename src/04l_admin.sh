# ---------------------------------------------------------------------------
#  Module 04l - admin tools (v6.4), client side. The world server decides who
#  is an admin (03d_admin.sh) and tells us with a private AR<id> ADMIN 0|1.
#  /admin <command> goes to the server; what it does to a hero comes back as
#  a private AR<id> ADM <effect> line - the client never grants itself
#  anything (only the world server can send AR<id> lines through the hub).
# ---------------------------------------------------------------------------
IS_ADMIN=0 ADM_GOD=0

ADM_HELP=(
  "Admin tools (the server checks every command and writes it to its log):"
  "  /admin who | admins            who is online (map, position) / who is admin"
  "  /admin grant|revoke NAME       make a hero admin / take it away"
  "  /admin tp X Y                  teleport to X,Y in the open world (your position: /admin where)"
  "  /admin goto|summon NAME        go to a hero / bring a hero to you"
  "  /admin god [NAME]              god mode on/off (no damage, no death)"
  "  /admin heal [NAME]             full HP and mana, no status effects"
  "  /admin level|xp|gold N [NAME]  set the level / give XP / give gold"
  "  /admin item CODE [NAME]        give an item (W.6.12.3  U.5  C.10  B.5 ...)"
  "  /admin spawn CREATURE [N]      creatures next to you (number or part of a name, at most 20)"
  "  /admin kill [RADIUS]           kill the monsters around you (default 8)"
  "  /admin wboss                   a world boss now"
  "  /admin time HH:MM              set the world's clock"
  "  /admin weather REGION KIND     rain storm fog sand snow ash clear"
  "  /admin ann TEXT                announcement to everybody"
  "  /admin kick NAME               send a hero out of the world"
)

adm_flag() {  # 0|1 from the server
  local was=$IS_ADMIN
  [[ $1 == 1 ]] && IS_ADMIN=1 || IS_ADMIN=0
  (( IS_ADMIN )) || ADM_GOD=0
  if (( IS_ADMIN && ! was )); then logm "You are an admin on this server - /admin help" "$K_ANN"
  elif (( was && ! IS_ADMIN )); then logm "You are no longer an admin." "$K_SYS"; fi
}

adm_cmd() {  # the text after /admin
  local t=${1#"${1%%[![:space:]]*}"} c
  c=${t%% *}; [[ $t == *" "* ]] && t=${t#* } || t=""
  case ${c,,} in
    ""|help) local l; for l in "${ADM_HELP[@]}"; do logm "$l" "$K_SYS"; done
             (( IS_ADMIN )) || logm "(You are not an admin here - the server's admins can make you one.)" "$K_HURT" ;;
    where)   logm "You are at $CUR_MAP $PX,$PY." "$K_SYS" ;;
    *)       [[ ${c,,} =~ ^[a-z]{1,10}$ ]] || { logm "Unknown admin command - /admin help"; return; }
             (( IS_ADMIN )) || { logm "You are not an admin on this server." "$K_HURT"; return; }
             send ADM "$MY_ID" "${c,,}" "$t" ;;
  esac
}

adm_effect() {  # effect args... (only ever from the world server, privately)
  local x
  case $1 in
    say)  clean_text "$2"; logm "[admin] $CLEAN" "$K_SYS" ;;
    god)  if [[ $2 == 1 ]]; then ADM_GOD=1; HP=$MAXHP; logm "God mode ON - nothing can hurt you." "$K_GOOD"
          else ADM_GOD=0; logm "God mode off." "$K_SYS"; fi
          POS_DIRTY=1 ;;
    heal) (( DEAD )) && return
          HP=$MAXHP MP=$MAXMP POS_DIRTY=1; pst_clear all
          logm "An admin heals you completely." "$K_GOOD" ;;
    tp)   [[ $2 == W ]] && num "$3" && num "$4" && (( $3 < ${MAPW[W]} && $4 < ${MAPH[W]} )) || return
          (( DEAD )) && return
          [[ $CUR_MAP != W ]] && leave_instance quiet
          (( RIDING )) && mount_off quiet
          (( FISH_ST )) && fish_stop quiet
          PX=$3 PY=$4 GATH_MID="" UI="" POS_DIRTY=1 MAP_DIRTY=1 NEED_FULL=1
          explore_here; send_pos
          RNAME=""; region_of "$PX" "$PY"; logm "Teleported to $PX,$PY${RNAME:+ ($RNAME)}." "$K_GOOD" ;;
    xp)   num "$2" || return; logm "An admin grants you $2 XP." "$K_GOOD"; gain_xp "$2" ;;
    gold) num "$2" || return; GOLD=$(( GOLD + $2 )); logm "An admin grants you $2 gold." "$K_LOOT" ;;
    level)
          num "$2" && (( $2 >= 1 && $2 <= MAXLVL )) || return
          x=$LVL; LVL=$2 XP=0; calc_stats; HP=$MAXHP MP=$MAXMP POS_DIRTY=1
          logm "An admin sets your level to $LVL." "$K_ANN"
          (( LVL > x )) && story_levelup
          save_char ;;
    item) valid_item "$2" || return; add_item "$2" ;;
  esac
}
