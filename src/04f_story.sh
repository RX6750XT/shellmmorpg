# ---------------------------------------------------------------------------
#  Module 04f - story (since v2.0): the Shattered Crown, 24 chapters through
#  every town. Chapters are data (ST_* in 01b_content.sh); this is the engine.
# ---------------------------------------------------------------------------
STORY=0 STORY_P=0 STORY_SEEN=0 ST_POP_T="" ST_POP_A="" ST_POP_R="" ST_POP_B="" ST_POP_C=""

st_obj() {  # chapter -> SO_K (T/D/K) SO_A SO_N
  local o=${ST_OBJ[$1]}
  IFS=. read -r SO_K SO_A SO_N <<< "$o"; SO_N=${SO_N:-1}
}

st_info() {  # chapter -> STXT (what to do) SWHERE STX STY
  st_obj "$1"
  STX="" STY="" SWHERE=""
  case $SO_K in
    T) STXT="Talk to ${N_FULL[$SO_A]}" SWHERE=${N_HOME[$SO_A]:-${MW_NAME[$SO_A]}} STX=${MW_X[$SO_A]} STY=${MW_Y[$SO_A]} ;;
    D) STXT="Clear the ${D_NAME[$SO_A]}" SWHERE=${D_WHERE[$SO_A]} STX=${D_ENTX[$SO_A]} STY=${D_ENTY[$SO_A]} ;;
    K) STXT="Slay $SO_N ${M_NAME[$SO_A]}s ($STORY_P/$SO_N)" SWHERE=${MW_NAME[$SO_A]} STX=${MW_X[$SO_A]} STY=${MW_Y[$SO_A]} ;;
  esac
}

story_active() { (( STORY < NST && LVL >= ST_LVL[STORY] )); }
story_npc() { story_active && [[ ${ST_OBJ[STORY]} == "T.$1" ]]; }      # npc type -> 0 if the story wants me there

