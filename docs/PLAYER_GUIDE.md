# Player guide

Everything you need to go from a level 1 nobody in Hearthmoor to the
Crownbearer at level 30 - and on to level 40, where the second act of the
story ends. The in-game help (**?**) has the short version.

## Getting started

```bash
./shellmmorpg.sh                 # host a world (friends come in over ssh)
./shellmmorpg.sh --ssh me@HOST   # play on a server: always over ssh
./shellmmorpg.sh --name Lyra     # play another character (default: your user name)
```

A new hero picks a class and a look (symbol and color). You wake up in
**Hearthmoor**. Talk to **Old Tom the Innkeeper** first - he starts the story.
The quest board (**!** / 📜 on the plaza) hands out your first jobs.

Your hero lives **on the server** (since 6.2), not on your computer. The
first time you join a world you choose a password for the name; afterwards
the game asks for it at login (`SHELLMMO_PASS` works only for the host's own
game). The server keeps your hero safe: it is saved every 30 seconds,
whenever something important happens and when you quit (**Q**) - or when
your connection drops. Another world is another hero. Only one session per
hero at a time. Five wrong passwords lock the name for a minute (the next time for two, then
four ... at most 30). A new hero needs a password of at least 8 characters.

Since 7.0 your game runs **on the server** and you reach it **only over
ssh**: ssh shows it in your terminal and sends your keys. On a slow connection you feel the round trip
when you walk; on a LAN you do not. Resizing your window works as usual.

## Controls

| Key | |
| --- | --- |
| `w a s d`, arrows, `h j k l` | walk - walking into a foe attacks it, into a person talks |
| `f` / `space` | attack whatever stands next to you |
| `1 2 3` | your three skills |
| `e` / `r` | health / mana potion (greater potions first) |
| `u` | eat (fish dishes heal over time and feed you) |
| `g` | fish (next to water) or gather the node you stand at |
| `i` | inventory |
| `y` | allies |
| `p` | professions and materials |
| `m` | world map (`+`/`-` zoom, arrows pan) |
| `q` | quests and the story |
| `b` | bestiary (`<` `>` turn pages) |
| `c` | the log: `1` chat, `2` events, `3` everything - with times; `↑↓` `PgUp` `PgDn` scroll, `Home` oldest, `End` newest, `enter` chat |
| `H` | collection book (`<` `>` turn pages) |
| `o` | achievements and titles |
| `n` | name tags on/off |
| `v` | HD emoji graphics ↔ classic ASCII |
| `enter` / `t` | chat, `/` starts a command |
| `?` | help |
| `Q` | quit (asks first; your hero is saved) |
| `PgUp` `PgDn` `Home` `End` | scroll any list that is taller than your window |

The chat line edits like a shell: `←` `→` `Home` `End` move, `Del` and
backspace delete, `ctrl+w` deletes a word, `ctrl+u` / `ctrl+k` the start /
the rest of the line, `↑` `↓` bring back what you said before, `Tab`
completes a player's name (or a `/command`), `esc` cancels.
At the forge, the alchemist's table, the campfire and a waystone: `↑` `↓`
choose, `enter` does it (letters and numbers still work for the first ones).

Chat commands: `/p text` party chat, `/w name text` whisper, `/invite name`,
`/accept`, `/leave`, `/trade name`, `/give name 100` (gold) or
`/give name #3` (bag item 3), `/symbol x`, `/color 5`, `/who`, `/me waves`,
`/home` (hearthstone back to Hearthmoor, once a minute), `/r text` answers
the last whisper, `/bell` switches the beep (name, whispers, invites) off
and on - it is remembered.

**Admins** (v6.4) - for testing. The server decides who is an admin (when
you host a world yourself, you are). `/admin help` lists the tools:
`/admin god`, `heal`, `level 30`, `xp 5000`, `gold 1000`, `item W.6.12.3`
(each also `... NAME` for somebody else), `tp X Y`, `goto NAME`,
`summon NAME`, `where`, `spawn wolf 5`, `kill 10`, `wboss`, `time 22:00`,
`weather Silverlake storm`, `ann text`, `who`, `admins`, `kick NAME`,
`grant NAME`, `revoke NAME`. Every command is written to the server's log.

