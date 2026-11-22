# Changelog

## 7.1 - comfort

**Chat**
- The log [c] scrolls (`↑↓` `PgUp` `PgDn` `Home` `End`), keeps 400 lines
  of chat and 400 of events instead of 60/80, shows the time of every line
  and wraps long messages instead of cutting them. Three tabs: chat, events,
  everything in order. Scrolled back, new lines do not move what you read.
  `enter` in the log starts chatting.
- The chat line edits like a shell: cursor (`←` `→` `Home` `End`), `Del`,
  `ctrl+w` / `ctrl+u` / `ctrl+k`, `↑` `↓` bring back earlier lines, `Tab`
  completes player names and `/commands`. Pasted text arrives in one go.
- `/r text` answers the last whisper. `/bell` switches the beep off (and is
  remembered with the graphics setting).

**Menus**
- Fixed: the forge has 26 recipes but only `a`-`l` worked - 14 recipes
  (and 4 at the alchemist and the campfire) could not be made at all. Now
  `↑` `↓` + `enter` pick any recipe; the letters still work.
- Fixed: waystones 11-17 could not be travelled to (the numbers 1-0 ran
  out and were shown twice). `↑` `↓` + `enter` pick any waystone.
- Every panel taller than the window scrolls (`PgUp` `PgDn` `Home` `End`)
  and says so - before, the rest was cut off silently (professions, the
  quest log, crafting, the quest board, trading, the jeweler on small
  windows).
- `PgUp` `PgDn` `Home` `End` `Del` and ctrl+arrows are understood (they
  used to be swallowed).

**Other**
- `Q` asks before quitting (`y` quits) - no more lost sessions to a typo.

## 7.0 - the server decides everything

**Only over ssh**
- Players reach a world only over ssh. The game listens on 127.0.0.1 only
  (the gate on the port, the hub on port + 1); nothing but sshd is exposed.
  `./shellmmorpg.sh --ssh user@host` (or `ssh -t user@host
  shellmmorpg-play`) is the way in; it now passes `--name` along too.
- `--join` only opens a world on the same machine (`--join 4747` - what ssh
  logins run); `--join other-host` says to use ssh. `--bind` is gone.
- Hosting with `./shellmmorpg.sh`: friends need an ssh login on your
  machine; the game shows the exact command.

**The game runs on the server**
- Every player's game now runs on the server, one process per player in a
  terminal of its own. Joining (`--join`, `--ssh`, `shellmmorpg-play`)
  opens a terminal to it (over ssh): your computer sends keys and shows the screen,
  nothing else. A modified client can only press other keys - levels,
  gold, items, damage, positions, trades and gifts are all decided by game
  code the server runs.
- The internal protocol never leaves the server: the hub listens on
  127.0.0.1 (the port + 1) and only hears processes that prove with
  a random token that the server started them. Players reach only the
  **gate** (127.0.0.1, the port), from their ssh login.
- The game on the server asks for the password itself; resizing your
  window works; when your connection drops your hero is saved at once.
- Your graphics choice ([v]) is kept per player on the server.
- Up to 32 players at a time (`SHELLMMO_MAX_PLAYERS`).

**Breaking**
- 6.x clients cannot join a 7.0 server (they are told to update), and a
  7.0 `--join` cannot join a 6.x server.
- Hosting needs python3; the socat and ncat hubs are gone (they could not
  check who is talking).
