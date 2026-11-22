# Architecture

How shellmmorpg is put together, for anyone who wants to change it.

## Processes

```
              ┌──────────────────────── server / host machine ────────────────────────┐
              │                                                                        │
 host ──────▶ │ game (bash, the host's own) ─┐                                         │
              │                              ▼                                         │
              │        hub (python3, 127.0.0.1:PORT+1) ◀── world server (bash)          │
              │                              ▲                                         │
              │        game sessions (bash, one per player, each in a pty)             │
              │                              ▲                                         │
              │        gate (python3, 127.0.0.1:PORT) ─┘                               │
              │                              ▲                                         │
              │        --join (a terminal) per player, started by sshd                 │
              └──────────────▲─────────────────────────────────────────────────────────┘
                             │ ssh: keys ▲  ▼ screen
                    players: ssh -t user@host shellmmorpg-play
```

Since 7.0 **the game runs on the server** and players reach it **only over
ssh**: nothing listens on the network but sshd. A player's ssh login runs a
terminal (`--join`, `term_main`) on the server: it sends keys and shows what
the game draws. Everything a player can do to the world goes through a game
process the server started - nothing a player sends is more than a key.

- **Gate** - 127.0.0.1:PORT. Every player who connects says hello
  (`SMT1|name|cols|rows|gfx`) and gets a pseudo-terminal with a game
  session of their own (`--session`) on the server; bytes are relayed both
  ways, an in-band sequence resizes the terminal. When the player goes away
  the session gets `SIGHUP`, saves and quits.
- **Hub** - relays every line it receives to every connection. It listens on
  127.0.0.1 only, and a connection must prove first that the server started
  it (`AUTH` with a random token from the environment): the world server
  speaks as `srv`, a session as its player id. Everything else is dropped.
  Gate and hub are one python3 process.
- **World server** (`--world-server PORT`, started in the background by a
  host, or `--server PORT` in the foreground) - a bash process connected to
  the hub like any client. It owns monsters, NPCs, loot, parties, party
  quests, the wanted list, the clock, weather, world bosses and dungeon
  instances.
- **Game sessions** (the "client" code) - one bash process per player, on
  the server. A session owns its character (stats, inventory, quests, story,
  bank), renders, reads keys, and tells the world where it is (`POS`) and
  what it hits (`HIT`). The world server rolls loot and sends it back
  (`REW`).

`./shellmmorpg.sh` (host) = gate + hub + world server in the background + the
host's own game, connected straight to the hub. `--server` = the same
without a player. `--join [PORT]` = a terminal only, for a world on the same
machine (what ssh players run); `--ssh user@host` = ssh + that. Every message between the
processes is one text line: see [PROTOCOL.md](PROTOCOL.md).

## Source layout

`build.sh` concatenates the modules (in this order - top-level code runs
while the script loads, so tables come first) and appends the world map as a
here-document and the start code:

