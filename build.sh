#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Build shellmmorpg.sh: all modules in src/ (in this order) + the world map.
#  The result is one self-contained bash script - that is what players run.
#    ./build.sh            build
#    ./build.sh --where N  which source file and line is line N of the build
# ---------------------------------------------------------------------------
cd "$(dirname "$0")" || exit 1
out=shellmmorpg.sh
MODULES=(src/01_core.sh src/01b_content.sh src/01c_v3data.sh src/01d_v4data.sh src/01e_v45data.sh src/01f_v50data.sh src/01g_v60data.sh src/01h_v80data.sh src/02_net.sh src/03_server.sh src/03b_server45.sh src/03c_accounts.sh src/03d_admin.sh src/04_client.sh
         src/04b_life.sh src/04c_gfx.sh src/04e_allies.sh src/04f_story.sh src/04g_v3.sh src/05_ui.sh
         src/05b_inv.sh src/05c_bank.sh src/05d_v3ui.sh src/04h_v45.sh src/05e_v45ui.sh src/04i_v50.sh src/05f_v50ui.sh src/04j_v60.sh src/04k_account.sh src/04l_admin.sh src/05g_qol.sh src/04m_v80.sh)

if [[ $1 == --where ]]; then             # map a line of the built script back to its source
  n=$2 at=0
  for f in "${MODULES[@]}"; do
    len=$(( $(wc -l < "$f") + 1 ))       # +1: the blank line between modules
    if (( n <= at + len )); then echo "$f:$(( n - at ))"; exit 0; fi
    at=$(( at + len ))
  done
  echo "world map or src/06_main.sh (line $n)"; exit 0
fi

[[ $(head -c 2 world.txt) ]] || { echo "world.txt missing"; exit 1; }
w=$(head -n 1 world.txt | tr -d '\n' | wc -c) h=$(wc -l < world.txt)
{
  first=1
  for f in "${MODULES[@]}"; do
    (( first )) || echo
    cat "$f"; first=0
  done
  printf '\n# ---------------------------------------------------------------------------\n'
  printf '#  The open world (%sx%s), made by tools/worldgen. Legend:\n' "$w" "$h"
  printf '#  . , " * grass/flowers  T trees  P pines  ~ water  = bridge  : road  ^ mountains\n'
  printf '#  %% swamp  S s sand/dunes  Y cactus  N n snow  I ice  A ash  L lava  R rock\n'
  printf '#  K C crystal ground/spires  J W jungle ground/trees  D V badlands/mesas\n'
  printf '#  E G void ground/chasms  # walls  _ floor  > dungeon  Q quest board  O fountain\n'
  printf '#  F campfire  Z waystone\n'
  printf '# ---------------------------------------------------------------------------\n'
  printf "world_data() {\n  cat <<'WORLD'\n"
  cat world.txt
  printf "WORLD\n}\n\n"
  cat src/06_main.sh
} > "$out"
chmod +x "$out"
bash -n "$out" && echo "built $out: $(wc -l < "$out") lines, $(wc -c < "$out") bytes"
