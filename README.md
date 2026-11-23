# shellmmorpg

A real-time multiplayer RPG for the terminal, written in pure bash.
One script, no dependencies for players: walk a 600×200 world with friends,
fight monsters, clear dungeons, follow a 55-chapter story, trade, craft,
level up to 50 - and rent a room at the inn to show off your trophies.

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
./shellmmorpg.sh                      # start a world and play - friends come in over ssh
ssh play@host                         # play on a server set up with deploy/install.sh (no ssh password)
./shellmmorpg.sh --ssh me@host        # play on a server (players always come in over ssh)
./shellmmorpg.sh --server 4747        # dedicated server, no player (docs/SERVER.md)
./shellmmorpg.sh --ascii              # classic ASCII graphics ([v] toggles in game)
```

Press **?** in the game for all controls. New here? Read the
[player guide](docs/PLAYER_GUIDE.md).

**Needs:** bash 4.3+ (5.x recommended), a 256-color UTF-8 terminal of at
least 100×30. Hosting a world also needs `python3` (and sshd, for
friends); playing on someone else's world needs `ssh`. Since 7.0 **the game
runs on the server**: over ssh you see your game, which runs on the host -
your computer only sends keys. Heroes live on the server, protected by a password you choose when you
create one: the world's host keeps them in `~/.shellmmorpg/chars/`
(`SHELLMMO_DIR` moves that), nothing is stored on a joining player's
computer.

## What's in it

- **8.0: Beyond the Edge** - level 50, four new lands east of everything
  (levels 40-50) with four towns and a new faction, gear tiers 13-15, five
  dungeons and a second raid (the Sundered Sky), act III of the story, four
  questlines, 25 uniques, five mounts, the Skyward Manor at the inn
- **6.0: more of everything** - 44 more creatures, a rare elite for every
  land, 4 more dungeons and world bosses, 8 more questlines, 20 more uniques,
  materials for levels 20-29
- **10 classes** (Warrior, Mage, Ranger, Cleric, Rogue, Paladin, Necromancer,
  Bard, Druid, Monk), 3 skills each, gear that only some classes can use, and **talent
  trees** - three per class, with capstones that change how you fight
- **Elements and status effects**: every creature has a weakness and a
  resistance; monsters poison, bleed, burn, chill, stun and weaken
- **A 600×200 world**: 26 regions from level 1 to 50, 21 towns with
  waystones, day and night, weather per region, 24 roaming world bosses
- **29 dungeons** (two of them raids), generated fresh for every visit, with
  elites, treasure chests, bosses that summon help, and 91 unique legendaries
- **Over 300 kinds of foes**: champions with 10 affixes, 54 rare elites,
  ranged casters and healers
- **Gems and sockets**: 18 gems, a jeweler at every smith
- **Endgame**: mythic dungeons (+2 to +20, weekly affixes, a clock), two
  raids (the Eclipse Throne, the Sundered Sky), town invasions, valor,
  dailies and weeklies, paragon levels after 50, 13 mounts, 60 achievements
  with titles
- **The story** in three acts, 55 chapters through every town, plus **31
  questlines** with choices, and **nine factions** to earn standing with
  (discounts, quartermasters, faction uniques)
- **12 allies** who follow you, fight and heal; **parties** with shared quests;
  quests to slay, collect, deliver, scout, hunt bounties and carry letters
- **Professions**: fishing, mining, herbalism; cooking, forging, alchemy
- **Inventory** with item cards and comparisons, bags in six sizes, a bank
  vault in every town and a chest shared by all your heroes, player trading
- **A home of your own** (5.0): rent a room at any inn - five sizes, a
  weekly rent - with a bed (Well Rested: more XP), a chest, displays, a
  collection book and a guestbook; friends visit while you are online
- **163 collectables** in seven sets: boss and world boss trophies, a curio
  for every land, finds from fishing and gathering, relics of the story,
  a hunter's trophy for every rare elite
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
| `docs/` | guides: [player](docs/PLAYER_GUIDE.md), [architecture](docs/ARCHITECTURE.md), [protocol](docs/PROTOCOL.md), [modding](docs/MODDING.md), [testing](docs/TESTING.md), [running a server](docs/SERVER.md) |
| `CHANGELOG.md` | what changed in every version |

Working on it:

```bash
./build.sh                 # build shellmmorpg.sh
tests/run.sh               # build + every test (a few minutes)
tests/run.sh quick         # without the network tests
./build.sh --where 4242    # which source line is line 4242 of the build?
SHELLMMO_DEBUG=1 ./shellmmorpg.sh   # frame time in the top right corner
```

## Playing together: only over ssh

Since 7.0 the server decides everything and **players reach a world only
over ssh**. Every player's game runs on the server; the game listens on
127.0.0.1 and nothing but sshd is exposed (ssh encrypts keys, screen and
password). The internal protocol never leaves the machine - see
[PROTOCOL.md](docs/PROTOCOL.md#trust-model). A server: `deploy/install.sh`
and [SERVER.md](docs/SERVER.md) - since 7.2 everybody plays through one open
account, `ssh play@host`, and logs in with their hero's name and password
(a new name makes a new hero). Hosting with `./shellmmorpg.sh`: friends
need an ssh login on your machine and run
`ssh -t user@your-host /path/to/shellmmorpg.sh --join 4747` (the game shows
the exact line).