| Module | Contents |
| --- | --- |
| `01_core.sh` | header/help, arguments, the terminal of `--join` (`term_main`, v7.0), all base tables (classes, skills, monsters, NPCs, zones, regions, gear kinds, materials), item codes, maps, dungeon generator |
| `01b_content.sh` | v2.0 content tables (new lands, creatures, NPCs, dungeons, uniques, allies, story) - data only |
| `01d_v4data.sh` | v4.0 data: the seven new lands (creatures via `m4`, towns and townsfolk via `n4`, zones, regions, waystones), dungeons 11-17, world bosses, gear tiers 10-12 and new kinds, the Druid and the Monk, uniques, allies, factions, rare elites, act II of the story, eight questlines; `classify4` names elements for the new creatures |
| `01e_v45data.sh` | v4.5 data: materials 40-53 and their tables (`MAT_PK`, `MAT_GRP`, `NODE_MAT`), perfect gems (`gem_kq`), paragon, mythic affixes and the clock, the raid (dungeon 18), mounts, the valor and stable NPCs, valor wares, daily and weekly templates, achievements |
| `01c_v3data.sh` | v3.0 data: elements and `classify_monsters`, rare elites, champion affixes, status effects, gems, talents, factions, scouting spots, the 11 questlines |
| `02_net.sh` | the gate and the hub (one python3 program, `PY_HUB`), tokens, starting/stopping them, `net_connect` (with `AUTH`), `send`, `net_poll` |
| `03_server.sh` | the world server: spawning, AI (timer wheel), combat on the server side, loot, parties, instances, world bosses, weather, clock, message handler |
| `03b_server45.sh` | v4.5 server: mythic scaling (`inst_mon`, `myth_scale`), Bolstering, `myth_finish`; the raid boss (`raid_attack`, delayed area blows `aoe_add`/`aoe_tick`), `raid_finish`; invasions (`inv_*`); `srv_loot` |
| `03c_accounts.sh` | v6.2 server side of heroes: `srv_aload` (login, new heroes, password check, lock-out, one session per hero), `srv_asave` (chunks, shape check, atomic write) |
| `03d_admin.sh` | v6.4 admin tools, server side: the admins file (`adm_is`, `adm_set`, `adm_cli` for `--admin`), `srv_adm` (every `/admin` command: checks, logs, world commands, private effects) |
| `04l_admin.sh` | v6.4 client side: `/admin` (`adm_cmd`), the admin flag (`adm_flag`), the effects the server sends (`adm_effect`: god mode, teleport, level, XP, gold, items, heal) |
| `04k_account.sh` | v6.2 client side: `acct_login`, `acct_resume` (after a lost connection), `acct_send_save`, `acct_flush` (wait for the last save when quitting) |
| `04_client.sh` | character, save/load, stats, combat, skills, items, shops, quests, NPC talk, party, and the network message handlers (`cli_line`, `cli_srv`) |
| `04b_life.sh` | day/night and light, weather, world boss client side, fishing, gathering, crafting, trading |
| `04c_gfx.sh` | HD and ASCII graphics, emoji tables, tile colors, text width helpers (`dispw`, `padr`, `clipl`), the tile-row cache |
| `04e_allies.sh` | allies |
| `04f_story.sh` | the story engine |
| `04g_v3.sh` | v3.0 client mechanics: talents (`tal_calc`), gems and sockets, status effects, reputation, questline engine (`ql_*`, `qev_*`), quartermasters |
| `05_ui.sh` | layout, frame, map rendering, side panel, log, menus, key handling, main loops |
| `05b_inv.sh` | inventory screen |
| `05c_bank.sh` | bags, bank vault, shared chest |
| `04h_v45.sh` | v4.5 client (loaded after the UI): paragon, valor, mounts, mythic keys, dailies and weeklies, achievements and titles, save/load hooks (`v45_save`, `v45_load_kv`) |
| `05e_v45ui.sh` | v4.5 screens: paragon page, mythic gate, stable, valor quartermaster, achievements, dailies tab |
| `01f_v50data.sh` | v5.0 data (loaded after `01e`): the 80 collectables (`cl` lines: set, rarity, sprite, glyph, source, name, story) and their lookups (`COL_BOSS`, `COL_CUR`, `COL_SETL`), the room sizes (`ROOM_*`) and their layouts, furniture, 13 achievements |
| `04i_v50.sh` | v5.0 client (loaded last): save/load hooks (`v50_*`), collectables (`col_give`, `col_kill`, `col_find`, `col_story`, `col_count`), the room map (`room_build`, `room_go`, `room_overlay`, `room_use`), rent (`room_rent`, `room_pay`), displays, the guestbook, visits (`room_msg`) |
| `01g_v60data.sh` | v6.0 data (after `01f`): 44 creatures (`m6`: like `m4`, plus element, weakness, resistance, trick, range), four dungeons, four world bosses, 22 rares, materials 54-59 and their nodes and recipes (`FORGE_X`, `ALCH_X`), two weapon kinds, eight townsfolk and their questlines, uniques 46-65, collectables (the hunter's trophies are made from `RARE_T`); runs the creature classifier - once, for everybody |
| `04j_v60.sh` | v6.0 client (loaded last): icons of the new materials, sprites of the hunter's trophies, achievements of 6.0, `mat_uses` from the recipes |
| `05f_v50ui.sh` | v5.0 screens: rooms at the inn, visiting, a display, the collection book, the guestbook |
| `05d_v3ui.sh` | v3.0 screens: talents, jeweler, quartermaster, questline choices, the tabbed quest log, panel lines for effects and targets |
| `06_main.sh` | picks the main loop for the mode |

`./build.sh --where N` maps line N of the built script back to its module.

## Data model

**Maps** are strings, one per row: `MAPROW["W:57"]` is row 57 of the open
world (480×200 since v4.0), `MAPROW["D12:3"]` row 3 of dungeon instance 12. One character per
tile (legend in `build.sh`). `tile map x y` reads one (off the map = `^`);
`p_walk` / `m_walk` / `blocks_shot` classify. Dungeons come from
`gen_dungeon map type seed` - deterministic, so the server only sends the
seed and every client builds the same dungeon.

**Monsters** live on the server in parallel arrays indexed by monster id:
`MT` (type), `MX`/`MY`, `MHP`/`MMAX`, `MMAP`, `MNEXT` (next think), `MAGG`
(target) ... The type tables (`M_NAME`, `M_HP`, `M_KIND`, `M_BOSS`, ...)
describe each kind; `M_KIND` 0 hostile, 1 townsperson, 2 guard, 3 resource
node, 4 treasure chest. Clients mirror the monsters of their current map in
`CM_T`/`CM_X`/`CM_Y`/`CM_HP`/`CM_MAX`, with `CM_POS["x,y"]` (who stands
where) and `CMR[y]` (who is on that row) as indexes.

**Other players** on a client: `OP_NAME`, `OP_MAP`, `OP_X`, ... keyed by
their 6-hex-digit id.

**Items** are codes: gear `S.kind.tier.rarity` (`W.6.5.2` = epic tier-5
bow), bags `B.k`, uniques `U.n`; a trailing `!` means locked. `valid_item`
checks, `item_stats` decodes into `IK IKD IT IRR IVAL IBT IBV ICLS ...`,
`item_name` adds `INAME`. Since v5.0 collectables are `C.n` (they decode
with `IK=C`, `IKD` = the index into the `CL_*` tables). **Quests** are codes too:
`type.target.need.have.xp.gold` (`K.5.10.3.100.50` = kill 10 of monster 5,
3 done).

**v3.0 state**: `TAL` is 12 digits (rank per talent), `QLS` one character
per questline (`0` not started, `1`-`9` active step, `x` done), `QLP` the
progress of each active step, `QLC` the choices (`-`, `a`, `b`), `REP` six
numbers. Server-side, `MCH[mid]` is a champion's affix and `M_EL M_WK M_RS
M_AB M_RNG M_HEALR M_SUMM` describe every monster type (filled by
`classify_monsters` from the names - override there).

**v5.0 state**: `ROOM_T` (0 = no room, 1-4), `ROOM_PAID` (the week rent is
paid for), `ROOM_DOOR` (0 locked, 1 party, 2 everybody), `ROOMD` (one code
or `-` per display), `ROOMC`/`ROOMM` (the room chest), `CLOG` (one
character per collectable: ever found), `REST_UNTIL`/`REST_PCT` (Well
Rested, epoch ms), `GUESTS` (`name:day` pairs). A room is a map like a
dungeon: `room_build H<n> tier` writes its rows from `ROOM_LAY` (walls `#`,
floor `_`, the door `<`, `+` where furniture stands - not walkable, drawn as
floor); the furniture itself (`RM_F`, `RM_AT["x,y"]`) is drawn on top like
sprites by `room_overlay`. Everybody in the same room sends `POS` with the
same map name, so they see each other as in any dungeon.

