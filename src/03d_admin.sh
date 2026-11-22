# ---------------------------------------------------------------------------
#  Module 03d - admin tools (v6.4), server side. The world server decides who
#  is an admin: the heroes listed in $SHELLMMO_DIR/admins (one name per line,
#  read again for every command, so changes count at once), plus the host's
#  own hero when a player hosts the world (SHELLMMO_ADMIN_NAME, set by
#  start_world_server). Admins send ADM <command> <args>; the server checks,
#  logs and carries it out - world commands right here, hero commands as a
#  private AR<id> ADM <effect> line to the hero's client (the only way a
#  client accepts them). ./shellmmorpg.sh --admin add|remove|list [NAME]
#  edits the list without a running server.
# ---------------------------------------------------------------------------
ADM_FILE="$DATA_DIR/admins"
declare -A ADM_GOD=() ADM_RATE=()

adm_listed() {  # name -> 0 if the name is in the admins file
  local want=${1,,} line
  [[ -r $ADM_FILE ]] || return 1
  while IFS= read -r line || [[ -n $line ]]; do
    line=${line%%#*}; line=${line//[[:space:]]/}
    [[ -n $line && ${line,,} == "$want" ]] && return 0
  done < "$ADM_FILE"
  return 1
}

adm_is() {  # name -> 0 if that hero is an admin
  [[ -n $1 ]] || return 1
  [[ -n $SHELLMMO_ADMIN_NAME && ${SHELLMMO_ADMIN_NAME,,} == "${1,,}" ]] && return 0
  adm_listed "$1"
}

adm_set() {  # add|remove name -> 0 if the file changed
  local want=${2,,} line n out="" hit=0
  [[ $2 =~ ^[A-Za-z0-9_-]{1,12}$ ]] || return 1
  if [[ -r $ADM_FILE ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      n=${line%%#*}; n=${n//[[:space:]]/}
      if [[ -n $n && ${n,,} == "$want" ]]; then hit=1; [[ $1 == remove ]] && continue; fi
      out+=$line$'\n'
    done < "$ADM_FILE"
  fi
  if [[ $1 == add ]]; then (( hit )) && return 1; out+=$2$'\n'
  else (( hit )) || return 1; fi
  mkdir -p "$DATA_DIR" || return 1
  printf '%s' "$out" > "$ADM_FILE.tmp" && mv -f "$ADM_FILE.tmp" "$ADM_FILE" && chmod 600 "$ADM_FILE" 2>/dev/null
  return 0
}

adm_cli() {  # ./shellmmorpg.sh --admin add|remove|list [NAME]
  local line
  case $1 in
    add|remove)
      [[ $2 =~ ^[A-Za-z0-9_-]{1,12}$ ]] || die "--admin $1 needs a hero name (1-12 letters, digits, _ or -)"
      if adm_set "$1" "$2"; then
        if [[ $1 == add ]]; then echo "$2 is now an admin"; else echo "$2 is no longer an admin"; fi
      elif [[ $1 == add ]]; then echo "$2 already is an admin"
      else echo "$2 is not an admin"; fi
      echo "(list: $ADM_FILE - a running server reads it for every command)" ;;
    list|"")
      if [[ -r $ADM_FILE ]] && grep -q '[^[:space:]]' "$ADM_FILE"; then
        while IFS= read -r line; do line=${line%%#*}; line=${line//[[:space:]]/}; [[ -n $line ]] && echo "$line"; done < "$ADM_FILE"
      else echo "no admins yet ($ADM_FILE) - add one: $0 --admin add NAME"; fi ;;
    *) die "--admin add NAME | remove NAME | list" ;;
  esac
}

adm_tell() { acc_reply "$1" ADM say "$2"; }          # id text: a line in the admin's log
adm_fx()   { acc_reply "$1" ADM "${@:2}"; }          # id effect args: the hero's client carries it out

adm_status() {  # id [always]: tell a client it is an admin (after a login only if it is - clients start as non-admins;
  if adm_is "${ACC_NAME[$1]}"; then acc_reply "$1" ADMIN 1      #  after a grant or a revoke either way)
  else unset "ADM_GOD[$1]"; [[ $2 == always ]] && acc_reply "$1" ADMIN 0; fi
}

adm_find() {  # name -> TID (a logged-in hero in the world), or tells the admin and fails
  local want=${2,,} id
  TID=""
  [[ -n $2 ]] || { adm_tell "$1" "Whom? (a hero's name)"; return 1; }
  for id in "${!SP_NAME[@]}"; do [[ ${SP_NAME[$id],,} == "$want" ]] && TID=$id; done
  [[ -n $TID ]] || { adm_tell "$1" "Nobody called '$2' is in the world."; return 1; }
}

adm_spot() {  # map x y -> SX SY: the nearest walkable, free tile (players may stand anywhere they can walk)
  local r i j
  for (( r = 0; r <= 6; r++ )); do
    for (( j = -r; j <= r; j++ )); do for (( i = -r; i <= r; i++ )); do
      (( i == -r || i == r || j == -r || j == r )) || continue
      p_walk "$1" $(( $2 + i )) $(( $3 + j )) || continue
      [[ -n ${OCC[$1:$(( $2 + i )):$(( $3 + j ))]} ]] && continue
      SX=$(( $2 + i )) SY=$(( $3 + j )); return 0
    done; done
  done
  return 1
}

adm_mtype() {  # text -> MTP: a creature by number or (part of) its name; only creatures that fight
  local q=${1,,} t best=""
  q=${q//_/ }
  if isnum "$1"; then (( $1 < NM )) && (( M_KIND[$1] == 0 )) && MTP=$1 && return 0; MTP=""; return 1; fi
  for (( t = 0; t < NM; t++ )); do
    (( M_KIND[t] == 0 )) || continue
    [[ ${M_NAME[t],,} == "$q" ]] && { MTP=$t; return 0; }
    [[ -z $best && ${M_NAME[t],,} == *"$q"* ]] && best=$t
  done
  MTP=$best; [[ -n $MTP ]]
}

adm_target() {  # id name|"" -> TID (empty = the admin)
  if [[ -n $2 ]]; then adm_find "$1" "$2"; else TID=$1; fi
}

srv_adm() {  # id command args...
  local id=$1 cmd=${2,,} a=$3 b=$4 me=${ACC_NAME[$1]} n i m x y r cnt=0 t gm list
  (( ACCT_ON )) || return
  adm_is "$me" || { adm_tell "$id" "You are not an admin."; return; }
  (( NOW - ${ADM_RATE[$id]:-0} >= 150 )) || return               # (a held key must not flood the server)
  ADM_RATE[$id]=$NOW
  [[ -n ${SP_NAME[$id]} ]] || { [[ $cmd == @(who|admins|grant|revoke|ann|time|weather|kick) ]] || { adm_tell "$id" "Walk into the world first."; return; }; }
  slog "admin $me: $cmd $a $b"
  case $cmd in
    who)
      list=""
      for i in "${!SP_NAME[@]}"; do
        list+="${list:+, }${SP_NAME[$i]} L${SP_LVL[$i]} ${SP_MAP[$i]} ${SP_X[$i]},${SP_Y[$i]}"
        adm_is "${SP_NAME[$i]}" && list+=" [admin]"
      done
      adm_tell "$id" "In the world: ${list:-nobody}" ;;
    admins)
      list=""; [[ -n $SHELLMMO_ADMIN_NAME ]] && list="$SHELLMMO_ADMIN_NAME (host)"
      if [[ -r $ADM_FILE ]]; then
        while IFS= read -r i || [[ -n $i ]]; do i=${i%%#*}; i=${i//[[:space:]]/}; [[ -n $i ]] && list+="${list:+, }$i"; done < "$ADM_FILE"
      fi
      adm_tell "$id" "Admins: ${list:-none}" ;;
    grant|revoke)
      [[ $a =~ ^[A-Za-z0-9_-]{1,12}$ ]] || { adm_tell "$id" "Usage: /admin $cmd <name>"; return; }
      if [[ $cmd == revoke && ${a,,} == "${SHELLMMO_ADMIN_NAME,,}" ]]; then adm_tell "$id" "$a hosts this world and stays an admin."; return; fi
      if [[ $cmd == grant ]]; then adm_set add "$a" && adm_tell "$id" "$a is now an admin." || adm_tell "$id" "$a already is an admin."
      else adm_set remove "$a" && adm_tell "$id" "$a is no longer an admin." || adm_tell "$id" "$a was not an admin."; fi
      for i in "${!ACC_NAME[@]}"; do [[ ${ACC_NAME[$i],,} == "${a,,}" ]] && { adm_status "$i" always; [[ $cmd == revoke && -n ${ADM_GOD[$i]} ]] && { unset "ADM_GOD[$i]"; adm_fx "$i" god 0; }; }; done ;;
    ann)
      clean_text "${*:3}"; [[ -n $CLEAN ]] || { adm_tell "$id" "Usage: /admin ann <text>"; return; }
      send ANN srv "[$me] $CLEAN" ;;
    kick)
      adm_find "$id" "$a" || return
      [[ $TID == "$id" ]] && { adm_tell "$id" "Not yourself."; return; }
      acc_reply "$TID" DENY KICK "An admin ($me) sent you out of the world."
      send ANN srv "${SP_NAME[$TID]} was sent out of the world by $me."
      srv_drop "$TID" ;;
    time)
      [[ $a =~ ^([01]?[0-9]|2[0-3]):([0-5][0-9])$ ]] || { adm_tell "$id" "Usage: /admin time HH:MM (e.g. 22:00 for night)"; return; }
      gm=$(( 10#${BASH_REMATCH[1]} * 60 + 10#${BASH_REMATCH[2]} ))
      SRV_CLK0=$(( NOW - gm * GMIN )); CLK_NEXT=0; clock_second
      send ANN srv "$me turns the world's clock to $a." ;;
    weather)
      r=""
      for i in "${!WEA_REG[@]}"; do
        [[ ${WEA_REG[i],,} == "${a,,}" || $a == "$i" ]] && r=$i
        [[ -z $r && -n $a && ${WEA_REG[i],,} == "${a,,}"* ]] && r=$i
      done
      if [[ -z $r ]]; then list=""; for i in "${!WEA_REG[@]}"; do list+=" $i:${WEA_REG[i]}"; done; adm_tell "$id" "Usage: /admin weather <region> rain|storm|fog|sand|snow|ash|clear - regions:$list"; return; fi
      if [[ $b == @(clear|-) ]]; then WS_T[r]="" WS_N[r]=$(( NOW + 240000 )); send WEATHER srv "$r" - 0
      elif [[ $b == @(rain|storm|fog|sand|snow|ash) ]]; then WS_T[r]=$b WS_E[r]=$(( NOW + 180000 )); send WEATHER srv "$r" "$b" 180
      else adm_tell "$id" "Weather: rain storm fog sand snow ash clear"; return; fi
      adm_tell "$id" "Weather over ${WEA_REG[r]//_/ }: $b" ;;
    wboss)
      if (( WB_MID >= 0 && MALIVE[WB_MID] )); then adm_tell "$id" "${M_NAME[${MT[WB_MID]}]} is already out, at ${MX[WB_MID]},${MY[WB_MID]}."; return; fi
      wb_spawn; (( WB_MID >= 0 && MALIVE[WB_MID] )) && adm_tell "$id" "${M_NAME[${MT[WB_MID]}]} at ${MX[WB_MID]},${MY[WB_MID]} - /admin tp ${MX[WB_MID]} ${MY[WB_MID]}" ;;
    spawn)
      adm_mtype "$a" || { adm_tell "$id" "No creature '$a' (a number below $NM or part of a name)."; return; }
      n=${b:-1}; isnum "$n" && (( n >= 1 )) || n=1; (( n > 20 )) && n=20
      m=${SP_MAP[$id]}
      [[ $m == H* ]] && { adm_tell "$id" "Not in a room at the inn."; return; }
      for (( i = 0; i < n; i++ )); do
        free_tile $(( SP_X[$id] - 4 )) $(( SP_Y[$id] - 4 )) $(( SP_X[$id] + 4 )) $(( SP_Y[$id] + 4 )) "$m" || continue
        spawn_mon "$m" "$MTP" "$SX" "$SY" -4 100 4; mon_state "$MID"; cnt=$(( cnt + 1 ))
      done
      if (( cnt )); then adm_tell "$id" "Spawned $cnt x ${M_NAME[MTP]} (level ${M_LVL[MTP]}). They do not come back."
      else adm_tell "$id" "No room around you (towns are safe ground - step outside)."; fi ;;
    kill)
      r=${a:-8}; isnum "$r" || r=8; (( r > 40 )) && r=40
      m=${SP_MAP[$id]}
      for i in "${!AL[@]}"; do
        [[ ${MMAP[i]} == "$m" ]] && (( M_KIND[MT[i]] == 0 )) || continue
        cheb $(( MX[i] - SP_X[$id] )) $(( MY[i] - SP_Y[$id] )); (( D <= r )) || continue
        mon_die "$i" "$id"; cnt=$(( cnt + 1 ))
      done
      adm_tell "$id" "Killed $cnt monster(s) within $r steps." ;;
    tp)
      isnum "$a" && isnum "$b" && (( a < ${MAPW[W]} && b < ${MAPH[W]} )) || { adm_tell "$id" "Usage: /admin tp X Y (0-$(( ${MAPW[W]} - 1 )), 0-$(( ${MAPH[W]} - 1 )))"; return; }
      adm_spot W "$a" "$b" || { adm_tell "$id" "Nowhere to stand near $a,$b."; return; }
      adm_fx "$id" tp W "$SX" "$SY" ;;
    goto|summon)
      adm_find "$id" "$a" || return
      [[ $TID == "$id" ]] && { adm_tell "$id" "That is you."; return; }
      if [[ $cmd == goto ]]; then x=$TID y=$id; else x=$id y=$TID; fi            # x: where to go, y: who goes
      [[ ${SP_MAP[$x]} == W ]] || { adm_tell "$id" "${SP_NAME[$x]} is not in the open world (${SP_MAP[$x]})."; return; }
      adm_spot W "${SP_X[$x]}" "${SP_Y[$x]}" || { adm_tell "$id" "No room next to ${SP_NAME[$x]}."; return; }
      adm_fx "$y" tp W "$SX" "$SY"
      [[ $cmd == summon ]] && adm_fx "$TID" say "An admin ($me) summons you."
      adm_tell "$id" "Off to ${SP_NAME[$x]}." ;;
    god)
      adm_target "$id" "$a" || return
      if [[ -n ${ADM_GOD[$TID]} ]]; then unset "ADM_GOD[$TID]"; adm_fx "$TID" god 0; else ADM_GOD[$TID]=1; adm_fx "$TID" god 1; fi
      [[ $TID != "$id" ]] && adm_tell "$id" "God mode for ${SP_NAME[$TID]}: ${ADM_GOD[$TID]:-0}" ;;
    heal)
      adm_target "$id" "$a" || return
      adm_fx "$TID" heal; [[ $TID != "$id" ]] && adm_tell "$id" "${SP_NAME[$TID]} is healed." ;;
    xp|gold|level)
      isnum "$a" || { adm_tell "$id" "Usage: /admin $cmd <number> [name]"; return; }
      case $cmd in
        xp)    (( a <= 50000000 )) || a=50000000 ;;
        gold)  (( a <= 100000000 )) || a=100000000 ;;
        level) (( a >= 1 && a <= MAXLVL )) || { adm_tell "$id" "Levels go from 1 to $MAXLVL."; return; } ;;
      esac
      adm_target "$id" "$b" || return
      adm_fx "$TID" "$cmd" "$a"; [[ $TID != "$id" ]] && adm_tell "$id" "${SP_NAME[$TID]}: $cmd $a" ;;
    item)
      valid_item "$a" || { adm_tell "$id" "Not an item code: '$a' (e.g. W.6.12.3, U.5, C.10, B.5)"; return; }
      adm_target "$id" "$b" || return
      adm_fx "$TID" item "$a"; [[ $TID != "$id" ]] && adm_tell "$id" "${SP_NAME[$TID]} gets $a." ;;
    *) adm_tell "$id" "Unknown admin command '$cmd' - /admin help" ;;
  esac
}