## Classes

| Class | Plays like | Skills |
| --- | --- | --- |
| Warrior | tough melee, cleaves crowds | Cleave, Charge, Battle Cry (+40% damage for the party) |
| Mage | fragile, huge damage | Fireball, Frost Nova (freezes), Blink |
| Ranger | fast ranged attacks | Arrow, Multishot, Evade |
| Cleric | the healer | Smite, Heal (party), Holy Light |
| Rogue | single-target burst | Backstab, Poison Blade, Shadowstep |
| Paladin | holy tank | Holy Strike, Divine Shield (immune), Consecrate |
| Necromancer | lines of bone, drain, plague | Bone Spear, Life Drain, Plague |
| Bard | support | Power Chord, Lullaby (sleep), Anthem (party speed + damage) |
| Druid | nature magic and healing | Thorn Whip (poison), Entangling Roots (holds foes in place), Wild Growth (party heal, cleanses) |
| Monk | fast melee, self-healing | Flurry (three blows), Flying Kick (dash + stun), Inner Peace (heal, cleanse, immune) |

Every class can only use some kinds of gear - gear you cannot use shows grey
in your bags and does nothing when worn. Trade it to someone who can.

| Class | Weapons | Armor | Offhand |
| --- | --- | --- | --- |
| Warrior | Sword, Axe, Hammer, Mace, Spear, War Drum, Morningstar | Mail, Plate | Shield, Lantern |
| Mage | Dagger, Wand, Staff, Orb, Tome, Grimoire | Robe | Spellbook, Lantern |
| Ranger | Spear, Dagger, Bow, Boomerang, Chakram | Jerkin, Mail | Quiver, Lantern |
| Cleric | Hammer, Mace, Wand, Staff, Tome, Holy Symbol, Censer, Harp, Morningstar | Robe, Jerkin, Mail | Shield, Spellbook, Lantern |
| Rogue | Sword, Mace, Dagger, Boomerang, Bomb Satchel, Chakram | Jerkin | Lantern, Smoke Bombs |
| Paladin | Sword, Axe, Hammer, Spear, Holy Symbol, Censer, Morningstar | Mail, Plate | Shield, Lantern |
| Necromancer | Wand, Staff, Tome, Scythe, Skull Totem, Grimoire | Robe | Spellbook, Lantern, Fetish |
| Bard | Sword, Dagger, Lute, Violin, War Drum, Trumpet, Chakram, Harp | Robe, Jerkin | Lantern, Songbook |
| Druid | Staff, Moon Sickle, Thornbough, Ironwood Staff | Robe, Jerkin, Leafweave | Lantern, Totem |
| Monk | Spear, Hand Wraps, War Glaive, Ironwood Staff | Jerkin, Gi | Lantern, Prayer Beads |

Helmets (Cap, Hat, Helmet, Circlet, Mask, Antler Crown, Mystic Hood) and
trinkets (Ring, Amulet, Medallion, Charm) also depend on the class.

## The world

Hearthmoor sits in the middle of the old lands. Monster levels rise the
further you go; the header always shows the region and its level.