**Characters** are `key=value` lines (`char_text`). Since 6.2 they live on
the world server, in `$SHELLMMO_DIR/chars/<name>.char` next to
`<name>.pw` (salt + hash of the password): the client logs in with `ALOAD`,
gets the text back in chunks, and `save_char` sends it with `ASAVE`
(`04k_account.sh` client side, `03c_accounts.sh` server side). The server
checks the shape (version line, `KEY=printable` lines, size) and writes a
temp file, then renames; the client validates every value on load - a save
is input like any other. In the test library (`CHAR_REMOTE=0`) `save_char`
and `load_char` use `$CHAR_FILE` instead. The shared chest is part of the
hero text (`SCI`/`SCG`/`SCM`).

## Main loops

Client (`client_main`): poll the network, run the timers (allies, damage
over time, gathering, fishing, regeneration once a second), send the
position, autosave every 30 s, render every 80 ms, read a key with a 30 ms
timeout.

World server (`server_main`): read a line with a 40 ms timeout, handle it,
every 150 ms `ai_tick`, every second `srv_second` (respawns, timeouts,
empty instances, world boss, weather, clock).

`ai_tick` does not look at every monster: monsters sleep in a **timer
wheel** of 150 ms slots (`WHEEL`, `wake`). A tick only touches the slots that
came due; a monster far from every player sleeps 4 s, one near a player
thinks every 0.4 - 1.5 s. A safety sweep (`wake_check`) every 10 s puts back
anything that fell out.

## Rendering

`render` builds one string `out` with cursor positioning and prints it once.

1. `render_header`, then either the map (`render_map`) or a menu
   (`render_ui`), then `render_panel`, `render_log`, `render_input`.
2. `render_map` collects everything that is not terrain per view row in
   `RI[row]` as `x*10+priority:width:key` items (you, players, monsters,
   allies, effects, floating numbers, name tags and chat bubbles) and calls
   `render_rows`.
3. `render_rows` (running with `LC_ALL=C` - every string it cuts is ASCII or
   cut at byte offsets) takes the map row, and `compose` splices the items
   between pieces of colored terrain.
4. Terrain comes from the **tile-row cache** (`tiles_row`, `tiles_at`): every
   map row is colored once - tile by tile, repeated color codes dropped - and
   stored with the byte offset of each tile, so a piece of terrain is one
   substring. HD rows with animated water or lava exist once per animation
   phase. Night and storms (`LITMODE`) paint only the lit spans in color and
   the rest from a cached moonlit sketch (`dark_at`). Dungeons show what your
   light reaches and remember the rest (fog, `EXPL`).
