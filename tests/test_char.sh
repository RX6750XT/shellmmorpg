#!/usr/bin/env bash
# The hero: save files, leveling, the story, allies, the bank, quests.
source "$(dirname "$0")/lib.sh"
stub_client
save_char_real=1

# --- save / load roundtrip ------------------------------------------------------------
new_hero 6 17
GOLD=12345 INV=(W.0.5.2 U.4 B.2 A.1.3.0!) BAGEQ=(3 - 1) BANK=(H.0.2.1) BANKG=777 STORY=7 STORY_P=2
QUESTS=(K.5.10.3.100.50) MATS[3]=42 PROF_LV=(4 2 9) PROF_XP=(10 0 99) ALLIES=101000000000 ALLY=2 SYM='&'
save_char
snap="$GOLD|${INV[*]}|${BAGEQ[*]}|${BANK[*]}|$BANKG|$STORY|$STORY_P|${QUESTS[*]}|${MATS[3]}|${PROF_LV[*]}|${PROF_XP[*]}|$ALLIES|$ALLY|$SYM|$LVL|$CLS"
new_hero 0 1
check "load_char reads the save" load_char
ALLY=$(( ALLYN - 1 ))
eq "save roundtrip" "$GOLD|${INV[*]}|${BAGEQ[*]}|${BANK[*]}|$BANKG|$STORY|$STORY_P|${QUESTS[*]}|${MATS[3]}|${PROF_LV[*]}|${PROF_XP[*]}|$ALLIES|$ALLY|$SYM|$LVL|$CLS" "$snap"
check "no temp file left behind" test ! -e "$CHAR_FILE.tmp"

# --- a hostile save file cannot inject code or break limits --------------------------------
cat > "$CHAR_FILE" <<'EOF'
version=2
CLS=3
LVL=999
GOLD=$(touch /tmp/pwned_by_save)
XP=a[$(touch /tmp/pwned_by_save)]
INV=W.0.1.0 a[$(touch /tmp/pwned_by_save)] U.99 W.0.2.0
QUESTS=K.1.2.3.4.5 K.a[$(touch /tmp/pwned_by_save)].1.1.1.1
MATS=5 x 7
SYM=|
PROF=99 1 1 1 1 1
EOF
check "a hostile save still loads" load_char
check "nothing was executed" test ! -e /tmp/pwned_by_save
eq "level clamped" "$LVL" 1
eq "only valid items kept" "${INV[*]}" "W.0.1.0 W.0.2.0"
eq "only valid quests kept" "${QUESTS[*]}" "K.1.2.3.4.5"
eq "protocol separator refused as symbol" "$SYM" "@"
eq "profession level clamped" "${PROF_LV[0]}" 1
printf 'garbage\n' > "$CHAR_FILE"; if load_char; then fail "a save without version must not load"; else ok; fi

# --- leveling ---------------------------------------------------------------------------
new_hero 0 1
gain_xp 100000
gt "XP levels you up" "$LVL" 5
calc_stats; h1=$MAXHP; new_hero 0 1; calc_stats
gt "higher level, more HP" "$h1" "$MAXHP"

# --- the story: every chapter can be completed in order ---------------------------------------
new_hero 2 30
init_where
for (( s = 0; s < NST; s++ )); do
  eq "chapter $s is current" "$STORY" "$s"
  st_obj "$s"
  case $SO_K in
    T) story_event T "$SO_A" ;;
    D) CUR_DT=$SO_A; story_event D "$SO_A" ;;
    K) for (( i = 0; i < SO_N; i++ )); do story_event K "$SO_A"; done ;;
  esac
  UI=""
done
eq "the story ends" "$STORY" "$NST"
st=0; for (( i = 0; i < NALY; i++ )); do aly_has "$i" && st=$(( st + 1 )); done
ge "the story hands out allies" "$st" 1
new_hero 2 1; STORY=5
story_event "${ST_OBJ[5]%%.*}" "$(cut -d. -f2 <<< "${ST_OBJ[5]}")"
eq "a chapter above your level waits" "$STORY" 5

# --- allies fight and heal ------------------------------------------------------------------
new_hero 0 20; EQW=W.0.7.1; calc_stats; HP=$MAXHP
PX=100 PY=34 CUR_MAP=W FDX=1 FDY=0
p_walk W 103 34 || { PX=$SPAWN_X PY=$SPAWN_Y; }
cm_set 5 2 $(( PX + 3 )) "$PY" 34 34; TARGET=5
ALLIES=11100000; ALLY=0; aly_place
check "an ally appears next to you" test -n "$AX"
cheb $(( AX - PX )) $(( AY - PY )); le "ally placed close" "$D" 2
hp0=${CM_HP[5]}
for i in 1 2 3 4 5 6; do NOW=$(( NOW + 1200 )); aly_tick; done
hits=0; for s in "${SENT[@]}"; do [[ $s == HIT* ]] && hits=$(( hits + 1 )); done
ge "the fighter attacked the target" "$hits" 1
ALLY=2; aly_place; HP=$(( MAXHP / 2 )); h=$HP
NOW=$(( NOW + 6000 )); aly_tick
gt "the healer heals you" "$HP" "$h"
aly_dismiss; eq "dismissed" "$ALLY" -1
for cs in "0 2" "3 1" "7 2"; do              # battle cry, heal and anthem talk about "allies" - the ally stays
  read -r c k <<< "$cs"; new_hero "$c" 20; ALLIES=11111111; ALLY=1; aly_place; MP=999 SKCD=(0 0 0)
  cast "$k"; eq "class $c skill $k keeps the ally" "$ALLY" 1
done

# --- the bank: items and gold go in and come out ---------------------------------------------
new_hero 0 10; GOLD=500 INV=(W.0.1.0 A.0.1.0); TALK_T=$BANK0
bank_open
BK_TAB=0 BK_SIDE=0 BK_CUR=(0 0); bk_transfer
eq "item stored" "${#BANK[@]}" 1; eq "bags shrink" "${#INV[@]}" 1
BK_SIDE=1 BK_CUR=(0 0); bk_transfer
eq "item taken back" "${#INV[@]}" 2; eq "vault empty" "${#BANK[@]}" 0
bk_gold dep 300; eq "gold deposited" "$GOLD/$BANKG" 200/300
bk_gold wd 1000; eq "withdraw is capped by the vault" "$GOLD/$BANKG" 500/0
BK_TAB=1; bk_store; sc_load; INV=(W.0.3.0); BK_SIDE=0 BK_CUR=(0 0); bk_transfer
check "the shared chest is written to disk" test -s "$SC_FILE"
SC_ITEMS=(); sc_load; eq "the shared chest survives a reload" "${SC_ITEMS[*]}" W.0.3.0

# --- quests: offers, kill counting, rewards -----------------------------------------------------
new_hero 0 8; QSRC=board; gen_offers
ge "the board offers quests" "${#OFFERS[@]}" 1
q=${OFFERS[0]}; QUESTS=("$q")
IFS=. read -r -a f <<< "$q"
g=$GOLD
if [[ ${f[0]} == K ]]; then
  for (( i = 0; i < f[2]; i++ )); do reward 1 0 "" "${f[1]}"; done
  eq "kill quest completes" "${#QUESTS[@]}" 0
  gt "quest pays gold" "$GOLD" "$g"
else ok; ok; fi

t_end
