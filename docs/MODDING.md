# Adding content

Almost everything in the game is a table in `src/01_core.sh` (the original
lands) and `src/01b_content.sh` (v2.0). Tables are **parallel bash arrays
indexed by position**: entry *n* of `M_NAME`, `M_HP`, `M_LVL`... all describe
monster type *n*. So the golden rules:

1. **Append, never insert.** Save files, quest codes, item codes and other
   tables refer to things by index. Inserting shifts everything after it.
2. **Every parallel table gets an entry.** `tests/test_content.sh` checks the
   lengths - run it (or `tests/run.sh quick`) after every change.
3. Rebuild with `./build.sh`; the game is the built `shellmmorpg.sh`.

The safest place for new content is the end of `01b_content.sh`, or a new
module `src/01c_mymod.sh` added to `MODULES` in `build.sh` right after
`01b_content.sh` (tables must exist before the code that uses them runs).

## A new monster

```bash
M_NAME+=("Swamp Troll") M_GLY+=(t) M_COL+=("1;38;5;100")   # name, ASCII glyph, 256-color SGR
M_LVL+=(9) M_HP+=(260) M_DMG+=(24) M_XP+=(180) M_GOLD+=(30)
M_AGGRO+=(6)        # notices you within 6 tiles (0 = only fights back)
M_MOVE+=(600) M_ATK+=(1200)   # ms per step / per attack
M_BOSS+=(0)         # 0 normal, 1 boss, 2 elite
M_KIND+=(0)         # 0 hostile, 1 townsperson, 2 guard, 3 resource node, 4 chest
NM=${#M_NAME[@]}
```

- HD sprite: append an emoji to `MEMO` in `src/04c_gfx.sh` at the same
  index (without one the ASCII glyph is shown).
- Make it live somewhere: `ZONES+=("<type> x1 y1 x2 y2 count")` spawns
  `count` of them on random walkable tiles in the rectangle.
- Quest boards pick kill quests from `WORLD_TYPES` (types near the player's
  level); quest givers from `N_QK[npc]`. Add the new type there if wanted.
- Undead get stronger at night: add the type to `UNDEAD` (space separated).
- In a dungeon pool: add the type to `D_POOL[dungeon]`.

## A new NPC

NPCs are monsters of kind 1 (or 2 for guards) with a role:

```bash
M_NAME+=("Gwen") M_GLY+=(G) M_COL+=("1;38;5;213;$NPCBG") M_LVL+=(12) M_HP+=(900) M_DMG+=(40)
M_XP+=(100) M_GOLD+=(200) M_AGGRO+=(0) M_MOVE+=(900) M_ATK+=(1100) M_BOSS+=(0) M_KIND+=(1)
NM=${#M_NAME[@]}; t=$(( NM - 1 ))
N_ROLE[$t]=smith               # general smith alchemist inn bank merc questgiver trader medic villager ...
N_FULL[$t]="Gwen the Tinker"   # the name in dialogs
N_HOME[$t]="Ironwood Camp"     # where quests say she is
NPC_SPAWNS+=("$t 116 37 0")    # type x y wander-radius
```

- What they say: `N_SAY[role]` holds `|`-separated lines for each role.
- Quest givers: `N_QK[$t]="monster types"`, `N_QD[$t]=dungeon type`,
  `N_QT[$t]=npc type` (who gets the letter).
- Shops: `shop_build` in `src/04_client.sh` decides the stock per role.

## Gear

Gear kinds are tables per slot: weapons `WK_*`, armor `AK_*`, offhand
`OK_*`, helmets `HK_*`, trinkets `JK_*`:

```bash
WK_NAME+=(Rapier) WK_E+=(🤺)        # name, HD icon
WK_CLS+=(04)                        # classes that may use it: digits 0-7 (Warrior=0 ... Bard=7)
WK_DMG+=(104)                       # damage in % of the tier's base
WK_BT+=(crit) WK_BV+=(6)            # bonus: crit hp mp arm dmg light, and its strength
```

