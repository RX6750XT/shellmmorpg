# Testing

```bash
tests/run.sh          # build, then every test (about 1.5 minutes)
tests/run.sh quick    # without the network tests
bash tests/test_items.sh   # one file
```

`run.sh` exits non-zero if anything fails. It also runs `shellcheck` (if
installed) for the warning classes that are real bugs in this code base.

## What is tested

| File | Covers |
| --- | --- |
| `test_content.sh` | every content table has an entry per index; bosses are bosses, NPC spawns stand on walkable tiles, waystones and dungeon entrances are where the tables say, story objectives point at real things, the world map has the right size and only known tiles |
| `test_items.sh` | every gear code is valid and has sane stats; garbage and injection strings are rejected; loot rolls of every monster are valid; bags, equipping, auto-sell (uniques are kept), sorting, class restrictions |
| `test_world.sh` | every dungeon type generates a reachable, deterministic layout for several seeds; the world server spawns; every instance gets its boss, elite and chests on floor tiles; re-entry resumes; boss death clears; closing frees all monster data; rate limits, the instance cap, the damage cap, injection through `HIT` |
| `test_char.sh` | save/load roundtrip, a hostile save file, leveling, the whole story from chapter 1 to 24, allies (fight, heal, skills that talk about "allies"), the bank and the shared chest, quests |
| `test_v3.sh` | talents (rows, ranks, capstones, save, reset), gems and sockets (codes, stats, the jeweler as a player uses it, combining), elements and resistances, status effects and Last Stand, quests 2.0 offers and objectives, every questline from start to finish with choices, reputation, discounts and quartermasters, champions, rares, poison on hit, ranged attacks with line of sight, boss summons, healers, gem drops |
| `test_v4.sh` | the 480x200 world (regions, towns, safe zones, factions, dungeon entrances, scouting spots, new tiles), old saves in the bigger world (explored map, reputation), level 40 and tiers 10-12 (loot, shops, uniques), the Druid's and the Monk's skills and talents, eight factions, twelve allies, the new champion affixes, every new creature and rare spawning on walkable ground |
| `test_v45.sh` | professions and gems to 40 (materials, nodes, recipes, perfect gems, the jeweler), paragon (points, stats, save, reset), mythic instances on the server (scaling, affixes, DSTART, the death penalty, MDONE, loot) and the client's keys, the raid boss (meteors, stepping out, the shield, the eclipse, loot), invasions (three waves, pay, defeat), valor wares, mounts (buying, riding, speed, being thrown off, other players' mounts), dailies and weeklies, achievements and titles, `LOOT i:`, the mythic gate |
| `test_v50.sh` | the collectables (every one a valid item with a 2-column sprite, a trophy for every boss, a curio for every land), every room layout (rectangle, one door, the display count, all furniture reachable), renting and rent, the furniture, Well Rested, displays and the room chest, save/load and a hostile save, drops from kills, chests, fishing and the story, duplicates at the shop, visits from both sides (doors, live updates, being shown out), the guestbook, rooms on the server, the innkeeper |
| `test_v60.sh` | the content of 6.0: every creature has an element and a sprite and lives somewhere walkable, the new dungeons, world bosses for low levels, every new questline (givers, spots that can be reached, a unique at the end), uniques and weapon kinds, materials, nodes and recipes, what every material is for, the hunter's trophies, three-digit collectables in saves, the achievements |
| `test_v61.sh` | other players with ids that start with digits (they used to crash every client): joining, moving, mounts, chat, effects, drawing, leaving |
| `test_v62.sh` | heroes on the server: the client's chunks, the server's storage and hashing, loading back, hostile saves, bad names and passwords |
| `test_monkey.sh` | thousands of random keys in every screen (both graphics modes), random network lines, time passing; after every step the hero must make sense (valid items, no negative gold, standing on the floor ...) and nothing may print a bash error. `bash tests/test_monkey.sh STEPS SEED` |
| `test_fuzz.sh` | a real world server flooded with valid, nearly valid and garbage lines from honest players and liars: no bash error, no code from a line ever runs. `bash tests/test_fuzz.sh LINES SEED` |
| `test_render.sh` | every screen in ASCII and HD at 100×30, 120×40 and 200×60: no bash error, nothing past the right edge, the map frame intact; incremental frames end up exactly like full redraws |
| `test_acct.py` | a real server with logins: new heroes, chunked saves, loading, wrong passwords and the lock-out, one session per hero, nobody plays without a login or under another name, hero data is private, no password in the log |
| `test_login.py` | real players in a pty, joining through the gate (v7.0): the game on the server asks for the password, create a hero, a smaller window redraws, Q ends the session and the terminal, come back from another computer, a takeover, wrong passwords, nothing on the player's disk (an old hero file there is ignored), a stranger never gets the host's old local hero, old 6.x clients are told to update, `--join` to another machine and `--bind` are refused (ssh only) |
| `test_guest.py` | (v7.2) the open ssh account (`--ask-name`): the game asks for the name; a new name asks before it makes a hero, "no" and bad names go back to the name, a known hero logs in, wrong passwords are asked again (three: back to the name), `RON` is `ron`, `--name` fills it in, the gate's `?` handshake, the guest login shell passes only `--hd`/`--ascii`/`--name` on |
| `test_v64.sh` | (v6.4) admin tools on the client: only the server's private lines count, every effect (god mode against blows and poison, teleport out of a dungeon, level, XP, gold, items, heal), `/admin`, the admins file |
| `test_v71.sh` | (v7.1) comfort: special keys, the chat line (cursor, history, Tab, ctrl keys, the limit), `/r`, `/bell` (remembered), the log (400 lines, times, wrapping, tabs, scrolling, a view that stays put), panels taller than the window scroll, every recipe and every waystone can be picked, no number shown twice, Q asks |
| `test_v80.sh` | (v8.0) Beyond the Edge: level 50 and tiers 13-15 (creature stats, loot, the forge, uniques), the 600x200 world (regions, towns, waystones, townsfolk on the floor, zones, entrances, elements and sprites), old heroes in the bigger world (explored map, ninth faction, mounts, counters), the Horizon Watch quartermaster, mounts 9-13 at the stable (`a`-`d`), the Skyward Manor, the second raid (instance, flares, shield, sundering, supernova, loot, uniques, gate), level-gated dailies and weeklies, act III, collectables and the achievements of 8.0 |
| `test_admin.py` | (v6.4) a real server: nobody is an admin by default, `--admin add`/`remove` count at once, refused commands do nothing, effects reach only their hero, spawn, kill, time, weather, announcements, grant and revoke in the game, kick, nobody fakes the server, everything in the log |
| `test_restart.py` | (v6.3) a host and a friend (through the gate, typing the password) in a pty, the world server is killed: the host restarts it, both log in again by themselves, see each other, nothing is lost, nothing is drawn over the game |
| `test_net.py` | a real dedicated server with protocol bots (they talk to the hub with the session token, like game sessions): world sync, combat and loot, monster AI, anti-spoofing, (v7.0) nobody without the token is heard or hears anything, neither the hub nor the gate is on the network, the gate refuses protocol lines and bad names, garbage input, dungeons, parties, interest management (only nearby monsters, walking somewhere brings its monsters, once), and no bash errors in the server log |

