# shellmmorpg

A real-time multiplayer RPG for the terminal, written in pure bash.
One script, no dependencies for players: walk a 480×200 world with friends,
fight monsters, clear dungeons, follow a 42-chapter story, trade, craft and
level up to 40.

```
 shellmmorpg | Hearthmoor (safe) | 🌞 08:06 | 84,31 | 2 online | hosting :4747
╭─────────────────────────────────────────────────╮ $ tess  Lv 25 Bard
│      🌱      🌲        🌾🌾🌾🌾  🌳        🌱    │ HP ██████████████████ 230/230
│🧱🧱🧱🧱🧱🧱      🧱🧱🧱🧱🧱🧱🌾🌳🌱🌱             │ MP ██████████████████ 376/376
│🧱    💂  🤵    👮    🧱🧱🧱🧱🧱    🧱      🌾🌾   │ 💰 17563   [e] 🍷 5+0   [r] 🧪 3+0
│🧱    🧱  🌸          🧝🕺🧱    👴    🧱    🍄🌱  │ 🎶🌀💜 Epic Voidforged Harp +93
```

## Quick start

```bash
./shellmmorpg.sh                      # start a world and play - friends can join
./shellmmorpg.sh --join 192.168.1.20  # join a friend's world (port 4747)
./shellmmorpg.sh --server 4747        # dedicated server, no player
./shellmmorpg.sh --ascii              # classic ASCII graphics ([v] toggles in game)
```

Press **?** in the game for all controls. New here? Read the
[player guide](docs/PLAYER_GUIDE.md).

**Needs:** bash 4.3+ (5.x recommended), a 256-color UTF-8 terminal of at
least 100×30. Hosting a world also needs one of `python3`, `socat` or `ncat`
for the network hub (joining needs nothing but bash). Characters live in
`~/.shellmmorpg/` (`SHELLMMO_DIR` moves them).

## What's in it

- **10 classes** (Warrior, Mage, Ranger, Cleric, Rogue, Paladin, Necromancer,
  Bard, Druid, Monk), 3 skills each, gear that only some classes can use, and **talent
  trees** - three per class, with capstones that change how you fight
- **Elements and status effects**: every creature has a weakness and a
  resistance; monsters poison, bleed, burn, chill, stun and weaken
- **A 480×200 world**: 22 regions from level 1 to 40, 17 towns with
  waystones, day and night, weather per region, 16 roaming world bosses
- **18 dungeons**, generated fresh for every visit, with elites, treasure
  chests, bosses that summon help, and 42 unique legendaries
- **266 kinds of creatures**: champions with 10 affixes, 24 rare elites,
  ranged casters and healers
- **Gems and sockets**: 18 gems, a jeweler at every smith
- **Endgame**: mythic dungeons (+2 to +20, weekly affixes, a clock), the
  Eclipse Throne raid, town invasions, valor, dailies and weeklies, paragon
  levels after 40, eight mounts, 32 achievements with titles
- **The story** in two acts, 42 chapters through every town, plus **19
  questlines** with choices, and **eight factions** to earn standing with
  (discounts, quartermasters, faction uniques)
- **12 allies** who follow you, fight and heal; **parties** with shared quests;
  quests to slay, collect, deliver, scout, hunt bounties and carry letters
- **Professions**: fishing, mining, herbalism; cooking, forging, alchemy
- **Inventory** with item cards and comparisons, bags in six sizes, a bank
  vault in every town and a chest shared by all your heroes, player trading
- **Two looks**: HD emoji graphics (2 columns per tile) or classic ASCII

## The project

| Path | What |
| --- | --- |
| `shellmmorpg.sh` | the game - **built**, do not edit; this is the file you hand out |
| `src/*.sh` | the source, one module per topic ([architecture](docs/ARCHITECTURE.md)) |
| `world.txt` | the world map (one character per tile) |
| `build.sh` | joins `src/` + `world.txt` into `shellmmorpg.sh` |
| `tests/` | the test suite ([testing](docs/TESTING.md)) |
| `tools/worldgen/` | the generators that made `world.txt` |
| `docs/` | guides: [player](docs/PLAYER_GUIDE.md), [architecture](docs/ARCHITECTURE.md), [protocol](docs/PROTOCOL.md), [modding](docs/MODDING.md), [testing](docs/TESTING.md) |
| `CHANGELOG.md` | what changed in every version |

Working on it:

```bash
./build.sh                 # build shellmmorpg.sh
tests/run.sh               # build + every test (a few minutes)
tests/run.sh quick         # without the network tests
./build.sh --where 4242    # which source line is line 4242 of the build?
SHELLMMO_DEBUG=1 ./shellmmorpg.sh   # frame time in the top right corner
```

## Playing over the internet

The host's port (default 4747/tcp) must be reachable. There is no account
system: the game trusts each player's own character file. The python3 and
socat hubs stop players from impersonating the server or each other; the
ncat hub cannot. For a public server prefer `SHELLMMO_HUB=python3` - see
[PROTOCOL.md](docs/PROTOCOL.md#trust-model).
