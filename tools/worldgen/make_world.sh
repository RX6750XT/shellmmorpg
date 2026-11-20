#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Rebuild the world map.
#    tools/worldgen/make_world.sh            generate, check, show the difference
#    tools/worldgen/make_world.sh --install  ... and make it the game's world.txt
#    tools/worldgen/make_world.sh --full     start from scratch (genmap -> v1.1
#                                            edits are NOT reproduced, see README)
# ---------------------------------------------------------------------------
here=$(cd "$(dirname "$0")" && pwd)
root=$(cd "$here/../.." && pwd)
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
set -e
if [[ $1 == --full ]]; then
  echo "history/extend.py: 240x100 world from world_v11.txt"
  python3 "$here/history/extend.py" "$tmp/world_v18.txt" > /dev/null 2>&1
  cmp -s "$tmp/world_v18.txt" "$here/world_v18.txt" && echo "  = world_v18.txt (unchanged)" || echo "  differs from world_v18.txt"
fi
echo "extend2.py: 360x150 world from world_v18.txt"
python3 "$here/extend2.py" "$tmp/world_v20.txt" > "$tmp/log" 2>&1
cmp -s "$tmp/world_v20.txt" "$here/world_v20.txt" && echo "  = world_v20.txt (unchanged)" || echo "  differs from world_v20.txt"
echo "extend4.py: 480x200 world from world_v20.txt"
python3 "$here/extend4.py" "$tmp/world.txt" > "$tmp/log" 2>&1
python3 "$here/check_world.py" "$tmp/world.txt"
if cmp -s "$tmp/world.txt" "$root/world.txt"; then
  echo "identical to the current world.txt"
else
  n=$(diff <(fold -w1 < "$tmp/world.txt") <(fold -w1 < "$root/world.txt") | grep -c '^<' || true)
  echo "differs from the current world.txt in about $n tiles"
  if [[ $1 == --install || $2 == --install ]]; then
    cp "$tmp/world.txt" "$root/world.txt"; echo "installed - now run ./build.sh"
  fi
fi