- `SHELLMMO_PASS` only works for the host's own game.
- Hero files from before 6.2 on a joining player's computer are no longer
  moved to the server (the host's own still are).
- New: `--session` (started by the gate), the gate handshake
  (`SMT1|...`), `AUTH` for every hub connection - see `docs/PROTOCOL.md`.
- Tests: the network tests talk to the hub with the session token;
  `test_login.py` and `test_restart.py` play through the gate.

## 6.4 - admin tools

**Admins, decided by the server**
- The world server keeps the list of admins: `$SHELLMMO_DIR/admins`, one
  hero name per line (`/var/lib/shellmmorpg/admins` on a deployed server).
  It is read for every command, so changes count at once - no restart.
- `./shellmmorpg.sh --admin add NAME` / `remove NAME` / `list` edits the
  list (run it as the server's user, with the server's `SHELLMMO_DIR`).
- When you host a world yourself, your own hero is an admin there.
- Admins can make others admins in the game: `/admin grant NAME`,
  `/admin revoke NAME`.
- A client never grants itself anything: the server checks every command,
  writes it to its log and sends what it does to a hero as a private line
  (`AR<id> ADM ...`) that only the world server can send.

**The tools** (`/admin help` in the game)
- heroes: `god` (no damage, no death), `heal`, `level N`, `xp N`, `gold N`,
  `item CODE` - for yourself or `[NAME]`
- moving: `tp X Y`, `goto NAME`, `summon NAME`, `where`
- the world: `spawn CREATURE [N]` (number or part of a name), `kill
  [RADIUS]`, `wboss` (a world boss now), `time HH:MM`, `weather REGION
  KIND`, `ann TEXT`
- people: `who` (everybody's map and position), `admins`, `kick NAME`
- New tests: `test_admin.py` (a real server, once per hub), `test_v64.sh`.

## 6.3 - stability and smoother multiplayer

**Multiplayer scales**
- **Interest management** in the python3 hub: in the open world every
  player gets only the monsters near them. Traffic per player stays at about
  30 lines a second while walking, however many are online (before: 30 with
  one player, 120 with eight). A player joining no longer floods everybody
  with the whole world (~1100 monsters). Clients parse a quarter of the
  lines and stay smooth in busy worlds.
- `MMOV` carries the monster's full state, so a monster that walks into
  range shows up at once; the hub hands you what is around you when you
  walk or teleport somewhere. Old clients still work.

**Stability**
- Heartbeat: the world server sends the clock every 10 s; a client that
  hears nothing for 35 s reconnects by itself instead of hanging in a dead
  world.
- When the host's world server dies, the host restarts it (and the hub);
  every player logs in again by themselves (new `AUTH` nudge) and keeps
  playing - nothing is lost, heroes are on disk. The log of the old server
  is kept in `server.log`.
- A dedicated server brings its hub back if the hub dies.
- No more "Killed" messages from bash drawn over the game.
- Logging in no longer fails when a client starts faster than the world
  server.
- **Quit and come straight back** works: logging in with the right password
  takes the hero over (it used to say "already playing" for up to 8 s). An
  older session of the same hero ends at once and does not save over the
  new one; a reconnecting client never kicks anybody.
- Quitting waits up to 4 s (was 2) for the server to confirm the last save.
- New tests: `test_restart.py` (the world server dies under two players),
  interest management in `test_net.py`, takeover in `test_acct.py` and
  `test_login.py`; flaky checks in the tests fixed.

## 6.2 - heroes live on the server

**Heroes are created and saved on the server only**
- Joining a world now means logging in: `name` + password. A new name
  creates a new hero (the game asks twice for the password); the hero is
  stored by the world server in `chars/<name>.char`, the password only as a
  salted hash (`<name>.pw`). Nothing is written on the joining player's
  computer - play from any machine, ssh login or not.
- Saved every 30 seconds, on important events and on quit (the client waits
  for the server to confirm); after a lost connection the client logs in
  again by itself and saves what happened meanwhile.
- One session per hero; a crashed session times out after 8 seconds. Five
  wrong passwords lock the name for a minute. Nobody can enter the world
  without logging in or under another name than their hero's.
- Hero data and passwords are private: the python3 and socat hubs deliver
  them to the world server only, answers to the one player only. (The ncat
  hub relays blindly, as it always did.)
- Old heroes saved on a player's computer move to the server the first time
  they log in (the file becomes `<name>.char.moved-to-server`).
- The shared chest is now part of the hero (it used to be a file shared by
  all heroes on one computer).
- New: `SHELLMMO_PASS`. For tests `SHELLMMO_OPEN=1` starts a server without
  logins. See [PROTOCOL.md](docs/PROTOCOL.md) and [SERVER.md](docs/SERVER.md).

## 6.1 - multiplayer fixed, servers over ssh

**The multiplayer crash**
- With two or more players every client died at once with `value too great
  for base`. Cause: the table of other players' mounts (`OP_MNT`) was never
  declared as an associative array, so a player id that starts with digits
  and has letters after them (`151add`, `9e1715` - about one in three ids)
  was evaluated as a number. Fixed; it is also cleaned up when a player
  leaves, together with that player's HD glyph.
- Tests now use such ids everywhere (`test_net`, `test_fuzz`, `test_monkey`)
  and the new `test_v61` replays a whole visit by players with ids like that.

**Servers over ssh**
- `--bind ADDR` makes the hub listen on one address only (all three hubs).
- `--ssh [user@]host[:sshport]` plays on a server through ssh.
- `deploy/install.sh` installs a server (systemd service, listening on
  127.0.0.1) and the `shellmmorpg-play` command players run after logging in.
  See [docs/SERVER.md](docs/SERVER.md).

## 6.0 - more of everything, and the big bug hunt

**More creatures**
- **44 new creatures**, two for every land - from the Thornhog and the
  Meadow Beetle at level 1 to the Starlit Wisp and the Crater Behemoth at
  40. Every one has its element, weakness, resistance and trick (poison,
  bleeding, burning, chill, stuns, curses, ranged casters), its sprite and
  its collect-quest item. The quest boards hand out work for them.
- **22 new rare elites**, one for every land (46 in all): Big Bertha, the
  Sultan of Sand, Whitefang the Elder, Shadowmaw, the Pumpkin King, Lady
  Brine, the Devourer's Eye...
- **4 new world bosses** for the levels that had none (20 in all): Old
  Grumblegut (4), Gorehorn the Mammoth (17), Vesper the Jade Panther (23)
  and Ruin, the Star Devourer (40).

**Four new dungeons** (23 in all), for the gaps on the way up
- **Cellar of the Old Mill** (level 2, Silverlake) - Rattigan the Rat King
- **Red Hand Hideout** (level 8, Stormcrag Foothills) - Rourke Red-Hand
- **Hrimgard's Tomb** (level 16, Frostfang Tundra) - Queen Hrimgard
- **The Cinderdeep Mine** (level 26, Scorched Badlands) - Foreman Gorrak
  the Molten
- Each with its own elite, walls, size and chests, two uniques on its boss
  and a trophy for your room.

**Eight new townsfolk, eight new questlines** (27 in all)
- Farmer Hesk (Hearthmoor) *The Mill Rats*, Warden Brannoc (Ironwood Camp)
  *The Red Hand*, Sheikha Amira (Oasis of Kadar) *Winds of the Djinn*,
  Skald Ragna (Frosthold) *The Frost Queen's Saga*, Admiral Vane (Port
  Coral) *Siren Song*, Gemcutter Pell (Shardhaven) *Fractured Light*,
  Elder Moku (Jadeleaf Village) *The Jade Fever*, Prospector Dusty
  (Redrock Outpost) *Cinderdeep*.
- Five steps each - slay, scout, collect, deliver, talk, clear a dungeon,
  hunt a rare - and a choice at the end: a unique of the line, or standing
  and gold. Eight new scouting spots. Every one of them also has kill
  quests and courier letters for you, like the other quest givers.

**Items**
- **20 new uniques** (66 in all): from the new dungeon bosses, the new
  world bosses and the questlines - Rattigan's Crown, the Red Hand Cutlass,
  Hrimgard's Frostcrown, the Cinderdeep Lantern, the Eye of Ruin...
- **2 new weapon kinds**: the Hand Cannon (rogues, rangers) and the
  Runestone (mages, necromancers, druids).

**Materials** (60 in all)
- Levels 20-29 had nothing to gather. Now: **Cobalt Ore** (22) and
  **Adamantite Ore** (26) in the highlands, badlands and the Void Rift,
  **Sungrass** (22) and **Nightshade** (26) in the jungle, isles and rift,
  **Reef Snapper** (sea, 20) and **Glacier Char** (ice and lava, 24).
- The forge makes tier 8 and 9 gear from cobalt and adamantite - no more
  waiting for titanite at 30. Alchemists brew greater potions and Elixirs
  of Swiftness from the new herbs.

**Collectables** (134 in all, seven sets)
- Trophies of the new dungeon bosses and world bosses.
- A new set, **Hunter's Trophies**: one for every rare elite (46). Rares
  leave their trophy behind like bosses do - often the first time.
- **5 new achievements** (50 in all): Big Game Hunter, Huntmaster, Hoarder,
  Pathfinder, Dungeon Lord - with titles.

**The bug hunt** - a monkey that presses thousands of random keys in every
screen and a fuzzer that floods the world server with nearly-right lines
(both are part of the test suite now) found:
- **Talking to Hilda the Stablemaster, Hale or Seren quit the game.** They
  had nothing to say, and picking a line out of nothing divided by zero -
  which in bash ends the main loop. They talk now, and an empty choice can
  never crash anything again.
- A level `08` (with a leading zero) is octal to bash and breaks its
  arithmetic: a mythic key level in a dungeon request (server), the ally
  in another player's position, the mythic fields of a dungeon start, and
  paragon points and dailies in a save file. All of them are checked
  properly now.
- A skill effect with an empty name from another player, an attack from a
  monster this client did not know yet, a shop or quartermaster screen
  without its NPC: each printed a bash error onto the screen.
- The world map could freeze the game if it was drawn before its zoom was
  set (after a resize at the wrong moment).
- Ore and herbs of 4.5 claimed to be for cooking in the inventory; every
  material now says what the forge or the alchemist makes of it.
- Collectables past number 99 would have been thrown away on loading.

**Faster**
- Lines about monsters on other maps (most of what the server says) are
  dropped before they are parsed: **4.5x faster**.
- Every number of every network line is checked with a glob instead of a
  regular expression (bash compiles a regex on every call): 9x faster
  checks, a quarter to a third less time per line for the client and the server.
- The creature classifier ran three times while the game loaded; it runs
  once now.

**Protocol**: unchanged, but play the same version (new creatures, items
and dungeon numbers). Old saves load unchanged.

New test files `tests/test_v60.sh` (72 checks), `tests/test_monkey.sh` and
`tests/test_fuzz.sh` (`bash tests/test_monkey.sh 5000 42` for a longer run).

## 5.0 - the housing update: a room of your own, and 80 collectables

**A room at the inn**
- Every innkeeper rents rooms upstairs (`[9]` when you talk to them) - and
  the whole Innkeepers' Guild keeps the same room for you, in every town.
- Four sizes: the **Attic Room** (level 5, 300 gold), the **Guest Room**
  (15, 2500), the **Grand Suite** (25, 12000) and the **Hero's Hall** (35,
  50000). Moving up pays the difference, and everything moves along.