story_reward() {  # chapter -> grants its reward, sets ST_POP_R
  local r=${ST_REW[$1]} code
  ST_POP_R="+${ST_XP[$1]} XP  +${ST_GOLD[$1]} gold"
  case $r in
    A.*) aly_unlock "${r#A.}"; ST_POP_R+="  -  ally: ${ALY_NAME[${r#A.}]}" ; return ;;
    U.*) code=$r ;;
    G.W.*) code="W.${DEFW[CLS]}.${r#G.W.}.3" ;;
    G.A.*) code="A.${DEFA[CLS]}.${r#G.A.}.3" ;;
    G.J.*) code="J.$(( RANDOM % 4 )).${r#G.J.}.3" ;;
    *) return ;;
  esac
  item_name "$code" "$CLS"
  ST_POP_R+="  -  $INAME"
  if (( ${#INV[@]} < BAGS )); then INV+=("$code"); NEWG[$code]=1
  else BANK+=("$code"); ST_POP_R+=" (bags full - sent to your bank vault)"; fi
}

story_complete() {
  local s=$STORY
  ST_POP_T="★ CHAPTER $(( s + 1 )) COMPLETE: ${ST_TITLE[s]}"
  ST_POP_A=${ST_DONE[s]}
  STORY=$(( s + 1 )) STORY_P=0
  story_reward "$s"
  GOLD=$(( GOLD + ST_GOLD[s] ))
  logm "${EMJ[quest]}STORY: ${ST_TITLE[s]} complete! +${ST_XP[s]} XP +${ST_GOLD[s]} gold" "$K_ANN"
  gain_xp "${ST_XP[s]}"
  if (( STORY < NST )); then
    ST_POP_B="CHAPTER $(( STORY + 1 )): ${ST_TITLE[STORY]}"
    ST_POP_C=${ST_TEXT[STORY]}
    (( LVL < ST_LVL[STORY] )) && ST_POP_C+="  (Reach level ${ST_LVL[STORY]} to begin this chapter.)"
    send EVT "$MY_ID" "$MY_NAME" "finished the chapter '${ST_TITLE[s]}'."
  else
    ST_POP_B="THE SHATTERED CROWN - COMPLETE"
    ST_POP_C="You are the Crownbearer. The world is yours to wander - the bosses still hunt, the uniques still wait."
    send EVT "$MY_ID" "$MY_NAME" "finished the story of the Shattered Crown! All hail the Crownbearer!"
  fi
  UI=story MAP_DIRTY=1
  save_char
}

story_event() {  # T npc | D dungeon | K monster -> 0 if it moved the story on
  story_active || return 1
  st_obj "$STORY"
  [[ $1 == "$SO_K" && $2 == "$SO_A" ]] || return 1
  if [[ $SO_K == K ]]; then
    STORY_P=$(( STORY_P + 1 ))
    if (( STORY_P < SO_N )); then
      (( STORY_P % 3 == 0 )) && logm "★ Story: ${M_NAME[$SO_A]}s $STORY_P/$SO_N" "$K_LOOT"
      return 1
    fi
  fi
  story_complete
}

story_intro() {  # first login: the dream
  (( STORY == 0 && STORY_SEEN == 0 )) || return
  STORY_SEEN=1
  ST_POP_T="★ THE SHATTERED CROWN"
  ST_POP_A=${ST_TEXT[0]} ST_POP_R=""
  ST_POP_B="CHAPTER 1: ${ST_TITLE[0]}"
  ST_POP_C="Old Tom runs the inn in the north-east corner of Hearthmoor. Press [q] any time to see where your story goes next."
  UI=story MAP_DIRTY=1
}

story_levelup() {
  (( STORY < NST && LVL == ST_LVL[STORY] )) || return
  st_info "$STORY"
  logm "★ New story chapter: ${ST_TITLE[STORY]} - $STXT. See [q]." "$K_ANN"
}

story_line() {  # -> SL (one line for the side panel) or empty
  SL=""
  (( STORY < NST )) || return
  if (( LVL < ST_LVL[STORY] )); then SL="★ ${ST_TITLE[STORY]}: level ${ST_LVL[STORY]}"; return; fi
  st_info "$STORY"; QTX=$STX QTY=$STY; track
  SL="★ $STXT ${K_SYS}$TRK"
}

ui_wrap() {  # text color [indent]
  local rest=$1 w=$(( VW - 6 )) cut
  while (( ${#rest} > w )); do
    cut=${rest:0:w}; cut=${cut% *}; (( ${#cut} < 10 )) && cut=${rest:0:w}
    ui "  ${3:-}$cut" "$2"; rest=${rest:${#cut}}; rest=${rest# }
  done
  [[ -n $rest ]] && ui "  ${3:-}$rest" "$2"
}

ui_story() {
  local roomy=$(( VH >= 26 ))
  (( roomy )) && ui ""
  ui "  $ST_POP_T" "$K_LOOT$B"
  ui ""
  ui_wrap "$ST_POP_A" "$K_CHAT"
  [[ -n $ST_POP_R ]] && { (( roomy )) && ui ""; ui_wrap "$ST_POP_R" "$K_GOOD"; }
  if [[ -n $ST_POP_B ]]; then
    ui ""; (( roomy )) && ui ""
    ui "  $ST_POP_B" "$K_ANN"
    (( roomy )) && ui ""
    ui_wrap "$ST_POP_C" "$K_NPC"
  fi
  ui ""; (( roomy )) && ui ""
  ui "  [enter] continue" "$K_SYS"
}

story_qlog() {  # the story block on top of the quest log
  (( STORY < NST )) || { ui "  ★ THE SHATTERED CROWN - complete. All hail the Crownbearer!" "$K_LOOT$B"; ui ""; return; }
  ui "  ★ STORY - Chapter $(( STORY + 1 ))/$NST: ${ST_TITLE[STORY]}" "$K_LOOT$B"
  if (( LVL < ST_LVL[STORY] )); then
    ui "          Reach level ${ST_LVL[STORY]} to continue the story." "$K_SYS"
  else
    st_info "$STORY"; QTX=$STX QTY=$STY; track
    ui "          $STXT" "$K_CHAT"
    ui "          where: $SWHERE${TRK:+   ->  $TRK}" "$K_SYS"
  fi
  ui "          reward: ${ST_XP[STORY]} XP, ${ST_GOLD[STORY]} gold${ST_REW[STORY]:+ and something special}" "$K_SYS"
  ui ""
}