Item codes stay valid as long as there are at most 100 kinds per slot.
Tiers are 1-9 (`TIER_Q` names them), rarities 0-3 (`RAR_*`).

**Uniques** (named legendaries) are `U_*` (name, slot, kind, tier, bonus,
flavor text). Who drops them: `U_DROP+=("<boss type>:<unique>:<chance %>")`.
Story chapters can give them as a reward (`U.<n>`).

## A new dungeon

```bash
D_NAME+=("Sunken Bell") D_REQ+=(19)
D_POOL+=("45 79 76")                 # monster types inside
D_BOSS+=(<boss type>) D_ELITE+=(<elite type>)   # M_BOSS 1 and 2
D_ENTX+=(60) D_ENTY+=(130)           # entrance: must be a '>' tile in world.txt
D_WHERE+=("Sapphire Isles, west")
D_WALL+=("38;5;30") D_FLOOR+=("38;5;23")         # ASCII colors
D_W+=(88) D_H+=(32) D_ROOMS+=(12) D_CHESTS+=(3)  # size
NDT=${#D_NAME[@]}
```

and append a wall emoji to `D_WE` in `src/04c_gfx.sh`. Put the `>` into
`world.txt` (see below). `tests/test_world.sh` generates every dungeon with
several seeds and checks that the boss can be reached.

## Allies

`ALY_NAME ALY_SHORT ALY_G (ASCII glyph) ALY_ROLE (melee ranged heal magic)
ALY_PCT (damage in % of yours) ALY_RNG (range) ALY_CD (ms between actions)
ALY_COST ALY_SELL (the merc NPC type, -1 = not for sale) ALY_DESC`, plus an
HD sprite `ALY_E`. At most 9 allies (the network sends one digit).

## Story chapters

`ST_TITLE ST_LVL ST_OBJ ST_XP ST_GOLD ST_REW ST_TEXT ST_DONE`, one entry per
chapter, in order. Objectives: `T.<npc type>` talk to, `D.<dungeon>` clear,
`K.<monster type>.<count>` slay. Rewards: `A.<ally>`, `U.<unique>`,
`G.W.<tier>` / `G.A.<tier>` / `G.J.<tier>` (epic class gear), or empty.
`tests/test_char.sh` plays the whole story through.

## The world map

`world.txt` is the map: 360 characters per line, 150 lines, one character
per tile (the legend is in `build.sh`). Edit it with any text editor that
keeps the lines aligned, then `./build.sh`.

- Walkable: `.,"*:=_%<>SsNnIAKJDE` - everything else blocks.
- Towns are drawn with `#` walls, `_` floors, `:` roads; mark them in
  `SAFE_RECTS` (monsters never enter, streets are lit at night) and
  `REGIONS` (name + level shown in the header).
- `Z` is a waystone (add it to `WAYSTONES`), `F` a campfire (light + cooking),
  `Q` a quest board, `O` a fountain, `>` a dungeon entrance.
- `python3 tools/worldgen/check_world.py` checks size, tiles and that every
  entrance and waystone can be reached from the spawn.

The current map was generated by `tools/worldgen/extend2.py` from
`world_v18.txt` (the 240×100 world of v1.8), which `history/extend.py` made
from the hand-edited v1.1 map. `tools/worldgen/make_world.sh` reruns the
generator and shows the difference to the current map. Hand edits after
that are fine - the generator is history, `world.txt` is the truth.

## New tiles

A new tile character needs: walkability (`p_walk`, `m_walk`, `blocks_shot`
in `01_core.sh`), an ASCII color (`Z_*` and a line in `colorize1`), an HD
look (`Z2_*` in `04c_gfx.sh`, a line in `colorize2`, the background in
`T2C`/`T2V`, the moonlit sketch in `dark_glyphs`, the grey world-map sketch
in `paint`), and the legend in `build.sh` and `check_world.py`.