5. Every screen line goes through `emit key text`, which only sends lines
   that changed since the last frame (`SCR`). An idle frame sends nothing;
   walking sends the map rows. Everything is resent every 5 s and after
   `draw_frame`.

**HD mode** draws every tile 2 columns wide with emoji; `build_vrow` makes a
decorated copy of each row (flowers, shells, waves...) that is deterministic
per position. **ASCII mode** uses one column and colored characters.

**Menus** are lists of lines: `ui "text" color` for plain text, `uix colored
[plain twin]` for pre-colored lines. `render_ui` pads every line to the
frame width and cuts anything too wide (`clipl`, keeps the colors). Widths
are terminal columns: `dispw` counts an emoji as 2.

Typical costs on a modest machine: a map frame 8 - 12 ms (night 18 - 25 ms),
a frame with nothing new 4 ms and 0 bytes of output, a step about 6 KB (HD)
to 12 KB (ASCII).

## Conventions

- **Functions return values in global variables** named in their comment
  (`item_stats code -> IK IKD IT ...`). No `$( )` in anything that runs per
  frame: a subshell fork costs more than a whole frame. `printf -v` instead.
- **Every variable a function uses is `local`**. bash has dynamic scoping: a
  helper that assigns an undeclared name changes its caller's variable. Two
  real bugs of v2.0 came from this (a "number of allies" text overwrote the
  current ally, an inventory card width overwrote the weather).
- **Never put network or file input into arithmetic unchecked.**
  `(( x ))` with `x='a[$(cmd)]'` runs `cmd`. Check with `isnum` (no leading
  zeros either: `08` is an octal error) or a regex first. The handlers in
  `srv_line`, `cli_line` and `cli_srv` validate every field.
- `set -f` (no globbing), `extglob` on, `patsub_replacement` off (`&` in a
  replacement stays literal).
- Strings are measured in characters (the script makes sure it runs in a
  UTF-8 locale), except inside `render_rows`.
- Top-level code in modules only defines tables and variables; the work
  starts in `06_main.sh`.

## Files on disk

`$SHELLMMO_DIR` (default `~/.shellmmorpg/`):

| File | |
| --- | --- |
| `chars/<name>.char`, `chars/<name>.pw` | a hero and its password hash - **on the server's computer only** (6.2) |
| `<name>.char` | (before 6.2) a local hero; moved to the server when the host logs in with that name (7.0: only the host's own) |
| `prefs/<name>.gfx` | (7.0) the graphics mode a player last picked |
| `shared.chest` | (before 6.2) the chest shared by the heroes on this computer |
| `config` | graphics mode (`GFX=hd` / `ascii`) |
| `admins` | (v6.4) the heroes that are admins on this server, one name per line |
| `server.log` | the world server's log when hosting |

Environment knobs: `SHELLMMO_DIR`, `SHELLMMO_NAME`, `SHELLMMO_GFX`,
`SHELLMMO_MAX_PLAYERS` (game sessions on a server, default 32), `SHELLMMO_DEBUG` (frame time),
`SHELLMMO_MAX_INST` (dungeon instances, default 40), `SHELLMMO_ADMIN_NAME`
(set by a host for its world server: that hero is an admin), `SHELLMMO_PASS` (the
hero's password, skips the prompt), and for tests `SHELLMMO_OPEN=1` (a server
without logins),
`SHELLMMO_LIB`, `SHELLMMO_WB_DELAY`, `SHELLMMO_CLOCK`, `SHELLMMO_WEATHER_DELAY`.

## Performance notes

Where the time goes, and the rules that keep it down:

- **Client frame** (120×40): about 1.9 ms when the map did not change,
  6-9 ms with a map redraw (at most every 250 ms or on a move). The side
  panel caches its gear lines (`PEQ_K`) and skips rows that are the same as
  last frame (`PRAW`); `emit` diffs everything else line by line.
- **Server AI**: about 14 ms per 150 ms tick with eight players spread over
  the 480×200 world (830 monsters). Who stands in a town is computed once
  per tick (`PSAFE`), the distance loop in `mon_think` is inlined, idle
  monsters far from everyone sleep in the timer wheel until a player could
  possibly reach them (1.5 s at 28 tiles, up to 15 s far away).
- Memoized: `item_stats` (last code), `tal_calc` (class + talents),
  `tal_points`, `pv_slot`, `clipc`, `colorize`.
- No `$(...)`, no here-strings and no pipelines in anything that runs per
  frame, per tick or per monster. Split codes with `${x//./ }` or `%`/`#`.
- Benchmarks: see [TESTING.md](TESTING.md#benchmarks).