| Region | Level | Town |
| --- | --- | --- |
| Greenfield Meadows | 1-2 | Hearthmoor |
| Silverlake | 2-3 | |
| Whisperwood | 3-5 | Orwin's Hut |
| Mirefen Swamp | 5-7 | Ironwood Camp |
| Stormcrag Foothills / Peaks | 8-12 | |
| Saltwind Coast | 10-11 | |
| Sunscorch Desert | 12-15 | Oasis of Kadar |
| Frostfang Tundra | 15-18 | Frosthold |
| Ashen Wastes | 18-20 | Kael's Camp |
| Sapphire Isles | 20-23 | Port Coral |
| Crystal Highlands | 21-24 | Shardhaven |
| Emerald Jungle | 22-25 | Jadeleaf Village |
| Scorched Badlands | 24-26 | Redrock Outpost |
| Void Rift | 27-30 | Last Light Bastion |
| Duskwood (south of the Badlands) | 30-32 | Hollowmere |
| Sunken Kingdom (west of Duskwood, south of the Isles) | 31-33 | Tidewatch |
| Stormreach Peaks (east of the Highlands) | 32-34 | Skyhold |
| Gloomcap Hollows (east of the Jungle) | 33-35 | Sporeholm |
| Dragonspine (east of the Void Rift) | 35-37 | Wyrmrest Keep |
| Bonefields (south of the Void Rift) | 36-38 | Gravewatch |
| Starfall Crater (far south-east) | 38-40 | Dawnspire |
| Shroudmarch (east of Starfall Crater, past Dawnspire) | 40-42 | Lanternfall |
| Gilded Expanse (east of Dragonspine, north of the Shroudmarch) | 42-45 | Sunhollow |
| Rimewastes (north of the Expanse) | 45-47 | Rimeholt |
| Aether Reach (the far north-east) | 47-50 | Zenith |

The four lands beyond the edge (8.0) are reached by two passes - east from
Dawnspire and east from Wyrmrest Keep - and joined by one road from
Lanternfall north to Zenith. Their towns belong to the Horizon Watch.

Every old land also got a new creature (an Angry Goose in the meadows,
Owlbears in Whisperwood, Ice Trolls on the tundra ...).

**Waystones** (💠 / `&`) in every town: come close to one once to attune
it, then walk into any waystone and pick an attuned town to travel there.
The **world map** (`m`) shows what you have explored, quests (`!`), your
target, dungeons, waystones and banks.

**Day and night**: a game day lasts about 19 minutes. At night only torches
light the way - yours, your friends', campfires and the lit streets of
towns. A lantern in your offhand makes your light bigger.

**Weather** moves through the regions: rain (fish bite faster), fog,
thunderstorms, sandstorms (you can barely see), blizzards (they slow you -
a frost tonic helps), ash rain in the Wastes (it burns - fire ward tonic).

**World bosses** appear now and then somewhere in the world (the panel and
map tell you where). Everyone who fights one gets loot.

## Getting stronger

- **XP** for kills, quests and story chapters; the next level needs
  30·L² + 70·L XP. The cap is level 50; after that, paragon levels (see
  Endgame).
- **Gear** has a tier (Worn, Sturdy, Fine, Mithril, Runic, Dragon, Celestial,
  Starforged, Voidforged - from level 30 Titanforged, Eclipsed, Godforged, and from level 42
  Mythforged, Primordial, Ascendant) and a rarity (Common, Rare, Epic, Legendary).
  **Uniques** are named legendaries - bosses carry them, and some story
  chapters give one. Bonus stats: crit, HP, MP, damage, armor or light.
- **Five slots**: weapon, armor, offhand, helmet, trinket.
- **Inventory** (`i`): tabs with `←` `→`, select with `w`/`s`, `enter`
  equips, the card on the right shows what would change. `l` locks an item
  (never sold or destroyed), `x` destroys, `o` sorts, `b` puts on your best
  gear for every slot.
- **Bags** (Small Pouch 4 slots … Bag of Holding 16) fill three bag slots on
  top of your 10 base slots. Shops sell the small ones, bosses drop the big.
- When your bags are full, new loot is sold automatically - except uniques,
  they always squeeze in.

## Talents

Press `x`. From level 2 you get a point every level (29 at level 30).
Every class has three trees of four talents:

| Row | Ranks | Opens at |
| --- | --- | --- |
| 1 | 5 | 0 points in the tree |
| 2 | 3 | 3 points |
| 3 | 3 | 6 points |
| 4 - capstone | 1 | 10 points |

Rows give damage, crit, crit damage, HP, armor, resistance, dodge, block,
regeneration, lifesteal, cheaper or stronger skills, shorter cooldowns,
stronger damage over time, healing or allies. Capstones change the game:
e.g. *Last Stand* (survive a killing blow once a minute), *Shatter* (frozen
targets take +60%), *Clearcast*, *Execute*, *Chain Lightning*, *Death Aura*,
*Echo* (skills sometimes cast twice). With 29 points you can finish two
trees and dip into the third. An innkeeper (`[8]`) resets them for gold.