## v8.0: Beyond the Edge (`src/01h_v80data.sh`)

The newest content module, and the easiest place to add more. It runs
**after** the classifier (01g), so:

- **A creature**: `m8 VAR "Name" glyph color level hp% dmg% aggro move atk
  emoji el weak resist ability range [healer]` sets its element itself.
  Bosses, elites and world bosses: `mb8` (like `m4` with a boss column,
  plus the element columns). Then `WORLD_TYPES`, a `ZONES` line, a
  `QI_NAME`. A rare (`add_rares`) has to copy its base's element - see the
  loop after `add_rares` there.
- **Levels above 50**: raise `MAXLVL`, append to `_SL/_SH/_SD/_SX/_SG`
  (`base_stats`), and for gear `MAXTIER`, `TIER_Q`, `MAT_E`, `TIER_FL` and
  the tier range in `valid_item` (`1[0-5]`).
- **A town**: `T8_NAME/T8_X/T8_Y` and `n8 town slot role ...` (slots
  `T8_DX/T8_DY`, 0 = the town's questgiver), then `SAFE_RECTS`, `REGIONS`,
  `WAYSTONES`, `TOWN_FAC` (the loop after the townsfolk).
- **A raid**: a boss with `M_RAID[boss]=<n>`, the dungeon in `D_RAID`, its
  name and lines in `RAID_NAME`/`RAID_ANN`/`RAID_SHIELD`, its uniques for
  `raid_finish` (`src/03b_server45.sh`); `M_RAID` 2 uses `raid2_attack`,
  anything else Nyxara's `raid_attack`.
- **A faction**: `FAC_NAME FAC_E FAC_COL`, and its quartermaster unique in
  `FAC_UQX[faction]` (the old ones are `FAC_UQ0 + faction`).
- **A mount**: as in 4.5, plus a key in `MNT_KEYS` (13 now: `1`-`9`, `a`-`d`).
- **A room**: `ROOM_*` and a `ROOM_LAY` line; the inn takes `[2]`-`[9]`.
- **The map**: `tools/worldgen/extend8.py` paints x 480-599 onto
  `world_v40.txt` (the map of 4.0-7.2). No new tiles were needed.

## v6.0: more of everything (`src/01g_v60data.sh`)

The easiest place for new content now. Patterns:

- **A creature**: one `m6` line (`m4` plus element, weakness, resistance,
  ability - `-` for none - and range), then `WORLD_TYPES`, a `ZONES` entry
  and a `QI_NAME`. The classifier runs at the end of this file, after which
  the `m6` elements win.
- **A rare elite**: `add_rares "Name:base:level:x:y"` - it gets a hunter's
  trophy by itself.
- **A dungeon**: a boss (`m4 ... 1`) and an elite (`m4 ... 2`), one entry in
  every `D_*` table, a `>` at `D_ENTX/D_ENTY` in `world.txt`, a `cl 0`
  trophy line and `U_DROP`s.
- **A material**: `MAT_NAME MAT_VAL MAT_RARE MAT_PK`, its group in
  `MAT_GRP`, an icon in `04j_v60.sh`, a node (kind 3) with `NODE_MAT
  NODE_PK NODE_T` and zones, or a `FISHW` entry; recipes in `FORGE_X`
  (`"tier:mat:n mat:n"`) or `ALCH_X` (`"id:label:mat:n mat:n"`).
- **Townsfolk**: `n45 x y role "Full Name" short glyph color emoji home` -
  check with `tests/test_content.sh` that they stand on the floor.

## v5.0: housing and collectables (`src/01f_v50data.sh`)

- **A collectable**: one `cl` line - `set rarity emoji glyph ref "Name"
  "story"`. The emoji must be 2 columns wide (`tests/test_v50.sh` checks),
  the glyph one printable ASCII character. `ref` says where it comes from:
  a dungeon index (set 0), an index into `WB_LIST` (set 1), a region name
  (set 2), `-` (sets 3 and 4: fishing, gathering) or a chapter count
  (set 5). Append only - saves store one character per collectable in
  `CLOG`, and items are `C.<index>`.
- **A new set**: `CS_NAME CS_E CS_HOW`, then decide in `col_kill`,
  `col_find` or `col_story` (`src/04i_v50.sh`) when it drops, and add a
  "complete the set" achievement (`ACH` + `ach_ok50`).
- **A room layout**: `ROOM_LAY[t]` is the map, rows joined with `/`. `#`
  wall, `.` floor, one `<` door in the bottom wall, and furniture letters:
  `B` bed, `C` chest, `D` display (numbered in reading order - keep the
  old ones where they are, saves fill them by number), `K` bookshelf, `G`
  guestbook, `F P T L A` decoration. Every room needs `B C K G`; the test
  checks that everything can be reached from the door.
- **Furniture**: a letter in `FURN_E` (HD), `FURN_G` (ASCII), `FURN_C`
  (color) and either `FURN_SAY` (a line when you walk into it) or a case in
  `room_use`.

## v4.5: endgame data (`src/01e_v45data.sh`)

- **A material**: append to `MAT_NAME/MAT_VAL/MAT_RARE`, then it gets its
  profession in `MAT_PK` (the loop there) - inventory, professions screen
  and cooking follow the tables. A node for it: a kind-3 creature plus
  `NODE_MAT`, `NODE_PK`, `NODE_T` and zones. Fish: an entry in `FISHW`.
- **A mount**: `MNT_NAME MNT_E MNT_SPD MNT_GOLD MNT_REQ MNT_SRC` (sold by
  Hilda if it has a gold price; otherwise give it with `mount_give`).
- **A daily/weekly**: `"kind:need:text"` in `DLY_T`/`WKY_T`; progress comes
  from `dly_ev kind [n]` calls in the code (`kill gath fish dung rare champ
  wboss inv myth mythn raid dungn repn`).
- **An achievement**: `"Name:what:title"` in `ACH` and a case in `ach_ok`.
  Append only - saves store one character per achievement.
- **Valor wares**: `VW_NAME VW_COST VW_WHAT` (`gem`, a slot letter, `LW`,
  `m<mount>`).
- **Mythic**: `MYTH_A/MYTH_B/MYTH_C` are the weekly affix pools,
  `myth_limit` the clock, `myth_scale` the numbers.

## v4.0: the bigger world (`src/01d_v4data.sh`)

The pattern for a whole new land, as v4.0 does it seven times:

1. **Terrain**: `tools/worldgen/extend4.py` paints the region (noise
   functions, `ellipse` for lakes, `town()` for walls, gates, waystone and
   campfire, `ruin()` for a dungeon entrance, `road()` - water becomes a
   bridge). `make_world.sh --install` writes `world.txt`. Or edit
   `world.txt` by hand.
2. **Creatures**: `m4 VAR "Name" glyph color level boss hp% dmg% aggro move
   atk emoji` - stats come from the level (`base_stats` interpolates the old
   creatures), `boss` is 0, 2 (elite), 1 (dungeon boss) or `w` (world boss).
   Then a `ZONES` line per creature: `"type x1 y1 x2 y2 count"`.
3. **Town**: append to `T4_NAME/T4_X/T4_Y`, then `n4 town slot role "Full
   Name" short glyph color emoji` for each townsperson (slot 0 is the quest
   giver; `N_QK`/`N_QD`/`N_QT` say what they ask for).
4. **Region**: a `REGIONS` line `"x1 y1 x2 y2 Name_With_Underscores 30-32"`,
   weather in `WEA_REG`/`WEA_KIND`, fish in `WATER_OF`, a faction in
   `REGION_FAC`.
5. **Dungeon**, **rare** (`add_rares "name:base:lvl:x:y"`), **story**
   chapters and a **questline** - as below.

Elements and abilities of new creatures: `classify4` (regexes on the name,
after the old `classify_monsters`).

**New tiles** (since v4.0: `q y M U H X B`) need: `T2C`/`T2V` and a `Z2_*`
in `04c_gfx.sh`, `colorize2` and `colorize1` (ASCII, `Z_*` in
`04_client.sh`), both branches of `dark_glyphs`, `paint`'s grey sketch in
`05_ui.sh`, `p_walk`/`m_walk`/`blocks_shot` in `01_core.sh`, the spawn
checks in `free_tile`, `check_world.py` and the tile test in
`test_content.sh`. A tile letter must never appear in an escape sequence
(no `m`, no digits).

**Gear tiers**: `tier_for level` is the one place that maps a level to a
tier; `MAXTIER` caps it. A new tier needs `TIER_Q`, `MAT_E` and `TIER_FL`.

## v3.0 systems (`src/01c_v3data.sh`)

**Elements and abilities** come from the monster's name in
`classify_monsters` (regexes: "Ice|Frost|Glacius" → frost, "Fire|Ember" →
fire ...). A new creature usually needs nothing; to override, add a line
after the regexes: `M_EL[t]=4 M_WK[t]=5 M_RS[t]=3 M_AB[t]=weaken`,
`M_RNG[t]=5` (shoots from 5 tiles), `M_HEALR[t]=1`, `M_SUMM[t]=1`.

**Rare elites**: one entry in `RARES` - `"name:base-type:level:x:y"`. It
copies the base creature, gets elite stats and a zone of ±5/±4 tiles.

**Talents**: per class 12 entries in `TL_NAME`/`TL_FX` (index
`class*12 + tree*4 + row`). Effects are `key:value` (`dmg:3` +3% damage per
rank, `sk0:12` skill 1 +12%, `cd1:10` skill 2 cooldown -10%, `res:4`,
`dodge:2`, `ls:1` ...) or `cap:name` for a capstone - add its text to
`CAP_DESC` and its effect where `has_cap name` is checked (`deal`,
`take_damage`, `cast`, `v3_tick`).

**Gems**: a gem kind is a letter in `GEM_L` plus entries in `GEM_NAME`,
`GEM_E`, `GEM_FX` (`dmg mp crit arm hp res`), `GEM_V` (three grades). They
are materials from `GEM0` on - append at the end only, saves store indexes.

**Factions**: `FAC_NAME FAC_E FAC_COL`, towns in `TOWN_FAC`, and a unique
in the `U_*` tables after `FAC_UQ0`.

**A questline**:

```bash
ql_add "The Name" <giver-npc-type> <faction> <level>
qs_add K.<monster>.<n> "what the giver says" "what they say when it's done" <reputation>
qs_add E.<spot>    "..." "..." 250          # scout a spot from SPOTS
qs_add T.<npc>     "..." "..." 300          # talk to someone (they finish the step)
qs_add C.<monster>.<n> ...                  # collect drops (QI_NAME[monster] names them)
qs_add G.<material>.<n> ...                 # bring materials
qs_add D.<dungeon> ...                      # clear a dungeon
qs_add B.<rare> "..." "..." 500 \
  "the question?" "Choice A|Choice B" "rep:0:600,gold:150|epic:W" "reply A|reply B"
```

Rewards: `rep:faction:amount`, `gold:n`, `pot:n`, `gem:n` (random gems of your level),
`epic:slot` (a socketed epic for your class), `uq:n`. XP and gold per step
scale with the questline's level. Append questlines at the end - saves
store one character per questline by position.

## Checklist

- [ ] appended to every parallel table (v3.0 data at the end only - saves store indexes)
- [ ] HD emoji added (`MEMO`, `D_WE`, `ALY_E`, `WK_E` ...)
- [ ] `./build.sh` and `tests/run.sh quick` pass
- [ ] tried it in the game (`--name modtest` keeps your real hero safe)