- **Rent**: 60 to 4000 gold a week, paid when you go up - from your purse,
  or from the vault if the purse is empty. Can't pay? The door stays shut,
  but nothing is lost.
- Your room is a little map you walk around in. Walk into the furniture:
  - the **bed** wakes you up **Well Rested**: +10% to +25% experience from
    fights for 30 minutes (+1% more for every four things on display, up to
    +10%),
  - the **room chest** stores 20 to 70 items and all your materials,
  - **displays** (4, 8, 14 or 20) show off whatever you put on them: gear,
    uniques, bags - and collectables,
  - the **bookshelf** opens your collection book, the **guestbook** shows
    who came to visit; fireplaces, plants, chairs, lanterns and banners
    are just nice.
- Rooms are safe and rest you as fast as a town.

**Collectables** (a new kind of item: `C.<n>`)
- **80 of them in six sets**: a trophy from the boss of every dungeon (19)
  and from every world boss (16), a curio for every land (22, rarely found
  on its creatures - more often on champions and rares), Angler's
  Treasures from fishing (8), Prospector's Finds from mining and herbalism
  (8), and a relic at every sixth chapter of the story (7 - heroes who are
  further along get theirs at once).
- Something new is a bit more likely than a copy; treasure chests hide odd
  things too. A collectable is never auto-sold: with full bags it goes to
  your room chest, or squeezes in like a unique.
