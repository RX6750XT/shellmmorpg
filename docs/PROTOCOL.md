# Network protocol

Everything travels as text lines through the hub, which sends each line to
every connection. There is no other channel.

```
SM1|TYPE|from|field|field|...
```

- `SM1` - protocol tag. Lines without it are ignored.
- `from` - the sender: a player id (6 lowercase hex digits, random per game
  session) or `srv` for the world server.
- Fields never contain `|`; text fields are cleaned (`clean_text`) on
  arrival. Lines longer than 2048 bytes are dropped everywhere.
- Receivers ignore unknown types, so old and new clients can share a world
  as long as the fields they both know stay where they are.

## Player → everyone

| Type | Fields | Meaning |
| --- | --- | --- |
| `HELLO` | name cls lvl | I joined (the server answers with the world state) |
| `POS` | name cls lvl map x y hp maxhp dead sym color ally ax ay [mount] | where I am - sent on every step, at least every 2 s. `map` is `W` or `D<n>`, `ally` -1 or the ally I walk with at `ax,ay`, `mount` `-` or the mount I ride (v4.5) |
| `BYE` | | I quit |
| `CHAT` | name text | says something (chat bubble for those nearby) |
| `PCHAT` | name text | party chat (only party members show it) |
| `WHISP` | name target-name text | whisper |
| `EMOTE` | name text | `/me` |
| `EVT` | name text | something happened to me ("reached level 12!") |
| `FX` | map kind "x,y x,y ..." | a skill effect others should see |
| `HEAL` | name target-id amount | I heal you (capped at 2000) |
| `BUFF` | name target-id ms fury\|anthem | Battle Cry / Anthem (capped at 16 s) |
| `GIVE` | name target-name G gold \| I itemcode | a gift |
| `TREQ` `TACC` `TCAN` | name target-id | trade: ask, accept, cancel |
| `TOFF` | name target-id seq gold items mats | my current trade offer (`items` = comma list of codes, max 10; `mats` = `k:n,...`) |
| `TOK` | name target-id their-seq my-seq | I accept the offers as they are now |

## Player → world server

| Type | Fields | Meaning |
| --- | --- | --- |
| `HIT` | map mid damage freeze-ms | I hit monster `mid` (damage is capped by the server at (level + 5) × 70, freeze at 4 s) |
| `DREQ` | dungeon-type [key] | I walk into this dungeon (rate-limited to one per 1.5 s); `key` 2-20 asks for a mythic one (v4.5, level 40, not the raid) |
| `SYNC` | map | please resend all monsters of `map` (at most one full resync per map per second) |
| `INV` | name target-name | invite a player into my party |
| `PACC` | | accept the pending invite |
| `PLEAVE` | | leave my party |
| `QADD` | quest-code | (party leader) take a party quest |
| `QTALK` | npc-type | (party) we delivered the letter to this NPC |

## World server → everyone

All sent with `from` = `srv`; clients act on the ones for their map or id.