## Elements and status effects

Skills deal **physical, fire, frost, poison, shadow, holy or arcane**
damage. Every creature is **weak** to one element (+50% damage) and
**resists** one (-50%) - the target panel and the bestiary say which.
Ice creatures fear fire, the undead fear holy light, elementals of fire
shrug off fire.

Monsters fight back with effects:

| Effect | What it does | Cure |
| --- | --- | --- |
| poisoned | damage every second, 5 s | health potion, cleansing skills, rest |
| bleeding | heavier damage over 4 s | health potion, cleansing skills, rest |
| burning | 3 s of fire | cleansing skills, rest |
| chilled | slower steps | cleansing skills, rest |
| stunned | no moves, no spells for a moment - then immune for 7 s | - |
| weakened | -25% damage for 6 s | cleansing skills, rest |

Cleansing skills: Heal and Holy Light (Cleric), Holy Strike and Consecrate (Paladin).

**Resistance** (amethyst and onyx gems, talents, tonics; at most 60%) cuts
elemental damage and shrugs effects off. **Dodge** avoids a hit entirely,
a **shield** blocks some, armor counts half against magic.

## Champions, rares and bosses

- **Champions** (their affix icon next to them in HD, `*` in ASCII): Vampiric (heal on hit), Frenzied
  (fast), Armored (-40% damage taken), Molten / Frozen / Venomous (burn,
  chill, poison you), Giant (3× HP). 3× XP and gold, a piece of gear one
  rarity better, often a gem.
- **Rare elites** (💀 / `E`): 14 named beasts, one or more per region.
  They come back a few minutes after they die - everyone hears it.
- Casters shoot from up to five tiles if they can see you - break line of
  sight behind walls and trees. Shamans and priests heal their friends:
  kill them first.
- Dungeon bosses summon help at 2/3 and 1/3 health and enrage below 1/4.

## Gems and sockets

Six gems in three grades (Chipped, Polished, Flawless):

| Gem | Gives |
| --- | --- |
| Ruby | +damage % |
| Sapphire | +mana % |
| Emerald | +crit % |
| Topaz | +armor |
| Amethyst | +HP % |
| Onyx | +resistance % |

Rare gear drops with one socket, epics with two, legendaries with up to
three (the item card shows them). Any **smith** sets gems (`[7]`): pick the
item, the socket, the gem. He also adds a socket for gold, and combines
three gems into one of the next grade. Gems in gear your class can't use do
nothing. Gems also sell for more inside an item.

## Quests

- The **quest board** and the quest givers (yellow **!** above them) offer
  kill quests, **collect** quests (drops from a kind of monster),
  **deliveries** (materials, hand them in at any quest board), **scouting**
  (walk to a place), **bounties** on rare elites, dungeon quests and courier
  letters (**?** above the receiver). Three at a time; `q` shows them with a
  direction to where they are.
- **Questlines**: every town has its own story of 4-5 steps (orange **!**
  / ❕ above the person who starts it). They send you through their region,
  to its places, its dungeons and its rare elite - and end with a choice:
  who gets the relic, the pelt, the confession. The choice changes the
  reward and which faction is grateful. `q` → tab `2` lists them.
- **Party quests**: the party leader takes them for everyone; progress is
  shared and rewards are 25% higher.
- **The story** (`q`, ⭐ / `*` above the person to talk to): 55 chapters in
  three acts - *The Shattered Crown* (level 1-28), *The Fallen Star*
  (level 30-40, through all seven lands of 4.0) and *Beyond the Edge*
  (level 40-50, 8.0) - through every town and every dungeon. Chapters wait
  until you reach their level. Rewards include allies, class gear and two
  uniques.

## Endgame (level 50)

