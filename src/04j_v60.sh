# ---------------------------------------------------------------------------
#  Module 04j - v6.0 client: what the new content needs once the sprites and
#  screens exist - icons of the new materials, the sprites of the hunter's
#  trophies, the achievements of 6.0, and the "what is it for" of a material
#  (it follows the tables now, for every material there is).
# ---------------------------------------------------------------------------
MAT_I[M60]=🔵 MAT_I[M60+1]=🟣 MAT_I[M60+2]=🌾 MAT_I[M60+3]=🍇 MAT_I[M60+4]=🐠 MAT_I[M60+5]=🐟
for i in ${COL_SETL[6]}; do CL_E[i]=${MEMO[CL_REF[i]]:-🎯}; done; unset i

ach_ok60() {  # achievements of 6.0 (index ACH60 and up)
  local n
  case $(( $1 - ACH60 )) in
    0) (( RAREK >= 50 )) ;;
    1) col_count; (( CLSD[6] >= CLST[6] )) ;;
    2) col_count; (( CLN >= 100 )) ;;
    3) n=${QLS//[^x]/}; (( ${#n} >= 25 )) ;;
    4) (( DCLR >= 250 )) ;;
    *) return 1 ;;
  esac
}

mat_uses() {  # material -> MU (lines): what the crafting tables do with it (v6.0: from the recipes, not from index ranges)
  local k=$1 i t TW2=0 sv=$CRAFT sf=$FWK sa=$FAK seen=" "
  MU=()
  if gem_kq "$k"; then
    local g=$GKI q=$(( GQI - 1 )) v=(${GEM_V[GKI]})
    MU+=("In a socket: +${v[q]}${GEM_TXT[g]}." "Jewelcrafting at any smith sets it into gear with sockets.")
    (( q < GEM_MAXQ - 1 )) && MU+=("Three of them make one ${GEM_GRADE[q+1]} ${GEM_NAME[g]}.")
    return
  fi
  mat_prof "$k"
  case $MP_K in
    1) CRAFT=forge; craft_build
       for i in "${!RC_ID[@]}"; do
         [[ " ${RC_NEED[i]} " == *" $k:"* && ${RC_ID[i]} == W.* ]] || continue
         t=${RC_ID[i]##*.}; [[ $seen == *" $t "* ]] && continue; seen+="$t "
         MU+=("Forge (any smith): ${TIER_Q[t]} weapons and armor - $(( 15 * t * t ))g, often Rare or better.")
       done ;;
    2) CRAFT=alch; craft_build
       for i in "${!RC_ID[@]}"; do
         [[ " ${RC_NEED[i]} " == *" $k:"* ]] || continue
         t=" ${RC_NEED[i]}"; t=${t#* $k:}; t=${t%% *}
         MU+=("Alchemy: ${RC_LAB[i]%% (*} ($t)")
       done ;;
    *) if (( MAT_RARE[k] == 2 )); then MU+=("Cooking: Fisherman's Feast"); else MU+=("Cooking: Grilled Fish"); fi
       MU+=("General stores, traders and spice stalls buy fish.") ;;
  esac
  (( ${#MU[@]} )) || MU+=("Shops pay ${MAT_VAL[k]}g for it.")
  CRAFT=$sv FWK=$sf FAK=$sa
}