- The **collection book** (`H`, or the bookshelf) shows every set, what you
  found, where you keep it - and where to look for the rest.
- They can't be worn. Shops buy the ones you have twice (`[c]` at general
  stores, traders and spice stalls); "sell everything" and "sell junk" keep
  them. Lock one (`[l]`) and it is always kept.
- **13 new achievements** (45 in all) - Homeowner, Grand Host, Collector,
  Curator, Master Collector, one for every complete set, Exhibitor, Good
  Company - with new titles: the Host, the Curator, the Collector, the
  Trophy Hunter, the Titanslayer, the Curious, the Lucky, the Rockhound,
  Keeper of Tales, the Hospitable.

**Visits**
- `[9]` then `[v]` at any inn: whose door is open to you? Knock, and the
  innkeeper takes you up. The owner must be online - their client lets you
  in and shows you their room as it is right now (changes appear live).
- Your **door**: locked, party only (the default) or open to everybody.
- Guests look at the displays, read your collection count and sign your
  guestbook (once per visit, the last twelve visitors are kept).

**Also**
- Help page 4 explains the home; the inventory has a card for collectables,
  the bank screen a tab for the room chest.

**Protocol** (play the same version): `POS` may carry a room map
`H<owner-id in decimal>`; new player-to-player messages `RASK RHAS RREQ
ROOM RNO RSIGN`; item code `C.<n>`. Old saves load unchanged.