**Mythic dungeons.** At level 50 every dungeon gate asks whether you want
the normal dungeon or a mythic one, at your key level (+2 to start, up to
+20). Every foe is scaled to level 50 and grows with each key level. The
week's affixes: *Fortified* or *Tyrannical* from +2, one champion affix on
a third of all foes from +4, *Bolstering* or *Raging* from +7. The clock
(30 seconds per room plus 2.5 minutes) shows in the side panel; each death
costs 5 seconds. In time: your key rises by one - by two in under 60% of
the time. The boss gives everyone Ascendant (tier-15) epic gear (legendary 5% + 2% per
key level), sometimes a perfect gem, and valor (20 + 6 per key level, half
again in time).

**The Eclipse Throne** (Starfall Crater, east rim): a raid for a group -
Nyxara's health grows with every hero. Every third blow drops dark stars on
everyone: step out of the marked ground. At two thirds her guards appear
and she takes a fifth of the damage until they are dead. Below a third
she unleashes a total eclipse around her - run. After eight minutes she
hits twice as hard. Everyone gets a three-socket legendary.

**The Sundered Sky** (Aether Reach, north-west of Zenith, level 50): the
second raid. Aurelion, the Sundered Sun, grows with every hero too. Every
third blow drops solar flares under everyone - step off them. At two thirds
his wardens appear and his sunfire shield takes four fifths of the damage
until they fall. Below half he sunders the sky: eight beams in a cross
around him - stand between them. Below a quarter: a supernova six tiles
wide - run as far as you can. After ten minutes he hits twice as hard.
Everyone gets a three-socket Ascendant legendary; four uniques and the
Sunfire Wyrm are his alone.

**Invasions.** About every 45 minutes the Horde attacks a town (an
announcement tells which): two waves and a warlord, twelve minutes. Hit
an invader and you count as a defender: valor, XP, gold and gear when the
town holds.

**Valor** buys Ascendant gear (epic, two sockets; a legendary weapon with
three), perfect gems and three mounts from Hale in Hearthmoor, Seren in
Dawnspire and Castor in Zenith.

**Dailies and weeklies** (from level 30, quest log tab 4): three tasks a
day, two a week, the same for everyone. Dailies pay 30 valor, gold and XP;
weeklies 150 valor and a perfect gem.

**Paragon.** After level 50 every 60,000 XP (a little more each time) is a
paragon level and a point; the talent points of levels 38-50 that no tree
can take count too (13 at level 50). `[x]` then `[p]`: Might (+1% damage), Vitality (+1% health),
Precision (+1 crit per 2), Warding (+1% resistance), Wisdom (+1% mana),
Celerity (-1% cooldowns). Innkeepers reset them along with your talents.

**Mounts.** `[z]` mounts and dismounts, `[Z]` picks which one. Hilda the
Stablemaster (Hearthmoor) sells the Brown Horse (+40%), the Swift Steed
(+60%, level 20), the Dune Camel and the Frost Ram (+60%, for the Honored
of Kadar and the Northern Clans). Valor buys the Storm Gryphon (+80%) and
the Ember Drake (+100%, also a Mythic +15 in time). The Pale Rider
sometimes leaves his Bone Charger (+80%), Nyxara her Starborn Stag (+100%).
Beyond the edge, Wren the Mistrider (Lanternfall) sells the Mist Stalker
(+100%, level 42) and the Gilded Scarab (+100%, for the Honored of the
Horizon Watch); Frostmaw sometimes leaves a Woolly Mammoth, valor buys the
Aurora Unicorn (+110%), and Aurelion sometimes leaves the Sunfire Wyrm
(+120%). At a stable, keys `1`-`9` and `a`-`d` pick a mount.
A hit, an attack or a dungeon gets you off.

**Achievements** (`[o]`): 60 of them, many with a title (`[t]` there to
choose one - it shows in your side panel). Everyone hears when you earn
one.

## Reputation

