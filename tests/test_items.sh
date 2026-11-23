#!/usr/bin/env bash
# Items: codes, stats, names, loot rolls, bags, equipping, the inventory screen logic.
source "$(dirname "$0")/lib.sh"
stub_client

nk() { declare -n _a=$1; echo "${#_a[@]}"; }
# --- every gear code is valid and has sane stats --------------------------------------
n=0
for s in W A O H J; do
  case $s in W) nkind=$(nk WK_NAME) ;; A) nkind=$(nk AK_NAME) ;; O) nkind=$(nk OK_NAME) ;; H) nkind=$(nk HK_NAME) ;; J) nkind=$(nk JK_NAME) ;; esac
  for (( k = 0; k < nkind; k++ )); do
    for t in 1 5 9; do
      for r in 0 3; do
        c="$s.$k.$t.$r"
        valid_item "$c" || { fail "$c should be valid"; continue; }
        item_name "$c" 0
        [[ -n $IKN && -n $INAME && -n $ICLS ]] || fail "$c: name '$INAME' kind '$IKN' classes '$ICLS'"
        [[ $s == W ]] && { (( IVAL > 0 )) || fail "$c: weapon without damage"; }
        (( ISELL > 0 )) || fail "$c: sells for $ISELL"
        n=$(( n + 1 ))
      done
    done
  done
done
ge "gear codes checked" "$n" 100
for (( k = 0; k < 6; k++ )); do check "bag B.$k valid" valid_item "B.$k"; item_name "B.$k" 0; eq "bag B.$k kind" "$IK" B; done
for c in W.0.1.0! U.0! B.2!; do check "locked $c valid" valid_item "${c%!}"; done

# --- garbage is rejected (codes arrive over the network and from save files) -----------
for c in "" W W.0 W.0.0.0 W.0.16.0 W.0.1.4 W.01.1.0 W.99.1.0 X.0.1.0 B.6 B.-1 U.01 "W.0.1.0 " \
         'W.0.1.$(id)' 'U.a[$(id)]' 'B.0;ls' W.0.1.0.0 W.0.1.0.x1 W.0.1.0._ W.0.1.0.r5 'W.0.1.0.r1r1r1r1' U.$NUQ; do
  if valid_item "$c"; then fail "'$c' must be invalid"; else ok; fi
done

# --- the item level curve: higher tier and rarity are never weaker ---------------------
item_stats W.0.1.0; a=$IVAL; item_stats W.0.9.0; b=$IVAL; item_stats W.0.9.3; c=$IVAL
gt "tier raises damage" "$b" "$a"; gt "rarity raises damage" "$c" "$b"
item_stats U.0; eq "uniques are rarity 4" "$IRR" 4

# --- loot rolls produce only valid things ------------------------------------------------
declare -A SP_CLS=([abc123]=0)
bad=0 got=0 uq=0
for (( t = 0; t < NM; t++ )); do
  (( M_KIND[t] == 0 || M_KIND[t] == 4 )) || continue
  for (( i = 0; i < 12; i++ )); do
    roll_item "$t" abc123
    [[ -z $ITEM || $ITEM == [HM] ]] && continue
    got=$(( got + 1 )); [[ $ITEM == U.* ]] && uq=$(( uq + 1 ))
    valid_item "$ITEM" || { bad=$(( bad + 1 )); fail "monster $t rolled invalid '$ITEM'"; }
  done
done
eq "invalid loot rolls" "$bad" 0
ge "loot rolls that produced gear" "$got" 100
for (( i = 0; i < 300; i++ )); do roll_item "$CHEST" abc123 30; [[ $ITEM == *.*.*.* || $ITEM == [BU].* ]] || { fail "chest gave '$ITEM'"; break; }; done; ok

# --- bags, equipping, auto-sell --------------------------------------------------------
new_hero 0 10
eq "starting bag slots" "$BAGS" 10
INV=(B.3); bag_equip 0; bag_cap
eq "a worn B.3 adds its slots" "$BAGS" $(( 10 + BAG_SZ[3] ))
eq "worn bag leaves the bags" "${#INV[@]}" 0
INV=(); g=$GOLD
for (( i = 0; i < BAGS; i++ )); do INV+=(W.0.1.0); done
add_item A.0.1.0
eq "full bags: nothing added" "${#INV[@]}" "$BAGS"
gt "full bags: the item was sold" "$GOLD" "$g"
add_item U.3
eq "uniques are never auto-sold" "${INV[-1]}" U.3
INV=(W.0.5.2 A.0.5.1 H.0.5.0)
ow=$EQW; inv_equip 0 quiet
eq "equip swaps the weapon in" "$EQW" W.0.5.2
eq "the old weapon goes to the bags" "${INV[0]}" "$ow"
calc_stats; a=$ATK; EQW=W.0.9.3; calc_stats
gt "a better weapon raises ATK" "$ATK" "$a"
INV=(W.0.1.0 U.2 B.1 W.0.9.3 A.0.3.0); sort_items INV
eq "sorting keeps every item" "${#INV[@]}" 5

# --- class restrictions ------------------------------------------------------------------
new_hero 1 10                      # mage
for (( k = 0; k < $(nk WK_NAME); k++ )); do
  item_stats "W.$k.3.0"
  if [[ $ICLS == *1* ]]; then check "mage can use ${WK_NAME[k]}" can_use "W.$k.3.0" 1
  else if can_use "W.$k.3.0" 1; then fail "mage must not use ${WK_NAME[k]}"; else ok; fi; fi
done
EQW=W.0.9.3; calc_stats; a=$ATK; EQW=""; calc_stats
item_stats W.0.9.3
[[ $ICLS == *1* ]] || eq "gear your class can't use does nothing" "$a" "$ATK"

t_end