New test file `tests/test_v50.sh` (182 checks); the render test draws every
room size, a visit, and every new screen.

## 4.5 - the endgame, and the gaps of 4.0 closed

**Gaps closed**
- **Professions go to 40.** New ore (Titanite 30, Starmetal 36), herbs
  (Duskbloom 30, Glowcap 36) and fish (Abyssal Eel, Storm Trout, Magma
  Carp, Starfish of Ys) in the new lands. Smiths forge tiers 8-12 from
  them, alchemists brew bulk potions and a Grand Elixir.
- **Perfect gems** (fourth grade): three flawless ones at any smith, or
  from mythic bosses, the raid, level 38+ bosses, valor and weeklies.
- **Paragon**: after level 40 every 60,000 XP is a paragon level, and the
  talent points over 36 (levels 38-40) count too. Six stats (Might,
  Vitality, Precision, Warding, Wisdom, Celerity) - `[x]` then `[p]`.
- Fixed: gems showed up as cookable fish; `[1]`-`[9]` on an empty quest
  board could throw an error.

**Mythic dungeons**
- At level 40 every dungeon gate asks: normal or mythic? Mythic +2 to +20:
  every foe is scaled to level 40 and gets stronger with every key level.
- Weekly affixes: Fortified or Tyrannical (+2), a champion affix on a third
  of all foes (+4), Bolstering or Raging (+7).
- A clock: finish in time and your key rises by one (by two if very fast);
  every death costs five seconds. The boss pays tier-12 epic or legendary
  gear for everyone, perfect gems and valor.

**The raid: the Eclipse Throne** (Starfall Crater, east rim, level 40)
- Nyxara, Queen of the Eclipse, grows with every hero who enters. Dark
  stars on everyone's head (step out of the marked ground), a shield of
  night while her guards live, the total eclipse below a third (run), and
  an enrage after eight minutes. Everyone gets a three-socket legendary;
  four raid uniques, a 10% Starborn Stag.

**Invasions**
- Every 40-55 minutes the Horde marches on a town: three waves in twelve
  minutes, the last one with a warlord. Every defender is paid in valor,
  experience, gold and gear.

**Valor, mounts, dailies, achievements**
- **Valor** from mythic dungeons, the raid, invasions, dailies (30) and
  weeklies (150). Hale (Hearthmoor) and Seren (Dawnspire) sell Godforged
  gear, perfect gems and mounts for it.
- **Eight mounts** (+40% to +100% speed): Hilda the Stablemaster in
  Hearthmoor, faction rewards, valor, rare drops of the Pale Rider and
  Nyxara, a Mythic +15. `[z]` ride, `[Z]` choose. Others see you mounted.
- **Dailies and weeklies** from level 30 - the same for everyone on the
  same day: quest log tab 4.
- **32 achievements** with titles (`[o]`), announced to everyone.

**Protocol** (play the same version): `DREQ` has a key level, `DSTART` the
key, the time limit and the time used, new `MDONE` and `EVREW`, `LOOT
i:<item>`, `REW` a champion flag, `POS` a mount.

