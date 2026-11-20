#!/usr/bin/env bash
# Dungeons and the world server: generation, reachability, instances, loot, cleanup.
source "$(dirname "$0")/lib.sh"
load_world
send() { SENT+=("$*"); return 0; }
slog() { :; }
SENT=() NOW=1000000

reach() {  # map sx sy tx ty -> 0 if a player can walk from s to t
  local map=$1 tx=$4 ty=$5 q=("$2 $3") h=0 x y d nx ny
  local -A seen=(["$2,$3"]=1)
  while (( h < ${#q[@]} )); do
    read -r x y <<< "${q[h]}"; h=$(( h + 1 ))
    (( x == tx && y == ty )) && return 0
    for d in "1 0" "-1 0" "0 1" "0 -1"; do
      read -r nx ny <<< "$d"; nx=$(( x + nx )) ny=$(( y + ny ))
      [[ -n ${seen[$nx,$ny]} ]] && continue
      p_walk "$map" "$nx" "$ny" || continue
      seen[$nx,$ny]=1; q+=("$nx $ny")
    done
  done
  return 1
}

# --- every dungeon type generates a playable layout --------------------------------------
for (( dt = 0; dt < NDT; dt++ )); do
  for seed in 1 77 4242 987654; do
    map=T$dt
    gen_dungeon "$map" "$dt" "$seed"
    ge "${D_NAME[dt]} seed $seed rooms" "${#DG_ROOMS[@]}" 4
    w=${MAPW[$map]} bad=0
    for (( y = 0; y < MAPH[$map]; y++ )); do (( ${#MAPROW[$map:$y]} == w )) || bad=1; done
    eq "${D_NAME[dt]} seed $seed rows are $w wide" "$bad" 0
    check "${D_NAME[dt]} seed $seed start walkable" p_walk "$map" "$DG_SX" "$DG_SY"
    check "${D_NAME[dt]} seed $seed boss reachable" reach "$map" "$DG_SX" "$DG_SY" "$DG_BX" "$DG_BY"
    a=$DG_SX b=$DG_SY c=$DG_BX
    gen_dungeon "$map" "$dt" "$seed"
    eq "${D_NAME[dt]} seed $seed is deterministic" "$DG_SX $DG_SY $DG_BX" "$a $b $c"
    for (( y = 0; y < MAPH[$map]; y++ )); do unset "MAPROW[$map:$y]"; done
  done
done

# --- the world server: spawning, instances, loot, cleanup -----------------------------------
spawn_world
ge "monsters in the open world" "$NMON" 400
bad=0
for m in "${!AL[@]}"; do
  m_walk W "${MX[m]}" "${MY[m]}" || [[ $T == [\#TRCQOFYPZVW^] ]] || { bad=$(( bad + 1 )); (( bad < 4 )) && fail "monster $m (${M_NAME[${MT[m]}]}) spawned on '$T'"; }
done
eq "monsters spawned on bad tiles" "$bad" 0

SP_NAME[aaaaaa]=alice SP_MAP[aaaaaa]=W SP_X[aaaaaa]=${D_ENTX[0]} SP_Y[aaaaaa]=${D_ENTY[0]} SP_LVL[aaaaaa]=5 SP_DEAD[aaaaaa]=0 SP_CLS[aaaaaa]=0
before=$NMON
for (( dt = 0; dt < NDT; dt++ )); do
  SENT=() DREQ_T=()
  srv_dreq aaaaaa "$dt"
  map=${SOLO_INST[aaaaaa]}
  [[ -n $map ]] || { fail "dungeon $dt: no instance"; continue; }
  boss=0 elite=0 chests=0 bad=0
  for m in ${IN_MONS[$map]}; do
    t=${MT[m]}
    (( t == D_BOSS[dt] )) && boss=1
    (( t == D_ELITE[dt] )) && elite=1
    (( t == CHEST )) && chests=$(( chests + 1 ))
    p_walk "$map" "${MX[m]}" "${MY[m]}" || bad=1
  done
  eq "${D_NAME[dt]}: boss spawned" "$boss" 1
  eq "${D_NAME[dt]}: elite spawned" "$elite" 1
  ge "${D_NAME[dt]}: chests" "$chests" 1
  eq "${D_NAME[dt]}: monsters on floor tiles" "$bad" 0
  [[ " ${SENT[*]} " == *"DSTART srv $map $dt "* ]] && ok || fail "${D_NAME[dt]}: no DSTART sent"
  # re-entering resumes the same instance ...
  DREQ_T=(); srv_dreq aaaaaa "$dt"; eq "${D_NAME[dt]}: re-entry resumes" "${SOLO_INST[aaaaaa]}" "$map"
  # ... until its boss is dead
  for m in ${IN_MONS[$map]}; do (( MT[m] == D_BOSS[dt] )) && mon_die "$m" aaaaaa; done
  eq "${D_NAME[dt]}: boss death marks the dungeon done" "${IN_DONE[$map]}" 1
  [[ " ${SENT[*]} " == *"DCLEAR srv $map"* ]] && ok || fail "${D_NAME[dt]}: no DCLEAR"
  close_instance "$map"
  eq "${D_NAME[dt]}: closing frees the monsters" "${#IN_MONS[$map]}" 0
  left=0; for m in "${!MMAP[@]}"; do [[ ${MMAP[m]} == "$map" ]] && left=$(( left + 1 )); done
  eq "${D_NAME[dt]}: no monster entries left" "$left" 0
  eq "${D_NAME[dt]}: instance forgotten" "${SOLO_INST[aaaaaa]:-}" ""
done
gt "instances spawned monsters" "$NMON" "$before"

# --- requests are rate-limited and validated ------------------------------------------------
DREQ_T=() SENT=(); srv_dreq aaaaaa 0; n=${#IN_TYPE[@]}
srv_dreq aaaaaa 1; eq "a second request within 1.5 s is ignored" "${#IN_TYPE[@]}" "$n"
for bad in "$NDT" -1 01 'a[$(id)]' ''; do DREQ_T=(); n=${#IN_TYPE[@]}; srv_dreq aaaaaa "$bad"; eq "dungeon request '$bad' rejected" "${#IN_TYPE[@]}" "$n"; done
SHELLMMO_MAX_INST=${#IN_TYPE[@]}; DREQ_T=(); SOLO_INST=(); srv_dreq aaaaaa 2
eq "instance cap holds" "${#IN_TYPE[@]}" "$SHELLMMO_MAX_INST"; unset SHELLMMO_MAX_INST

# --- hits: damage cap, gathering, guards ----------------------------------------------------
for m in "${!AL[@]}"; do [[ ${MMAP[m]} == W ]] && (( M_KIND[MT[m]] == 0 && M_BOSS[MT[m]] == 0 )) && { wolf=$m; break; }; done
hp=${MHP[wolf]}
srv_hit aaaaaa W "$wolf" 999999 0
le "damage is capped by level" $(( hp - ${MHP[wolf]:-0} )) $(( (5 + 5) * 70 ))
for bad in '1+1' '08' 'a[$(id)]' -5; do srv_hit aaaaaa W "$bad" 10 0; ok; done
srv_line 'SM1|HIT|aaaaaa|W|a[$(touch /tmp/pwned_by_test)]|5|0'
check "arithmetic injection via HIT is inert" test ! -e /tmp/pwned_by_test

t_end
