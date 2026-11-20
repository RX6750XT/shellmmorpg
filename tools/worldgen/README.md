# World generation

The world map (`world.txt` in the project root) grew in three steps:

| Step | Script | Result |
| --- | --- | --- |
| 1.0 | `history/genmap.py` | `history/world_v1.txt` - the first 160×64 world |
| 1.1 | by hand (88 tiles) | `history/world_v11.txt` |
| 1.2 | `history/extend.py` | `world_v18.txt` - 240×100, the world of v1.2 - v1.8 |
| 2.0 | `extend2.py` | `world_v20.txt` - 360×150 with the five new lands (v2.0 - v3.0) |
| 4.0 | `extend4.py` | `world.txt` - 480×200 with seven more lands for levels 30-40 |

Every step is deterministic (fixed random seeds), so

```bash
tools/worldgen/make_world.sh            # rerun extend2.py + extend4.py, check, compare with world.txt
tools/worldgen/make_world.sh --full     # also rerun extend.py from v1.1
tools/worldgen/make_world.sh --install  # replace world.txt with the generated map
python3 tools/worldgen/check_world.py   # check any map: size, tiles, reachability
```

The generators are history: once the map is generated, `world.txt` is the
truth and can be edited by hand (see `docs/MODDING.md`). Only run
`--install` if you changed a generator and want its output.