New test file `tests/test_v45.sh` (84 checks).

## 4.0 - the big content update: a world a third bigger, levels 30-40

Nothing old changed - there is just a lot more of everything.

**The world: 360×150 → 480×200**
- Seven new lands for levels 30-40: **Duskwood** (an autumn forest that
  never sees the sun), the **Sunken Kingdom** (drowned ruins on islands,
  bridges everywhere), **Stormreach Peaks**, the **Gloomcap Hollows**
  (mushrooms taller than towers), **Dragonspine**, the **Bonefields** and
  **Starfall Crater**. New ground: autumn leaves and trees, mycelium and
  giant mushrooms, storm heights and thunder crags, bone fields.
- Seven new towns with waystones, smiths, inns, banks, shops and
  mercenaries: Hollowmere, Tidewatch, Skyhold, Sporeholm, Wyrmrest Keep,
  Gravewatch, Dawnspire (17 towns in all).
- Roads, long bridges and passes connect them to the old world.

**Levels 30-40**
- The level cap is 40. Gear gets three more tiers: Titanforged (30),
  Eclipsed (34), Godforged (38).
- **Act II of the story, "The Fallen Star"**: 18 new chapters (42 in all)
  through every new land - a witch queen, a drowned kingdom, a storm god, a
  mushroom king, a dragon tyrant, an undying king and the thing that fell
  from the sky. New rewards include two uniques and two allies.

**More of everything**
- **Two new classes**: the **Druid** (Thorn Whip, Entangling Roots, Wild
  Growth) and the **Monk** (Flurry, Flying Kick, Inner Peace) - each with
  three talent trees, their own gear kinds and starting kit.
- **107 new creatures** (266 kinds): one more for every old land, 29 in
  the new lands, 7 dungeon elites, 7 bosses, 4 world bosses (the Drowned
  Colossus, Skyrender the Storm Titan, Vorgath the Ashen Dragon, the Pale
  Rider), 35 townsfolk and 10 more rare elites (24 in all).
- **7 new dungeons** (18): Witchroot Barrow, Drowned Cathedral, Thunderpeak
  Citadel, Mycelium Heart, Dragon's Roost, Necropolis of Kings, the
  Shattered Star - bigger than ever, with more rooms and chests.
- **8 new questlines** (19): one for every new town and *The Crownbearer's
  Blade* in Hearthmoor - with choices, as before.
- **16 new uniques** (42), **5 new weapon kinds**, 2 armor, 2 offhand and
  2 helmet kinds.
- **4 new allies** (12): Thornback the Bear, Wisp of Dawn, Gale the Storm
  Hawk and Ser Revenant. Allies are called with `1`-`9`, `0`, `-`, `=`.
- **2 new factions** (8): The Wildwatch and The Dawnguard, with
  quartermasters and faction uniques.
- **3 new champion affixes** (10): Storming (stuns), Cursed (weakens),
  Swift (fast).
- 14 new scouting spots, 44 new collection items, new rumours.

**Fixed**
- Rare elites had no HD sprite (they showed a letter) - they now look like
  their kind.

**Compatibility**
- 3.0 saves load unchanged: your explored map is carried over to the
  bigger world, reputation grows to eight factions, allies to twelve.
- Protocol: class 0-9, champion affix 0-10, gear tier 1-12. A 3.0 client
  cannot see druids and monks - play the same version.
- New test file `tests/test_v4.sh` (163 checks); the story test plays all
  42 chapters, the questline test all 19 lines, the render test visits
  every new land.

## 3.0 - depth: talents, elements, champions, gems, questlines, factions

**Talents** (`x`)
- A talent point every level from 2. Every class has three trees of four
  talents (ranks 5/3/3/1); rows open at 0, 3, 6 and 10 points in their tree,
  the last row is a capstone that changes how you play (Bleeding Edge,
  Last Stand, Shatter, Clearcast, Execute, Chain Lightning, Death Aura,
  Echo ... 24 in all). Innkeepers make you forget them for gold (`[8]`).