Eight factions: **Crown of Hearthmoor**, **Frontier Wardens**, **Sands of
Kadar**, **Northern Clans**, **Tidecallers**, **The Last Light**, and since
4.0 **The Wildwatch** (Duskwood, Gloomcap) and **The Dawnguard**
(Dragonspine, Starfall Crater). Quests
in their lands, questline steps and choices raise your standing:
Neutral → Friendly (1500) → Honored (4500) → Revered (9000) → Exalted
(15000). Each rank takes 5% off prices in that faction's towns. Every
faction has a **quartermaster** (`[6]` when you talk to the questline giver):
gems for the Friendly, socketed epic armor and weapons for the Honored, a
faction unique for the Revered, a legendary weapon with three sockets for
the Exalted.
`q` → tab `3` shows your standing.

## Dungeons

Walk into a `>` (🚪) to enter. Every visit generates a new layout (bigger
the deeper you go); a party shares one instance - whoever is near the
entrance comes along, the others can walk in later. An **elite** guards the
middle, **treasure chests** hide in side rooms, the **boss** waits in the
last room. Kill it and you return to the surface after 10 seconds.
Leaving and coming back before the boss is dead resumes your dungeon.

| Dungeon | Level | Where | Boss |
| --- | --- | --- | --- |
| Forgotten Crypt | 3 | Whisperwood | Lich |
| Goblin Warrens | 6 | Mirefen Swamp | Goblin King |
| Dragon's Lair | 10 | Stormcrag Peaks | Ancient Dragon |
| Sunken Tomb | 12 | Sunscorch Desert | Pharaoh Anketh |
| Ice Caverns | 15 | Frostfang Tundra | Frost Wyrm |
| Infernal Gate | 18 | Ashen Wastes | Azgor the Demon Lord |
| Coral Grotto | 20 | Sapphire Isles | Ishara the Leviathan Queen |
| Crystal Depths | 22 | Crystal Highlands | The Crystal Archon |
| Temple of the Jade Serpent | 23 | Emerald Jungle | Quetzal the Jade Serpent |
| Obsidian Forge | 24 | Scorched Badlands | Ignis the Molten King |
| Throne of the Void | 28 | Void Rift | The Hollow King |
| ... | 30-40 | the lands of 4.0 and 6.0 | ... |
| Shroud Abbey | 41 | Shroudmarch | Abbess Morwyn the Veiled |
| Tomb of the Sun Kings | 43 | Gilded Expanse | Ramahet the Sun King |
| Hall of Endless Winter | 46 | Rimewastes | Skadi, the Winter Unending |
| The Starwright's Observatory | 48 | Aether Reach | The Starwright |
| The World's Edge | 50 | Aether Reach | Oblivion, the Last Horizon |
| The Sundered Sky (raid) | 50 | Aether Reach | Aurelion, the Sundered Sun |

Dungeons are dark: you see what your torch lights and remember what you saw.

## Allies

Companions follow you, fight what you fight, and some heal. Hire them from
mercenaries - **Captain Varga** (Hearthmoor), **Kesh the Beastmaster**
(Shardhaven), **Warden Lysa** (Last Light Bastion) - or earn them in the
story. `y` lists them: `1`-`8` calls one, `x` sends it home. Only one walks
with you at a time, and everybody in the world sees it.

| Ally | Role | |
| --- | --- | --- |
| Brutus the Sellsword | melee | 300 gold (Varga) |
| Lyra the Huntress | ranged | 600 gold (Varga) |
| Brother Aldo | healer | 900 gold (Varga) |
| Fang the Wolf | melee | 1500 gold (Kesh) |
| Hootsworth the Owl | ranged | 2000 gold (Kesh) |
| Zephyr the Djinn | magic, hits around the target | 4000 gold (Lysa) |
| Cinder the Whelp | magic | story reward |
| Bonejack | melee | story reward |

## Towns, shops and the bank

Every town has an inn (rest: HP and MP full), most have a smith (weapons,
armor, forging), an alchemist (potions, brewing) or a general store, and
every town has a **banker** (🏦 / `B`):

- the **vault** is yours, the same in every town; gold in the vault is safe
  when you die (you lose 10% of the gold you carry);
- the **shared chest** is one for all heroes on this computer - the way to
  hand things to your other characters. More vault space can be rented.

## A home of your own

Talk to any innkeeper and press `[9]`: **rooms upstairs**. The Innkeepers'
Guild keeps the same room for you in every town.