## How the bash tests work

`tests/lib.sh` sources the built game with `SHELLMMO_LIB=1` - every function
and table is loaded, nothing starts - in a temporary `SHELLMMO_DIR`.

```bash
source "$(dirname "$0")/lib.sh"
stub_client            # no network, logs go to LOGS, sends to SENT, world loaded
new_hero 3 12          # a level 12 cleric in Hearthmoor

eq    "description" "$actual" "expected"
check "description" some_command args     # passes if the command succeeds
ge / gt / le "description" a b            # numbers
fail  "message"; ok                       # by hand

t_end                  # prints the summary, sets the exit code
```

`tests/vt.py` is a small terminal emulator: `vt.py frame rows cols mw vh`
checks a rendered frame, `vt.py --cells frame rows cols` prints every cell
with its colors (handy to diff two renderings).

## Debugging

- `./build.sh --where N` - which module and line is line N of
  `shellmmorpg.sh` (bash error messages give built line numbers).
- `SHELLMMO_DEBUG=1 ./shellmmorpg.sh` - average frame time, top right.
- A second terminal: `./shellmmorpg.sh --join 4747 --name tester` (on the same machine; others come in over ssh).
- The world server writes `~/.shellmmorpg/server.log` when you host.
- To try a function by hand:
  `SHELLMMO_LIB=1 bash -c 'set --; source ./shellmmorpg.sh; item_name U.3 0; echo "$INAME"'`

## Benchmarks

There is no benchmark runner in the repo (timings depend on the machine),
but the pattern is simple - source the game in library mode and time a
function in a loop:

```bash
source tests/lib.sh; stub_client
t0=${EPOCHREALTIME/./}
for i in {1..200}; do out=""; render_panel; done
echo "$(( (${EPOCHREALTIME/./} - t0) / 200 )) us"
```

For the server: `load_world`, `send() { :; }`, `spawn_world`, put a few
players into `SP_*` next to monsters, then advance `NOW` by 150 and call
`ai_tick` in a loop. Wrap functions with a timing shim (rename with
`declare -f` + `sed`, call through) to see where the time goes.