**Elements and status effects**
- Skills deal fire, frost, poison, shadow, holy or arcane damage. Every
  creature is weak to one element (+50%) and resists one (-50%); the
  target panel shows both, and so does the bestiary.
- Monsters poison, bleed, burn, chill (slower steps), stun (no moves, no
  spells, then immune for a while) and weaken (-25% damage). Resistance
  (gems, talents, tonics) shrugs effects off. Potions cure poison and
  bleeding; Heal, Holy Light, Holy Strike, Consecrate and resting cure everything.
- New defences: dodge, shield block, magic resistance, barriers.

**Monsters**
- Champions: 4% of the world's monsters (8% in dungeons) are Vampiric,
  Frenzied, Armored, Molten, Frozen, Venomous or Giant - 2-3× HP, 3× XP and
  gold, always a piece of gear one rarity higher, often a gem.
- 14 rare elites roam the regions (Grimfang the Elder Wolf, Glacius the
  Crystal Drake ...) - announced when they return, wanted by bounty boards.
- Shamans, witches, liches, sirens and others shoot from range (with line
  of sight); shamans and priests heal their friends; dungeon bosses call
  for help at 2/3 and 1/3 health and enrage at 1/4.

**Gems and sockets**
- Rubies, sapphires, emeralds, topazes, amethysts and onyx in three grades
  (damage, mana, crit, armor, HP, resistance). They drop from rares,
  champions, bosses and chests.
- Rare and better gear drops with sockets (1-3). Every smith is a jeweler
  now (`[7]`): set gems, add a socket, combine three gems into a better one.

**Quests 2.0**
- New objectives: collect drops from monsters, deliver materials to any
  quest board, scout a place, hunt a bounty. Boards and givers mix them in.
- **11 questlines**, one per town, 4-5 steps each, with their own NPCs,
  places and bosses - and choices at the end that change the reward and
  who is grateful. Questline NPCs carry an orange `!`.
- The quest log (`q`) has tabs: quests, questlines, reputation.

**Reputation**
- Six factions (Crown of Hearthmoor, Frontier Wardens, Sands of Kadar,
  Northern Clans, Tidecallers, The Last Light). Quests in their lands raise
  your standing: 5% discount per rank in their shops, and each faction's
  quartermaster (`[6]` at the questline giver) sells gems, socketed epics,
  a faction unique (Revered) and a three-socket legendary (Exalted).

**Faster**
- The world server's monster AI is 3.4× faster with many players online
  (safe-zone checks once per tick instead of per monster and player).
- Frames without map changes take half the time (side panel: gear lines
  and unchanged rows are cached, quest tracking no longer scans every zone).
- Talents, item stats and progress bars are cached or computed without
  forks; no here-strings left in per-frame code.

**Also**
- In-game help has a second page (`>`) for the new systems.
- Item cards show sockets and gems; gems add to the sell price.
- Save files gain `TAL QLS QLP QLC REP` - 2.x saves load unchanged.
- Protocol: `MON` has an 8th field (champion affix), `MATK` carries element
  and effect, new `LOOT` (gem drops). 2.x clients ignore the extras.
- New test file `tests/test_v3.sh` (177 checks): talents, gems and the
  jeweler, elements, status effects, every questline from start to finish,
  reputation and quartermasters, champions, rares, ranged and healing AI.

## 2.1 - cleanup, bug fixes, speed, tests and guides

**Bugs fixed**
- Battle Cry, Heal and Anthem overwrote the number of your current ally - the
  ally stopped following and fighting after you used one of them.
- Opening an item card in the inventory overwrote the current weather and
  sight radius (two modules used the same variable names).
- ASCII mode: colors bled across neighbouring tiles that share a character
  (e.g. sand next to grass, both `.`).
- The bestiary did not fit the frame at 100×30 since v2.0's 87 creatures:
  it now has pages (`<` `>`); HD cells were one column too wide.
- Quest board lines with emoji were one column too wide in HD.
- Long item names in the side panel, long log lines and the header could run
  past the right edge; menus wider than the frame printed a huge run of
  blanks. Everything is clipped to the screen now, colors kept.
- Re-entering a dungeon alone always opened a new instance (and left the old
  one running); a party could re-enter its finished dungeon. Now you resume
  your dungeon until its boss is dead, then get a fresh one.