| Room | Level | Move in | Rent / week | Displays | Chest | Well Rested |
| --- | --- | --- | --- | --- | --- | --- |
| Attic Room | 5 | 300 | 60 | 4 | 20 | +10% XP |
| Guest Room | 15 | 2500 | 300 | 8 | 35 | +15% XP |
| Grand Suite | 25 | 12000 | 1200 | 14 | 50 | +20% XP |
| Hero's Hall | 35 | 50000 | 4000 | 20 | 70 | +25% XP |
| Skyward Manor | 45 | 150000 | 8000 | 26 | 90 | +30% XP |

Moving up only pays the difference and takes everything along. The rent
for the week is paid when you go up - from your purse, or from the vault.
If you can't pay, the door stays closed until you can; nothing is lost.

Inside, walk into the furniture:

- 🛌 **bed**: sleep, wake up with full HP and MP and **Well Rested** - more
  experience from fights for 30 minutes (+1% more for every four things on
  display, up to +10%);
- 📦 **chest**: like the vault, for items and materials (no gold);
- 🔲 **displays**: put anything from your bags on them - gear, uniques,
  bags and above all **collectables**. Walk into one to change it;
- 📚 **bookshelf**: the collection book; 📒 **guestbook**: who came by.

The door `<` (🚪) leads back down to the taproom.

**Visiting**: `[9]`, then `[v]` asks around who has a room you may enter;
pick one and the innkeeper takes you up. The owner must be online. Your own
door (`[d]`) is locked, open for your party (the default) or open for
everybody. Guests can look at the displays and sign the guestbook.

**Collectables** can't be worn - they are for showing off. There are 80 in
six sets:

- **Dungeon Trophies** - the boss of every dungeon (and the raid) may leave
  one behind; the first time it is likely, later less so;
- **Trophies of the Titans** - the same for every world boss;
- **Curios of the Realm** - one for every land, rarely found on its
  creatures (champions and rare elites carry them more often). Not in
  towns, not in dungeons;
- **Angler's Treasures** - fished up now and then; **Prospector's Finds** -
  dug up while mining or picking herbs;
- **Relics of the Story** - one every sixth chapter.

`H` (or the bookshelf) opens the collection book: every set, what you have
found, where you keep it, and for the rest a hint where to look. Complete
sets give achievements and titles. Shops buy collectables you have twice
(`[c]`); "sell everything" never sells them, and a locked one is always
kept.

## Professions

- **Fishing**: stand next to water and press `g`, strike (`space`) when the
  ▲ is in the green. Rare fish live in special waters; rain helps.
- **Mining** and **Herbalism**: walk into ore veins (◆) and herbs (♣).
  Better nodes need a higher profession level.
- **Cooking** at campfires (`*`) and inns, **forging** at smiths (ore →
  weapons and armor of your class), **alchemy** at alchemists (herbs →
  potions, elixirs, frost / fire / veil tonics).

`p` shows your levels, materials and where to find everything.

## Playing together

- **Parties** of up to 4: `/invite name`, `/accept`, `/leave`. Party members
  show in the panel with their HP; skills like Heal, Battle Cry and Anthem
  reach everyone nearby.
- **Trade**: `/trade name` asks, the other side types `/trade yourname`.
  Toggle items with `1`-`0` (`<` `>` for more pages), `g` adds gold, `m`
  materials; both sides press `y`. Any change resets both acceptances.
- **Visits**: friends can come up to your room at the inn (see *A home of
  your own*) - while you are online.
- **Murder**: attacking a townsperson (you are asked twice) makes you
  **WANTED** - guards hunt you until the sentence runs out or you die.

## Troubleshooting

- *Emoji look broken or shifted*: press `v` for ASCII mode, or use a font
  with emoji support (Noto Color Emoji, Apple Color Emoji, Segoe UI Emoji).
- *"needs at least 100x30"*: make the window bigger.
- *Friends cannot join*: the host's port (default 4747) must be reachable -
  firewall, router port forward, or use the same network.
- *Slow*: classic ASCII mode (`v`) is a bit lighter; a smaller window too.