| Type | Fields | Meaning |
| --- | --- | --- |
| `MON` | map mid type x y hp max [champ] | a monster exists (full state); `champ` 0 = normal, 1-10 = champion affix + 1 (v3.0, 8-10 since v4.0) |
| `MMOV` | map mid x y | it moved |
| `MHP` | map mid hp [attacker] | its HP changed |
| `MDIE` | map mid killer-name\|- | it died |
| `MATK` | map mid target-id damage [element effect] | it hits a player; `element` 0-6 (physical fire frost poison shadow holy arcane), `effect` `poison` `bleed` `burn` `chill` `stun` `weaken` or empty (v3.0) |
| `LOOT` | player-id g<material> \| i:<item> | a gem dropped for that player (v3.0; material index of a gem), or an item handed out directly (v4.5: mythic, raid, invasion rewards) |
| `MDONE` | player-id key in-time seconds valor | a mythic dungeon is done (v4.5); in-time 0 = too slow, 1 = in time, 2 = very fast |
| `EVREW` | player-id valor xp gold | a defender's pay after an invasion (v4.5) |
| `REW` | player-id xp gold item monster-type [champion] | loot for a kill (`item`: code, `H`/`M` potion or empty; `champion` 1 since v4.5) |
| `FX` | map kind cells | an effect (boss warnings, blasts) |
| `BOSS` | map text [x y] | a boss shouts (shown within 40 tiles) |
| `WBOSS` | mid type x y | where the world boss is (`-1 0 0 0` = gone) |
| `CLOCK` | ms-into-the-day | the world time |
| `WEATHER` | region kind seconds | weather starts (`-` = clears) |
| `ANN` | text | announcement to everyone |
| `INFO` | player-id text | a message for one player |
| `WANTED` | player-id seconds | a player is wanted (0 = pardoned) |
| `PARTY` | party-id leader-id member,ids | a party changed (empty members = dissolved) |
| `PINV` | player-id inviter-name | you are invited |
| `PQUEST` | party-id code,code | the party's quests |
| `QDONE` | party-id xp gold code | a party quest is done - everyone gets the reward |
| `PINFO` | party-id text | a message for a party |
| `DSTART` | map type seed scale id,id [key limit used] | these players enter dungeon instance `map` - generate it from the seed; v4.5: mythic key (0 = normal), the clock in ms and the ms already used |
| `DCLEAR` | map boss-name | the boss is dead |
| `DEND` | map | the instance closed |

## World server ↔ hub

| Type | Fields | Meaning |
| --- | --- | --- |
| `AUTH` | token | the world server proves it may speak as `srv` (never relayed) |

## Codes

- **Items**: `W.kind.tier.rarity` (also `A` armor, `O` offhand, `H` helmet,
  `J` trinket), tier 1-12 (10-12 since v4.0), rarity 0-3; `B.0`-`B.5` bags;
  `U.0`-`U.41` uniques.
- **Classes** in `HELLO`/`POS`/`WHO`: 0-9 (8 Druid and 9 Monk since v4.0). Old saves may hold `W.tier.rarity` (pre-1.6) - still accepted.
- **Sockets** (v3.0): gear codes may end in `.` + 2 characters per socket:
  `__` empty or a gem `r s e t a o` + grade `1-3` - `W.6.5.2.e3__` is an
  epic bow with a flawless emerald and an empty socket. At most 3.
- **Quests**: `K.monster.need.have.xp.gold`, `D.dungeon.1.have.xp.gold`,
  `T.npc.1.have.xp.gold`; v3.0 adds `C` (collect, monster), `B` (bounty,
  rare), `E` (scout, spot index) and `G` (deliver, material). Party quests
  stay `K D T`: the server never sees the new kinds.

## Validation

Every receiver checks every field before using it. Numbers must match
`^(0|[1-9][0-9]{0,8})$` (`isnum`) - no signs, no leading zeros, no
expressions: a value like `a[$(cmd)]` must never reach `(( ))`. Map names
must be `W` or `D<digits>`, ids six hex digits, item codes pass
`valid_item`, quest codes `valid_quest`. Amounts are capped (gold gifts 10
million, heals 2000, buffs 16 s, damage by level).

## Trust model

The game has no accounts. **Clients are trusted with their own character**:
a modified client can claim any level, gear or gold. This is a game for
friends.

What the server and hub do guarantee (python3 and socat hubs):

- only the world server can send as `srv` - nobody can fake monsters, loot,
  announcements or dungeon starts;
- every connection is bound to the first sender id it uses - nobody can chat,
  trade, heal or quit in someone else's name;
- input is validated before use; garbage, oversized lines and injection
  attempts are dropped (`tests/test_net.py` checks this);
- requests that create work for the server are limited (dungeon instances:
  one request per 1.5 s per player, 40 at a time; full resyncs: one per map
  per second; slow clients are cut off at 1 MiB of unread output).

The ncat hub (`ncat --broker`) relays blindly - it is only picked when
neither python3 nor socat is installed.