- Closed dungeon instances left all their monster data behind on the server
  (memory grew with every dungeon run).
- Map lookups left of column 0 wrapped around to the far side of the map.
- Unique legendaries were auto-sold when your bags were full - now they
  always squeeze in.
- Trading: only the first 10 bag slots could be offered (now pages with
  `<` `>`), and offering more than 10 items could lose the extra ones.
- Dungeon type checks only allowed 11 dungeons (blocked adding more).

**Security and robustness**
- The python3 and socat hubs bind every connection to its sender id and
  only let the world server (secret token) speak as `srv`: nobody can fake
  monsters, loot, announcements or other players any more. python3 is now
  the preferred hub; ncat (which cannot do this) comes last.
- Clients that stop reading are cut off instead of filling the hub's memory.
- Dungeon requests are rate-limited (1.5 s per player, at most 40 instances);
  full world resyncs are combined (at most one per map per second).

**Faster**
- Map frames are 4-6× faster: every map row is colored once and frames cut
  pieces out of it; monsters are indexed by row. Town 64 → 11 ms, wild
  77 → 8 ms (ASCII), night 68 → 24 ms.
- Frames only send the screen lines that changed: an idle frame sends
  nothing (was 2.3 KB every 80 ms), a map refresh 0.6-1.3 KB (was 13-18 KB).
  Much better over SSH.
- The world server keeps sleeping monsters in a timer wheel: about 40% less
  CPU with players online.
- The world map is redrawn at most twice a second while nothing is pressed.

**Project**
- `tests/`: six test files, about 1000 checks - content tables, items, loot,
  dungeons, the world server, save files, the whole story, allies, bank,
  every screen in both graphics modes and three sizes, incremental frames,
  and a real server driven by protocol bots (`tests/run.sh`).
- Guides: README, player guide, architecture, protocol, modding, testing.
- `tools/worldgen/`: the world generators with a reproducible pipeline,
  `make_world.sh` and `check_world.py`.
- `build.sh --where N` maps a line of the built script to its source;
  `SHELLMMO_LIB=1` loads the game as a library (tests, experiments).
- Removed dead code (unused tables and functions), consistent module
  headers.

## 2.0 - the big content update
The world grows to 360×150 with five new lands (Sapphire Isles, Crystal
Highlands, Emerald Jungle, Scorched Badlands, Void Rift) and five new towns;
11 bigger dungeons with elites and treasure chests; 20 unique legendaries;
allies who fight at your side; the story of the Shattered Crown through
every town; level cap 30.

## 1.8 - bags and banks
Bags in six sizes in three bag slots; a banker in every town with a personal
vault (gold there is safe when you die) and a chest shared by all your
heroes.

## 1.7 - inventory 2.0
Tabs for gear, items, materials and your hero; a cursor; item cards with
"what if I wear it"; power score; locks; sorting; equip-best; every material
with its own icon.

## 1.6 - gear for every class
Five gear slots, 20 weapon kinds, armor/offhand/helmet/trinket kinds that
only some classes may use; bonus stats (crit, HP, MP, damage, light).

## 1.5 - everything is emoji
Decorated terrain, walls, lava, volcanoes, item icons (type + material +
rarity), consumables, skills and shops in HD mode.

## 1.4 - HD graphics
Emoji sprites on 2-column tiles, animated water and lava, floating damage
numbers, hit flashes, smooth bars; `v` switches to classic ASCII.

## 1.3 - a living world
Day and night with torches, weather per region (sandstorms, blizzards, ash
rain, thunderstorms), roaming world bosses with shared loot, fishing,
mining, herbalism, cooking, forging, alchemy and safe player trading.

## 1.0 - 1.2 - the game
A real-time multiplayer RPG in pure bash: host or join a world, 8 classes
with 3 skills each, an open world (240×100 by 1.2) with towns, regions and
monsters, procedurally generated dungeons with bosses, parties and party
quests, NPC quest givers and courier quests, shops, waystones, a zoomable
world map with fog of war, bestiary, quest tracker, chat bubbles, and a
symbol and color for every player.
