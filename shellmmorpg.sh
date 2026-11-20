#!/usr/bin/env bash
# ============================================================================
#  shellmmorpg - a real-time multiplayer RPG for your terminal, in pure bash
# ============================================================================
#  ./shellmmorpg.sh                     start a world and play (friends can join)
#  ./shellmmorpg.sh --join HOST[:PORT]  join a friend's world
#  ./shellmmorpg.sh --server [PORT]     dedicated server without a player
#  ./shellmmorpg.sh --port PORT         port to host on (default 4747)
#  ./shellmmorpg.sh --bind ADDR         listen only on this address (127.0.0.1 behind ssh)
#  ./shellmmorpg.sh --ssh [USER@]HOST   play on a server over ssh (see deploy/ and docs/SERVER.md)
#  ./shellmmorpg.sh --name NAME         character name (default: $USER)
#  ./shellmmorpg.sh --ascii / --hd      classic ASCII or HD emoji graphics ([v] in game)
#  ./shellmmorpg.sh --help              this help
#
#  A 480x200 open world with 17 towns and 22 regions, 10 classes and 30
#  skills, 23 procedurally generated dungeons with elites, chests and bosses,
#  roaming world bosses, day & night, weather, parties and party quests,
#  professions and crafting, trading, bags and banks, 66 unique legendaries,
#  12 allies and a 42-chapter story in two acts - for up to level 40. Talent
#  trees, elements and status effects, champions and 46 rare elites, gems and
#  sockets, 27 questlines with choices and eight factions. Since 4.5: mythic
#  dungeons, a raid, invasions, valor, mounts, paragon levels, dailies,
#  achievements and titles - and professions and gems up to level 40.
#  Since 5.0: a room of your own at every inn - rent it, sleep in it, store
#  things in it, show off 80 collectables on its displays, invite friends.
#  Since 6.0: more of everything - 44 creatures, 22 rares, 4 dungeons, 4 world
#  bosses, 8 questlines, 20 uniques, 6 materials, 54 more collectables.
#
#  Hosting needs python3, socat or ncat (force one: SHELLMMO_HUB=socat).
#  Joining needs nothing but bash. Characters are saved in ~/.shellmmorpg/
#  Needs bash 4.3+, a 256-color UTF-8 terminal, at least 100x30.
#  In game press [?] for all controls. Guides: README.md and docs/.
#
#  This file is built from src/*.sh and world.txt by build.sh - edit those.
# ============================================================================

VERSION="6.3"
DATA_DIR="${SHELLMMO_DIR:-$HOME/.shellmmorpg}"
SELF=$(readlink -f "$0" 2>/dev/null || echo "$0")
# string lengths must count characters, not bytes (emoji graphics): make sure we run in a UTF-8 locale
_u="é"
if (( ${#_u} != 1 )); then
  for _l in C.UTF-8 C.utf8 en_US.UTF-8 en_GB.UTF-8 de_DE.UTF-8 UTF-8; do
    { LC_ALL=$_l; } 2>/dev/null; _u="é"; (( ${#_u} == 1 )) && break
  done
fi
unset _u _l
shopt -s extglob
shopt -u patsub_replacement 2>/dev/null   # "&" in replacements stays literal
set -f                                   # no globbing on word splits

hub_handler() {   # socat backend: one process per client, relays via a shared log
  local log=$1 line tp me="" r f mf="$1.me.$$"
  # relay the log to this client - except the private lines meant for others (hero data and passwords
  # go to the world server only, AR<id> answers to that one player); awk learns who we are from $mf
  { tail -n0 -F "$log" 2>/dev/null | awk -F'|' -v mf="$mf" '
      function who() { if (me == "") { getline me < mf; close(mf) } return me }
      { t = $2
        if (t == "ALOAD" || t == "ASAVE") { if (who() != "srv") next }
        else if (substr(t, 1, 2) == "AR" && length(t) == 8) { if (t != "AR" who()) next }
        print; fflush() }'; } &
  tp=$!
  while IFS= read -r line; do
    (( ${#line} <= 2048 )) && [[ $line == SM1\|*\|* ]] || continue
    r=${line#SM1|}; f=${r#*|}; f=${f%%|*}             # sender id (same rules as the python hub)
    if [[ $r == AUTH\|srv\|* ]]; then
      [[ -n $SHELLMMO_HUB_TOKEN && ${r#AUTH|srv|} == "$SHELLMMO_HUB_TOKEN" ]] && { me=srv; printf '%s\n' srv > "$mf"; }
      continue
    fi
    [[ -z $me && $f != srv ]] && { me=$f; printf '%s\n' "$me" > "$mf"; }
    [[ $f == "$me" ]] || continue
    case ${r%%|*} in
      ALOAD|ASAVE) [[ $me == srv ]] && continue ;;
      AR??????) [[ $me == srv ]] || continue ;;
    esac
    printf '%s\n' "$line" >> "$log"
  done
  pkill -P "$tp" 2>/dev/null; kill "$tp" 2>/dev/null; rm -f "$mf"
}

die() { echo "shellmmorpg: $*" >&2; exit 1; }

MODE=host NET_BIND="" NET_HOST=127.0.0.1 NET_PORT=4747 MY_NAME="${SHELLMMO_NAME:-${USER:-hero}}" GFX=${SHELLMMO_GFX:-}
while (( $# )); do
  case $1 in
    -h|--help) awk 'NR > 2 && !/^#/ { exit } NR > 2 && !/====/ { sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    --hub-handler)  hub_handler "$2"; exit 0 ;;
    --world-server) MODE=world NET_PORT=$2; shift ;;
    --server) MODE=server; if [[ $2 =~ ^[0-9]+$ ]]; then NET_PORT=$2; shift; fi ;;
    --port)   [[ $2 =~ ^[0-9]+$ ]] || die "--port needs a number"; NET_PORT=$2; shift ;;
    --join)
      [[ -n $2 ]] || die "--join needs an address, e.g. --join 192.168.1.20:4747"
      MODE=join
      if [[ $2 == *:* && ${2##*:} =~ ^[0-9]+$ ]]; then NET_HOST=${2%:*} NET_PORT=${2##*:}; else NET_HOST=$2; fi
      shift ;;
    --bind) [[ $2 =~ ^[A-Za-z0-9.:_-]+$ ]] || die "--bind needs an address, e.g. 127.0.0.1"; NET_BIND=$2; shift ;;
    --ssh)
      [[ $2 =~ ^[A-Za-z0-9._@-]+(:[0-9]+)?$ ]] || die "--ssh needs [user@]host[:sshport], e.g. --ssh me@play.example.org"
      command -v ssh >/dev/null 2>&1 || die "--ssh needs the ssh command"
      ssh_to=${2%%:*} ssh_port=()
      [[ $2 == *:* ]] && ssh_port=(-p "${2##*:}")
      ssh_args=(); [[ -n $GFX ]] && ssh_args+=("--$GFX")
      exec ssh -t "${ssh_port[@]}" "$ssh_to" "${SHELLMMO_REMOTE:-shellmmorpg-play}" "${ssh_args[@]}" ;;
    --name) [[ -n $2 ]] || die "--name needs a value"; MY_NAME=$2; shift ;;
    --ascii) GFX=ascii ;;
    --hd)    GFX=hd ;;
    *) die "unknown option '$1' (try --help)" ;;
  esac
  shift
done
[[ $NET_HOST =~ ^[A-Za-z0-9._-]+$ ]] || die "invalid host '$NET_HOST'"
(( NET_PORT >= 1 && NET_PORT <= 65535 )) || die "invalid port '$NET_PORT'"
MY_NAME=${MY_NAME//[^A-Za-z0-9_-]/}; MY_NAME=${MY_NAME:0:12}
[[ -n $MY_NAME ]] || MY_NAME="hero$(( RANDOM % 1000 ))"
if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
  die "needs bash 4.3 or newer (you have $BASH_VERSION)"
fi

# ---------------------------------------------------------------------------
#  Game data
# ---------------------------------------------------------------------------
NCLS=8
C_NAME=(Warrior Mage Ranger Cleric Rogue Paladin Necromancer Bard)
C_DESC=("tough melee fighter, cleaves crowds and charges in"
        "fragile but deadly: fireballs, frost nova, blink"
        "fast ranged attacks, multishot, evasive leaps"
        "the healer every party wants: heals, smite, holy light"
        "backstabs, poison and shadowsteps - brutal single target"
        "holy tank: hammer strikes, divine shield, consecration"
        "bone spears pierce whole lines, drains life, spreads plague"
        "songs: stun foes with a lullaby, make the party fast and furious")
C_HP0=(44 26 32 34 32 42 28 30)  C_HPL=(12 7 9 10 9 11 7 8)
C_MP0=(20 40 30 40 25 30 45 40)  C_MPL=(3 8 5 7 4 5 8 7)
C_DMG=(110 90 100 90 115 100 85 85)  C_ARM=(3 0 1 2 1 3 0 1)

S_NAME=("Cleave" "Charge" "Battle Cry"   "Fireball" "Frost Nova" "Blink"
        "Arrow" "Multishot" "Evade"      "Smite" "Heal" "Holy Light"
        "Backstab" "Poison Blade" "Shadowstep"  "Holy Strike" "Divine Shield" "Consecrate"
        "Bone Spear" "Life Drain" "Plague"      "Power Chord" "Lullaby" "Anthem")
S_MP=(8 12 20  10 18 10  3 14 10  6 16 24  10 12 12  10 25 20  12 14 22  8 20 25)
S_CD=(3500 8000 30000  2200 10000 7000  700 6000 12000  1400 6000 15000
      4000 7000 9000  3500 25000 9000  3000 4000 12000  2000 14000 30000)

M_NAME=("Rat" "Slime" "Wolf" "Goblin" "Spider" "Bog Zombie" "Bandit" "Troll" "Wyvern"
        "Skeleton" "Ghost" "Lich" "Orc" "Hobgoblin" "Goblin King" "Cultist" "Drake" "Ancient Dragon" "Behemoth"
        "Town Guard" "Mara" "Brom" "Ysolde" "Old Tom" "Villager" "Orwin" "Garrick" "Senna"
        "Sand Crab" "Scorpion" "Sand Raider" "Dune Wurm" "Mummy" "Tomb Guardian" "Pharaoh Anketh"
        "Frost Wolf" "Yeti" "Ice Elemental" "Frost Giant" "Frost Wyrm" "Fire Imp" "Lava Golem" "Hellhound"
        "Demon" "Azgor the Demon Lord" "Drowned Sailor"
        "Captain Rahim" "Nadia" "Samira" "Jarl Hrolf" "Ingrid" "Olaf" "Ser Kael")
M_GLY=(r j w g a z b T W s G L o h K c d D B   G M B A I v H T +
       x k R U m N P f Y E F V i J q X Z S   C N + J S O K)
NPCBG="48;5;24"
M_COL=("38;5;180" "38;5;118" "38;5;252" "38;5;76" "38;5;135" "38;5;107" "38;5;167" "1;38;5;160" "1;38;5;99"
       "1;38;5;255" "38;5;159" "1;38;5;231;48;5;54" "1;38;5;70" "38;5;172" "1;38;5;231;48;5;94"
       "38;5;161" "1;38;5;202" "1;38;5;231;48;5;88" "1;38;5;231;48;5;130"
       "1;38;5;231;$NPCBG" "1;38;5;226;$NPCBG" "1;38;5;208;$NPCBG" "1;38;5;213;$NPCBG" "1;38;5;46;$NPCBG"
       "38;5;250;$NPCBG" "1;38;5;151;48;5;22" "1;38;5;180;48;5;94" "1;38;5;46;48;5;94"
       "38;5;209" "1;38;5;178" "1;38;5;137" "1;38;5;231;48;5;130" "38;5;230" "1;38;5;186" "1;38;5;226;48;5;94"
       "1;38;5;153" "1;38;5;255" "1;38;5;51" "1;38;5;117" "1;38;5;231;48;5;25" "1;38;5;208" "1;38;5;166" "1;38;5;160"
       "1;38;5;124" "1;38;5;231;48;5;52" "38;5;66"
       "1;38;5;226;$NPCBG" "1;38;5;213;$NPCBG" "1;38;5;46;$NPCBG" "1;38;5;231;$NPCBG" "1;38;5;208;$NPCBG"
       "1;38;5;180;$NPCBG" "1;38;5;228;$NPCBG")
M_LVL=(1 2 3 4 5 6 8 10 12 4 5 7 8 7 10 12 13 16 14   15 5 9 7 4 1 12 8 6
       10 12 13 15 13 14 15 15 16 17 18 19 18 19 19 20 22 11   14 10 9 18 15 12 21)
M_HP=(14 22 34 45 50 85 100 190 210 50 40 650 120 95 1400 160 240 3800 5200   900 150 320 180 160 40 400 250 160
      170 210 240 520 260 330 4500 300 420 380 650 7000 380 800 480 900 12000 190   600 300 250 900 500 400 1500)
M_DMG=(3 4 7 8 11 12 16 24 28 9 10 22 17 15 32 26 30 48 42   38 8 22 15 8 3 30 18 10
       20 27 30 40 30 34 52 36 42 46 55 65 50 62 56 70 85 24   40 25 20 60 45 35 80)
M_XP=(8 12 22 30 38 50 70 110 140 32 40 650 75 65 1300 130 170 4200 3200   80 40 80 60 30 8 150 60 40
      100 135 160 330 160 200 5000 210 260 290 380 9000 330 450 400 600 16000 120   120 80 60 200 120 90 300)
M_GOLD=(2 3 4 8 6 9 18 25 30 7 6 220 15 14 450 30 35 1300 900   15 160 250 220 120 12 90 300 80
        20 26 45 60 30 35 1500 30 40 45 60 2500 50 70 55 90 4000 28   300 350 150 400 400 250 500)
M_AGGRO=(4 3 6 6 5 5 7 6 8 6 7 9 7 7 9 7 8 10 9   10 0 0 0 0 0 0 0 0
         4 6 7 5 6 6 9 7 6 7 6 10 8 5 8 7 10 6   0 0 0 0 0 0 0)
M_MOVE=(600 900 380 520 420 800 480 650 350 520 450 700 500 520 600 480 420 650 800   420 900 900 900 900 1500 900 900 900
        700 420 460 700 650 600 650 360 600 550 700 600 380 800 350 500 600 550   900 900 900 900 900 900 900)
M_ATK=(1100 1300 1000 1100 1000 1400 1000 1500 1200 1100 1400 1300 1100 1100 1200 1000 1100 1400 1500   1000 1200 1100 1200 1200 1300 1000 1100 1200
       1200 1000 1000 1500 1200 1300 1300 1000 1300 1200 1600 1300 1000 1600 1000 1300 1300 1100   1000 1100 1200 1000 1100 1200 900)
M_BOSS=(0 0 0 0 0 0 0 0 0 0 0 1 0 0 1 0 0 1 1   0 0 0 0 0 0 0 0 0
        0 0 0 0 0 0 1 0 0 0 0 1 0 0 0 0 1 0   0 0 0 0 0 0 0)
M_KIND=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0   2 1 1 1 1 1 1 1 1
        0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0   1 1 1 1 1 1 1)   # 1 = civilian NPC, 2 = guard
# v1.3: resource nodes (kind 3: ore veins + herbs, M_LVL = profession level needed, M_HP = charges)
NODE0=${#M_NAME[@]}
M_NAME+=("Copper Vein" "Iron Vein" "Silver Vein" "Gold Vein" "Mithril Vein" "Obsidian Vein"
         "Peacebloom" "Silverleaf" "Bog Myrtle" "Desert Rose" "Frost Lotus" "Emberroot")
M_GLY+=(◆ ◆ ◆ ◆ ◆ ◆ ♣ ♣ ♣ ♣ ♣ ♣)
M_COL+=("1;38;5;173" "1;38;5;250" "1;38;5;231" "1;38;5;220" "1;38;5;87" "1;38;5;99"
        "1;38;5;213" "1;38;5;152" "1;38;5;143" "1;38;5;204" "1;38;5;159" "1;38;5;202")
M_LVL+=(1 3 6 10 14 18 1 3 6 10 14 18)  M_HP+=(3 3 3 3 3 3 3 3 3 3 3 3)  M_DMG+=(0 0 0 0 0 0 0 0 0 0 0 0)
M_XP+=(8 11 15 20 26 32 8 11 15 20 26 32)  M_GOLD+=(0 0 0 0 0 0 0 0 0 0 0 0)
M_AGGRO+=(0 0 0 0 0 0 0 0 0 0 0 0)  M_MOVE+=(900 900 900 900 900 900 900 900 900 900 900 900)
M_ATK+=(1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000 1000)
M_BOSS+=(0 0 0 0 0 0 0 0 0 0 0 0)  M_KIND+=(3 3 3 3 3 3 3 3 3 3 3 3)
# v1.3: world bosses (one roams the world at a time, everybody who fights it gets loot)
WB0=${#M_NAME[@]}
M_NAME+=("Elder Treant" "Bog Hydra" "Dread Corsair" "Sand Colossus" "Ymir the Frost Titan" "Infernal Juggernaut")
M_GLY+=(e y p Q t u)
M_COL+=("1;38;5;231;48;5;22" "1;38;5;231;48;5;58" "1;38;5;231;48;5;23" "1;38;5;16;48;5;179" "1;38;5;16;48;5;117" "1;38;5;231;48;5;160")
M_LVL+=(7 10 12 16 19 22)  M_HP+=(2600 4200 5000 8000 11000 15000)  M_DMG+=(20 28 34 46 58 72)
M_XP+=(1500 2600 3400 6000 9000 14000)  M_GOLD+=(400 650 900 1500 2200 3500)
M_AGGRO+=(8 8 9 9 10 10)  M_MOVE+=(800 700 500 750 650 600)  M_ATK+=(1500 1300 1100 1500 1400 1300)
M_BOSS+=(1 1 1 1 1 1)  M_KIND+=(0 0 0 0 0 0)
# v1.8: bankers, one in every town (they all share the same vault)
BANK0=${#M_NAME[@]}
M_NAME+=("Gilda" "Otto" "Zahra" "Sven" "Morga")
M_GLY+=('$' '$' '$' '$' '$')
M_COL+=("1;38;5;220;$NPCBG" "1;38;5;220;$NPCBG" "1;38;5;220;$NPCBG" "1;38;5;220;$NPCBG" "1;38;5;220;$NPCBG")
M_LVL+=(15 15 15 18 21)  M_HP+=(600 600 600 800 1000)  M_DMG+=(30 30 30 40 50)
M_XP+=(100 100 100 150 200)  M_GOLD+=(500 500 500 600 700)
M_AGGRO+=(0 0 0 0 0)  M_MOVE+=(900 900 900 900 900)  M_ATK+=(1100 1100 1100 1100 1100)
M_BOSS+=(0 0 0 0 0)  M_KIND+=(1 1 1 1 1)
NM=${#M_NAME[@]}
WORLD_TYPES=(0 1 2 3 4 5 6 7 8 28 45 29 30 31 35 36 37 40 41 42 43)
BEHEMOTH=18
# world boss rotation: type and where it may appear (x1 y1 x2 y2)
WB_LIST=($WB0 $(( WB0 + 1 )) $BEHEMOTH $(( WB0 + 2 )) $(( WB0 + 3 )) $(( WB0 + 4 )) $(( WB0 + 5 )))
WB_RECT=("8 6 60 26" "110 44 154 60" "104 26 154 36" "4 65 58 76" "70 66 150 96" "166 4 232 44" "166 52 232 96")
WB_ADDS=("2 2 3" "5 5 5" "7 7 6" "45 45 6" "29 30 31" "35 35 36" "42 42 41")
UNDEAD=" 5 9 10 11 32 33 34 45 "

# v1.3: professions & materials (ore 0-5, herbs 6-11, fish 12-21)
MAT_NAME=("Copper Ore" "Iron Ore" "Silver Ore" "Gold Ore" "Mithril Ore" "Obsidian"
          "Peacebloom" "Silverleaf" "Bog Myrtle" "Desert Rose" "Frost Lotus" "Emberroot"
          "Minnow" "Trout" "Silverscale" "Moonfin" "Mudfish" "Sea Bass" "Swordfish" "Golden Koi" "Ice Pike" "Lava Eel")
MAT_VAL=(6 10 16 24 34 46  5 8 13 20 28 38  4 9 30 45 8 14 40 50 36 60)
MAT_RARE=(0 0 0 0 0 0  0 0 0 0 0 0  0 1 2 2 0 0 2 2 1 1)
NMAT=${#MAT_NAME[@]}
PROF_NAME=(Fishing Mining Herbalism)
# fishing grounds: "material required-level rarity [night]" per kind of water
declare -A FISHW=([fresh]="12:1:0 13:3:1" [forest]="12:1:0 13:3:1 14:8:2" [lake]="12:1:0 13:3:1 14:8:2 15:6:2:night"
                  [swamp]="16:1:0 13:3:1" [sea]="17:8:0 18:12:2" [oasis]="12:1:0 19:10:2" [ice]="20:14:1" [lava]="21:18:1")
declare -A WATER_OF=([Greenfield_Meadows]=fresh [Silverlake]=lake [Whisperwood]=forest [Stormcrag_Peaks]=forest
                     [Stormcrag_Foothills]=forest [Mirefen_Swamp]=swamp [Saltwind_Coast]=sea [Sunscorch_Desert]=oasis
                     [Frostfang_Tundra]=ice [Ashen_Wastes]=ice)

# v1.3: weather per region (server rolls it, clients render it)
WEA_REG=(Greenfield_Meadows Silverlake Whisperwood Mirefen_Swamp Saltwind_Coast Sunscorch_Desert Frostfang_Tundra Ashen_Wastes)
WEA_KIND=("rain" "rain" "rain fog" "fog rain" "rain storm" "sand" "snow" "ash")
declare -A WEA_LABEL=([rain]="Rain" [storm]="Thunderstorm" [fog]="Fog" [sand]="Sandstorm" [snow]="Blizzard" [ash]="Ash rain")
declare -A WEA_START=([rain]="Rain starts to fall over" [storm]="A thunderstorm rolls in over" [fog]="A thick fog creeps over"
                      [sand]="A sandstorm sweeps across" [snow]="A howling blizzard engulfs" [ash]="Burning ash rains down on")
# day & night: one game minute = 800 ms, a full day = 19.2 minutes
GMIN=800 DAYLEN=1152000

# NPCs: role per type, full name, and where they live (type x y wander-radius)
declare -A N_ROLE=([19]=guard [20]=general [21]=smith [22]=alchemist [23]=inn [24]=villager [25]=hermit [26]=trader [27]=medic
                   [46]=questgiver [47]=spice [48]=medic [49]=questgiver [50]=smith [51]=inn [52]=questgiver
                   [$BANK0]=bank [$(( BANK0 + 1 ))]=bank [$(( BANK0 + 2 ))]=bank [$(( BANK0 + 3 ))]=bank [$(( BANK0 + 4 ))]=bank)
declare -A N_FULL=([19]="Town Guard" [20]="Mara the Merchant" [21]="Brom the Blacksmith" [22]="Ysolde the Alchemist"
                   [23]="Old Tom the Innkeeper" [24]="Villager" [25]="Orwin the Hermit" [26]="Garrick the Trader" [27]="Senna the Medic"
                   [46]="Captain Rahim" [47]="Nadia the Spice Trader" [48]="Samira the Healer" [49]="Jarl Hrolf"
                   [50]="Ingrid the Smith" [51]="Olaf the Mead Keeper" [52]="Ser Kael the Exiled"
                   [$BANK0]="Gilda the Banker" [$(( BANK0 + 1 ))]="Otto the Banker" [$(( BANK0 + 2 ))]="Zahra the Banker"
                   [$(( BANK0 + 3 ))]="Sven the Banker" [$(( BANK0 + 4 ))]="Morga the Banker")
# quest givers: kill-quest monster types | dungeon | courier target (npc type)
declare -A N_QK=([25]="2 3 4" [26]="5 6 7 8" [46]="28 45 29 30 31" [49]="35 36 37" [52]="40 41 42 43")
declare -A N_QD=([25]=0 [26]=1 [46]=3 [49]=4 [52]=5)
declare -A N_QT=([25]=26 [26]=46 [46]=49 [49]=52 [52]=23)
declare -A N_HOME=([23]="Hearthmoor" [25]="Orwin's Hut" [26]="Ironwood Camp" [46]="Oasis of Kadar" [49]="Frosthold" [52]="Kael's Camp")
NPC_SPAWNS=("19 78 29 1" "19 82 29 1" "19 78 39 1" "19 82 39 1" "19 67 33 1" "19 93 35 1"
            "20 72 31 0" "23 88 31 0" "21 72 38 0" "22 88 38 0"
            "24 77 33 3" "24 83 35 3" "24 80 38 3" "25 23 13 1" "26 112 37 0" "27 119 37 0"
            "46 106 78 0" "47 118 78 0" "48 118 86 0" "19 110 77 1" "19 114 77 1" "19 101 81 1" "19 123 83 1"
            "49 200 18 0" "50 208 18 0" "51 208 24 0" "19 199 17 1" "19 205 17 1" "19 193 22 1"
            "52 190 63 1"
            "$BANK0 79 30 0" "$(( BANK0 + 1 )) 114 38 0" "$(( BANK0 + 2 )) 112 79 0" "$(( BANK0 + 3 )) 200 24 0" "$(( BANK0 + 4 )) 196 60 0")
declare -A N_SAY=(
  [guard]="Move along, citizen.|Keep the peace and we'll get along fine.|Seen any trouble at the gates? No? Good."
  [general]="Potions, provisions - and I buy whatever junk you drag in.|Back from the meadows? Let's see what you found.|Fresh potions, brewed this morning. Mostly."
  [smith]="Steel doesn't lie. Need a new blade, or shall I reforge yours?|Bring me your gear, I'll make it sing.|That armor has seen better days. So have I."
  [alchemist]="Careful, that one's still bubbling.|Strength, iron skin, swiftness - every elixir has its price.|Don't drink the purple one. Trust me."
  [inn]="A warm bed and a hot stew - always on the house for heroes.|Sit, rest your feet. The road is long.|Heard the latest? Everybody talks at my tables."
  [villager]="Lovely weather for slaying rats, isn't it?|My cousin went into the crypt. Never came back.|You adventurers are so brave. Or foolish.|Have you seen my chicken?"
  [hermit]="Few find their way to my hut. Sit, stranger.|The forest whispers. Tonight it whispers about you.|I sell brews that would wake the dead. Well, almost."
  [trader]="Long way from town, eh? My prices reflect that.|Buying and selling, no questions asked.|The swamp folk bring me odd things. Want some?"
  [medic]="Hold still, this will sting.|Another one from the foothills? Sit down.|Bandages, salves, a kind word. Free of charge."
  [questgiver]="I could use someone like you. Interested in some work?|The wilds grow more dangerous every day. Will you help?|Ah, an adventurer. I have tasks that pay well."
  [spice]="Spices, salts and elixirs from beyond the dunes!|The desert takes, but it also gives. To those who pay.|Careful, the red one burns going in AND coming out."
  [bank]="Your valuables are safe with us - in every town, the same vault.|Gold in the vault never falls out of your pockets when you die.|We guard it like a dragon guards its hoard. Only friendlier.")
RUMORS=("The Lich of the Forgotten Crypt hates being frozen - mages, take note."
        "Goblins in the Warrens follow their king. Kill him and they scatter."
        "They say the Ancient Dragon's hoard is never-ending. Bring friends. Many friends."
        "World bosses wake up all over the land. Everyone who fights one gets a share of the loot."
        "Not every hero can swing an axe. Check who can use a piece before you pay for it - or trade it away."
        "A lantern in your off hand pushes the night back a few steps."
        "Rings, amulets, medallions and charms fit every class. Legendary ones are worth a fortune."
        "Bags come in six sizes. The biggest ones only drop from bosses - the Bag of Holding from world bosses."
        "Every town has a banker. Gold in the vault is safe when you die, and the shared chest reaches all your heroes."
        "Lock your favourite gear with [l] so you never sell it by accident."
        "The inventory tells you exactly what a piece would change. Look for the green arrows."
        "Ore veins glitter next to the mountains, herbs grow in the wild. Walk into them to gather."
        "Fish bite faster in the rain. Some say a Moonfin rises in Silverlake, but only at night."
        "Brom forges Rare gear from six chunks of ore - and sometimes something Legendary."
        "A sandstorm blinds you, a blizzard slows you, ash rain burns. Tonics help against all of it."
        "At night the dead walk harder. Stay near the torches - or bring friends, they carry light too."
        "Brom can turn a common blade into a legend - if luck is on your side."
        "Party quests from the board pay a quarter more. The leader picks them."
        "Murder someone in Hearthmoor and the guards will hunt you until you drop."
        "Orwin the hermit lives deep in Whisperwood, west of the crypt."
        "Garrick keeps a camp on the east road. Handy before the swamp or the peaks."
        "A bard's anthem makes the whole party faster. Faster is alive."
        "Waystones (&) link the outposts. Touch one once and you can travel back for a few coins."
        "Captain Rahim guards the Oasis of Kadar, far south past the meadows. He always needs help."
        "Pharaoh Anketh sleeps in the Sunken Tomb. Mummies don't like fire, they say."
        "In Frosthold, Jarl Hrolf pays heroes who thin out the yetis."
        "Beyond the tundra lie the Ashen Wastes. Ser Kael watches the Infernal Gate there, alone."
        "Press [q] to see where your quest targets are - the arrow points the way.")

D_NAME=("Forgotten Crypt" "Goblin Warrens" "Dragon's Lair" "Sunken Tomb" "Ice Caverns" "Infernal Gate")
D_REQ=(3 6 10 12 15 18)
D_POOL=("9 10 9 0" "3 13 12 13" "15 16 8 16" "32 33 32 29" "37 38 35 37" "40 41 42 43")
D_BOSS=(11 14 17 34 39 44)
D_ENTX=(40 134 140 142 228 226)  D_ENTY=(10 50 8 94 8 90)
D_WHERE=("Whisperwood, north-west" "Mirefen Swamp, south-east" "Stormcrag Peaks, north-east"
         "Sunscorch Desert, far south" "Frostfang Tundra, far east" "Ashen Wastes, far south-east")
D_WALL=("38;5;245" "38;5;136" "38;5;124" "38;5;180" "38;5;117" "38;5;88")
D_FLOOR=("38;5;238" "38;5;94" "38;5;52" "38;5;137" "38;5;24" "38;5;236")
NDT=${#D_NAME[@]}

# spawn zones: type x1 y1 x2 y2 count
ZONES=("0 70 18 100 26 6" "1 70 18 100 26 3" "1 52 26 64 44 4" "0 52 26 64 44 3" "0 96 26 104 44 4"
       "1 64 43 100 60 6" "0 64 43 100 60 5" "1 10 36 52 60 4" "2 10 36 52 60 4"
       "2 4 4 68 28 7" "3 4 4 68 28 7" "4 4 4 68 28 4" "5 106 40 156 60 8" "4 106 40 156 60 4"
       "6 100 24 156 38 8" "7 104 3 156 23 5" "8 104 3 156 23 4"
       "28 5 64 62 76 6" "45 5 64 62 76 4" "29 62 66 158 97 9" "30 62 66 158 97 7" "31 62 66 158 97 3"
       "35 162 2 237 45 8" "36 162 2 237 45 6" "37 162 2 237 45 5"
       "40 162 52 237 97 8" "41 162 52 237 97 5" "42 162 52 237 97 6" "43 162 52 237 97 2")
n=$NODE0   # ore veins (next to mountains) and herbs
ZONES+=("$n 40 14 108 62 7" "$(( n + 1 )) 4 4 68 30 5" "$(( n + 1 )) 100 24 158 38 4" "$(( n + 2 )) 100 2 158 23 6"
        "$(( n + 3 )) 62 64 159 99 7" "$(( n + 4 )) 162 2 237 45 7" "$(( n + 5 )) 162 52 237 97 7"
        "$(( n + 6 )) 40 14 108 62 8" "$(( n + 7 )) 2 34 54 62 6" "$(( n + 7 )) 4 4 68 28 4" "$(( n + 8 )) 104 40 158 62 7"
        "$(( n + 9 )) 62 64 159 99 7" "$(( n + 9 )) 5 64 62 76 3" "$(( n + 10 )) 162 2 237 45 7" "$(( n + 11 )) 162 52 237 97 7")
SAFE_RECTS=("64 26 96 42" "108 33 123 41" "19 10 29 17" "98 74 126 90" "190 14 214 28" "184 56 200 68")   # monsters never enter
SPAWN_X=80 SPAWN_Y=35                          # respawn next to the fountain
REGIONS=("66 28 94 40 Hearthmoor safe" "110 35 121 39 Ironwood_Camp safe" "21 12 26 15 Orwin's_Hut safe"
         "2 2 70 28 Whisperwood 3-5" "100 2 158 23 Stormcrag_Peaks 10-12"
         "100 24 158 38 Stormcrag_Foothills 8-9" "104 40 158 62 Mirefen_Swamp 5-7"
         "2 34 54 62 Silverlake 2-3" "0 0 159 63 Greenfield_Meadows 1-2"
         "100 76 124 88 Oasis_of_Kadar safe" "192 16 212 26 Frosthold safe" "186 58 198 66 Kael's_Camp safe"
         "0 64 61 99 Saltwind_Coast 10-11" "62 64 159 99 Sunscorch_Desert 12-15"
         "160 0 239 47 Frostfang_Tundra 15-18" "160 48 239 99 Ashen_Wastes 18-20")
WAYSTONES=("Hearthmoor 77 35" "Ironwood_Camp 118 36" "Oasis_of_Kadar 103 78" "Frosthold 195 18" "Kael's_Camp 188 60")

RAR_NAME=(Common Rare Epic Legendary)
RAR_COL=("38;5;252" "1;38;5;33" "1;38;5;171" "1;38;5;214")
RAR_MUL=(100 130 170 230)

# player colors (pick one at character creation, /color to change)
P_COLN=(red orange yellow lime green cyan sky blue purple magenta pink white)
P_COLC=(196 208 226 118 46 51 39 33 129 201 213 231)
# ---------------------------------------------------------------------------
#  Helpers
# ---------------------------------------------------------------------------
if [[ -n $EPOCHREALTIME ]]; then
  now_ms() { local t=${EPOCHREALTIME/[.,]/}; NOW=$(( 10#$t / 1000 )); }
else
  now_ms() { NOW=$(date +%s%3N); }
fi

# deterministic LCG, identical on every machine/bash version (dungeon layouts)
lcg() { DRNG=$(( (DRNG * 1103515245 + 12345) & 0x7fffffff )); R=$(( (DRNG >> 8) % $1 )); }

isqrt() {
  local n=$1 x y
  if (( n < 2 )); then R=$n; return; fi
  x=$n; y=$(( (x + 1) / 2 ))
  while (( y < x )); do x=$y; y=$(( (x + n / x) / 2 )); done
  R=$x
}

clean_text() { local t=${1//[[:cntrl:]]/}; t=${t//'|'/'/'}; CLEAN=${t:0:200}; }

isnum() { [[ ${#1} -le 9 && $1 == @(0|[1-9]*([0-9])) ]]; }   # no leading zeros: '08' would crash bash arithmetic
# (a glob, not a regex: bash compiles a regex on every call - this runs for every number of every network line, 9x faster)

cheb() { local a=$(( $1 < 0 ? -$1 : $1 )) b=$(( $2 < 0 ? -$2 : $2 )); D=$(( a > b ? a : b )); }

# --- gear: 5 slots, lots of kinds, and every class may only use some of them ----------
# code = slot.kind.tier.rarity   slot: W weapon, A body armor, O offhand, H helm, J trinket
# per kind: name, sprite, classes that may use it (digits), main stat %, bonus type + base value
WK_NAME=(Sword Axe Hammer Mace Spear Dagger Bow Boomerang Wand Staff Orb Tome "Holy Symbol" Scythe "Skull Totem"
         Lute Violin "War Drum" Trumpet "Bomb Satchel")
WK_E=("🗡 " 🪓 🔨 🏏 🔱 🔪 🏹 🪃 🪄 🦯 🔮 📕 📿 🌙 💀 🪕 🎻 🥁 🎺 💣)
WK_CLS=(0457 05 053 034 025 4271 2 24 163 136 1 136 35 6 6 7 7 70 7 4)
WK_DMG=(100 108 105 98 102 90 105 98 100 104 112 96 95 110 100 100 105 98 102 115)
WK_BT=(crit crit hp arm crit crit crit crit mp mp dmg mp hp crit mp mp crit hp mp dmg)
WK_BV=(3 4 6 3 3 8 5 6 10 14 6 18 8 4 12 10 4 6 8 8)
AK_NAME=(Robe Jerkin Mail Plate)
AK_E=(👘 🧥 🦺 🦾)
AK_CLS=(1367 2347 0235 05)  AK_MUL=(60 80 100 125)  AK_BT=(mp crit hp hp)  AK_BV=(10 3 5 10)
OK_NAME=(Shield Spellbook Quiver Lantern "Smoke Bombs" Songbook Fetish)
OK_E=("🛡 " 📖 🎯 🏮 💨 🎼 🦴)
OK_CLS=(035 136 2 01234567 4 7 6)  OK_MUL=(100 0 0 0 0 0 0)  OK_BT=(hp mp crit light crit mp dmg)  OK_BV=(5 12 6 2 6 12 8)
HK_NAME=(Cap Hat Helmet Circlet Mask)
HK_E=(🧢 🎩 🪖 👑 🎭)
HK_CLS=(2347 167 025 357 47)  HK_MUL=(60 40 100 50 50)  HK_BT=(crit mp hp mp crit)  HK_BV=(3 10 5 8 5)
JK_NAME=(Ring Amulet Medallion Charm)
JK_E=(💍 🧿 🏅 🔔)
JK_CLS=(01234567 01234567 01234567 01234567)  JK_BT=(crit hp arm mp)  JK_BV=(4 8 6 10)
declare -A SLOT_LABEL=([W]=Weapon [A]=Armor [O]=Offhand [H]=Helm [J]=Trinket)
# what every class starts with / finds most often (weapon, alt weapon, armor, helm, offhand)
DEFW=(0 9 6 3 5 2 13 15) ALTW=(1 8 7 12 19 0 14 16) DEFA=(2 0 1 2 1 3 0 1) DEFH=(2 1 0 3 4 2 1 3) DEFO=(0 1 2 0 4 0 6 5)
TIER_Q=("" Worn Sturdy Fine Mithril Runic Dragon Celestial)
MAXTIER=12 MAXLVL=40
tier_for() {  # level -> TF: the gear tier of that level (1 + level/3 up to 9 at 24; 10-12 for 30-40, v4.0)
  TF=$(( 1 + $1 / 3 ))
  if (( TF > 9 )); then TF=9; (( $1 >= 30 )) && TF=$(( 9 + ($1 - 26) / 4 )); fi
  (( TF > MAXTIER )) && TF=$MAXTIER
}
# v1.8: bags - code B.<kind>; worn in one of 3 bag slots on top of the starter backpack (10)
BAG_NAME=("Small Pouch" "Leather Satchel" "Traveler's Backpack" "Merchant's Case" "Explorer's Trunk" "Bag of Holding")
BAG_E=(👝 👜 🎒 💼 🧳 🌌) BAG_M=(🧵 🧵 🧶 🧶 🐉 🌠)
BAG_SZ=(4 6 8 10 12 16) BAG_RR=(0 0 1 1 2 3) BAG_PRICE=(150 400 900 1800 4000 12000)
BAG_FL=("Room for a few coins and a snack." "Sturdy leather that smells of the tannery." "Every traveler's best friend."
        "Lined with velvet and secret pockets." "Survived three shipwrecks and a dragon." "Bigger on the inside. Don't climb in.")

slot_kinds() {  # slot -> KCLS (classes per kind) KCNT
  case $1 in
    W) KCLS=("${WK_CLS[@]}") ;; A) KCLS=("${AK_CLS[@]}") ;; O) KCLS=("${OK_CLS[@]}") ;;
    H) KCLS=("${HK_CLS[@]}") ;; J) KCLS=("${JK_CLS[@]}") ;; *) KCLS=() ;;
  esac
  KCNT=${#KCLS[@]}
}

valid_item() {  # code -> 0 if it is well-formed gear (or a bag, a unique, a collectable)
  [[ $1 =~ ^B\.[0-5]$ ]] && return 0
  [[ $1 =~ ^C\.(0|[1-9][0-9]{0,2})$ ]] && { (( BASH_REMATCH[1] < NCOL )); return; }    # v5.0: collectables
  [[ $1 =~ ^U\.(0|[1-9][0-9]?)$ ]] && { (( BASH_REMATCH[1] < NUQ )); return; }
  [[ $1 =~ ^([WAOHJ])\.(0|[1-9][0-9]?)\.([1-9]|1[0-2])\.([0-3])(\.(__|[rseato][1-4]){1,3})?$ ]] || return 1   # v3.0: sockets, v4.0: tiers 10-12, v4.5: perfect gems
  local k=${BASH_REMATCH[2]}
  slot_kinds "${BASH_REMATCH[1]}"; (( k < KCNT ))
}

kind_pick() {  # slot [class] -> KP: mostly something this class can use, sometimes anything
  local i ok=()
  slot_kinds "$1"
  if [[ -n $2 ]] && (( RANDOM % 100 < 60 )); then
    for i in "${!KCLS[@]}"; do [[ ${KCLS[i]} == *"$2"* ]] && ok+=("$i"); done
  fi
  if (( ${#ok[@]} )); then KP=${ok[RANDOM % ${#ok[@]}]}; else KP=$(( RANDOM % KCNT )); fi
}

IS_LAST=""
item_stats() {  # code -> IK IKD IT IRR IVAL (dmg/armor) IBT IBV (bonus) ICLS IKN IKE ISELL
  [[ -n $1 && $1 == "$IS_LAST" ]] && return                                  # item_name + item_icon ask twice in a row
  IS_LAST=$1
  local IFS=. p m
  p=(${1%!})                                                         # "!" = locked (v1.7)
  IK=${p[0]} IKD=${p[1]:-0} IT=${p[2]:-1} IRR=${p[3]:-0} IUQ=""
  if [[ $IK == B ]]; then                                            # bags (v1.8)
    IT=1 IRR=${BAG_RR[IKD]:-0} IVAL=${BAG_SZ[IKD]:-4} IBT="" IBV=0 ICLS=0123456789
    IKN=${BAG_NAME[IKD]} IKE=${BAG_E[IKD]} ISELL=$(( ${BAG_PRICE[IKD]:-100} / 4 ))
    return
  fi
  if [[ $IK == C ]]; then                                            # collectables (v5.0): nothing to wear, all to show
    IT=1 IRR=${CL_RR[IKD]:-0} IVAL=0 IBT="" IBV=0 ICLS=0123456789
    IKN=${CL_NAME[IKD]} IKE=${CL_E[IKD]} ISELL=${CL_VAL[IKD]:-50}
    return
  fi
  if [[ $IK == U ]]; then                                            # uniques (v2.0): fixed name, legendary+ stats
    IUQ=${p[1]:-0}; IK=${U_SLOT[IUQ]:-J} IKD=${U_KIND[IUQ]:-0} IT=${U_TIER[IUQ]:-1} IRR=4
  elif (( ${#p[@]} == 3 )); then IKD=0 IT=${p[1]} IRR=${p[2]}; fi     # pre-1.6 code
  m=${RAR_MUL[IRR]:-100}
  case $IK in
    W) IKN=${WK_NAME[IKD]} IKE=${WK_E[IKD]} ICLS=${WK_CLS[IKD]} IBT=${WK_BT[IKD]} IBV=${WK_BV[IKD]}
       IVAL=$(( (IT * 6 + 2) * m / 100 * WK_DMG[IKD] / 100 )) ;;
    A) IKN=${AK_NAME[IKD]} IKE=${AK_E[IKD]} ICLS=${AK_CLS[IKD]} IBT=${AK_BT[IKD]} IBV=${AK_BV[IKD]}
       IVAL=$(( (IT * 3 + 1) * m * AK_MUL[IKD] / 10000 )) ;;
    O) IKN=${OK_NAME[IKD]} IKE=${OK_E[IKD]} ICLS=${OK_CLS[IKD]} IBT=${OK_BT[IKD]} IBV=${OK_BV[IKD]}
       IVAL=$(( (IT * 2 + 1) * m * OK_MUL[IKD] / 10000 )) ;;
    H) IKN=${HK_NAME[IKD]} IKE=${HK_E[IKD]} ICLS=${HK_CLS[IKD]} IBT=${HK_BT[IKD]} IBV=${HK_BV[IKD]}
       IVAL=$(( (IT * 2 + 1) * m * HK_MUL[IKD] / 10000 )) ;;
    *) IKN=${JK_NAME[IKD]} IKE=${JK_E[IKD]} ICLS=${JK_CLS[IKD]} IBT=${JK_BT[IKD]} IBV=${JK_BV[IKD]} IVAL=0 ;;
  esac
  if [[ -n $IUQ ]]; then IBT=${U_BT[IUQ]}; IBV=${JK_BV[0]}
    case $IBT in crit) IBV=5 ;; hp) IBV=8 ;; mp) IBV=12 ;; arm) IBV=7 ;; dmg) IBV=7 ;; esac
    IKN=${U_NAME[IUQ]}
  fi
  if [[ $IBT == light ]]; then IBV=$(( 1 + IT / 3 + IRR / 2 ))
  else IBV=$(( IBV * (IT + 2) * m / 500 )); (( IBV < 1 )) && IBV=1; fi
  ISELL=$(( IT * IT * 8 * m / 100 )); [[ $IK == [OHJ] ]] && ISELL=$(( ISELL * 7 / 10 + 2 ))
  if [[ -n ${p[4]} ]]; then                                          # v3.0: gems in the sockets are worth something
    local g=${p[4]} i
    for (( i = 0; i < ${#g}; i += 2 )); do [[ ${g:i:1} == _ ]] || ISELL=$(( ISELL + 25 * ((${g:i+1:1} - 1) * (${g:i+1:1} - 1) * 4 + 1) )); done
  fi
}

item_name() {  # code cls -> INAME (plain) ICOL
  item_stats "$1"
  INAME="${TIER_Q[IT]} $IKN" INSHORT="${TIER_Q[IT]} $IKN"
  (( IRR > 0 )) && INAME="${RAR_NAME[IRR]} $INAME"
  [[ $IK == [BC] || -n $IUQ ]] && INAME=$IKN INSHORT=$IKN
  ICOL=${RAR_COL[IRR]}
}

bonus_txt() {  # after item_stats -> BTX
  case $IBT in
    crit) BTX="+$IBV% crit" ;; hp) BTX="+$IBV% HP" ;; mp) BTX="+$IBV% MP" ;;
    arm) BTX="+$IBV armor" ;; dmg) BTX="+$IBV% dmg" ;; light) BTX="+$IBV light" ;; *) BTX="" ;;
  esac
}

can_use() { item_stats "$1"; [[ $ICLS == *"$2"* ]]; }    # code cls

cls_list() {  # ICLS -> CLT "Warrior/Paladin" (short names)
  local i c=$1 o=""
  for (( i = 0; i < ${#c}; i++ )); do o+="${C_NAME[${c:i:1}]:0:4}/"; done
  CLT=${o%/}
  (( ${#c} >= NCLS )) && CLT="everyone"
}

# ---------------------------------------------------------------------------
#  Maps: rows live in MAPROW["<map>:<y>"]; "W" is the open world
# ---------------------------------------------------------------------------
declare -A MAPROW=() MAPW=() MAPH=()

tile() {  # map x y -> T (off the map counts as mountains; a negative x would wrap around)
  [[ $2 == -* ]] && { T='^'; return; }
  T=${MAPROW[$1:$3]:$2:1}; [[ -n $T ]] || T='^'
}
# walkable for players / for monsters
p_walk() { tile "$@"; [[ $T == [.,\":=_*%\<\>SsNnIAKJDEqMHB] ]]; }
m_walk() { tile "$@"; [[ $T == [.,\":=_*%SsNnIAKJDEqMHB] ]]; }
blocks_shot() { tile "$@"; [[ $T == [\#T^QOFYPRZCWVyUX] ]]; }

in_safe_xy() {  # x y -> 0 inside a safe zone of the open world
  local i n
  if (( ${#SAFE_A[@]} != ${#SAFE_RECTS[@]} * 4 )); then SAFE_A=(${SAFE_RECTS[*]}); fi   # flat copy, built once
  n=${#SAFE_A[@]}
  for (( i = 0; i < n; i += 4 )); do
    (( $1 >= SAFE_A[i] && $1 <= SAFE_A[i+2] && $2 >= SAFE_A[i+1] && $2 <= SAFE_A[i+3] )) && return 0
  done
  return 1
}

name_color() {  # name -> NCI (stable default color index per name)
  local h=7 i c
  for (( i = 0; i < ${#1}; i++ )); do printf -v c '%d' "'${1:i:1}"; h=$(( (h * 31 + c) % 10007 )); done
  NCI=$(( h % ${#P_COLC[@]} ))
}

gen_dungeon() {  # map dtype seed -> rows + DG_SX DG_SY DG_BX DG_BY DG_ROOMS
  local map=$1 W=${D_W[$2]:-64} H=${D_H[$2]:-26} i x y w h ok r n=0 full wall floor row a x1 y1 x2 y2 t want=${D_ROOMS[$2]:-9}
  DRNG=$3
  printf -v full '%*s' "$W" ''; wall=${full// /#}; floor=${full// /_}
  for (( y = 0; y < H; y++ )); do MAPROW["$map:$y"]=$wall; done
  MAPW[$map]=$W MAPH[$map]=$H
  DG_ROOMS=()
  for (( i = 0; i < 240 && n < want; i++ )); do
    lcg 9; w=$(( 6 + R )); lcg 5; h=$(( 4 + R ))
    lcg $(( W - w - 2 )); x=$(( 1 + R )); lcg $(( H - h - 2 )); y=$(( 1 + R ))
    ok=1
    for r in "${DG_ROOMS[@]}"; do
      a=($r)
      if (( x < a[0] + a[2] + 2 && x + w + 2 > a[0] && y < a[1] + a[3] + 2 && y + h + 2 > a[1] )); then ok=0; break; fi
    done
    (( ok )) && { DG_ROOMS+=("$x $y $w $h"); n=$(( n + 1 )); }
  done
  for (( i = 1; i < n; i++ )); do          # sort rooms left -> right
    t=${DG_ROOMS[i]}; a=($t); x=$i
    while (( x > 0 )); do
      r=(${DG_ROOMS[x-1]}); (( r[0] > a[0] )) || break
      DG_ROOMS[x]=${DG_ROOMS[x-1]}; x=$(( x - 1 ))
    done
    DG_ROOMS[x]=$t
  done
  for r in "${DG_ROOMS[@]}"; do
    a=($r)
    for (( y = a[1]; y < a[1] + a[3]; y++ )); do
      row=${MAPROW[$map:$y]}; MAPROW["$map:$y"]="${row:0:a[0]}${floor:0:a[2]}${row:a[0]+a[2]}"
    done
  done
  for (( i = 1; i < n; i++ )); do          # corridors between neighbours
    a=(${DG_ROOMS[i-1]}); r=(${DG_ROOMS[i]})
    x1=$(( a[0] + a[2] / 2 )) y1=$(( a[1] + a[3] / 2 )) x2=$(( r[0] + r[2] / 2 )) y2=$(( r[1] + r[3] / 2 ))
    (( x1 > x2 )) && { t=$x1; x1=$x2; x2=$t; t=$y1; y1=$y2; y2=$t; }
    row=${MAPROW[$map:$y1]}; MAPROW["$map:$y1"]="${row:0:x1}${floor:0:x2-x1+1}${row:x2+1}"
    if (( y1 > y2 )); then t=$y1; y1=$y2; y2=$t; fi
    for (( y = y1; y <= y2; y++ )); do
      row=${MAPROW[$map:$y]}; MAPROW["$map:$y"]="${row:0:x2}_${row:x2+1}"
    done
  done
  local r0 r1 r2 seg out                   # solid rock away from rooms becomes void
  for (( y = 0; y < H; y++ )); do
    r0=${MAPROW[$map:$(( y - 1 ))]:-$wall} r1=${MAPROW[$map:$y]} r2=${MAPROW[$map:$(( y + 1 ))]:-$wall} out=""
    r0="#$r0#" r1="#$r1#" r2="#$r2#"
    for (( x = 0; x < W; x++ )); do
      if [[ ${r1:x+1:1} == '#' ]]; then
        seg="${r0:x:3}${r1:x:3}${r2:x:3}"
        if [[ $seg == *_* ]]; then out+='#'; else out+=' '; fi
      else out+=${r1:x+1:1}; fi
    done
    NEWROW[y]=$out
  done
  for (( y = 0; y < H; y++ )); do MAPROW["$map:$y"]=${NEWROW[y]}; done
  a=(${DG_ROOMS[0]})
  x=$(( a[0] + 1 )) y=$(( a[1] + a[3] / 2 ))
  row=${MAPROW[$map:$y]}; MAPROW["$map:$y"]="${row:0:x}<${row:x+1}"
  DG_SX=$(( x + 1 )) DG_SY=$y
  a=(${DG_ROOMS[n-1]})
  DG_BX=$(( a[0] + a[2] / 2 )) DG_BY=$(( a[1] + a[3] / 2 ))
}

load_world() {
  local y=0 line
  while IFS= read -r line; do MAPROW["W:$y"]=$line; y=$(( y + 1 )); done < <(world_data)
  MAPW[W]=${#MAPROW[W:0]} MAPH[W]=$y
}

region_of() {  # x y [nosafe] -> RNAME RLVL
  local r a
  for r in "${REGIONS[@]}"; do
    a=($r)
    [[ $3 == nosafe && ${a[5]} == safe ]] && continue
    if (( $1 >= a[0] && $1 <= a[2] && $2 >= a[1] && $2 <= a[3] )); then RNAME=${a[4]//_/ } RLVL=${a[5]}; return; fi
  done
}

# ---------------------------------------------------------------------------
#  Module 01b - content (since v2.0): the five new lands of the 360x150 world,
#  their creatures, NPCs, dungeons, unique legendaries, allies and the story of
#  the Shattered Crown. Pure data: the tables of 01_core.sh grow here.
#  See docs/MODDING.md for how to add things.
# ---------------------------------------------------------------------------
# --- creatures of the new lands (76-95) -------------------------------------------------
#        Sapphire Isles 20-23            Crystal Highlands 21-24            Emerald Jungle 22-25
M_NAME+=("Reef Lobster" "Cutthroat Pirate" "Giant Octopus" "Dragon Turtle"  "Highland Ram" "Crystal Mantis" "Shard Golem" "Gem Basilisk"
         "Poison Frog" "Jungle Panther" "Mosquito Swarm" "Jungle Tiger"   "Canyon Vulture" "Rampaging Bison" "Fire Giant" "Obsidian Scorpion"
         "Void Stalker" "Nightmare Bat" "Hollow Knight" "Abyssal Eye")
M_GLY+=(l p o t  r m G b  f P q T  v B F s  V n K e)
M_COL+=("38;5;203" "38;5;209" "38;5;170" "1;38;5;72"  "38;5;254" "1;38;5;141" "1;38;5;147" "1;38;5;183"
        "1;38;5;118" "38;5;214" "38;5;144" "1;38;5;208"  "38;5;137" "38;5;130" "1;38;5;196;48;5;52" "1;38;5;99;48;5;52"
        "1;38;5;99" "38;5;97" "1;38;5;189;48;5;53" "1;38;5;201")
M_LVL+=(20 21 22 23  21 22 23 24  22 23 23 25  24 25 26 26  27 28 29 30)
M_HP+=(820 760 980 1400  780 820 1300 1100  700 900 600 1150  900 1500 1700 1250  1300 1150 1900 1600)
M_DMG+=(64 72 70 78  70 80 82 86  76 86 70 94  88 92 104 100  108 106 116 124)
M_XP+=(540 600 680 820  600 680 800 880  640 760 700 950  860 980 1100 1050  1180 1200 1400 1500)
M_GOLD+=(70 110 80 95  70 85 100 110  75 90 60 120  100 110 140 130  150 140 180 190)
M_AGGRO+=(4 7 6 5  5 7 5 7  6 8 8 8  8 5 6 7  9 9 7 9)
M_MOVE+=(700 460 650 900  420 380 850 500  400 340 300 360  330 450 750 420  380 300 600 700)
M_ATK+=(1300 1000 1200 1500  1100 1000 1600 1200  1000 950 800 1000  1000 1400 1600 1000  1000 900 1300 1100)
M_BOSS+=(0 0 0 0  0 0 0 0  0 0 0 0  0 0 0 0  0 0 0 0)  M_KIND+=(0 0 0 0  0 0 0 0  0 0 0 0  0 0 0 0  0 0 0 0)
# --- dungeon creatures (96-114): elites (M_BOSS 2) for every dungeon, the new dungeon pools and bosses ---
M_NAME+=("Bone Lord" "Goblin Shaman" "Drake Matriarch" "Anubis Sentinel" "Frost Witch" "Pit Fiend"
         "Tidecaller Siren" "Ishara the Leviathan Queen" "Prism Warden" "The Crystal Archon" "Temple Monkey"
         "Serpent Priest" "Quetzal the Jade Serpent" "Forge Imp" "Forgemaster Brann" "Ignis the Molten King"
         "Void Horror" "Void Herald" "The Hollow King")
M_GLY+=(L S M A W P  S I W A k  S Q i F I  h H K)
M_COL+=("1;38;5;255;48;5;238" "1;38;5;76;48;5;58" "1;38;5;202;48;5;52" "1;38;5;220;48;5;136" "1;38;5;159;48;5;31" "1;38;5;196;48;5;52"
        "1;38;5;87;48;5;24" "1;38;5;231;48;5;24" "1;38;5;183;48;5;54" "1;38;5;231;48;5;54" "38;5;179"
        "1;38;5;118;48;5;28" "1;38;5;231;48;5;28" "1;38;5;202;48;5;52" "1;38;5;220;48;5;52" "1;38;5;231;48;5;52"
        "1;38;5;171;48;5;53" "1;38;5;201;48;5;53" "1;38;5;231;48;5;53")
M_LVL+=(6 9 14 15 18 21  23 24 25 26 24  26 27 25 27 28  30 31 32)
M_HP+=(420 700 1300 1500 1900 2600  3200 16000 3800 19000 900  4200 22000 950 4800 25000  2000 6000 34000)
M_DMG+=(18 26 40 46 58 78  86 96 92 104 84  100 112 96 110 122  120 128 138)
M_XP+=(300 520 1100 1300 1800 2600  3200 18000 3800 21000 860  4300 24000 940 4800 27000  1550 6000 40000)
M_GOLD+=(90 160 300 350 450 600  700 4500 800 5000 90  900 5500 110 1000 6000  200 1300 10000)
M_AGGRO+=(8 8 9 9 9 9  9 10 9 10 7  9 10 8 9 10  8 10 10)
M_MOVE+=(600 520 450 500 550 450  500 650 600 700 380  480 550 400 600 600  650 450 600)
M_ATK+=(1200 1200 1100 1100 1200 1000  1100 1300 1300 1400 1000  1100 1200 1000 1300 1300  1200 1100 1200)
M_BOSS+=(2 2 2 2 2 2  2 1 2 1 0  2 1 0 2 1  0 2 1)  M_KIND+=(0 0 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0)
# --- treasure chest (115): kind 4 - never moves, one blow opens it -----------------------------------
CHEST=${#M_NAME[@]}
M_NAME+=("Treasure Chest") M_GLY+=('=') M_COL+=("1;38;5;220;48;5;94") M_LVL+=(1) M_HP+=(1) M_DMG+=(0) M_XP+=(0) M_GOLD+=(0)
M_AGGRO+=(0) M_MOVE+=(900) M_ATK+=(1000) M_BOSS+=(0) M_KIND+=(4)
# --- world bosses of the new lands (116-120) ------------------------------------------------------
WB1=${#M_NAME[@]}
M_NAME+=("The Kraken" "Glacius the Crystal Drake" "Titanback" "Thunder Roc" "The Void Leviathan")
M_GLY+=(K D E R V)
M_COL+=("1;38;5;231;48;5;24" "1;38;5;16;48;5;141" "1;38;5;231;48;5;22" "1;38;5;16;48;5;179" "1;38;5;231;48;5;53")
M_LVL+=(24 25 26 27 30)  M_HP+=(18000 20000 23000 24000 30000)  M_DMG+=(88 94 100 108 124)
M_XP+=(18000 20000 23000 25000 32000)  M_GOLD+=(4500 5000 5500 6000 8000)
M_AGGRO+=(9 9 10 10 10)  M_MOVE+=(700 600 800 450 650)  M_ATK+=(1300 1300 1500 1100 1300)
M_BOSS+=(1 1 1 1 1)  M_KIND+=(0 0 0 0 0)
# --- people of the new towns (121-144) ---------------------------------------------------------------
NPC1=${#M_NAME[@]}
M_NAME+=("Varga"  "Isolde" "Barnaby" "Rosa" "Pearl"  "Quill" "Tova" "Kesh" "Quartz" "Ilse"
         "Mo'ana" "Zuri" "Tavi" "Jade"  "Dusk" "Ruth" "Joe" "Copper" "Kate"  "Seraphine" "Halvard" "Lysa" "Ember" "Lamplighter")
M_GLY+=(V  I B R '$'  Q T K '$' I  M Z T '$'  D R J '$' K  S H L '$' L)
M_COL+=("1;38;5;214;$NPCBG"  "1;38;5;51;$NPCBG" "1;38;5;180;$NPCBG" "1;38;5;205;$NPCBG" "1;38;5;220;$NPCBG"
        "1;38;5;141;$NPCBG" "1;38;5;250;$NPCBG" "1;38;5;120;$NPCBG" "1;38;5;220;$NPCBG" "1;38;5;223;$NPCBG"
        "1;38;5;118;$NPCBG" "1;38;5;154;$NPCBG" "1;38;5;229;$NPCBG" "1;38;5;220;$NPCBG"
        "1;38;5;179;$NPCBG" "1;38;5;209;$NPCBG" "1;38;5;250;$NPCBG" "1;38;5;220;$NPCBG" "1;38;5;217;$NPCBG"
        "1;38;5;231;$NPCBG" "1;38;5;153;$NPCBG" "1;38;5;196;$NPCBG" "1;38;5;220;$NPCBG" "1;38;5;228;$NPCBG")
M_LVL+=(16  22 18 16 22  23 20 22 23 18  24 20 18 24  25 22 22 25 20  30 26 28 30 24)
M_HP+=(900  1400 900 800 1200  1400 1000 1300 1200 900  1500 1000 900 1300  1600 1200 1200 1300 1000  2400 1600 2000 1800 1200)
M_DMG+=(40  80 60 50 70  80 70 80 70 55  85 65 55 75  90 75 80 80 65  120 95 110 100 80)
M_XP+=(100  200 150 120 200  200 150 200 200 150  220 160 150 220  240 180 180 240 160  300 240 260 300 200)
M_GOLD+=(300  500 350 300 800  500 400 400 800 300  550 400 300 800  600 450 400 800 350  800 500 600 900 400)
M_AGGRO+=(0  0 0 0 0  0 0 0 0 0  0 0 0 0  0 0 0 0 0  0 0 0 0 0)
M_MOVE+=(900  900 900 900 900  900 900 900 900 900  900 900 900 900  900 900 900 900 900  900 900 900 900 900)
M_ATK+=(1100  1000 1100 1200 1100  1000 1100 1000 1100 1200  1000 1100 1200 1100  1000 1100 1100 1100 1200  900 1000 1000 1000 1100)
M_BOSS+=(0  0 0 0 0  0 0 0 0 0  0 0 0 0  0 0 0 0 0  0 0 0 0 0)
M_KIND+=(1  1 1 1 1  1 1 1 1 1  1 1 1 1  1 1 1 1 1  1 1 1 1 1)
NM=${#M_NAME[@]}

WORLD_TYPES+=(76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91 92 93 94 95)
UNDEAD+="94 96 112 113 114 "
WB_LIST+=($WB1 $(( WB1 + 1 )) $(( WB1 + 2 )) $(( WB1 + 3 )) $(( WB1 + 4 )))
WB_RECT+=("5 100 115 148" "242 2 357 48" "242 52 357 98" "122 101 236 147" "243 102 357 147")
WB_ADDS+=("76 77 77" "81 81 82" "85 85 87" "88 89 89" "92 93 93")

# --- the new lands -------------------------------------------------------------------------------
ZONES+=("76 5 100 115 148 8" "77 5 100 115 148 7" "78 5 100 115 148 6" "79 5 100 115 148 4"
        "80 242 2 357 48 8" "81 242 2 357 48 7" "82 242 2 357 48 6" "83 242 2 357 48 5"
        "84 242 52 357 98 8" "85 242 52 357 98 7" "86 242 52 357 98 7" "87 242 52 357 98 5"
        "88 122 101 236 147 7" "89 122 101 236 147 7" "90 122 101 236 147 5" "91 122 101 236 147 6"
        "92 243 102 357 147 7" "93 243 102 357 147 7" "94 243 102 357 147 5" "95 243 102 357 147 4")
n=$NODE0
ZONES+=("$(( n + 4 )) 242 2 357 48 5" "$(( n + 10 )) 242 2 357 48 4" "$(( n + 5 )) 122 101 236 147 5" "$(( n + 11 )) 122 101 236 147 4"
        "$(( n + 5 )) 243 102 357 147 4" "$(( n + 8 )) 242 52 357 98 5" "$(( n + 9 )) 242 52 357 98 3" "$(( n + 7 )) 5 100 115 148 4"
        "$(( n + 4 )) 5 100 115 148 3")
SAFE_RECTS+=("46 113 70 128" "280 14 304 30" "288 64 310 80" "166 108 188 124" "266 106 290 120")
REGIONS+=("48 115 68 126 Port_Coral safe" "282 16 302 28 Shardhaven safe" "290 66 308 78 Jadeleaf_Village safe"
          "168 110 186 122 Redrock_Outpost safe" "268 108 288 118 Last_Light_Bastion safe"
          "0 100 119 149 Sapphire_Isles 20-23" "240 0 359 49 Crystal_Highlands 21-24" "240 50 359 99 Emerald_Jungle 22-25"
          "120 100 239 149 Scorched_Badlands 24-26" "240 100 359 149 Void_Rift 27-30")
WAYSTONES+=("Port_Coral 51 117" "Shardhaven 285 18" "Jadeleaf_Village 293 68" "Redrock_Outpost 171 112" "Last_Light_Bastion 271 110")
WEA_REG+=(Sapphire_Isles Crystal_Highlands Emerald_Jungle Scorched_Badlands Void_Rift)
WEA_KIND+=("rain storm" "snow fog" "rain fog" "sand ash" "ash fog")
WATER_OF+=([Sapphire_Isles]=sea [Crystal_Highlands]=ice [Emerald_Jungle]=swamp [Scorched_Badlands]=lava [Void_Rift]=lava)

# --- dungeons 6-10 and the bigger layout of every dungeon -------------------------------------------
D_NAME+=("Coral Grotto" "Crystal Depths" "Temple of the Jade Serpent" "Obsidian Forge" "Throne of the Void")
D_REQ+=(20 22 23 24 28)
D_POOL+=("76 78 45 79" "81 82 83 81" "85 86 84 106" "90 91 109 41" "94 95 92 112")
D_BOSS+=(103 105 108 111 114)
D_ENTX+=(22 342 346 226 340)  D_ENTY+=(140 10 92 142 140)
D_WHERE+=("Sapphire Isles, south-west island" "Crystal Highlands, far north-east" "Emerald Jungle, far east"
          "Scorched Badlands, south-east" "Void Rift, far south-east")
D_WALL+=("38;5;37" "38;5;141" "38;5;71" "38;5;166" "38;5;93")
D_FLOOR+=("38;5;23" "38;5;60" "38;5;22" "38;5;52" "38;5;54")
NDT=${#D_NAME[@]}
D_ELITE=(96 97 98 99 100 101 102 104 107 110 113)
D_W=(72 72 76 76 80 84 90 92 96 100 112)  D_H=(28 28 30 30 30 32 34 34 36 36 40)
D_ROOMS=(10 10 11 11 12 12 13 13 14 14 16) D_CHESTS=(2 2 2 2 3 3 3 3 3 3 4)

# --- the people of the new towns ------------------------------------------------------------------
N_ROLE+=([$NPC1]=merc [$(( NPC1 + 1 ))]=questgiver [$(( NPC1 + 2 ))]=general [$(( NPC1 + 3 ))]=inn [$(( NPC1 + 4 ))]=bank
         [$(( NPC1 + 5 ))]=questgiver [$(( NPC1 + 6 ))]=smith [$(( NPC1 + 7 ))]=merc [$(( NPC1 + 8 ))]=bank [$(( NPC1 + 9 ))]=inn
         [$(( NPC1 + 10 ))]=questgiver [$(( NPC1 + 11 ))]=alchemist [$(( NPC1 + 12 ))]=inn [$(( NPC1 + 13 ))]=bank
         [$(( NPC1 + 14 ))]=questgiver [$(( NPC1 + 15 ))]=trader [$(( NPC1 + 16 ))]=smith [$(( NPC1 + 17 ))]=bank [$(( NPC1 + 18 ))]=inn
         [$(( NPC1 + 19 ))]=questgiver [$(( NPC1 + 20 ))]=alchemist [$(( NPC1 + 21 ))]=merc [$(( NPC1 + 22 ))]=bank [$(( NPC1 + 23 ))]=inn)
N_FULL+=([$NPC1]="Captain Varga" [$(( NPC1 + 1 ))]="Admiral Isolde" [$(( NPC1 + 2 ))]="Barnaby the Boatman" [$(( NPC1 + 3 ))]="Rosa of the Rum House"
         [$(( NPC1 + 4 ))]="Pearl the Banker" [$(( NPC1 + 5 ))]="Loremaster Quill" [$(( NPC1 + 6 ))]="Tova the Gemcutter"
         [$(( NPC1 + 7 ))]="Kesh the Beastmaster" [$(( NPC1 + 8 ))]="Quartz the Banker" [$(( NPC1 + 9 ))]="Mother Ilse"
         [$(( NPC1 + 10 ))]="Sage Mo'ana" [$(( NPC1 + 11 ))]="Zuri the Herbalist" [$(( NPC1 + 12 ))]="Tavi of the Treehouse"
         [$(( NPC1 + 13 ))]="Jade the Banker" [$(( NPC1 + 14 ))]="Marshal Dusk" [$(( NPC1 + 15 ))]="Rattlesnake Ruth"
         [$(( NPC1 + 16 ))]="Anvil Joe" [$(( NPC1 + 17 ))]="Copper the Banker" [$(( NPC1 + 18 ))]="Cactus Kate"
         [$(( NPC1 + 19 ))]="Archmage Seraphine" [$(( NPC1 + 20 ))]="Brother Halvard" [$(( NPC1 + 21 ))]="Warden Lysa"
         [$(( NPC1 + 22 ))]="Ember the Banker" [$(( NPC1 + 23 ))]="The Lamplighter")
N_QK+=([$(( NPC1 + 1 ))]="76 77 78 79" [$(( NPC1 + 5 ))]="80 81 82 83" [$(( NPC1 + 10 ))]="84 85 86 87"
       [$(( NPC1 + 14 ))]="88 89 90 91" [$(( NPC1 + 19 ))]="92 93 94 95")
N_QD+=([$(( NPC1 + 1 ))]=6 [$(( NPC1 + 5 ))]=7 [$(( NPC1 + 10 ))]=8 [$(( NPC1 + 14 ))]=9 [$(( NPC1 + 19 ))]=10)
N_QT+=([$(( NPC1 + 1 ))]=$(( NPC1 + 5 )) [$(( NPC1 + 5 ))]=$(( NPC1 + 10 )) [$(( NPC1 + 10 ))]=$(( NPC1 + 14 ))
       [$(( NPC1 + 14 ))]=$(( NPC1 + 19 )) [$(( NPC1 + 19 ))]=$(( NPC1 + 1 )))
N_HOME+=([$NPC1]="Hearthmoor" [$(( NPC1 + 1 ))]="Port Coral" [$(( NPC1 + 5 ))]="Shardhaven" [$(( NPC1 + 10 ))]="Jadeleaf Village"
         [$(( NPC1 + 14 ))]="Redrock Outpost" [$(( NPC1 + 19 ))]="Last Light Bastion"
         [$BANK0]="Hearthmoor" [$(( BANK0 + 1 ))]="Ironwood Camp" [$(( BANK0 + 2 ))]="the Oasis of Kadar" [$(( BANK0 + 3 ))]="Frosthold"
         [$(( BANK0 + 4 ))]="Kael's Camp" [$(( NPC1 + 4 ))]="Port Coral" [$(( NPC1 + 8 ))]="Shardhaven" [$(( NPC1 + 13 ))]="Jadeleaf Village"
         [$(( NPC1 + 17 ))]="Redrock Outpost" [$(( NPC1 + 22 ))]="Last Light Bastion" [$(( NPC1 + 7 ))]="Shardhaven"
         [$(( NPC1 + 21 ))]="Last Light Bastion")
N_SAY+=([merc]="Swords for hire, bows for hire, everything for hire.|Nobody should walk the wilds alone. I have just the companion for you.|Pay once, and they follow you to the end of the world. Loyal folk, mine.")
NPC_SPAWNS+=("$NPC1 82 30 0"
             "$(( NPC1 + 1 )) 58 118 0" "$(( NPC1 + 2 )) 53 123 0" "$(( NPC1 + 3 )) 64 118 0" "$(( NPC1 + 4 )) 56 124 0" "19 57 116 1" "19 59 116 1"
             "$(( NPC1 + 5 )) 292 19 0" "$(( NPC1 + 6 )) 288 25 0" "$(( NPC1 + 7 )) 298 19 0" "$(( NPC1 + 8 )) 292 26 0" "$(( NPC1 + 9 )) 286 22 0"
             "19 291 17 1" "19 293 17 1"
             "$(( NPC1 + 10 )) 299 69 0" "$(( NPC1 + 11 )) 305 70 0" "$(( NPC1 + 12 )) 297 76 0" "$(( NPC1 + 13 )) 302 73 0" "19 298 67 1" "19 300 67 1"
             "$(( NPC1 + 14 )) 177 113 0" "$(( NPC1 + 15 )) 182 113 0" "$(( NPC1 + 16 )) 173 119 0" "$(( NPC1 + 17 )) 177 120 0"
             "$(( NPC1 + 18 )) 184 117 0" "19 176 111 1" "19 178 111 1"
             "$(( NPC1 + 19 )) 278 111 0" "$(( NPC1 + 20 )) 273 115 0" "$(( NPC1 + 21 )) 284 111 0" "$(( NPC1 + 22 )) 278 116 0"
             "$(( NPC1 + 23 )) 286 116 0" "19 277 109 1" "19 279 109 1")
RUMORS+=("Admiral Isolde of Port Coral says the sea went mad when the Void Rift opened. Take the long bridge south from the Saltwind Coast."
         "East of Frosthold, past the Ice Caverns road, the ground turns to crystal. Shardhaven sits up there."
         "The Emerald Jungle lies east of the Ashen Wastes. Mind the tigers - and the mosquitoes, which are worse."
         "South of the Sunscorch Desert the land burns red. Marshal Dusk keeps the peace at Redrock Outpost."
         "Last Light Bastion is the only fort left in the Void Rift. Do not go there before you are very, very strong."
         "Dungeons are bigger now: an elite guards the middle, and treasure chests hide in the side rooms."
         "Captain Varga in Hearthmoor hires out companions. Press [y] to call yours."
         "Some bosses carry unique weapons with their own names. Nobody else will ever have one quite like it."
         "Old Tom dreams of a broken crown. Ask him about it - every story starts somewhere.")

# --- items: two more tiers, five more weapon kinds, unique legendaries ------------------------------------
TIER_Q+=(Starforged Voidforged)
WK_NAME+=(Chakram Censer Grimoire Harp Morningstar)
WK_E+=(💿 🏺 📗 🎶 ⭐)
WK_CLS+=(427 35 16 73 053)  WK_DMG+=(100 96 102 98 104)  WK_BT+=(crit hp mp mp arm)  WK_BV+=(6 8 14 12 4)
RAR_NAME[4]=Unique RAR_COL[4]="1;38;5;208" RAR_MUL[4]=260
#    name                          slot kind tier bonus  flavor
U_NAME=("Orwin's Lucky Charm" "Whisperwind" "Dragonheart Plate" "Ring of the Pharaoh" "Rimefang" "Lute of Endless Spring"
        "Tidecaller" "Prism Crown" "Jadefang" "Heart of Ignis" "Crown of the First King" "Voidweave Robe"
        "Krakenhide Jerkin" "Glacius' Scale" "Titan's Maul" "Stormcaller Harp" "Leviathan's Eye" "Skull of the Lich"
        "Goblin King's Crown" "Mask of a Thousand Faces")
U_SLOT=(J W A J W W  W H W J H A  A O W W J W  H H)
U_KIND=(3 6 3 0 5 15  9 3 6 1 3 0  1 0 2 23 2 14  4 4)
U_TIER=(3 5 6 6 7 8  8 8 9 9 9 9  8 8 9 9 9 4  5 9)
U_BT=(crit crit hp crit crit mp  mp mp crit hp hp mp  crit hp dmg mp arm mp  crit crit)
U_FL=("Smells faintly of mushrooms and good luck." "The bow of a forest that never forgets." "Still beats, very slowly."
      "Anketh wore it for three thousand years." "Cold enough to bite." "Every song played on it makes flowers bloom."
      "The sea listens when it speaks." "Light from before the first dawn." "The last tooth of the Jade Serpent."
      "Burns without fire." "King Aldric's crown, whole again." "Woven from the dark between stars."
      "Tough, wet and slightly embarrassing." "A shield made from a dragon of ice." "Shakes the ground a little when you hold it."
      "Thunder answers its strings." "It looks back." "The Lich still mutters inside it."
      "A bit sticky. Very shiny." "Never the same face twice.")
NUQ=${#U_NAME[@]}
# bosses that sometimes drop a unique: "type:unique:chance%"
U_DROP=("65:1:20" "17:2:30" "34:3:30" "39:4:30" "44:5:30" "103:6:30" "105:7:30" "108:8:30" "111:9:30"
        "114:11:35" "116:12:25" "117:13:25" "118:14:25" "119:15:25" "120:16:25" "11:17:25" "14:18:25" "113:19:20")

# --- allies -------------------------------------------------------------------------------------
ALY_NAME=("Brutus the Sellsword" "Lyra the Huntress" "Brother Aldo" "Fang the Wolf" "Hootsworth the Owl"
          "Zephyr the Djinn" "Cinder the Whelp" "Bonejack")
ALY_SHORT=(Brutus Lyra Aldo Fang Hootsworth Zephyr Cinder Bonejack)
ALY_G=(B L A F H Z C J)
ALY_ROLE=(melee ranged heal melee ranged magic magic melee)
ALY_PCT=(70 55 25 45 50 45 60 60)  ALY_RNG=(1 6 4 1 7 5 4 1)  ALY_CD=(1100 1300 1500 700 1100 1600 1500 1000)
ALY_COST=(300 600 900 1500 2000 4000 0 0)
ALY_SELL=($NPC1 $NPC1 $NPC1 $(( NPC1 + 7 )) $(( NPC1 + 7 )) $(( NPC1 + 21 )) -1 -1)
ALY_DESC=("Hits hard up close and never complains." "Shoots arrows from six steps away." "Heals you whenever you get hurt."
          "Fast bites - a loyal friend." "Swoops at foes from far away." "Wind strikes your target and everything around it."
          "Breathes fire on your target and its neighbours." "Rattles in close. Never tires, never sleeps.")
NALY=${#ALY_NAME[@]}

# --- the story of the Shattered Crown ------------------------------------------------------------------
# objective: T.<npc> talk | D.<dungeon> clear | K.<type>.<n> slay; reward: "" | A.<ally> | U.<unique> | G.<slot>.<tier>
ST_TITLE=("A Stranger's Dream" "Steel for Hire" "The Restless Dead" "The Goblin Hoard" "Words of the Hermit" "Wings of Fire"
          "Sands of Kadar" "The Pharaoh's Curse" "North to Frosthold" "Heart of Ice" "The Exile's Oath" "Gate of Fire"
          "Beyond the Sea" "Song of the Deep" "The Shining Peaks" "Crystal Depths" "The Serpent's Coil" "Temple of the Jade Serpent"
          "The Molten King" "The Obsidian Forge" "Last Light" "Hollow Ranks" "Throne of the Void" "Home Again")
ST_LVL=(1 1 3 6 8 10  12 13 15 16 18 19  20 21 22 22 23 23  24 25 27 27 28 28)
ST_OBJ=("T.23" "T.$NPC1" "D.0" "D.1" "T.25" "D.2"  "T.46" "D.3" "T.49" "D.4" "T.52" "D.5"
        "T.$(( NPC1 + 1 ))" "D.6" "T.$(( NPC1 + 5 ))" "D.7" "T.$(( NPC1 + 10 ))" "D.8"
        "T.$(( NPC1 + 14 ))" "D.9" "T.$(( NPC1 + 19 ))" "K.94.12" "D.10" "T.23")
ST_XP=(50 80 400 800 600 2500  1500 4000 2500 6000 4000 12000  6000 16000 8000 18000 9000 20000  10000 24000 12000 20000 40000 10000)
ST_GOLD=(30 40 120 250 200 600  400 900 600 1200 800 2000  1000 2500 1200 2800 1300 3000  1500 3500 1600 3000 8000 5000)
ST_REW=("" A.0 A.7 G.A.3 U.0 G.W.4  "" G.A.5 "" G.W.6 "" A.6  "" G.W.8 "" G.A.8 "" G.J.9  "" G.W.9 "" "" U.10 "")
ST_TEXT=(
 "Every night the same dream: a golden crown breaking into five pieces, and a king with no face laughing in the dark. Old Tom at the inn of Hearthmoor waved you over this morning. Maybe he knows something."
 "Old Tom: 'Dreams of a broken crown? You are not the first. Captain Varga in the plaza hires folk for strange work. Tell her I sent you.'"
 "Varga: 'A dreamer. Good, I need one. The dead in the Forgotten Crypt, north-west in Whisperwood, will not stay buried - and something down there glows like gold. Bring it back.'"
 "Varga: 'One shard, and it hums? Then there are more. The goblins of the Warrens in Mirefen Swamp dug something up - their king wears it as a belt buckle.'"
 "Varga: 'Two shards. This is old magic. Orwin the hermit lives deep in Whisperwood, west of the crypt. He knows the old songs - show him what you found.'"
 "Orwin: 'The third shard sleeps under a dragon. The Ancient Dragon of the Stormcrag Peaks, north-east. Do not go alone.'"
 "Orwin: 'Captain Rahim of the Oasis of Kadar, far south past the meadows, has seen a shard's light in the desert at night. Go to him.'"
 "Rahim: 'The Sunken Tomb glows when the moon is up. Pharaoh Anketh took something to his grave that was never his.'"
 "Rahim: 'The last shard went north. Jarl Hrolf of Frosthold sent word of a blue light under the ice. Follow the road past the peaks.'"
 "Jarl Hrolf: 'The Frost Wyrm sleeps on it, deep in the Ice Caverns. My warriors will not go. Will you?'"
 "Jarl Hrolf: 'Five shards, but no setting to hold them. Only one man knows where it went: Ser Kael, who guards the Infernal Gate in the Ashen Wastes.'"
 "Ser Kael: 'Azgor the Demon Lord took the crown's setting through the Gate. He serves the Hollow King. I swore to stop him. Help me keep that oath.'"
 "Ser Kael: 'The crown is whole, but the Hollow King's power grows in the Void Rift. Admiral Isolde of Port Coral knows the way. Take the long bridge south from the Saltwind Coast.'"
 "Isolde: 'The sea went mad when the Rift opened. Ishara the Leviathan Queen drowns my ships from her Coral Grotto on the south-west island. Silence her.'"
 "Isolde: 'The crown needs light to burn the Void. Loremaster Quill of Shardhaven studies such things - in the Crystal Highlands, east of Frosthold past the Ice Caverns road.'"
 "Quill: 'The Crystal Archon hoards the oldest light in the world in the Crystal Depths, far to the north-east. The crown wants it. So do I, frankly.'"
 "Quill: 'Sage Mo'ana of Jadeleaf Village, south of here through the jungle, knows the Jade Serpent - the crown's last guardian.'"
 "Mo'ana: 'Quetzal coils in the Temple of the Jade Serpent, east of the village. It was a guardian once. Now the Void whispers to it.'"
 "Mo'ana: 'The Void needs fire to burn through our world. Marshal Dusk of Redrock Outpost, in the Scorched Badlands south of the desert, fights the Molten King.'"
 "Dusk: 'Ignis forges weapons for the Hollow King in the Obsidian Forge, south-east of here. Shut it down. Permanently.'"
 "Dusk: 'Last Light Bastion is the only fort left in the Void Rift, east of here. Archmage Seraphine leads it. Go - and take the crown.'"
 "Seraphine: 'You carry Aldric's crown! Then there is hope. But his Hollow Knights guard every path. Break their ranks - twelve of them should do.'"
 "Seraphine: 'The way is open. The Throne of the Void lies in the far south-east. End this, Crownbearer.'"
 "Seraphine: 'Go home, Crownbearer. Old Tom will want to hear this one.'")
ST_DONE=(
 "Old Tom wipes a mug. 'Dreams like that do not come for nothing, friend.'"
 "Varga laughs and whistles. A broad-shouldered man with a dented shield steps up: Brutus. 'He needs the exercise,' she says. Press [y] to call your allies."
 "Among the Lich's dust lies a shard of gold, warm to the touch - the First Shard. A rattling skeleton bows to you. It seems Bonejack has found a new master."
 "The Second Shard, still on the Goblin King's belt. It hums when you hold it next to the first."
 "Orwin turns the shards in his hands. 'The Crown of King Aldric. Shattered when the Hollow King rose, a thousand years ago.' He presses a little charm into your palm. 'For luck. You will need it.'"
 "Gold and bones everywhere, and in the middle of it: the Third Shard, still glowing from dragonfire."
 "Rahim listens, then nods slowly. 'So the old tales are true.'"
 "The Fourth Shard was set into Anketh's golden mask. It comes loose with a sigh."
 "Jarl Hrolf slams his fist on the table. 'Finally, someone with a spine!'"
 "The Fifth Shard. All five pieces fit together - but the golden setting that held them is missing."
 "Ser Kael grips the hilt of his sword. 'Then we go through the Gate together.'"
 "Azgor falls, and in his claw lies the crown's golden setting. The five shards click into place. Ser Kael whistles - a small red dragon lands on your shoulder. 'Cinder. He has waited long for a worthy hero.'"
 "Isolde studies the crown. 'Aldric's crown. I never thought I would see it.'"
 "Ishara's song fades. The waves calm, and the crown glows a little brighter."
 "Quill adjusts her spectacles. 'Oh my. Oh MY. May I touch it? No? Fair.'"
 "The Archon shatters into a thousand glittering pieces. One of them settles into the crown as if it always belonged there."
 "Mo'ana closes her eyes. 'The jungle remembers the crown. So does the serpent.'"
 "Quetzal's eyes clear before the end. 'Thank you,' it hisses, and turns to jade."
 "Dusk spits into the dust. 'About time someone came to help.'"
 "The forge fires die. In the slag lies a blade marked with the Hollow King's sigil. He is waiting for you."
 "Seraphine bows deeply. 'Crownbearer. We have waited a long time.'"
 "The Hollow ranks break. The Throne of the Void lies open."
 "The Hollow King's armor falls apart - empty, as it always was. The crown flares, and the Rift begins to close. You are the Crownbearer now."
 "Old Tom pours you the good stuff. 'No more dreams, eh? To the Crownbearer!' The whole inn cheers. THE END - for now.")
NST=${#ST_TITLE[@]}

# ---------------------------------------------------------------------------
#  Module 01c - v3.0 data: elements and resistances, monster abilities,
#  champion affixes, rare elites, gems, talents, factions, scouting spots and
#  the questlines of every town. Pure data (plus the classifier that gives
#  every creature its element and abilities). See docs/MODDING.md.
# ---------------------------------------------------------------------------

# --- elements ---------------------------------------------------------------------------------
#        0        1     2      3       4       5     6
EL_NAME=(physical fire frost poison shadow holy arcane)
EL_E=(🗡 🔥 ❄ ☠ 🌑 ✨ 🔮)
EL_COL=("38;5;250" "38;5;202" "38;5;117" "38;5;112" "38;5;141" "38;5;228" "38;5;213")
NEL=${#EL_NAME[@]}
# the element of every skill (Cleave ... Anthem)
S_EL=(0 0 0  1 2 6  0 0 0  5 5 5  0 3 4  5 5 5  4 4 3  6 6 6)

# --- rare elites: one roams every region, bounty boards want them -----------------------------
#          name                            base lvl  x   y   ability
RARES=("Grimfang the Elder Wolf:2:6:49:21"   "Gloop the Gigantic:1:4:41:54"       "Mother Rot:5:8:144:55"
       "Bloodknuckle the Bandit Lord:6:10:143:33" "Skarn the Stormwing:8:13:143:16" "Captain Barnacle:45:12:50:77"
       "Kharr the Sand King:29:16:134:92"    "Whitemaw:36:19:219:32"              "Cinderclaw:42:21:219:83"
       "Old Ironshell:79:24:89:134"          "The Glass Widow:81:25:329:35"       "Shadowstripe:87:26:330:87"
       "Thunderhoof:89:27:209:134"           "The Unblinking:95:31:329:134")
RARE0=${#M_NAME[@]}
declare -A RARE_BASE=()
RARE_T=()                                                    # every rare elite type (v4.0 adds more later on)
add_rares() {  # "name:base:lvl:x:y"...
  local _r _n _b _l _x _y _t
  for _r in "$@"; do
  IFS=: read -r _n _b _l _x _y <<< "$_r"
  _t=${#M_NAME[@]}; RARE_BASE[$_t]=$_b; RARE_T+=("$_t")
  M_NAME+=("$_n") M_GLY+=("${M_GLY[_b]^^}") M_COL+=("1;38;5;220;48;5;52") M_LVL+=("$_l")
  M_HP+=($(( M_HP[_b] * 5 * (_l + 4) / (M_LVL[_b] + 4) ))) M_DMG+=($(( M_DMG[_b] * 3 / 2 * (_l + 4) / (M_LVL[_b] + 4) )))
  M_XP+=($(( M_XP[_b] * 8 ))) M_GOLD+=($(( M_GOLD[_b] * 10 ))) M_AGGRO+=($(( M_AGGRO[_b] + 2 )))
  M_MOVE+=("${M_MOVE[_b]}") M_ATK+=($(( M_ATK[_b] * 9 / 10 ))) M_BOSS+=(2) M_KIND+=(0)
  ZONES+=("$_t $(( _x - 5 )) $(( _y - 4 )) $(( _x + 5 )) $(( _y + 4 )) 1")
  done
}
add_rares "${RARES[@]}"
NRARE=${#RARES[@]}
NM=${#M_NAME[@]}

# --- what every creature is made of: attack element, weakness, resistance, abilities ----------
# M_EL attack element, M_WK weak to (+50% damage), M_RS resists (-50%), M_AB on-hit ability,
# M_RNG ranged attack (tiles, 0 = melee), M_HEALR heals its friends, M_SUMM summons help
classify_monsters() {
  local t n ab
  for (( t = 0; t < NM; t++ )); do
    n=${M_NAME[t]}; (( RARE_BASE[$t] )) && n="$n ${M_NAME[RARE_BASE[$t]]}"
    M_EL[t]=0 M_WK[t]=-1 M_RS[t]=-1 M_AB[t]="" M_RNG[t]=0 M_HEALR[t]=0 M_SUMM[t]=0
    (( M_KIND[t] == 0 )) || continue
    if [[ $n =~ Frost|Ice|Yeti|Ymir|Glacius|Whitemaw|Wyrm ]]; then
      M_EL[t]=2 M_WK[t]=1 M_RS[t]=2 ab=chill
    elif [[ $n =~ Fire|Lava|Magma|Infernal|Demon|Imp|Hellhound|Fiend|Azgor|Ignis|Forge|Molten|Cinder|Drake|Dragon|Wyvern|Juggernaut ]]; then
      M_EL[t]=1 M_WK[t]=2 M_RS[t]=1 ab=burn
    elif [[ " $UNDEAD " == *" $t "* || $n =~ Bone|Skeleton|Ghost|Lich|Mummy|Zombie|Drowned|Hollow|Barnacle|Rot ]]; then
      M_EL[t]=4 M_WK[t]=5 M_RS[t]=3 ab=""
      [[ $n =~ Ghost|Lich|Hollow ]] && ab=weaken
      [[ $n =~ Zombie|Mummy|Rot ]] && ab=poison
    elif [[ $n =~ Void|Abyssal|Nightmare|Unblinking ]]; then
      M_EL[t]=4 M_WK[t]=5 M_RS[t]=4 ab=weaken
    elif [[ $n =~ Crystal|Shard|Prism|Gem|Glass|Archon ]]; then
      M_EL[t]=6 M_WK[t]=0 M_RS[t]=6 ab=""
    elif [[ $n =~ Spider|Scorpion|Serpent|Frog|Mosquito|Slime|Gloop|Basilisk|Hydra|Quetzal|Kharr ]]; then
      M_EL[t]=3 M_WK[t]=1 M_RS[t]=3 ab=poison
    elif [[ $n =~ Siren|Octopus|Kraken|Leviathan|Ishara|Tide ]]; then
      M_EL[t]=2 M_WK[t]=1 M_RS[t]=2 ab=chill
    elif [[ $n =~ Treant ]]; then
      M_WK[t]=1 ab=stun
    else ab=""; fi
    [[ $n =~ Wolf|Panther|Tiger|Shadowstripe|Bandit|Pirate|Cutthroat|Raider|Corsair|Mantis|Widow|Grimfang|Bloodknuckle ]] && ab=bleed
    [[ $n =~ Troll|Golem|Giant|Behemoth|Titan|Colossus|Turtle|Ironshell|Bison|Thunderhoof|Ram|Juggernaut|Stormwing|Roc ]] && ab=stun
    [[ $n =~ Bat|Mosquito|Vampire|Leech ]] && ab=drain
    M_AB[t]=$ab
    [[ $n =~ Shaman|Witch|Cultist|Lich|Siren|Priest|Eye|Herald|Unblinking|Fire\ Imp|Forge\ Imp ]] && M_RNG[t]=5
    [[ $n =~ Shaman|Priest ]] && M_HEALR[t]=1
    (( M_BOSS[t] == 1 )) && M_SUMM[t]=1
  done
}
classify_monsters

# --- champions: sometimes a monster spawns stronger, with an affix ---------------------------
CHP_NAME=(Vampiric Frenzied Armored Molten Frozen Venomous Giant)
CHP_DESC=("heals itself when it hits" "fast and furious" "takes 40% less damage" "burns whoever it hits"
          "chills whoever it hits" "poisons whoever it hits" "huge and tough")
CHP_COL=("1;38;5;160" "1;38;5;208" "1;38;5;250" "1;38;5;202" "1;38;5;117" "1;38;5;112" "1;38;5;180")
CHP_E=(🧛 ⚡ 🛡 🔥 ❄ 🧪 ⛰)
NCHP=${#CHP_NAME[@]}

# --- status effects on players -----------------------------------------------------------------
#        poison bleed burn chill stun weaken
PS_NAME=(poisoned bleeding burning chilled stunned weakened)
PS_E=(🤢 🩸 🔥 🥶 💫 😵)
PS_COL=("38;5;112" "38;5;160" "38;5;202" "38;5;117" "38;5;226" "38;5;141")

# --- gems: six kinds, three grades, kept with your materials ------------------------------------
GEM_L=(r s e t a o)                         # the letter in an item code's sockets
GEM_NAME=(Ruby Sapphire Emerald Topaz Amethyst Onyx)
GEM_E=(🔴 🔵 🟢 🟡 🟣 ⚫)
GEM_GRADE=(Chipped Polished Flawless)
GEM_FX=(dmg mp crit arm hp res)             # +% damage, +% MP, +crit, +armor, +% HP, +% all resistances
GEM_V=("3 6 10" "5 10 16" "2 4 6" "3 7 12" "4 8 13" "4 8 12")
GEM_TXT=("% damage" "% MP" "% crit" " armor" "% HP" "% resistances")
NFISHE=${#MAT_NAME[@]}                       # materials before the gems end with the fish
GEM0=${#MAT_NAME[@]}
for (( _g = 0; _g < 6; _g++ )); do
  for _q in 0 1 2; do
    MAT_NAME+=("${GEM_GRADE[_q]} ${GEM_NAME[_g]}")
    MAT_VAL+=($(( 25 * (_q * _q * 4 + 1) ))) MAT_RARE+=($(( _q )))
  done
done
unset _g _q
NMAT=${#MAT_NAME[@]}
gem_mat() { GM=$(( GEM0 + $1 * 3 + $2 - 1 )); }              # kind grade(1-3) -> GM material index
SOCK_MAX=(1 2 2 3)                                           # sockets a jeweler can give, by rarity

# --- talents: three trees per class, four talents each -----------------------------------------
# effect "key:value per rank": dmg crit cdmg hp mp arm res dodge block regen ls sk0 sk1 sk2 cd0 cd1 cd2
#   mpc melee el<n> dot heal aly speed pot thorns | "cap:<name>" for the 1-point capstones
TL_REQ=(0 3 6 10)                                            # points in the tree before a row opens
TL_TREE=("Arms" "Fury" "Protection"    "Fire" "Frost" "Arcane"         "Marksmanship" "Survival" "Beast Mastery"
         "Holy" "Discipline" "Light"  "Assassination" "Subtlety" "Combat"  "Retribution" "Bulwark" "Grace"
         "Bone" "Blood" "Pestilence"  "Virtuoso" "Harmony" "Rhythm")
TL_NAME=( # Warrior
  "Weapon Mastery" "Mighty Cleave" "Brutality" "Deep Wounds"
  "Battle Rage" "Rampage" "Bloodlust" "Bloodthirst"
  "Toughness" "Iron Skin" "Shield Wall" "Last Stand"
  # Mage
  "Kindling" "Pyroblast" "Critical Mass" "Combustion"
  "Ice Shards" "Permafrost" "Glacial Ward" "Shatter"
  "Arcane Mind" "Efficiency" "Temporal Flux" "Clearcasting"
  # Ranger
  "Steady Aim" "Piercing Shots" "Deadeye" "Killshot"
  "Light Feet" "Thick Hide" "Rapid Retreat" "Ghost Step"
  "Pack Bond" "Wild Spirit" "Trailblazer" "Pack Leader"
  # Cleric
  "Divine Fury" "Searing Light" "Holy Focus" "Holy Words"
  "Inner Fire" "Fortitude" "Spirit Ward" "Power Word: Shield"
  "Meditation" "Benediction" "Purity" "Serenity"
  # Rogue
  "Toxicology" "Envenom" "Lethality" "Toxic Edge"
  "Elusiveness" "Shadow Arts" "Opportunity" "Shadow Dance"
  "Dual Wielding" "Precision" "Swiftness" "Adrenaline"
  # Paladin
  "Zeal" "Crusader Strike" "Sanctity" "Hammer of Wrath"
  "Stalwart" "Devotion" "Holy Shield" "Retribution Aura"
  "Divine Grace" "Illumination" "Blessed Life" "Consecration Aura"
  # Necromancer
  "Bone Craft" "Bone Lance" "Marrow" "Bone Storm"
  "Blood Thirst" "Vitality" "Crimson Tide" "Blood Pact"
  "Contagion" "Virulence" "Epidemic" "Death Aura"
  # Bard
  "Virtuosity" "Power Chords" "Perfect Pitch" "Encore"
  "Harmony" "Lullaby of Life" "Warm Voice" "Ballad of Shielding"
  "Tempo" "Syncopation" "Quickstep" "Crescendo" )
TL_FX=( "dmg:3" "sk0:12" "cdmg:15" "cap:bleed0"     "melee:6" "dmg:4" "ls:2" "cap:onkill"       "hp:4" "arm:3" "block:5" "cap:laststand"
        "el1:6" "sk0:12" "crit:2" "cap:ignite"      "el2:6" "cd1:10" "res:5" "cap:shatter"       "mp:6" "mpc:6" "cdall:5" "cap:clearcast"
        "sk0:6" "sk1:10" "cdmg:15" "cap:execute"    "dodge:2" "hp:5" "cd2:12" "cap:evasion"      "aly:12" "regen:15" "speed:5" "cap:pack"
        "el5:6" "sk0:12" "crit:2" "cap:smiteheal"   "res:4" "hp:5" "arm:4" "cap:barrier"         "mp:6" "heal:12" "mpc:8" "cap:clearcast"
        "dot:10" "sk1:15" "crit:2" "cap:toxic"      "dodge:2" "cd2:12" "cdmg:15" "cap:critreset" "melee:6" "dmg:3" "speed:5" "cap:frenzy"
        "el5:5" "sk0:12" "crit:2" "cap:execute"     "arm:4" "hp:5" "block:5" "cap:thorns"         "heal:10" "mp:5" "regen:15" "cap:aura"
        "el4:6" "sk0:12" "cdmg:15" "cap:chain"      "ls:2" "hp:5" "sk1:15" "cap:lifelink"         "dot:10" "el3:8" "cd2:12" "cap:deathaura"
        "el6:6" "sk0:12" "crit:2" "cap:echo"        "aly:10" "heal:10" "regen:15" "cap:barrier"   "speed:4" "cdall:5" "dodge:2" "cap:frenzy" )
TL_MAX=(5 3 3 1)
declare -A CAP_DESC=(
  [bleed0]="your first skill makes every foe it hits bleed"     [onkill]="kills restore 6% HP and 4% MP"
  [laststand]="once every 90s a killing blow leaves you at 1 HP, immune for 3s"
  [ignite]="fire damage sets foes burning"                     [shatter]="frozen foes take 50% more damage"
  [clearcast]="20% chance a skill costs no mana"                [execute]="+60% damage to foes below 30% health"
  [evasion]="+10% dodge; after a dodge your next hit crits"     [pack]="your ally deals 50% more and never leaves your side"
  [smiteheal]="your damage skills heal the party for 20% of the damage" [barrier]="every 20s a shield absorbs 15% of your max HP"
  [toxic]="+25% crit chance against poisoned foes"             [critreset]="critical hits take 1s off every cooldown"
  [frenzy]="kills speed up your attacks and steps for 6s (stacks 3x)" [thorns]="melee attackers take 30% of their damage back"
  [aura]="foes next to you take 15% of your attack as holy damage every second" [chain]="your first skill jumps to a second foe for 60%"
  [lifelink]="8% of all your damage heals you"                 [deathaura]="foes next to you take 15% of your attack as shadow damage every second"
  [echo]="30% chance your third skill does not go on cooldown" )

# --- factions and reputation ---------------------------------------------------------------------
FAC_NAME=("Crown of Hearthmoor" "Frontier Wardens" "Sands of Kadar" "Northern Clans" "Tidecallers" "The Last Light")
FAC_E=(👑 🏕 🏜 🏔 🐚 🕯)
FAC_COL=("38;5;220" "38;5;107" "38;5;179" "38;5;153" "38;5;45" "38;5;230")
declare -A TOWN_FAC=([Hearthmoor]=0 ["Orwin's Hut"]=0 ["Ironwood Camp"]=1 ["Kael's Camp"]=1 ["Oasis of Kadar"]=2
  ["the Oasis of Kadar"]=2 ["Redrock Outpost"]=2 [Frosthold]=3 [Shardhaven]=3 ["Port Coral"]=4 ["Jadeleaf Village"]=4
  ["Last Light Bastion"]=5)
NFAC=${#FAC_NAME[@]}
REP_RANK=(0 1500 4500 9000 15000)
REP_NAME=(Neutral Friendly Honored Revered Exalted)
REP_COL=("38;5;250" "38;5;114" "38;5;45" "38;5;171" "38;5;214")
# faction uniques, sold by the quartermasters to the Revered
U_NAME+=("Signet of the Crown" "Warden's Oathstone" "Sunstone of Kadar" "Clanmother's Torc" "Tidecaller's Conch" "Lamp of the Last Light")
U_SLOT+=(J J J J J O)  U_KIND+=(0 2 2 1 3 3)  U_TIER+=(6 7 7 8 8 9)  U_BT+=(dmg arm crit hp mp light)
U_FL+=("Worn by the King's own champions." "Given to those who held the frontier." "Warm even at midnight."
       "Every clan has one. Now so do you." "Hold it to your ear: the sea answers." "It has never once gone out.")
FAC_UQ0=$(( ${#U_NAME[@]} - 6 ))
NUQ=${#U_NAME[@]}

# --- places worth scouting -------------------------------------------------------------------------
SPOTS=("the Hanging Stones:26:9" "the Witch's Clearing:49:21"   "the Drowned Chapel:15:43" "the Old Mill:41:54"
       "the Sunken Bridge:117:47" "the Rot Pools:144:55"        "the Bandit Watchtower:114:28" "the Broken Wagon:143:33"
       "the Eagle's Seat:116:9" "the Thunder Altar:143:16"      "the Lighthouse Ruins:15:76" "the Shipwreck Cove:50:77"
       "the Last Caravan Camp:86:75" "the Buried Obelisk:134:92"  "the Frozen Battlefield:179:16" "the Ice Tomb:219:32"
       "the Ruins of Kael's Keep:179:65" "the Ember Fissure:219:83" "the Wreck of the Silver Gull:29:112" "the Turtle Beach:89:134"
       "the Singing Spire:269:17" "the Glass Garden:329:35"      "the Overgrown Idol:269:67" "the Tiger's Den:330:87"
       "the Dry Waterfall:149:117" "the Stampede Canyon:209:134" "the Lamp of Vigil:269:121" "the Edge of the World:329:134"
       "the Old Well:90:52" "the Shepherd's Hill:70:55")
SPT_NAME=() SPT_X=() SPT_Y=()
for _s in "${SPOTS[@]}"; do IFS=: read -r _n _x _y <<< "$_s"; SPT_NAME+=("$_n") SPT_X+=("$_x") SPT_Y+=("$_y"); done
unset _s _n _x _y
NSPOT=${#SPT_NAME[@]}

# --- things monsters drop for collection quests ------------------------------------------------------
declare -A QI_NAME=([0]="Rat Tail" [1]="Slime Jelly" [2]="Wolf Pelt" [3]="Goblin Ear" [4]="Spider Silk" [5]="Rotting Heart"
  [6]="Bandit Badge" [7]="Troll Tusk" [8]="Wyvern Scale" [9]="Old Bone" [10]="Ectoplasm" [12]="Orc Tooth" [28]="Crab Claw"
  [29]="Scorpion Stinger" [30]="Raider Bandana" [31]="Wurm Hide" [35]="Frost Fang" [36]="Yeti Fur" [37]="Frozen Core"
  [40]="Imp Horn" [41]="Magma Core" [42]="Hellhound Collar" [43]="Demon Ichor" [45]="Soggy Map" [76]="Lobster Shell"
  [77]="Pirate Earring" [78]="Octopus Ink" [79]="Turtle Scute" [80]="Ram Horn" [81]="Mantis Blade" [82]="Shard Core"
  [83]="Basilisk Eye" [84]="Frog Venom" [85]="Panther Whisker" [86]="Mosquito Proboscis" [87]="Tiger Claw"
  [88]="Vulture Feather" [89]="Bison Horn" [90]="Giant's Ember" [91]="Obsidian Stinger" [92]="Void Shard"
  [93]="Shadow Wing" [94]="Hollow Crest" [95]="Abyssal Lens")

# --- questlines: every town has its own story ----------------------------------------------------------
# QL_*: name, giver (NPC type), faction, level; QS_*: the steps of all lines, in order
# objectives: K.monster.count  C.monster.count (collect drops)  G.material.count (deliver)
#             E.spot  D.dungeon  T.npc (talk to)  B.monster (bounty on a rare elite)
# choices (last step): QS_CH question, QS_CHA "option A|option B", QS_CHR "rewards A|rewards B",
#   QS_CHT "what happens A|what happens B"; rewards: rep:faction:+-n gold:n gem:n pot:n epic:slot uq:n
R=$RARE0
QL_NAME=() QL_NPC=() QL_FAC=() QL_LVL=() QL_S0=() QL_N=()
QS_OBJ=() QS_TXT=() QS_DONE=() QS_REP=() QS_CH=() QS_CHA=() QS_CHR=() QS_CHT=()
ql_add() { QL_NAME+=("$1") QL_NPC+=("$2") QL_FAC+=("$3") QL_LVL+=("$4") QL_S0+=("${#QS_OBJ[@]}") QL_N+=(0); }
qs_add() {  # obj "giver text" "done text" rep [question "A|B" "rewA|rewB" "textA|textB"]
  QS_OBJ+=("$1") QS_TXT+=("$2") QS_DONE+=("$3") QS_REP+=("$4") QS_CH+=("${5:-}") QS_CHA+=("${6:-}") QS_CHR+=("${7:-}") QS_CHT+=("${8:-}")
  QL_N[${#QL_N[@]}-1]=$(( QL_N[${#QL_N[@]}-1] + 1 ))
}
ql_add "The Hearthmoor Watch" "$NPC1" 0 2
qs_add K.2.6 "Wolves take sheep from the farms west of town every night. Thin the pack - six of them should send a message." \
  "Good work. But the farmers swear something bigger leads them." 250
qs_add E.29 "Scout the Shepherd's Hill west of the river. If the pack has a den, that's where it starts." \
  "Huge paw prints - and a gnawed Watch helmet with a name scratched inside." 250
qs_add T.25 "Take that helmet to Orwin the Hermit in Whisperwood. He knows every beast in those woods." \
  "Orwin turns the helmet over: 'Grimfang. Old, clever, hungry. He'll be in the Witch's Clearing.'" 300
qs_add B.$(( R + 0 )) "Grimfang the Elder Wolf prowls Whisperwood. End it before it takes more than sheep." \
  "Grimfang lies still. Its silver pelt is magnificent." 500 \
  "The pelt is worth a small fortune. What do you do with it?" \
  "Give it to Varga for the Watch hall|Sell it to Garrick in Ironwood Camp" \
  "rep:0:600,gold:150,pot:3|rep:1:300,gold:600" \
  "Varga hangs the pelt above the barracks door. 'Let every wolf see it.'|Garrick whistles and counts out the coins. 'Pleasure doing business.'"

ql_add "Whispers in the Wood" 25 0 3
qs_add C.4.6 "My old bones need a new net, and the spiders of Whisperwood spin the best. Six bundles of silk, please." \
  "Fine silk. Strong as a promise." 250
qs_add G.7.4 "Now silverleaf - four sprigs. The forest gives, the forest takes; we only borrow." \
  "Silk and leaf: now I can weave a ward." 250
qs_add D.0 "Carry this ward into the Forgotten Crypt and put the Lich's restless dead to sleep for good." \
  "The crypt falls silent. Even the bats seem relieved." 400
qs_add T.23 "Tell Old Tom the crypt is quiet. He worries more than he lets on, that one." \
  "Old Tom pours you a drink on the house. 'To quiet crypts!'" 400 \
  "Orwin's ward still glows in your pack. Where should it go?" \
  "Leave it with Old Tom at the inn|Bury it at the crypt door" \
  "rep:0:500,gem:2|rep:0:300,gold:400" \
  "Tom hangs it over the bar. Somehow the ale tastes better.|You bury the ward. The grass there will always grow greener."

ql_add "Fever in the Fen" 27 1 5
qs_add C.5.5 "Something in Mirefen makes the dead walk and my patients burn with fever. Bring me five hearts of the bog dead." \
  "These hearts are black with rot. It is a poison, not a curse." 300
qs_add G.8.6 "Bog myrtle - six handfuls - for the fever draught. Pick it upwind of the zombies." \
  "The draught is brewing. Now we need the source." 300
qs_add E.5 "The trappers say the Rot Pools glow at night. Look - but don't drink." \
  "The pools seethe. Something huge wallows in them at night." 300
qs_add B.$(( R + 2 )) "The trappers call it Mother Rot. Burn it out of the fen." \
  "Mother Rot bursts. The fever breaks across the camp within the hour." 600 \
  "Senna holds up the last vial of Mother Rot's blood. 'The most potent poison I have ever seen.'" \
  "Destroy it|Keep it for your blades" \
  "rep:1:700,pot:5|gold:300,gem:2" \
  "Senna pours it into the fire. 'Some things should not exist.'|You cork the vial. Senna does not look at you the same way."

ql_add "Salt and Steel" 47 2 12
qs_add K.30.8 "Sand raiders hit my caravan again. Teach them the price of pepper - eight of them." \
  "Eight fewer thieves. The road breathes easier." 350
qs_add C.29.6 "My cook says scorpion stingers make the finest spice. Don't ask. Six, please." \
  "Mm. The cook is delighted. Do not eat at my stall." 350
qs_add E.12 "My caravan master's last camp was out in the dunes. Find it - find what happened." \
  "Torn tents, raider arrows - and tracks leading to the Sunken Tomb." 350
qs_add D.3 "The raiders hid my spices in the Sunken Tomb. Get them back - and mind the Pharaoh." \
  "You return with the spice chests - and the raiders' strongbox." 700 \
  "The raiders' strongbox is full of gold - stolen from half the desert." \
  "Return everything to Nadia|Keep the raiders' gold" \
  "rep:2:900,gold:300|gold:1500,rep:2:-400" \
  "Nadia weeps with joy and the whole oasis hears your name.|You keep the gold. Nadia's smile is thin."

ql_add "The Frozen Forge" 50 3 15
qs_add G.4.5 "My forge burns cold. Without mithril I cannot make a single blade - bring me five pieces." \
  "Good ore. Now to make it sing." 400
qs_add C.37.4 "To temper mithril you need cold that never melts - the frozen cores of ice elementals. Four." \
  "The steel hisses and rings. Beautiful." 400
qs_add B.$(( R + 7 )) "Whitemaw, the great yeti, broke my bellows - and my apprentice's leg. Return the favor." \
  "Whitemaw will break nothing ever again." 450
qs_add D.4 "The Frost Wyrm sleeps on the ancient anvil of the clans in the Ice Caverns. Bring it home." \
  "The anvil is older than Frosthold itself - and humming." 800 \
  "The old anvil could forge you something wonderful - or make Frosthold proud again." \
  "Give the anvil to Ingrid|Have Ingrid forge you a weapon on it" \
  "rep:3:1200,gem:2|epic:W,rep:3:300" \
  "The whole clan comes to see the anvil set in its place. They sing for you.|Ingrid works all night. The blade is perfect."

ql_add "Embers of Exile" 52 1 18
qs_add K.40.10 "Imps nest in the old watchtowers of the Wastes. Clear ten of them." \
  "Ten imps. The towers are ours again." 450
qs_add E.16 "My keep stood in these Wastes before the ash came. Find its ruins - tell me if my banner still flies." \
  "Kael's banner hangs in tatters from a scorched wall." 450
qs_add B.$(( R + 8 )) "A hellhound called Cinderclaw dens in the ruins now. I want my home back." \
  "Cinderclaw is ash. Kael's keep is quiet." 500
qs_add D.5 "Azgor's horn could buy my way home to Hearthmoor. Bring it from the Infernal Gate." \
  "You hold Azgor's horn. It is still warm." 900 \
  "Kael wants the horn to buy his pardon. The Crown wants it as a trophy." \
  "Give it to Ser Kael|Send it to the Crown" \
  "rep:1:1200,gold:500|rep:0:1200,rep:1:-500,gem:2" \
  "Kael grips your arm. 'I'll see Hearthmoor again. Thanks to you.'|A royal courier takes the horn. Kael says nothing for a long time."

ql_add "Rum and Ruin" 123 4 20
qs_add K.77.8 "Pirates sink my boats and drink my rum. Mostly the rum. Eight of them, if you'd be so kind." \
  "Ha! The harbor's safer already." 450
qs_add C.78.5 "Octopus ink makes the best sea charts. Five sacs - and mind the tentacles." \
  "Ink for a hundred charts. Now where to sail?" 450
qs_add E.18 "The Silver Gull went down with my brother's cargo. Find the wreck." \
  "The wreck is picked clean - but turtle tracks lead along the beach." 450
qs_add B.$(( R + 9 )) "Old Ironshell sank the Silver Gull. That turtle is older than the harbor. End its reign." \
  "Old Ironshell's shell cracks. Beneath it: a single glowing egg." 900 \
  "A last egg of the ancient turtles. It glows faintly." \
  "Return it to the sea|Sell it to a collector" \
  "rep:4:1300,gem:2|gold:2000" \
  "The egg sinks into the reef. Somewhere, the sea remembers you.|The collector pays without counting. You try not to think about it."

ql_add "Shards of the Past" 127 3 21
qs_add C.81.6 "Mantis blades are the only tools that cut living crystal. Six of them, please." \
  "Sharp. Careful. Perfect." 500
qs_add G.4.6 "Mithril to set the shards in - six pieces." \
  "The setting is ready. Now the shards." 500
qs_add B.$(( R + 10 )) "The Glass Widow nests in the Glass Garden - she swallowed the shard I need." \
  "The Glass Widow shatters. A shard of memory glitters inside." 550
qs_add D.7 "The Crystal Archon guards the heart of the highlands. With it I can read the old memories in the stone." \
  "The Archon's heart pulses with stolen memories." 950 \
  "The Archon's heart holds the memories of a thousand years. The Last Light fears what they might wake." \
  "Give it to Tova|Hand it to the Last Light" \
  "rep:3:1300,gem:3|rep:5:1300,rep:3:-300,gold:600" \
  "Tova cuts the heart into a lens and sees the age of kings.|The Last Light seals the heart away. Tova does not speak to you."

ql_add "The Serpent's Coil" 132 4 22
qs_add C.84.6 "Frog venom, six vials. In the right dose it cures the jungle fever." \
  "The right dose. Remember: the right dose." 500
qs_add G.9.5 "Desert rose to sweeten the cure - five blooms." \
  "The village children will drink it now." 500
qs_add B.$(( R + 11 )) "Shadowstripe hunts the village paths at dusk. The hunters won't go out." \
  "Shadowstripe will hunt no more." 600
qs_add D.8 "The Serpent Priests poison our river from their temple. Silence the Jade Serpent." \
  "The river runs clear by morning." 1000

ql_add "Iron and Thunder" 136 2 24
qs_add K.89.8 "Bison stampedes flattened my fences three times. Eight of them, and I'll call it even." \
  "That's beef for a year, partner." 550
qs_add C.88.6 "Vulture feathers make the best fletching this side of the canyon. Six." \
  "Straight and true. Like you." 550
qs_add B.$(( R + 12 )) "Thunderhoof leads the stampedes. Big as a house, mean as a rattler." \
  "Thunderhoof falls. The canyon goes quiet." 600
qs_add D.9 "The Forgemaster in the Obsidian Forge keeps a ledger of every outlaw he arms. Bring it to me." \
  "The ledger names half the outlaws in the Badlands - and a few 'honest' folk." 1100 \
  "With the ledger Ruth can hang half the Badlands. Or blackmail them." \
  "Give the ledger to Ruth|Burn it" \
  "rep:2:1400,gold:800|rep:5:800,gem:3" \
  "Ruth grins like a coyote. 'Justice is coming, partner.'|The ledger curls in the flames. Some secrets are better as ash."

ql_add "The Last Lamp" 141 5 27
qs_add K.92.10 "Void stalkers creep closer to the walls every night. Ten of them, before the lamps gutter." \
  "The walls hold another night." 600
qs_add C.93.6 "The wings of nightmare bats hold a shadow that feeds our lamps. Six." \
  "The lamps burn brighter. For now." 600
qs_add E.26 "The Lamp of Vigil stood at the edge of the Rift. Find it. See if it still burns." \
  "The Lamp of Vigil is dark - and something watches from beyond it." 600
qs_add B.$(( R + 13 )) "The Unblinking stares out of the Rift and darkens every lamp it sees. Close its eye." \
  "The Unblinking closes its eye forever." 700
qs_add D.10 "The Hollow King is the heart of the dark. End him, and the Lamp of Vigil can burn again." \
  "The Rift trembles and is still. The Lamp of Vigil flickers - then burns." 1500 \
  "The last flame of the Lamp of Vigil dances in your hand." \
  "Relight the Lamp of Vigil|Keep the flame" \
  "rep:5:2000,gem:3|uq:$(( FAC_UQ0 + 5 )),rep:5:-500" \
  "The Lamp burns again, and every lamp in the Bastion burns with it.|The flame burns in a lantern on your belt. The Bastion grows a little darker."
NQL=${#QL_NAME[@]}
NQS=${#QS_OBJ[@]}
unset R

# ---------------------------------------------------------------------------
#  Module 01d - v4.0 content: the 480x200 world. Seven new lands for levels 30-40
#  (Duskwood, the Sunken Kingdom, Stormreach Peaks, Gloomcap Hollows, Dragonspine,
#  the Bonefields, Starfall Crater), a new creature for every old land, seven
#  towns, seven dungeons, world bosses, rare elites, uniques, gear tiers 10-12,
#  allies, two factions, Act II of the story and eight more questlines.
#  Pure data, appended to the tables of 01_core/01b/01c (indexes never move:
#  save files store them). See docs/MODDING.md.
# ---------------------------------------------------------------------------
MAXLVL=40
declare -a MEMO_X=()                              # HD sprites of the new creatures (applied in 04c)
#           L:  1   3   5   8  10  12  15  17  19  21  24   27   30   40
_SL=(           1   3   5   8  10  12  15  17  19  21  24   27   30   40)
_SH=(          14  34  50 100 180 210 300 380 480 780 900 1300 1600 3000)
_SD=(           3   7  11  16  22  27  36  46  56  70  88  108  124  190)
_SX=(           8  22  38  70 105 137 210 290 400 600 860 1180 1500 2800)
_SG=(           2   4   6  18  22  28  30  45  55  70 100  150  190  270)
base_stats() {  # level -> BH BD BX BG: what a plain creature of that level has (interpolated from the old ones)
  local l=$1 i a b
  for (( i = 0; i < ${#_SL[@]} - 1; i++ )); do (( l <= _SL[i+1] )) && break; done
  a=${_SL[i]} b=${_SL[i+1]}; (( l < a )) && l=$a
  BH=$(( _SH[i] + (_SH[i+1] - _SH[i]) * (l - a) / (b - a) )) BD=$(( _SD[i] + (_SD[i+1] - _SD[i]) * (l - a) / (b - a) ))
  BX=$(( _SX[i] + (_SX[i+1] - _SX[i]) * (l - a) / (b - a) )) BG=$(( _SG[i] + (_SG[i+1] - _SG[i]) * (l - a) / (b - a) ))
}
m4() {  # var name glyph color level boss hp% dmg% aggro move atk emoji: one more creature, its index in $var
  local v=$1 t=${#M_NAME[@]} xm=100 gm=100
  base_stats "$5"
  case $6 in 1) xm=1600 gm=3000 ;; 2) xm=300 gm=500 ;; w) xm=1800 gm=3200 ;; esac
  M_NAME+=("$2") M_GLY+=("$3") M_COL+=("$4") M_LVL+=("$5")
  M_HP+=($(( BH * $7 / 100 ))) M_DMG+=($(( BD * $8 / 100 ))) M_XP+=($(( BX * xm / 100 ))) M_GOLD+=($(( BG * gm / 100 )))
  M_AGGRO+=("$9") M_MOVE+=("${10}") M_ATK+=("${11}") M_KIND+=(0)
  case $6 in 1|w) M_BOSS+=(1) ;; 2) M_BOSS+=(2) ;; *) M_BOSS+=(0) ;; esac
  MEMO_X[t]=${12}
  printf -v "$v" '%d' "$t"
}

# --- a new creature for every old land (159-173) ----------------------------------------------------
#   var       name                 gly  color        lvl boss hp%  dmg% ag move atk  emoji
m4 X_GOOSE   "Angry Goose"          g "1;38;5;255"     2  0  110  110  5  420  1000 🦆
m4 X_LEECH   "Giant Leech"          l "38;5;95"        3  0  100  100  4  700  1200 🐛
m4 X_OWLB    "Owlbear"              O "1;38;5;137"     5  0  150  110  5  560  1300 🦉
m4 X_HYDRA   "Mire Hydra"           H "1;38;5;71"      7  0  140  110  6  620  1200 🐍
m4 X_OGRE    "Hill Ogre"            O "1;38;5;130"     9  0  150  110  5  700  1500 👹
m4 X_HARPY   "Crag Harpy"           h "38;5;180"      11  0   95  110  8  340  1000 🦅
m4 X_SMUG    "Saltwind Smuggler"    s "38;5;110"      10  0  100  105  7  460  1000 🤠
m4 X_JACKAL  "Desert Jackal"        j "38;5;179"      13  0   90  105  8  330   900 🦊
m4 X_ITROLL  "Ice Troll"            T "1;38;5;159"    17  0  140  105  6  650  1500 🧟
m4 X_WRAITH  "Ash Wraith"           W "1;38;5;245"    19  0  100  110  8  450  1100 👻
m4 X_SERP    "Sea Serpent"          S "1;38;5;37"     22  0  110  105  6  450  1100 🐍
m4 X_CBAT    "Crystal Bat"          b "1;38;5;183"    23  0   85  100  9  300   900 🦇
m4 X_GORILLA "Jungle Gorilla"       G "1;38;5;94"     24  0  130  110  7  420  1300 🦍
m4 X_LIZARD  "Lava Lizard"          z "1;38;5;202"    25  0  100  105  7  400  1000 🦎
m4 X_VWRAITH "Void Wraith"          w "1;38;5;99"     29  0  100  105  9  400  1000 👻
WORLD_TYPES+=($X_GOOSE $X_LEECH $X_OWLB $X_HYDRA $X_OGRE $X_HARPY $X_SMUG $X_JACKAL $X_ITROLL $X_WRAITH
              $X_SERP $X_CBAT $X_GORILLA $X_LIZARD $X_VWRAITH)
ZONES+=("$X_GOOSE 64 43 100 60 4" "$X_LEECH 10 36 52 60 4" "$X_OWLB 4 4 68 28 4" "$X_HYDRA 106 40 156 60 4"
        "$X_OGRE 100 24 156 38 4" "$X_HARPY 104 3 156 23 4" "$X_SMUG 5 64 62 76 4" "$X_JACKAL 62 66 158 97 5"
        "$X_ITROLL 162 2 237 45 4" "$X_WRAITH 162 52 237 97 4" "$X_SERP 5 100 115 148 4" "$X_CBAT 242 2 357 48 5"
        "$X_GORILLA 242 52 357 98 4" "$X_LIZARD 122 101 236 147 5" "$X_VWRAITH 243 102 357 147 4")

# --- the creatures of the seven new lands (174-201) ---------------------------------------------------
#   Duskwood 30-32
m4 DW_WOLF   "Dusk Wolf"            w "1;38;5;137"    30  0  100  100  8  360  1000 🐺
m4 DW_TREANT "Briar Treant"         t "1;38;5;94"     31  0  150  100  5  800  1500 🌲
m4 DW_WISP   "Jack-o'-Wisp"         j "1;38;5;214"    31  0   80  105  9  420  1100 🎃
m4 DW_BEAR   "Werebear"             B "1;38;5;130"    32  0  130  110  7  480  1300 🐻
m4 DW_WITCH  "Bramble Witch"        W "1;38;5;141"    32  0   90  110  8  520  1200 🧙
#   the Sunken Kingdom 31-33
m4 SK_LEGION "Sunken Legionnaire"   L "1;38;5;72"     31  0  110  100  7  560  1100 🧟
m4 SK_NAGA   "Reef Naga"            N "1;38;5;43"     32  0  100  105  8  440  1000 🐍
m4 SK_ANGLER "Abyssal Angler"       a "1;38;5;105"    32  0   95  105  9  480  1100 🐡
m4 SK_KRAKEN "Kraken Spawn"         k "1;38;5;168"    33  0  120  105  7  560  1200 🦑
#   Stormreach Peaks 32-34
m4 ST_HARPY  "Storm Harpy"          h "1;38;5;153"    32  0   90  105  9  330  1000 🦅
m4 ST_GIANT  "Frost Giant"          G "1;38;5;159"    33  0  160  110  6  700  1600 🥶
m4 ST_SERP   "Cloud Serpent"        S "1;38;5;195"    34  0  110  105  8  420  1100 🐉
m4 ST_RAM    "Thunder Ram"          r "1;38;5;250"    33  0  110  105  6  380  1200 🐐
#   Gloomcap Hollows 33-35
m4 GC_CRAWL  "Spore Crawler"        c "1;38;5;143"    33  0  100  100  7  450  1000 🐛
m4 GC_SHAMAN "Sporecap Shaman"      S "1;38;5;176"    34  0   90  100  8  520  1200 🧙
m4 GC_SPIDER "Gloom Spider"         s "1;38;5;96"     34  0  100  105  8  380  1000 🐜
m4 GC_BEHEM  "Fungal Behemoth"      B "1;38;5;139"    35  0  170  110  5  800  1600 🦏
#   Dragonspine 35-37
m4 DS_HOUND  "Magma Hound"          h "1;38;5;202"    35  0  100  105  9  330  1000 🐕
m4 DS_KIN    "Dragonkin Warrior"    D "1;38;5;166"    36  0  130  110  7  460  1200 🦖
m4 DS_RIDER  "Wyvern Rider"         R "1;38;5;208"    36  0  110  110  9  340  1100 🐲
m4 DS_BASIL  "Ash Basilisk"         b "1;38;5;243"    37  0  120  105  7  480  1200 🦎
#   the Bonefields 36-38
m4 BF_KNIGHT "Grave Knight"         K "1;38;5;252"    36  0  130  110  7  520  1300 🧟
m4 BF_BANSH  "Wailing Banshee"      b "1;38;5;195"    37  0   85  110  9  420  1100 👻
m4 BF_PRIEST "Death Priest"         P "1;38;5;139"    37  0   95  105  8  560  1200 🧛
m4 BF_COLOS  "Bone Colossus"        C "1;38;5;255"    38  0  180  115  5  850  1700 🦴
#   Starfall Crater 38-40
m4 SF_SPAWN  "Star Spawn"           s "1;38;5;219"    38  0  100  105  9  380  1000 👽
m4 SF_HORROR "Astral Horror"        H "1;38;5;99"     39  0  120  110  8  480  1200 🐙
m4 SF_GOLEM  "Meteor Golem"         G "1;38;5;209"    39  0  170  115  5  800  1600 🤖
m4 SF_SERAPH "Fallen Seraph"        A "1;38;5;229"    40  0  110  115  9  420  1100 👼
WORLD_TYPES+=($DW_WOLF $DW_TREANT $DW_WISP $DW_BEAR $DW_WITCH $SK_LEGION $SK_NAGA $SK_ANGLER $SK_KRAKEN
              $ST_HARPY $ST_GIANT $ST_SERP $ST_RAM $GC_CRAWL $GC_SHAMAN $GC_SPIDER $GC_BEHEM
              $DS_HOUND $DS_KIN $DS_RIDER $DS_BASIL $BF_KNIGHT $BF_BANSH $BF_PRIEST $BF_COLOS
              $SF_SPAWN $SF_HORROR $SF_GOLEM $SF_SERAPH)
#        region rects:  Duskwood 120 150 239 199 | Sunken 0 150 119 199 | Stormreach 360 0 479 49
#   Gloomcap 360 50 479 99 | Dragonspine 360 100 479 149 | Bonefields 240 150 359 199 | Starfall 360 150 479 199
ZONES+=("$DW_WOLF 122 151 237 198 8" "$DW_TREANT 122 151 237 198 6" "$DW_WISP 122 151 237 198 6"
        "$DW_BEAR 122 151 237 198 5" "$DW_WITCH 122 151 237 198 4"
        "$SK_LEGION 38 160 84 186 6" "$SK_NAGA 2 150 118 198 6" "$SK_ANGLER 2 150 118 198 5" "$SK_KRAKEN 2 150 118 198 5"
        "$ST_HARPY 362 2 477 47 8" "$ST_GIANT 362 2 477 47 5" "$ST_SERP 362 2 477 47 6" "$ST_RAM 362 2 477 47 7"
        "$GC_CRAWL 362 52 477 97 8" "$GC_SHAMAN 362 52 477 97 5" "$GC_SPIDER 362 52 477 97 7" "$GC_BEHEM 362 52 477 97 4"
        "$DS_HOUND 362 102 477 147 8" "$DS_KIN 362 102 477 147 6" "$DS_RIDER 362 102 477 147 6" "$DS_BASIL 362 102 477 147 5"
        "$BF_KNIGHT 242 152 357 197 7" "$BF_BANSH 242 152 357 197 6" "$BF_PRIEST 242 152 357 197 5" "$BF_COLOS 242 152 357 197 4"
        "$SF_SPAWN 362 152 477 197 8" "$SF_HORROR 362 152 477 197 6" "$SF_GOLEM 362 152 477 197 5" "$SF_SERAPH 362 152 477 197 4")
n=$NODE0                                                    # ore veins and herbs out there
ZONES+=("$(( n + 5 )) 122 151 237 198 4" "$(( n + 11 )) 122 151 237 198 5" "$(( n + 10 )) 2 150 118 198 4"
        "$(( n + 4 )) 362 2 477 47 5" "$(( n + 9 )) 362 2 477 47 3" "$(( n + 11 )) 362 52 477 97 6"
        "$(( n + 5 )) 362 102 477 147 6" "$(( n + 11 )) 362 102 477 147 3" "$(( n + 5 )) 242 152 357 197 4"
        "$(( n + 5 )) 362 152 477 197 5" "$(( n + 10 )) 362 152 477 197 4")
UNDEAD+="$SK_LEGION $BF_KNIGHT $BF_BANSH $BF_PRIEST $BF_COLOS "

# --- dungeon elites and bosses (202-215) ---------------------------------------------------------------
m4 E_THORN   "Thornmother"                 T "1;38;5;94;48;5;58"    31 2 400 120 9 520 1200 🧙
m4 E_BISHOP  "Drowned High Priest"         P "1;38;5;72;48;5;23"    32 2 360 120 9 560 1200 🧟
m4 E_WARDEN  "Storm Warden"                W "1;38;5;153;48;5;24"   34 2 400 120 9 480 1100 🤺
m4 E_BRUTE   "Rotcap Brute"                B "1;38;5;139;48;5;53"   35 2 450 125 9 650 1400 👹
m4 E_MATRON  "Brood Matron"                M "1;38;5;202;48;5;52"   37 2 420 125 9 520 1200 🐉
m4 E_LICH    "Lich Chancellor"             L "1;38;5;255;48;5;238"  38 2 380 125 10 560 1200 💀
m4 E_HERALD  "Herald of the Star"          H "1;38;5;229;48;5;54"   40 2 420 125 10 480 1100 👼
m4 B_MORW    "Morwenna the Witch Queen"    Q "1;38;5;231;48;5;58"   32 1 1700 118 10 600 1300 🧙
m4 B_NEREZ   "Nerezza the Drowned Queen"   N "1;38;5;231;48;5;23"   33 1 1700 118 10 650 1300 🧜
m4 B_VOLTAR  "Voltar the Storm Thane"      V "1;38;5;231;48;5;24"   35 1 1800 120 10 600 1200 🤴
m4 B_SPORE   "The Sporefather"             S "1;38;5;231;48;5;53"   36 1 1900 118 10 750 1400 🍄
m4 B_VYRNAX  "Vyrnax the Ember Tyrant"     V "1;38;5;231;48;5;52"   38 1 2000 120 10 600 1300 🐉
m4 B_MORDR   "Mordrath the Undying King"   M "1;38;5;231;48;5;238"  39 1 2100 120 10 600 1200 💀
m4 B_AZOTH   "Azoth, Heart of the Star"    A "1;38;5;16;48;5;229"   40 1 2600 125 10 650 1200 🌟
UNDEAD+="$E_BISHOP $E_LICH $B_NEREZ $B_MORDR "

# --- world bosses (216-219) ----------------------------------------------------------------------------
m4 W_COLOS   "The Drowned Colossus"        C "1;38;5;231;48;5;23"   33 w 2000 110 10 750 1500 🐋
m4 W_TITAN   "Skyrender the Storm Titan"   T "1;38;5;16;48;5;153"   35 w 2100 112 10 700 1400 🗿
m4 W_VORG    "Vorgath the Ashen Dragon"    D "1;38;5;231;48;5;88"   37 w 2200 115 10 600 1300 🐲
m4 W_RIDER   "The Pale Rider"              R "1;38;5;16;48;5;252"   38 w 2200 115 10 450 1100 🐴
UNDEAD+="$W_COLOS $W_RIDER "
WB_LIST+=($W_COLOS $W_TITAN $W_VORG $W_RIDER)
WB_RECT+=("2 150 118 198" "362 2 477 47" "362 102 477 147" "242 152 357 197")
WB_ADDS+=("$SK_LEGION $SK_NAGA $SK_KRAKEN" "$ST_HARPY $ST_HARPY $ST_RAM" "$DS_HOUND $DS_KIN $DS_KIN" "$BF_KNIGHT $BF_KNIGHT $BF_BANSH")

# --- the people of the seven new towns (220-254) ---------------------------------------------------------
#   town            x1  y1 (the walls are 21x13: waystone at +3+2, campfire at +14+9)
T4_NAME=(Hollowmere Tidewatch Skyhold Sporeholm "Wyrmrest Keep" Gravewatch Dawnspire)
T4_X=(168 50 410 410 410 290 366)  T4_Y=(166 166 18 68 116 166 154)
T4_DX=(10 4 17 7 17) T4_DY=(4 9 3 7 8)              # questgiver, then the others: where they stand
NPC4=${#M_NAME[@]}
n4() {  # town slot role "Full Name" short glyph color emoji
  local t=${#M_NAME[@]}
  M_NAME+=("$5") M_GLY+=("$6") M_COL+=("1;38;5;$7;$NPCBG") M_LVL+=($(( 30 + $1 ))) M_HP+=(2400) M_DMG+=(120)
  M_XP+=(300) M_GOLD+=(800) M_AGGRO+=(0) M_MOVE+=(900) M_ATK+=(1000) M_BOSS+=(0) M_KIND+=(1)
  MEMO_X[t]=$8 N_ROLE[$t]=$3 N_FULL[$t]=$4 N_HOME[$t]=${T4_NAME[$1]}
  NPC_SPAWNS+=("$t $(( T4_X[$1] + T4_DX[$2] )) $(( T4_Y[$1] + T4_DY[$2] )) 0")
}
n4 0 0 questgiver "Warden Aldra"           Aldra       A 214 🧝
n4 0 1 smith      "Old Hob the Smith"      Hob         H 180 👷
n4 0 2 inn        "Widow Fenna"            Fenna       F 217 💁
n4 0 3 bank       "Maple the Banker"       Maple       '$' 220 🤵
n4 0 4 merc       "Rook the Trapper"       Rook        R 137 🧗
n4 1 0 questgiver "Captain Maren"          Maren       M 51 👩
n4 1 1 smith      "Ironfin the Smith"      Ironfin     I 180 👷
n4 1 2 inn        "Barnacle Bess"          Bess        B 217 🧖
n4 1 3 bank       "Shelly the Banker"      Shelly      '$' 220 🤵
n4 1 4 trader     "Corwin the Diver"       Corwin      C 75 🚣
n4 2 0 questgiver "Stormcaller Eira"       Eira        E 153 🧙
n4 2 1 smith      "Brakka Stonehand"       Brakka      B 180 👷
n4 2 2 inn        "Hildr of the Hearth"    Hildr       H 217 💁
n4 2 3 bank       "Ingot the Banker"       Ingot       '$' 220 🤵
n4 2 4 merc       "Falkor the Falconer"    Falkor      F 110 🧔
n4 3 0 questgiver "Elder Puffcap"          Puffcap     P 176 🧓
n4 3 1 alchemist  "Morel the Alchemist"    Morel       M 118 🧚
n4 3 2 inn        "Truffle"                Truffle     T 217 🧖
n4 3 3 bank       "Spore the Banker"       Spore       '$' 220 🤵
n4 3 4 general    "Chanterelle"            Chanterelle C 214 🙋
n4 4 0 questgiver "Dragonlord Veyra"       Veyra       V 202 👸
n4 4 1 smith      "Forgewarden Ulric"      Ulric       U 180 👷
n4 4 2 inn        "Sister Calla"           Calla       C 217 💁
n4 4 3 bank       "Garnet the Banker"      Garnet      '$' 220 🤵
n4 4 4 merc       "Scalebreaker Torv"      Torv        T 166 💂
n4 5 0 questgiver "Gravekeeper Mortimer"   Mortimer    M 250 👴
n4 5 1 alchemist  "Sister Ashlyn"          Ashlyn      A 118 🧕
n4 5 2 inn        "Digger"                 Digger      D 217 🧒
n4 5 3 bank       "Bones the Banker"       Bones       '$' 220 🤵
n4 5 4 smith      "Ser Aldous"             Aldous      S 180 🤺
n4 6 0 questgiver "High Seer Lumen"        Lumen       L 229 👼
n4 6 1 smith      "Starsmith Orrin"        Orrin       O 180 👷
n4 6 2 inn        "Dawnmother Ilya"        Ilya        I 217 💁
n4 6 3 bank       "Comet the Banker"       Comet       '$' 220 🤵
n4 6 4 general    "Astra the Provisioner"  Astra       A 214 🙋
for (( _i = 0; _i < 7; _i++ )); do                  # two guards at every north gate
  NPC_SPAWNS+=("19 $(( T4_X[_i] + 9 )) $(( T4_Y[_i] + 2 )) 1" "19 $(( T4_X[_i] + 11 )) $(( T4_Y[_i] + 2 )) 1")
done
Q_HOLLOW=$NPC4 Q_TIDE=$(( NPC4 + 5 )) Q_SKY=$(( NPC4 + 10 )) Q_SPORE=$(( NPC4 + 15 )) Q_WYRM=$(( NPC4 + 20 ))
Q_GRAVE=$(( NPC4 + 25 )) Q_DAWN=$(( NPC4 + 30 ))
N_QK+=([$Q_HOLLOW]="$DW_WOLF $DW_TREANT $DW_WISP $DW_BEAR" [$Q_TIDE]="$SK_LEGION $SK_NAGA $SK_ANGLER $SK_KRAKEN"
       [$Q_SKY]="$ST_HARPY $ST_GIANT $ST_SERP $ST_RAM" [$Q_SPORE]="$GC_CRAWL $GC_SHAMAN $GC_SPIDER $GC_BEHEM"
       [$Q_WYRM]="$DS_HOUND $DS_KIN $DS_RIDER $DS_BASIL" [$Q_GRAVE]="$BF_KNIGHT $BF_BANSH $BF_PRIEST $BF_COLOS"
       [$Q_DAWN]="$SF_SPAWN $SF_HORROR $SF_GOLEM $SF_SERAPH")
N_QD+=([$Q_HOLLOW]=11 [$Q_TIDE]=12 [$Q_SKY]=13 [$Q_SPORE]=14 [$Q_WYRM]=15 [$Q_GRAVE]=16 [$Q_DAWN]=17)
N_QT+=([$Q_HOLLOW]=$Q_TIDE [$Q_TIDE]=$Q_SKY [$Q_SKY]=$Q_SPORE [$Q_SPORE]=$Q_WYRM [$Q_WYRM]=$Q_GRAVE
       [$Q_GRAVE]=$Q_DAWN [$Q_DAWN]=$Q_HOLLOW)

# --- the new lands on the map -------------------------------------------------------------------------
for (( _i = 0; _i < 7; _i++ )); do
  _x=${T4_X[_i]} _y=${T4_Y[_i]} _n=${T4_NAME[_i]// /_}
  SAFE_RECTS+=("$_x $_y $(( _x + 20 )) $(( _y + 12 ))")
  REGIONS+=("$_x $_y $(( _x + 20 )) $(( _y + 12 )) $_n safe")
  WAYSTONES+=("$_n $(( _x + 3 )) $(( _y + 2 ))")
done
unset _i _x _y _n
REGIONS+=("120 150 239 199 Duskwood 30-32" "0 150 119 199 Sunken_Kingdom 31-33" "360 0 479 49 Stormreach_Peaks 32-34"
          "360 50 479 99 Gloomcap_Hollows 33-35" "360 100 479 149 Dragonspine 35-37" "240 150 359 199 Bonefields 36-38"
          "360 150 479 199 Starfall_Crater 38-40")
WEA_REG+=(Duskwood Sunken_Kingdom Stormreach_Peaks Gloomcap_Hollows Dragonspine Bonefields Starfall_Crater)
WEA_KIND+=("rain fog" "storm rain" "storm snow" "fog rain" "ash sand" "fog ash" "storm ash")
WATER_OF+=([Duskwood]=swamp [Sunken_Kingdom]=sea [Stormreach_Peaks]=ice [Gloomcap_Hollows]=swamp [Dragonspine]=lava
           [Bonefields]=swamp [Starfall_Crater]=ice)

# --- dungeons 11-17 ----------------------------------------------------------------------------------
D_NAME+=("Witchroot Barrow" "Drowned Cathedral" "Thunderpeak Citadel" "Mycelium Heart" "Dragon's Roost"
         "Necropolis of Kings" "The Shattered Star")
D_REQ+=(30 31 33 34 36 37 39)
D_POOL+=("$DW_WOLF $DW_TREANT $DW_WITCH $DW_WISP" "$SK_LEGION $SK_NAGA $SK_ANGLER $SK_LEGION" "$ST_HARPY $ST_GIANT $ST_SERP $ST_RAM"
         "$GC_CRAWL $GC_SHAMAN $GC_SPIDER $GC_BEHEM" "$DS_HOUND $DS_KIN $DS_RIDER $DS_BASIL"
         "$BF_KNIGHT $BF_BANSH $BF_PRIEST $BF_COLOS" "$SF_SPAWN $SF_HORROR $SF_GOLEM $SF_SERAPH")
D_BOSS+=($B_MORW $B_NEREZ $B_VOLTAR $B_SPORE $B_VYRNAX $B_MORDR $B_AZOTH)
D_ELITE+=($E_THORN $E_BISHOP $E_WARDEN $E_BRUTE $E_MATRON $E_LICH $E_HERALD)
D_ENTX+=(140 22 468 468 468 252 424)  D_ENTY+=(190 190 8 92 140 192 182)
D_WHERE+=("Duskwood, south-west of Hollowmere" "the Sunken Kingdom, south-west island" "Stormreach Peaks, far north-east"
          "Gloomcap Hollows, far east" "Dragonspine, far east" "the Bonefields, far south-west" "the heart of Starfall Crater")
D_WALL+=("38;5;94" "38;5;30" "38;5;67" "38;5;96" "38;5;124" "38;5;250" "38;5;229")
D_FLOOR+=("38;5;58" "38;5;23" "38;5;59" "38;5;53" "38;5;52" "38;5;238" "38;5;54")
D_WE_X=(🟫 🟦 ⬜ 🟪 🟥 ⬜ 🟨)
D_W+=(112 112 116 116 120 124 128)  D_H+=(40 40 42 42 42 44 44)
D_ROOMS+=(16 16 17 17 18 18 20)  D_CHESTS+=(4 4 4 4 5 5 5)
NDT=${#D_NAME[@]}

# --- gear: three more tiers, more kinds (for the new classes too) ----------------------------------------
TIER_Q+=(Titanforged Eclipsed Godforged)
#   weapons 25-29
WK_NAME+=("Hand Wraps" "Moon Sickle" "Thornbough" "War Glaive" "Ironwood Staff")
WK_E+=(🥊 🌛 🎋 🏒 🎍)
WK_CLS+=(9 86 83 059 89)  WK_DMG+=(104 100 98 106 102)  WK_BT+=(crit mp hp arm hp)  WK_BV+=(5 10 8 4 6)
WK_CLS[4]+="9" WK_CLS[9]+="8"                          # spears for monks, staves for druids
#   armor 4-5, offhands 7-8, helms 5-6
AK_NAME+=(Gi Leafweave) AK_E+=(🥋 🍃) AK_CLS+=(94 82) AK_MUL+=(85 75) AK_BT+=(crit hp) AK_BV+=(4 6)
AK_CLS[0]+="8" AK_CLS[1]+="89"
OK_NAME+=(Totem "Prayer Beads") OK_E+=(🗿 📿) OK_CLS+=(8 9) OK_MUL+=(0 0) OK_BT+=(hp crit) OK_BV+=(8 6)
OK_CLS[3]+="89"
HK_NAME+=("Antler Crown" "Mystic Hood") HK_E+=(🌿 🧣) HK_CLS+=(8 94) HK_MUL+=(55 50) HK_BT+=(mp crit) HK_BV+=(8 4)
HK_CLS[0]+="89"
for _i in "${!JK_CLS[@]}"; do JK_CLS[_i]+="89"; done; unset _i
DEFW+=(27 25) ALTW+=(26 29) DEFA+=(5 4) DEFH+=(5 6) DEFO+=(7 8)

# --- the two new classes -------------------------------------------------------------------------------
C_NAME+=(Druid Monk)
C_DESC+=("nature's wrath: thorns, entangling roots and healing growth"
         "lightning fists and flying kicks, and the calm to heal himself")
C_HP0+=(34 38) C_HPL+=(9 10) C_MP0+=(38 28) C_MPL+=(7 5) C_DMG+=(92 108) C_ARM+=(1 2)
S_NAME+=("Thorn Whip" "Entangling Roots" "Wild Growth"   "Flurry" "Flying Kick" "Inner Peace")
S_MP+=(8 16 22  6 12 18)  S_CD+=(1800 9000 14000  1500 7000 16000)
NCLS=${#C_NAME[@]}

# --- uniques 26-41 (26 and 27 belong to the new factions' quartermasters) ----------------------------------
U_NAME+=("Heartwood Amulet" "Sunwell Medallion" "Morwenna's Thornstaff" "Tidebreaker" "Crown of Storms" "Sporeheart"
         "Emberscale Plate" "Mordrath's Grasp" "Shard of Azoth" "Abyssal Pearl" "Titan's Thunderfists" "Wyrmfire Bow"
         "The Pale Lance" "The Dawnbringer" "Cloak of Starlight" "Moonwhisper")
U_SLOT+=(J J W W H J  A W J J W W  W W A W)
U_KIND+=(1 2 9 4 3 3  3 13 0 1 25 6  28 0 0 26)
U_TIER+=(11 12 10 10 11 11  11 12 12 10 11 11  12 12 11 11)
U_BT+=(hp crit mp crit mp hp  hp mp crit mp crit crit  arm crit mp mp)
U_FL+=("Grown, not carved. It still has a heartbeat." "The first light of every morning lives in it."
       "The witch's roots still twitch in the wood." "It remembers the sea that drowned a kingdom." "Lightning sleeps in every point."
       "Soft, warm and slightly breathing. Do not eat." "Every scale is a dragon's grudge." "Its grip outlasted death once already."
       "A splinter of a fallen star. It hums when you are near the crater." "The deep keeps its secrets in pearls like this."
       "Each punch arrives a moment before the thunder." "The string is a dragon's sinew. It does not miss."
       "The Rider carried it for a thousand years. It is still cold." "Forged at dawn, for the one who brings it."
       "Woven from the light of stars that no longer exist." "It whispers to the moon. Sometimes the moon answers.")
NUQ=${#U_NAME[@]}
U_DROP+=("$B_MORW:28:25" "$B_MORW:41:15" "$B_NEREZ:29:25" "$B_VOLTAR:30:25" "$B_SPORE:31:25" "$B_VYRNAX:32:25"
         "$B_MORDR:33:25" "$B_AZOTH:34:30" "$W_COLOS:35:25" "$W_TITAN:36:25" "$W_VORG:37:25" "$W_RIDER:38:25")

# --- allies 8-11 -----------------------------------------------------------------------------------------
ALY_NAME+=("Thornback the Bear" "Wisp of Dawn" "Gale the Storm Hawk" "Ser Revenant")
ALY_SHORT+=(Thornback Wisp Gale Revenant) ALY_G+=(T W G R) ALY_ROLE+=(melee heal ranged melee)
ALY_PCT+=(80 30 65 85) ALY_RNG+=(1 4 7 1) ALY_CD+=(1200 1400 1000 1100) ALY_COST+=(8000 10000 12000 0)
ALY_SELL+=($NPC4 $(( NPC4 + 24 )) $(( NPC4 + 14 )) -1)
ALY_DESC+=("A bear the size of a cart. Hugs hard, bites harder." "A little sun that keeps you alive."
           "Dives at your foes from seven steps away, faster than the wind." "A knight who came back from the Bonefields. Fights like nothing can kill him - nothing can.")
ALY_E_X=(🐻 🌞 🦅 🛡)
NALY=${#ALY_NAME[@]}

# --- two more factions -------------------------------------------------------------------------------------
FAC_NAME+=("The Wildwatch" "The Dawnguard") FAC_E+=(🌲 🌅) FAC_COL+=("38;5;136" "38;5;229")
NFAC=${#FAC_NAME[@]}
TOWN_FAC+=([Hollowmere]=6 [Tidewatch]=4 [Skyhold]=3 [Sporeholm]=6 ["Wyrmrest Keep"]=7 [Gravewatch]=5 [Dawnspire]=7)
declare -A REGION_FAC=([Duskwood]=6 ["Sunken Kingdom"]=4 ["Stormreach Peaks"]=3 ["Gloomcap Hollows"]=6 [Dragonspine]=7
                       [Bonefields]=5 ["Starfall Crater"]=7)

# --- three more champion affixes ----------------------------------------------------------------------------
CHP_NAME+=(Storming Cursed Swift) CHP_DESC+=("stuns whoever it hits" "weakens whoever it hits" "fast on its feet")
CHP_COL+=("1;38;5;153" "1;38;5;141" "1;38;5;51") CHP_E+=(💫 😈 💨)
NCHP=${#CHP_NAME[@]}

# --- rare elites of the new lands --------------------------------------------------------------------------
R4=${#M_NAME[@]}
RARES4=("Old Mother Briar:$DW_TREANT:32:205:180"    "The Headless Huntsman:$DW_WISP:32:150:186" "Captain Saltbones:$SK_LEGION:33:96:190"
        "Gnasher the Deep:$SK_KRAKEN:34:22:182"     "Thunderbeak:$ST_HARPY:34:440:12"          "Sporemaw:$GC_BEHEM:36:392:90"
        "Ashwing the Old:$DS_RIDER:37:382:126"      "Weeping Mary:$BF_BANSH:38:272:184"        "The Bone Collector:$BF_COLOS:39:330:190"
        "The Comet:$SF_GOLEM:40:454:188")
add_rares "${RARES4[@]}"
NRARE=${#RARE_T[@]}
NM=${#M_NAME[@]}

# --- what every creature is made of (v4.0 names the old classifier does not know) ----------------------------
classify4() {
  local t n
  for (( t = 0; t < NM; t++ )); do
    (( M_KIND[t] == 0 )) || continue
    n=${M_NAME[t]}; (( RARE_BASE[$t] )) && n="$n ${M_NAME[RARE_BASE[$t]]}"
    if [[ $n =~ Wisp|Huntsman ]]; then M_EL[t]=1 M_WK[t]=2 M_RS[t]=1 M_AB[t]=burn M_RNG[t]=5
    elif [[ $n =~ Bramble|Thorn|Morwenna|Briar ]]; then M_EL[t]=3 M_WK[t]=1 M_RS[t]=3 M_AB[t]=poison
    elif [[ $n =~ Naga ]]; then M_EL[t]=3 M_WK[t]=1 M_RS[t]=3 M_AB[t]=poison
    elif [[ $n =~ Spore|Fungal|Rotcap|Crawler ]]; then M_EL[t]=3 M_WK[t]=1 M_RS[t]=3; M_AB[t]=poison
    elif [[ $n =~ Harpy|Thunderbeak ]]; then M_EL[t]=6 M_WK[t]=0 M_RS[t]=6 M_AB[t]=bleed M_RNG[t]=4
    elif [[ $n =~ Storm|Thunder|Cloud|Voltar|Skyrender ]]; then M_EL[t]=6 M_WK[t]=0 M_RS[t]=6
    elif [[ $n =~ Magma|Ember|Vyrnax|Vorgath|Ashwing|Brood|Meteor|Comet ]]; then M_EL[t]=1 M_WK[t]=2 M_RS[t]=1; M_AB[t]=burn
    elif [[ $n =~ Grave|Banshee|Death\ Priest|Mordrath|Pale|Legionnaire|Saltbones|Weeping|Wraith|Bone\ Collector ]]; then
      M_EL[t]=4 M_WK[t]=5 M_RS[t]=3 M_AB[t]=""
      [[ $n =~ Banshee|Weeping|Mordrath|Wraith ]] && M_AB[t]=weaken
    elif [[ $n =~ Star|Astral|Azoth ]]; then M_EL[t]=6 M_WK[t]=4 M_RS[t]=6 M_AB[t]=weaken
    elif [[ $n =~ Seraph ]]; then M_EL[t]=5 M_WK[t]=4 M_RS[t]=5 M_AB[t]=weaken
    fi
    [[ $n =~ Owlbear|Werebear|Gorilla|Ogre|Golem|Colossus|Giant|Ram ]] && M_AB[t]=stun
    [[ $n =~ Jackal|Smuggler|Dusk\ Wolf|Huntsman|Dragonkin|Grave\ Knight ]] && M_AB[t]=bleed
    [[ $n =~ Leech|Crystal\ Bat|Angler ]] && M_AB[t]=drain
    [[ $n =~ Banshee|Weeping|Seraph|Herald|Shaman|Priest|Witch ]] && M_RNG[t]=5
    [[ $n =~ Shaman|Priest ]] && M_HEALR[t]=1
  done
}
# (the classifier runs once, after all creatures: 01g)
S_EL+=(3 3 5  0 0 5)                               # Thorn Whip .. Inner Peace

# --- scouting spots, collection items -----------------------------------------------------------------------------
SP4=${#SPT_NAME[@]}
for _s in "Witch's Hollow:153:162" "the Hanging Tree:214:186" "the Sunken Bell Tower:102:156" "the Pearl Shallows:96:191" \
          "the Eye of the Storm:451:23" "Skyfather's Cairn:379:9" "the Glowing Grotto:448:60" "the Rotting Throne:390:85" \
          "Wyrmfall:440:108" "the Ember Steps:380:128" "the Kings' Road:320:158" "the Weeping Field:270:186" \
          "the Crater Rim:460:164" "the Starstone:408:190"; do
  IFS=: read -r _n _x _y <<< "$_s"; SPT_NAME+=("$_n") SPT_X+=("$_x") SPT_Y+=("$_y")
done
unset _s _n _x _y
NSPOT=${#SPT_NAME[@]}
QI_NAME+=([$X_GOOSE]="Goose Feather" [$X_LEECH]="Leech Fang" [$X_OWLB]="Owlbear Plume" [$X_HYDRA]="Hydra Scale"
  [$X_OGRE]="Ogre Tooth" [$X_HARPY]="Harpy Talon" [$X_SMUG]="Smuggled Rum" [$X_JACKAL]="Jackal Hide" [$X_ITROLL]="Frozen Tusk"
  [$X_WRAITH]="Ash Shroud" [$X_SERP]="Serpent Scale" [$X_CBAT]="Crystal Wing" [$X_GORILLA]="Gorilla Fist" [$X_LIZARD]="Lizard Tail"
  [$X_VWRAITH]="Void Shroud" [$DW_WOLF]="Dusk Pelt" [$DW_TREANT]="Briar Heartwood" [$DW_WISP]="Glowing Pumpkin"
  [$DW_BEAR]="Werebear Claw" [$DW_WITCH]="Witch's Charm" [$SK_LEGION]="Legion Badge" [$SK_NAGA]="Naga Scale"
  [$SK_ANGLER]="Angler Lure" [$SK_KRAKEN]="Kraken Ink" [$ST_HARPY]="Storm Feather" [$ST_GIANT]="Giant's Rune"
  [$ST_SERP]="Cloud Scale" [$ST_RAM]="Thunder Horn" [$GC_CRAWL]="Glowing Spore Sac" [$GC_SHAMAN]="Spore Fetish"
  [$GC_SPIDER]="Gloom Silk" [$GC_BEHEM]="Behemoth Cap" [$DS_HOUND]="Magma Heart" [$DS_KIN]="Dragonkin Scale"
  [$DS_RIDER]="Rider's Spur" [$DS_BASIL]="Basilisk Eye" [$BF_KNIGHT]="Grave Seal" [$BF_BANSH]="Banshee Veil"
  [$BF_PRIEST]="Death Mask" [$BF_COLOS]="Colossus Bone" [$SF_SPAWN]="Star Dust" [$SF_HORROR]="Astral Eye"
  [$SF_GOLEM]="Star Iron" [$SF_SERAPH]="Fallen Feather")

# --- the talents of the druid and the monk ---------------------------------------------------------------------
TL_TREE+=("Balance" "Feral" "Restoration"   "Windwalker" "Brewmaster" "Mistweaver")
TL_NAME+=( # Druid
  "Nature's Wrath" "Thorns of Fury" "Moonfire" "Toxic Bloom"
  "Feral Instinct" "Thick Fur" "Predatory Strikes" "Primal Fury"
  "Gift of the Wild" "Nurturing" "Living Roots" "Tree of Life"
  # Monk
  "Tiger Palm" "Rising Fists" "Killing Strikes" "Touch of Death"
  "Iron Body" "Stagger" "Fluidity" "Fortifying Brew"
  "Clear Mind" "Serenity" "Spirit Flow" "Way of the Crane" )
TL_FX+=( "el3:6" "sk0:12" "dot:15" "cap:toxic"   "melee:6" "arm:3" "crit:2" "cap:frenzy"   "hp:4" "heal:10" "regen:15" "cap:lifelink"
         "dmg:3" "sk0:12" "cdmg:15" "cap:execute"  "hp:4" "arm:3" "dodge:2" "cap:barrier"  "mp:6" "cdall:5" "mpc:6" "cap:evasion" )

# --- rumours of the new lands -----------------------------------------------------------------------------------
RUMORS+=("South of Redrock Outpost the trees turn red and never lose their leaves. They call it the Duskwood. Warden Aldra keeps Hollowmere there."
         "A bridge runs west from the Duskwood across the sea to Tidewatch. On quiet nights you can hear bells under the water."
         "East of the Crystal Highlands the mountains touch the storms. Skyhold sits up there, if the wind lets you in."
         "The mushrooms of the Gloomcap Hollows grow taller than towers. The spore-folk of Sporeholm are friendly. Mostly."
         "Dragons still nest in the Dragonspine, east of the Void Rift. Dragonlord Veyra of Wyrmrest Keep rides them."
         "The Bonefields lie south of Last Light Bastion. Gravekeeper Mortimer knows every grave out there by name."
         "Something fell from the sky a thousand years ago, far in the south-east. The crater still glows at night."
         "There are druids and monks among the heroes now. A druid heals with flowers, a monk with a kick. Or so I hear.")

# --- the story, act II: the Fallen Star (chapters 25-42, levels 30-40) ----------------------------------------
ST_TITLE+=("The Crown Grows Cold" "Witchroot" "Bells Beneath the Waves" "The Drowned Cathedral" "Where Storms Are Born"
           "Thunderpeak" "The Spore Song" "Silence the Singers" "The Sporefather" "A Dragon's Bargain" "The Ember Tyrant"
           "Where Kings Rot" "The Grave Knights" "Necropolis of Kings" "The Last Dawn" "Children of the Star"
           "The Shattered Star" "Home, Again")
ST_LVL+=(30 30 31 32 32 33 34 34 35 35 36 36 37 37 38 39 40 40)
ST_OBJ+=("T.$Q_HOLLOW" "D.11" "T.$Q_TIDE" "D.12" "T.$Q_SKY" "D.13" "T.$Q_SPORE" "K.$GC_SHAMAN.10" "D.14"
         "T.$Q_WYRM" "D.15" "T.$Q_GRAVE" "K.$BF_KNIGHT.12" "D.16" "T.$Q_DAWN" "K.$SF_SPAWN.15" "D.17" "T.23")
ST_XP+=(12000 30000 14000 34000 15000 38000 16000 24000 42000 17000 46000 18000 30000 50000 20000 36000 70000 20000)
ST_GOLD+=(3000 6000 3200 6500 3400 7000 3600 5000 7500 3800 8000 4000 6000 8500 4500 7000 15000 8000)
ST_REW+=("" G.W.10 "" G.A.10 "" U.40 "" "" A.9 "" G.W.11 "" A.11 G.A.12 "" "" U.39 "")
ST_TEXT+=(
 "Old Tom wakes you before dawn. 'The crown went cold in the night, friend. Cold as a grave. And every time I hold it, it tugs south - past Redrock, into the Duskwood.' Warden Aldra keeps the forest village of Hollowmere down there. Ask her what stirs in her woods."
 "Aldra: 'Morwenna, the Witch Queen, holds court in the Witchroot Barrow, south-west of Hollowmere. She found a shard of a fallen star and grew a forest of nightmares from it. Bring me that shard.'"
 "Aldra: 'There is a second shard. The fishermen of Tidewatch hear bells under the sea at night. Take the long bridge west from Hollowmere to the Sunken Kingdom and find Captain Maren.'"
 "Maren: 'Their queen, Nerezza, still rules down there - in the Drowned Cathedral on the south-western island. Whatever she guards, the sea will not let it go.'"
 "Maren: 'Two shards, and both pull north-east now. Past the Crystal Highlands the mountains touch the clouds - the Stormreach. Stormcaller Eira of Skyhold reads the winds there.'"
 "Eira: 'Voltar, the Storm Thane, has made a crown of lightning from the third shard. He sits in the Thunderpeak Citadel, far north-east of Skyhold, and calls himself a god. Disagree with him.'"
 "Eira: 'The fourth shard fell into the Gloomcap Hollows, south of here, where mushrooms grow taller than towers. The spore-folk of Sporeholm are friendly. Mostly. Find Elder Puffcap.'"
 "Puffcap: 'The Sporefather keeps the singing stone, and his Sporecap Shamans sing the forest to sleep. If they keep singing, the whole Hollows will sleep forever - us too. Make them stop. Ten should do.'"
 "Puffcap: 'He is awake now, and he will come for us. Go first! The Mycelium Heart lies far to the east. Be brave! Be quick! Mind the drips!'"
 "Puffcap: 'The last shard... the stone says it is with the dragons. South. Hot. Very hot. Dragonlord Veyra of Wyrmrest Keep tames dragons. Or the dragons tame her - nobody is quite sure.'"
 "Veyra: 'Vyrnax the Ember Tyrant has burned three of my riders and sleeps on your fifth shard in the Dragon's Roost, far east. Kill him - the shard is yours, his hoard is mine. Fair? Fair.'"
 "Veyra: 'The shards want to go home - to the crater where the star fell. But the road runs through the Bonefields, south of the Void Rift. Gravekeeper Mortimer of Gravewatch knows the way. He knows every grave by name.'"
 "Mortimer: 'Mordrath the Undying King felt your shards the moment you came. His Grave Knights ride every night. Break their ranks - twelve of them - and the dead will have one master less.'"
 "Mortimer: 'Mordrath waits in the Necropolis of Kings, far south-west in the Bonefields. He was the first to touch the star - and he never let go. He wants your shards. Do not let him have them.'"
 "Mortimer: 'Dawnspire stands on the rim of Starfall Crater, east of here. High Seer Lumen has watched the star for longer than I have dug graves. Go to her.'"
 "Lumen: 'The star was not a star, Crownbearer. It was an egg, and it is hatching. Its children crawl out of the crater every night - Star Spawn, hungry for light. Fifteen of them, and the way to the heart is open.'"
 "Lumen: 'Azoth, the heart of the star, has woken. Your crown and the five shards were the cage that held it once. Go down into the Shattered Star and close the cage - forever.'"
 "Lumen: 'Go home, Crownbearer. Truly, this time. Someone in Hearthmoor will want to hear the whole story.'")
ST_DONE+=(
 "Aldra turns the crown in her scarred hands. 'Star-metal. Same as the thing the witches dug up last spring. That is no coincidence, Crownbearer.'"
 "Morwenna screams as the roots let her go. In the heart of the barrow lies a shard of black star-metal - it pulls towards your crown like a lodestone."
 "Maren spits into the sea. 'Bells? Aye. The drowned kingdom of Ys rings them. It sank the night the star fell - a thousand years ago.'"
 "Nerezza sinks back into the dark. On her altar: a second shard. The bells stop. All of Tidewatch comes out to listen to the silence."
 "Eira listens to the shards hum. 'The storms have spoken of you. They are not happy about it.'"
 "Voltar's lightning dies with him. The third shard was set into his crown - still warm. Eira wraps a cloak of starlight around your shoulders. 'For the road ahead.'"
 "Elder Puffcap wobbles with excitement. 'The singing stone! You came for the singing stone! The Sporefather keeps it and will not share. He never shares.'"
 "The singing stops. Somewhere deep below, something very large wakes up - and it is angry."
 "The Sporefather crumbles into dust and glitter. The fourth shard lies in his heart. A tiny light rises from the spores and settles on your shoulder: the Wisp of Dawn has chosen you."
 "Veyra looks at the four shards and laughs. 'You want the fifth? So do I. Let us not kill each other over it.'"
 "The Ember Tyrant falls and the mountains shake. The fifth shard glows in the ashes of his hoard. Five shards - and they are trying to become one."
 "Mortimer leans on his shovel. 'The Undying King. I wondered when someone would come for him.'"
 "The last Grave Knight kneels instead of falling. 'I served him a thousand years,' it rasps. 'Let me serve someone worth it.' Ser Revenant follows you now."
 "Mordrath crumbles at last. 'It... calls... you... now,' he whispers. The shards burn cold. Across the Bonefields, the crater glows."
 "Lumen's blind eyes find you anyway. 'Five shards and the crown. Then it is time.'"
 "The last Star Spawn bursts into silver dust. In the heart of the crater, something enormous turns towards you."
 "Azoth's light folds in on itself, smaller and smaller, until it fits into the crown. The crater goes dark - and then, for the first time in a thousand years, the sun rises over it. Lumen presses a blade of pure dawn into your hands."
 "Old Tom has kept a seat for you by the fire. He pours two mugs of the very good stuff and listens until morning. 'Two kings, a witch, a drowned queen, a storm, a mushroom, a dragon and a star. Not bad, friend. Not bad at all.' THE END.")
NST=${#ST_TITLE[@]}

# --- eight more questlines -----------------------------------------------------------------------------------
_r() { printf -v "$1" '%d' "$(( R4 + $2 ))"; }      # rare n of the new lands
_r RB 0; _r RH 1; _r RS 2; _r RT 4; _r RM 5; _r RA 6; _r RW 7; _r RC 9
ql_add "The Witch of Duskwood" "$Q_HOLLOW" 6 30
qs_add K.$DW_WOLF.8 "Dusk wolves hunt right up to our gates now. Eight fewer of them, and my rangers might sleep again." \
  "The pack pulls back. Something drives them, though - they flee from the south-west." 400
qs_add E.$SP4 "My scouts found a clearing where nothing grows but thorns: Witch's Hollow, north-west of the village. See what waits there." \
  "Witch-marks on every stone, and the thorns are fresh. Someone is growing them." 400
qs_add C.$DW_TREANT.6 "The thorns come from the Briar Treants. Cut six heartwoods out of them - we will burn them and read the smoke." \
  "The heartwood smoke turns green, then black. Old Rook will know what that means." 450
qs_add T.$(( NPC4 + 4 )) "Take the ashes to Rook the Trapper, here in town. He lived with the witches once, before he came to his senses." \
  "Rook sniffs the ashes and goes pale. 'Old Mother Briar. The oldest treant in the wood. She is the root of all of it.'" 450
qs_add B.$RB "Old Mother Briar walks again, east of the village. End her, and the Duskwood will breathe." \
  "Old Mother Briar falls with a sound like a whole forest sighing. Her heart is a seed of black star-metal - still beating." 700 \
  "The seed still beats. What will you do with it?" \
  "Burn it in Hollowmere's hearth|Plant it in the shade of the Hanging Tree" \
  "rep:6:800,gold:700,pot:4|rep:6:300,gem:2,epic:J" \
  "The seed screams in the fire, then it is gone. Hollowmere cheers all night.|By morning a sapling stands there, silver-leaved and silent. Aldra just stares at it."
ql_add "The Bells of Ys" "$Q_TIDE" 4 31
qs_add K.$SK_NAGA.8 "Reef Nagas cut our nets and drown our divers. Eight of them, and Tidewatch can fish again." \
  "The nets come up full for the first time in weeks." 400
qs_add E.$(( SP4 + 2 )) "The bells ring loudest by the old bell tower on the north-eastern island. Go and listen." \
  "The tower's bell is long gone - but you hear it ringing far below the waves." 400
qs_add C.$SK_LEGION.6 "The drowned legion still wears the badges of Ys. Bring me six - their names may tell us who rings the bells." \
  "Every badge bears the same name: Captain Saltbones, Bellwarden of Ys." 450
qs_add B.$RS "Saltbones rings the bells to call the drowned to war. He haunts the south-eastern island. Silence him." \
  "Saltbones' bell-rope snaps. The drowned stop marching." 600
qs_add G.$(( NFISHE - 1 )).3 "The sea gave much and took more. Bring three of the rarest fish for the drowned - an old Tidewatch custom." \
  "Maren casts the fish into the sea. The waves calm, the way they did when she was a girl." 500 \
  "Maren holds out Saltbones' bell. 'It's yours, if you want it.'" \
  "Keep the bell|Give it to the Tidecallers' shrine" \
  "gold:900,gem:2|rep:4:900,pot:5" \
  "You hang the bell on your belt. It only rings for you now.|The shrine bell rings once, clear and bright. The Tidecallers will remember this."
ql_add "Eye of the Storm" "$Q_SKY" 3 32
qs_add K.$ST_HARPY.8 "Storm Harpies tear the roofs off Skyhold every night. Eight fewer, and we might keep our roofs." \
  "The harpies scatter, screaming at the wind." 400
qs_add E.$(( SP4 + 4 )) "The harpies nest near the Eye of the Storm, east of Skyhold, where the wind never stops. Find out why they gather there." \
  "In the eye of the storm the air is still - and something huge has left feathers everywhere." 400
qs_add G.5.6 "Brakka wants obsidian to forge lightning rods for the walls. Six chunks should do." \
  "Brakka hammers the rods into shape. 'Now let the sky do its worst.'" 450
qs_add B.$RT "The feathers belong to Thunderbeak, the oldest harpy of the peaks. She nests north of the Eye. Bring her down." \
  "Thunderbeak falls out of the sky like a broken storm. Her feathers still crackle." 700 \
  "Thunderbeak's feathers crackle with lightning. What do you do with them?" \
  "Give them to Brakka for the lightning rods|Have a storm cloak made from them" \
  "rep:3:900,gold:600|epic:A,gold:300" \
  "Brakka whistles. 'With these, Skyhold will never burn again.'|The cloak hums. When you walk, the air smells of rain."
ql_add "Sing, Little Spores" "$Q_SPORE" 6 33
qs_add C.$GC_CRAWL.6 "Our lamps run on glowing spore sacs, and the crawlers have eaten all of ours. Six, please! Fresh ones!" \
  "Sporeholm glows again. The little ones dance in the light." 400
qs_add E.$(( SP4 + 6 )) "The glow is fading in the Glowing Grotto, north-east of here. The grotto is where spore-folk are born. Go see!" \
  "The grotto's light is dim. Webs cover everything - spider webs." 400
qs_add K.$GC_SPIDER.8 "Gloom Spiders in the grotto! They eat the newborn! Eight of them, quickly, quickly!" \
  "The webs are torn down. Tiny spores float up into the light again." 450
qs_add T.$(( NPC4 + 16 )) "Morel the alchemist says the spiders were driven out of their own home. Ask her by whom." \
  "Morel stirs her pot. 'Sporemaw. The biggest behemoth in the Hollows has gone mad, and everything flees from it.'" 450
qs_add B.$RM "Sporemaw rages near the Rotting Throne, south-west of here. Please make it stop. Gently, if you can. Not gently, if you can't." \
  "Sporemaw topples like a felled tower. The Hollows go very quiet." 700 \
  "Sporemaw's enormous cap lies in front of you." \
  "Let the spore-folk eat it at a feast|Sell it to Morel for her potions" \
  "rep:6:900,pot:6|gold:1200,gem:1" \
  "The feast lasts three days. You are invited to all of it.|Morel counts out the gold. 'This will make SO many potions.'"
ql_add "Ashes of the Brood" "$Q_WYRM" 7 35
qs_add K.$DS_HOUND.8 "Magma Hounds have learned to hunt our hatchlings. Eight of them, and the nests are safe again." \
  "The hounds slink back into the lava fields." 450
qs_add E.$(( SP4 + 8 )) "One of my riders went down at Wyrmfall, north-east of the keep. Find out what happened to her." \
  "You find the rider's saddle, burned through - and dragonkin footprints all around it." 450
qs_add C.$DS_KIN.6 "Dragonkin did this. Bring me six of their scales - I want to know which clan." \
  "Veyra lays the scales out on her table. 'Every one of them marked with the same sign: Ashwing.'" 500
qs_add T.$(( NPC4 + 24 )) "Scalebreaker Torv fought Ashwing once and lived. Ask him how." \
  "Torv laughs. 'Lived? I ran! Ashwing is old, but old dragons fight dirty. Aim for the wings.'" 500
qs_add B.$RA "Ashwing the Old nests at the Ember Steps, west of the keep. Finish what Torv started." \
  "Ashwing crashes into the lava, wings burning. Behind him, in the ashes, a single egg still glows." 800 \
  "Ashwing's last egg survived. It is warm in your hands." \
  "Give the egg to Veyra's riders|Smash it - no more of his kind" \
  "rep:7:1000,epic:W|rep:7:300,rep:5:600,gold:800" \
  "Veyra holds the egg like a newborn. 'This one will be raised kindly. Thank you.'|The egg cracks. Somewhere, the Last Light breathes easier."
ql_add "The Weeping Field" "$Q_GRAVE" 5 36
qs_add K.$BF_KNIGHT.8 "Grave Knights dig up my graves faster than I can fill them. Put eight of them back where they belong." \
  "The dead stay in the ground for a night. Mortimer sleeps for the first time in weeks." 450
qs_add E.$(( SP4 + 11 )) "Every night someone cries in the Weeping Field, south-west of Gravewatch. Living or dead, I'd like to know who." \
  "The crying stops when you arrive. On a broken grave: fresh flowers, and a death mask." 450
qs_add C.$BF_PRIEST.5 "The Death Priests wear masks like that one. Bring me five - I want to know what they're hiding." \
  "Every mask is carved with the same face: a weeping woman." 500
qs_add T.$(( NPC4 + 26 )) "Sister Ashlyn knows the old faces. Show her the masks." \
  "Ashlyn goes very still. 'Mary. She was Mordrath's queen. He killed her first, so she would never leave him.'" 500
qs_add B.$RW "Weeping Mary haunts the field. Free her - one way or another." \
  "Mary's wailing fades into a sigh. She looks at you - truly looks - for the first time in a thousand years." 800 \
  "Mary's ghost asks you to find her daughter's grave before she goes." \
  "Search the Bonefields for the grave|Let her rest without it" \
  "rep:5:900,gem:2|rep:5:400,gold:900" \
  "You find the little grave beneath a bone-white tree. Mary smiles, and is gone.|'Then I will look for her myself,' Mary whispers, and fades into the morning."
ql_add "Children of the Star" "$Q_DAWN" 7 38
qs_add K.$SF_SPAWN.10 "The Star Spawn grow bolder every night. Ten of them - before they find the courage to climb our walls." \
  "The spawn retreat into the crater. They will be back. They always come back." 500
qs_add E.$(( SP4 + 12 )) "From the Crater Rim, east of here, you can see the heart of the star. Look. Tell me if it is brighter than last night." \
  "It is brighter. Much brighter." 500
qs_add G.11.4 "Dawnmother Ilya brews starlight tea from emberroot - it keeps our watchers awake. Four sprigs, please." \
  "Ilya's tea glows faintly in the cup. The watchers stand a little straighter." 500
qs_add E.$(( SP4 + 13 )) "The Starstone, south of the crater's heart, is where the first spawn crawled out. Find it." \
  "The Starstone is cracked open, and the crack is still growing. Something enormous rolls around the crater towards you." 500
qs_add B.$RC "The Comet - a golem of pure star-iron - guards the crack. Break it." \
  "The Comet shatters into a shower of sparks. Its core rolls to your feet, still glowing." 900 \
  "The Comet's core is pure star-iron." \
  "Give it to Starsmith Orrin|Keep it for yourself" \
  "rep:7:1100,epic:W|gold:1500,gem:3" \
  "Orrin weighs the core in his hands. 'I can make something with this. Something for YOU.'|It hums quietly in your pack, like a heart."
ql_add "The Crownbearer's Blade" 21 0 38
qs_add G.5.8 "A Crownbearer with a borrowed blade? Shameful. Bring me obsidian - eight pieces - and we'll start on something worthy." \
  "Brom heaps the obsidian next to his anvil. 'Good. Now the hard part.'" 400
qs_add C.$SF_GOLEM.5 "Obsidian holds the shape, but the edge needs star-iron. The Meteor Golems of Starfall Crater are made of it. Five chunks." \
  "The star-iron is so cold it burns." 500
qs_add T.$(( NPC4 + 31 )) "Only one smith alive can work star-iron: Starsmith Orrin of Dawnspire. Take him my letter." \
  "Orrin reads Brom's letter twice and laughs. 'That old goat still owes me a hammer. Tell him yes.'" 500
qs_add D.17 "Orrin says the blade must be quenched in the light of the star's heart. That means the Shattered Star. Good luck." \
  "You hold the blade into Azoth's dying light. It drinks all of it." 900 \
  "Brom finishes the blade with a last ringing blow. 'It's yours - or the Crown's.'" \
  "Keep the blade|Lay it on the throne of Hearthmoor" \
  "epic:W,gold:1000|rep:0:1500,gem:3" \
  "'Then make it famous,' Brom grunts.|All of Hearthmoor comes to look at it. Brom pretends not to cry."
NQL=${#QL_NAME[@]} NQS=${#QS_OBJ[@]}
unset -f _r

# ---------------------------------------------------------------------------
#  Module 01e - v4.5 data: closing the gaps of 4.0 (professions and gems up to
#  level 40, paragon levels after 40) and the endgame: mythic dungeons, the
#  raid, invasions, dailies and weeklies, valor, mounts, achievements, titles.
#  Pure data, appended to the tables before it (indexes never move).
# ---------------------------------------------------------------------------

# --- materials 40-47: ore, herbs and fish of the new lands; 48-53: perfect gems --------------------------------
M45=${#MAT_NAME[@]}
MAT_NAME+=("Titanite Ore" "Starmetal Ore" "Duskbloom" "Glowcap" "Abyssal Eel" "Storm Trout" "Magma Carp" "Starfish of Ys")
MAT_VAL+=(60 110 55 100 70 80 95 260)
MAT_RARE+=(1 2 1 2 0 1 1 2)
GEM4_0=${#MAT_NAME[@]}
for (( _i = 0; _i < 6; _i++ )); do MAT_NAME+=("Perfect ${GEM_NAME[_i]}"); MAT_VAL+=(900); MAT_RARE+=(2); done; unset _i
NMAT=${#MAT_NAME[@]}
GEM_GRADE+=(Perfect)
GEM_V=("3 6 10 15" "5 10 16 24" "2 4 6 9" "3 7 12 18" "4 8 13 19" "4 8 12 17")
GEM_MAXQ=4
gem_mat() { if (( $2 >= 4 )); then GM=$(( GEM4_0 + $1 )); else GM=$(( GEM0 + $1 * 3 + $2 - 1 )); fi; }   # kind grade -> GM
gem_kq() {  # material -> GKI (gem kind) GQI (grade 1-4); returns 1 if it is no gem
  if (( $1 >= GEM4_0 && $1 < GEM4_0 + 6 )); then GKI=$(( $1 - GEM4_0 )) GQI=4; return 0; fi
  if (( $1 >= GEM0 && $1 < GEM0 + 18 )); then GKI=$(( ($1 - GEM0) / 3 )) GQI=$(( ($1 - GEM0) % 3 + 1 )); return 0; fi
  return 1
}
# what every material is (0 fishing, 1 mining, 2 herbalism, 3 gem), and the groups the inventory shows
MAT_PK=() MAT_GRP=("" "" "" "")
for (( _i = 0; _i < NMAT; _i++ )); do
  if gem_kq "$_i"; then _k=3
  elif (( _i < 6 || _i == M45 || _i == M45 + 1 )); then _k=1
  elif (( _i < 12 || _i == M45 + 2 || _i == M45 + 3 )); then _k=2
  else _k=0; fi
  MAT_PK[_i]=$_k MAT_GRP[_k]+="$_i "
done; unset _i _k
PROF_MAX=40

# --- four more resource nodes (kind 3) --------------------------------------------------------------------
N45=${#M_NAME[@]}
M_NAME+=("Titanite Vein" "Starmetal Vein" "Duskbloom" "Glowcap") M_GLY+=(◆ ◆ ♣ ♣)
M_COL+=("1;38;5;109" "1;38;5;229" "1;38;5;133" "1;38;5;51")
M_LVL+=(30 36 30 36) M_HP+=(3 3 3 3) M_DMG+=(0 0 0 0) M_XP+=(40 52 40 52) M_GOLD+=(0 0 0 0)
M_AGGRO+=(0 0 0 0) M_MOVE+=(900 900 900 900) M_ATK+=(1000 1000 1000 1000) M_BOSS+=(0 0 0 0) M_KIND+=(3 3 3 3)
MEMO_X[N45]=🪙 MEMO_X[N45+1]=⭐ MEMO_X[N45+2]=🌺 MEMO_X[N45+3]=🍄
declare -A NODE_MAT=() NODE_PK=()                   # node type -> material, profession
NODE_T=()
for (( _i = 0; _i < 12; _i++ )); do NODE_MAT[$(( NODE0 + _i ))]=$_i NODE_PK[$(( NODE0 + _i ))]=$(( _i < 6 ? 1 : 2 )); NODE_T+=($(( NODE0 + _i ))); done
for (( _i = 0; _i < 4; _i++ )); do NODE_MAT[$(( N45 + _i ))]=$(( M45 + _i )) NODE_PK[$(( N45 + _i ))]=$(( _i < 2 ? 1 : 2 )); NODE_T+=($(( N45 + _i ))); done
unset _i
ZONES+=("$N45 122 151 237 198 4" "$N45 362 2 477 47 4" "$N45 362 102 477 147 3"
        "$(( N45 + 1 )) 242 152 357 197 4" "$(( N45 + 1 )) 362 152 477 197 4" "$(( N45 + 1 )) 362 102 477 147 3"
        "$(( N45 + 2 )) 122 151 237 198 5" "$(( N45 + 2 )) 362 52 477 97 4"
        "$(( N45 + 3 )) 362 52 477 97 5" "$(( N45 + 3 )) 362 152 477 197 4")
FISHW[sea]+=" $(( M45 + 4 )):30:0 $(( M45 + 7 )):36:2:night" FISHW[swamp]+=" $(( M45 + 4 )):31:0"
FISHW[ice]+=" $(( M45 + 5 )):32:1" FISHW[lava]+=" $(( M45 + 6 )):34:1"

# --- paragon: after level 40 every 60k XP is a point; points over 36 talents count too ------------------------
PARA_NAME=(Might Vitality Precision Warding Wisdom Celerity)
PARA_FX=(dmg hp crit res mp cd)            # +1% damage, +1% HP, +1 crit per 2 points, +1% resist, +1% mana, -1% cooldowns
PARA_MAX=(50 50 40 30 50 20)
PARA_DESC=("+1% damage" "+1% health" "+1% crit per 2 points" "+1% resistance" "+1% mana" "-1% cooldowns")
para_next() { PNX=$(( 60000 + 2000 * ${1:-0} )); }

# --- mythic dungeons: any dungeon at level 40, +2 to +20, weekly affixes, a timer --------------------------------
MYTH_MAX=20
MYTH_A=(Fortified Tyrannical)              # from +2 (alternating weeks)
MYTH_AD=("normal foes have 30% more health and hit 15% harder" "bosses and elites have 40% more health and hit 20% harder")
MYTH_B=(0 3 4 5 7 8 9)                     # from +4: this champion affix is on a third of all foes
MYTH_C=(Bolstering Raging)                 # from +7
MYTH_CD=("when a foe dies, its friends nearby heal and grow stronger" "foes below 30% health hit half again as hard")
week_now() { DAYN=$(( EPOCHSECONDS / 86400 )); WEEK=$(( (DAYN + 3) / 7 )); }   # weeks start on Monday
myth_afx() {  # -> MA MB MC: this week's affixes (the same on every machine with a sane clock)
  week_now; MA=$(( WEEK % 2 )) MB=${MYTH_B[$(( WEEK % ${#MYTH_B[@]} ))]} MC=$(( (WEEK / 2) % 2 ))
}
myth_limit() { MYL=$(( (D_ROOMS[$1] * 30 + 150) * 1000 )); }      # dungeon type -> MYL ms on the clock
MYTH_LVL=40                                                     # the level mythic monsters are scaled to

# --- the raid: the Eclipse Throne (dungeon 18) -----------------------------------------------------------------
m4 RD_CULT   "Eclipse Cultist"              c "1;38;5;99"    40 0  110 110  9 420 1100 🧙
m4 RD_KNIGHT "Shadowbound Knight"           K "1;38;5;60"    40 0  160 115  8 480 1300 🤺
m4 RD_BEHEM  "Twilight Behemoth"            B "1;38;5;54"    40 0  240 120  6 700 1600 🦏
m4 RD_SERAPH "Dusk Seraph"                  S "1;38;5;183"   40 0  120 115  9 420 1100 👼
m4 RD_SENT   "Twilight Sentinel"            T "1;38;5;231;48;5;54"  40 2  700 125 10 520 1200 🗿
m4 RD_NYX    "Nyxara, Queen of the Eclipse" N "1;38;5;16;48;5;99"   40 1 4200 120 12 600 1200 🌘
declare -A M_RAID=([$RD_NYX]=1)
D_NAME+=("The Eclipse Throne") D_REQ+=(40) D_POOL+=("$RD_CULT $RD_KNIGHT $RD_BEHEM $RD_SERAPH")
D_BOSS+=($RD_NYX) D_ELITE+=($RD_SENT) D_ENTX+=(456) D_ENTY+=(166) D_WHERE+=("Starfall Crater, on the eastern rim (raid)")
D_WALL+=("38;5;99") D_FLOOR+=("38;5;17") D_WE_X+=(⬛) D_W+=(100) D_H+=(40) D_ROOMS+=(9) D_CHESTS+=(3)
NDT=${#D_NAME[@]} RAID_DT=$(( NDT - 1 ))
U_NAME+=("Eclipse Crown" "Nyxara's Embrace" "Twilight Edge" "Heart of the Eclipse")
U_SLOT+=(H A W J) U_KIND+=(3 0 0 3) U_TIER+=(12 12 12 12) U_BT+=(crit mp crit hp)
U_FL+=("It is always a little dark under this crown." "Woven from the shadow of the moon."
       "The edge exists only half the time. That is the dangerous half." "It beats once every eclipse.")
RAID_UQ=($(( NUQ )) $(( NUQ + 1 )) $(( NUQ + 2 )) $(( NUQ + 3 ))); NUQ=${#U_NAME[@]}

# --- mounts ---------------------------------------------------------------------------------------------------
MNT_NAME=("Brown Horse" "Swift Steed" "Dune Camel" "Frost Ram" "Storm Gryphon" "Bone Charger" "Ember Drake" "Starborn Stag")
MNT_E=(🐴 🐎 🐫 🐏 🦅 🦓 🐉 🦌)
MNT_SPD=(40 60 60 60 80 80 100 100)        # % faster than on foot
MNT_GOLD=(1500 6000 4000 4000 0 0 0 0)
MNT_REQ=("" "lvl:20" "rep:2:4500" "rep:3:4500" "" "" "" "")
MNT_SRC=("Hilda the Stablemaster in Hearthmoor, 1500 gold" "Hilda, 6000 gold, from level 20"
         "Hilda, 4000 gold - for the Honored of the Sands of Kadar" "Hilda, 4000 gold - for the Honored of the Northern Clans"
         "the Valor Quartermaster, 1000 valor" "sometimes left behind by the Pale Rider"
         "a Mythic +15 in time - or 2500 valor" "sometimes left behind by Nyxara, Queen of the Eclipse")
NMNT=${#MNT_NAME[@]}

# --- the people of the endgame ----------------------------------------------------------------------------------
NPC45=${#M_NAME[@]}
n45() {  # x y role "Full Name" short glyph color emoji home
  local t=${#M_NAME[@]}
  M_NAME+=("$5") M_GLY+=("$6") M_COL+=("1;38;5;$7;$NPCBG") M_LVL+=(40) M_HP+=(2600) M_DMG+=(120)
  M_XP+=(300) M_GOLD+=(800) M_AGGRO+=(0) M_MOVE+=(900) M_ATK+=(1000) M_BOSS+=(0) M_KIND+=(1)
  MEMO_X[t]=$8 N_ROLE[$t]=$3 N_FULL[$t]=$4 N_HOME[$t]=$9
  NPC_SPAWNS+=("$t $1 $2 0")
}
n45 92 29 stable "Hilda the Stablemaster"        Hilda H 180 🧑 Hearthmoor
n45 68 29 valor  "Hale the Valor Quartermaster"  Hale  V 220 💂 Hearthmoor
n45 $(( 366 + 13 )) $(( 154 + 10 )) valor "Seren the Valor Quartermaster" Seren V 220 💂 Dawnspire
NM=${#M_NAME[@]}
# (the classifier runs once, after all creatures: 01g)
N_SAY+=([stable]="Every hero needs a good horse. Or a camel. Or a gryphon, if you can afford one.|Mind the hooves, love.|They're fed, brushed and ready to run."
        [valor]="Valor can't be bought with gold - only earned. Then you can spend it here.|Mythic keys, the Eclipse Throne, invasions: that is where valor comes from.|Godforged steel, for those who earned it.")

# --- valor: earned in mythic dungeons, the raid, invasions, dailies and weeklies --------------------------------------
VW_NAME=("Perfect gem (random)" "Godforged weapon, epic, 2 sockets" "Godforged armor, epic, 2 sockets"
         "Godforged helmet, epic, 2 sockets" "Godforged offhand, epic, 2 sockets" "Godforged trinket, epic, 2 sockets"
         "Godforged weapon, LEGENDARY, 3 sockets" "Storm Gryphon (mount)" "Ember Drake (mount)")
VW_COST=(400 600 600 450 450 450 1500 1000 2500)
VW_WHAT=(gem W A H O J LW m4 m6)

# --- dailies and weeklies (the same for everyone on the same day) -------------------------------------------------------
#   kind:need:text   (%R = a region of the new lands)
DLY_T=("kill:40:Slay 40 creatures in %R" "dung:1:Clear a level 30+ dungeon" "gath:15:Gather 15 ore or herbs"
       "fish:10:Catch 10 fish" "rare:1:Slay a rare elite" "champ:8:Slay 8 champions" "wboss:1:Defeat a world boss"
       "inv:1:Defend a town from an invasion" "myth:1:Complete a Mythic dungeon in time")
WKY_T=("mythn:4:Complete 4 Mythic dungeons" "raid:1:Defeat Nyxara, Queen of the Eclipse" "dungn:8:Clear 8 dungeons"
       "repn:4000:Earn 4000 reputation")
DLY_REG=(Duskwood "Sunken Kingdom" "Stormreach Peaks" "Gloomcap Hollows" Dragonspine Bonefields "Starfall Crater")

# --- achievements: name : what : title ("" = none) -------------------------------------------------------------------
ACH=("Seasoned:Reach level 20:" "Veteran:Reach level 30:the Veteran" "Legend:Reach level 40:the Legend"
     "Paragon:Reach paragon level 10:the Paragon" "Ascendant:Reach paragon level 50:the Ascendant"
     "Slayer:Slay 2000 creatures:the Slayer" "Exterminator:Slay 10000 creatures:the Exterminator"
     "Crownbearer:Finish the first act of the story:Crownbearer" "Starbreaker:Finish the story:Starbreaker"
     "Storyteller:Finish 10 questlines:the Storyteller" "Loremaster:Finish every questline:the Loremaster"
     "Delver:Clear 25 dungeons:" "Deep Delver:Clear 100 dungeons:the Delver"
     "Keystone:Complete a Mythic +5 in time:" "Mythic:Complete a Mythic +10 in time:the Mythic"
     "Timeless:Complete a Mythic +15 in time:the Timeless" "Unbound:Complete a Mythic +20 in time:the Unbound"
     "Eclipsebreaker:Defeat Nyxara, Queen of the Eclipse:Eclipsebreaker" "Eclipse Veteran:Defeat Nyxara 10 times:"
     "Exalted:Be exalted with a faction:the Exalted" "Friend of All:Be exalted with all eight factions:Friend of All"
     "Artisan:Reach 40 in a profession:" "Master Artisan:Reach 40 in all three professions:Master Artisan"
     "Rider:Own a mount:" "Stablemaster:Own all eight mounts:the Stablemaster"
     "Bounty Hunter:Slay 15 rare elites:Bounty Hunter" "Defender:Defend 5 towns from invasions:Defender of the Realm"
     "Daily Grind:Finish 50 dailies:" "Wanderer:Explore 80% of the world:the Wanderer"
     "Naturalist:Discover 200 kinds of creatures:the Naturalist" "Wealthy:Own 250000 gold:the Wealthy"
     "Gemcutter:Make a perfect gem:")
NACH=${#ACH[@]}

RUMORS+=("Hilda in Hearthmoor sells horses. A horse! In this economy! Ride with [z]."
         "When you are strong enough, any dungeon can be made mythic - harder, faster, richer. Valor buys the best gear there is."
         "Something dark sits on the eastern rim of Starfall Crater: the Eclipse Throne. Do not go alone."
         "Now and then the Horde marches on a town. Everyone who helps defend it is paid in valor.")

# ---------------------------------------------------------------------------
#  Module 01f - v5.0 data: housing (a room to rent at every inn, four sizes,
#  furniture) and collectables (item code C.<n>: 80 of them in six sets).
#  Pure data, appended to the tables before it (indexes never move).
# ---------------------------------------------------------------------------

# --- collectables ----------------------------------------------------------------------------------------
CS_NAME=("Dungeon Trophies" "Trophies of the Titans" "Curios of the Realm" "Angler's Treasures"
         "Prospector's Finds" "Relics of the Story")
CS_E=(🏆 👑 🔍 🎣 🔨 📜)
CS_HOW=("taken from the bosses of dungeons" "taken from world bosses" "found on the creatures of every land"
        "fished up from lakes, rivers and seas" "dug up while mining and picking herbs" "earned by following the story")
NCS=${#CS_NAME[@]}
CL_NAME=() CL_E=() CL_G=() CL_SET=() CL_RR=() CL_REF=() CL_FL=()
cl() {  # set rarity emoji ascii-glyph ref "Name" "flavor"
  CL_SET+=("$1") CL_RR+=("$2") CL_E+=("$3") CL_G+=("$4") CL_REF+=("$5") CL_NAME+=("$6") CL_FL+=("$7")
}
# 0: one trophy for the boss of every dungeon (ref = dungeon index)
cl 0 1 🏺 '&'  0 "Lich's Phylactery"              "Empty now. Shake it and something inside still whispers your name."
cl 0 1 💰 '$'  1 "Goblin King's Loot Sack"        "Mostly buttons, three teeth and a single gold coin. He loved it dearly."
cl 0 1 🪙 'o'  2 "Ancient Hoard Coin"             "From the bottom of a hoard that nobody ever counted to the end."
cl 0 1 🪲 'x'  3 "Golden Scarab of Anketh"        "Its legs still twitch when the moon is full."
cl 0 1 💙 '*'  4 "Frost Wyrm's Heart"             "Frozen solid, and still it beats once a winter."
cl 0 1 📯 'y'  5 "Horn of Azgor"                  "One blast and every imp within a mile stands to attention."
cl 0 2 🦪 'o'  6 "Ishara's Pearl"                 "Hold it to your ear: it hums the song of the deep."
cl 0 2 🌈 '*'  7 "Prism of the Archon"            "It turns candlelight into rainbows on your ceiling."
cl 0 2 🗿 'I'  8 "Jade Serpent Idol"              "Its eyes follow you around the room. Probably a trick of the light."
cl 0 2 🌋 '^'  9 "Living Lavastone"               "Warm to the touch. Do not leave it on the rug."
cl 0 2 🌑 'O' 10 "Crown of the Hollow King"       "Light falls into it and never comes back out."
cl 0 3 🪆 'i' 11 "Morwenna's Poppet"              "It looks a little like you. That is not a coincidence."
cl 0 3 🔔 'A' 12 "Bell of the Drowned Cathedral"  "It rings by itself at high tide, wherever you are."
cl 0 3 ⚡ 'z' 13 "Voltar's Bottled Storm"         "Your hair stands on end when you walk past it."
cl 0 3 🧫 'c' 14 "Culture of the Sporefather"     "Keep the lid on. Keep the lid ON."
cl 0 3 🥚 'e' 15 "Ember Tyrant's Egg"             "It is warm, and it is getting warmer."
cl 0 3 👑 'M' 16 "Crown of the Undying King"      "Heavy with a thousand years of refusing to die."
cl 0 3 💫 '*' 17 "Fragment of Azoth"              "A sliver of the star. It hums a note no instrument can play."
cl 0 3 🌗 'C' 18 "Shard of the Eclipse"           "Half of it is always night."
# 1: one trophy for every world boss (ref = index in WB_LIST)
cl 1 2 🪵 '='  0 "Heartwood of the Elder Treant"  "It still puts out a green leaf every spring."
cl 1 2 🐲 'S'  1 "Hydra's Ninth Head"             "The other eight grew back. This one sulks."
cl 1 2 🦏 'R'  2 "Behemoth's Horn"                "As long as your arm and twice as heavy."
cl 1 2 🏴 'F'  3 "Jolly Roger of the Corsair"     "The skull on it winks when nobody is looking."
cl 1 2 ⏳ 'X'  4 "Hourglass of the Sand Colossus" "The sand runs upwards. Nobody knows why."
cl 1 2 ⛄ 'Y'  5 "Ymir's Frozen Effigy"           "A tiny frost titan, carved by a very patient giant."
cl 1 2 🧡 'Q'  6 "Furnace Heart of the Juggernaut" "It glows orange and smells of hot iron."
cl 1 2 🦑 'K'  7 "Kraken Tentacle"                "Pickled. It still grabs at things."
cl 1 2 🔷 'D'  8 "Glacius' Frozen Eye"            "It sees in colors that have no names."
cl 1 2 🐢 'T'  9 "Titanback's Shell Shard"        "A whole village lived on this shell once."
cl 1 2 🪶 'f' 10 "Thunder Roc Feather"            "It crackles with static in dry weather."
cl 1 2 🔮 'V' 11 "Pearl of the Void Leviathan"    "Look inside, and something looks back."
cl 1 3 ⚓ 'J' 12 "Barnacled Anchor"               "The Drowned Colossus wore it as an earring."
cl 1 3 🎐 'W' 13 "Skyrender's Wind Chime"         "It plays storms instead of songs."
cl 1 3 🖤 'H' 14 "Vorgath's Cinder Heart"         "Black as ash, hot as the first day of the world."
cl 1 3 ⌛ 'P' 15 "The Pale Rider's Hourglass"     "When it runs out, turn it over. Always turn it over."
# 2: a curio for every land (ref = region name) - rarely found on its creatures
cl 2 1 🌰 'a' "Whisperwood"         "Whispering Acorn"            "Plant it and the tree will tell you secrets. In about two hundred years."
cl 2 1 🗻 'A' "Stormcrag Peaks"     "Miniature Stormcrag"         "A perfect little mountain with its own little clouds."
cl 2 1 🧦 's' "Stormcrag Foothills" "Troll's Lost Sock"           "Enormous, unwashed and somehow lonely."
cl 2 1 🐸 'f' "Mirefen Swamp"       "Golden Bog Frog"             "Kiss it at your own risk."
cl 2 1 🌕 'o' "Silverlake"          "Silverlake Moonstone"        "Fished out of the lake on a night with two moons."
cl 2 1 🐔 'c' "Greenfield Meadows"  "A Very Lost Chicken"         "Somebody in Hearthmoor has been looking for this one."
cl 2 1 🧭 'N' "Saltwind Coast"      "Smuggler's Compass"          "It points to the nearest tavern, not to the north."
cl 2 1 🦂 'x' "Sunscorch Desert"    "Scorpion in Amber"           "Caught mid-sting a thousand years ago. Still annoyed."
cl 2 1 🦣 'M' "Frostfang Tundra"    "Mammoth Ivory Carving"       "A hunting scene, carved by firelight in a long winter."
cl 2 1 🥀 'r' "Ashen Wastes"        "Cinder Rose"                 "It bloomed in the ash and never wilted. It never will."
cl 2 1 🐚 'e' "Sapphire Isles"      "Singing Sapphire Shell"      "It holds the sea. Every sea."
cl 2 1 🎶 'n' "Crystal Highlands"   "Chiming Crystal"             "Tap it and the whole room hums along."
cl 2 1 🐒 'm' "Emerald Jungle"      "Golden Monkey Idol"          "Every adventurer's dream. Watch out for rolling boulders."
cl 2 1 🌵 'Y' "Scorched Badlands"   "Potted Badlands Cactus"      "Water it once a year. Do not hug it."
cl 2 1 🎲 'd' "Void Rift"           "Die That Always Rolls Seven" "It has six sides. Do not ask how."
cl 2 2 🍂 'l' "Duskwood"            "Eternal Autumn Leaf"         "It fell in Duskwood and never stopped being autumn."
cl 2 2 🧩 'p' "Sunken Kingdom"      "Mosaic Tile of Ys"           "One piece of a picture of a drowned king, smiling."
cl 2 2 🪁 'k' "Stormreach Peaks"    "Storm Kite"                  "It flies by itself, even indoors. Especially indoors."
cl 2 2 🧸 'b' "Gloomcap Hollows"    "Sporeling Plushie"           "Soft, fuzzy and faintly glowing. Do not sniff it."
cl 2 2 🦴 'v' "Dragonspine"         "Dragonspine Vertebra"        "One bone of the mountain's spine. It is still warm."
cl 2 2 🦷 't' "Bonefields"          "Chattering Jaw"              "It chatters on cold nights. It has opinions."
cl 2 2 🌠 '*' "Starfall Crater"     "Meteorite Chip"              "It fell from the sky in the same night as the star itself."
# 3: what anglers pull out of the water now and then
cl 3 0 👢 'L' - "Old Boot"                  "Every angler catches one. Yours has a fish living in it."
cl 3 1 🍾 'i' - "Message in a Bottle"       "'If found, please return to...' - the rest is smudged."
cl 3 1 🦆 'd' - "Rubber Duck"               "Who loses a rubber duck in the open sea?"
cl 3 1 🔭 '/' - "Sailor's Spyglass"         "Everything looks closer and slightly wetter."
cl 3 2 🪞 'O' - "Mermaid's Mirror"          "Your reflection smiles a moment before you do."
cl 3 2 🔑 'k' - "Key to Davy's Locker"      "Whatever it opens is at the bottom of the sea."
cl 3 3 ⚫ 'o' - "Black Pearl"               "As dark as the deep and worth a small ship."
cl 3 3 🔱 'E' - "Tidecaller's Trident Head" "The tide comes in a little when you touch it."
# 4: what miners and herbalists find between the ore and the leaves
cl 4 0 🪨 'o' - "Lucky Pebble"              "Perfectly round and perfectly ordinary. Lucky anyway."
cl 4 1 🐌 '@' - "Fossilized Snail"          "Ten thousand years old and still slow."
cl 4 1 🍀 '%' - "Four-Leaf Clover"          "Found between the herbs and pressed between two pages."
cl 4 1 💮 '*' - "Pressed Moonflower"        "It only blooms at midnight, and only for a minute."
cl 4 2 🦟 'a' - "Amber with a Mosquito"     "Some say there is dragon blood in it."
cl 4 2 🦕 'S' - "Sauropod Fossil"           "A whole little skeleton, curled up in the rock."
cl 4 2 🥥 'G' - "Thunder Egg"               "A geode, not a coconut. Crack it open and it sparkles."
cl 4 3 💗 'H' - "Heart of the Mountain"     "A red crystal that pulses slowly, like something asleep."
# 5: the story gives one at every sixth chapter (ref = chapters done)
cl 5 2 🍺 'u'  6 "Old Tom's Tankard"         "'To the hero who listened to an old man's tale!'"
cl 5 2 💍 'q' 12 "Ser Kael's Signet Ring"    "The sign of an exiled knight, given to a friend."
cl 5 2 🫖 'w' 18 "Orwin's Bubbling Kettle"   "It brews tea without fire. And sometimes without tea."
cl 5 3 🏅 'W' 24 "The Crownbearer's Medal"   "Given by the five towns to the one who mended the crown."
cl 5 3 💌 'h' 30 "Sealed Dawnguard Letter"   "Never opened. Some letters are better kept."
cl 5 3 🚩 'B' 36 "Banner of the Dawn"        "Carried through the Bonefields and back again."
cl 5 3 🪐 'Z' 42 "Orrery of the Fallen Star" "The whole sky in brass - with one star missing."
COL_W=(50 30 15 5)                                    # pick weights per rarity
col_index() {  # (re)build what the cl lines imply: NCOL, sell values, sources, set lists, who drops what (v6.0 appends more)
  local i r t n
  NCOL=${#CL_NAME[@]} NCS=${#CS_NAME[@]} CL_VAL=() CL_SRC=() COL_SETL=() COL_BOSS=() COL_CUR=()
  for (( i = 0; i < NCOL; i++ )); do
    r=${CL_REF[i]}
    CL_VAL[i]=$(( ${CL_RR[i]} == 0 ? 80 : (${CL_RR[i]} == 1 ? 300 : (${CL_RR[i]} == 2 ? 1000 : 3500)) ))
    COL_SETL[CL_SET[i]]+="$i "
    case ${CL_SET[i]} in
      0) t=${D_BOSS[r]}; COL_BOSS[$t]=$i; n=${D_NAME[r]}; [[ $n == The\ * ]] || n="the $n"
         CL_SRC[i]="${M_NAME[t]}, the master of $n" ;;
      1) t=${WB_LIST[r]}; COL_BOSS[$t]=$i; CL_SRC[i]="${M_NAME[t]}, a world boss" ;;
      2) COL_CUR[$r]=$i; CL_SRC[i]="the creatures of the $r" ;;
      3) CL_SRC[i]="fishing, anywhere" ;;
      4) CL_SRC[i]="mining and herbalism, anywhere" ;;
      5) CL_SRC[i]="chapter $r of the story" ;;
      6) COL_BOSS[$r]=$i; CL_SRC[i]="${M_NAME[r]}, a rare elite (level ${M_LVL[r]})" ;;
    esac
  done
}
declare -A COL_BOSS=() COL_CUR=()                     # monster type -> trophy, region name -> curio
col_index

# --- housing: four rooms, rented at any inn (they all keep the same room for you) -----------------------------
ROOM_NAME=("" "Attic Room" "Guest Room" "Grand Suite" "Hero's Hall")
ROOM_LVL=(0 5 15 25 35)                 # level you need
ROOM_COST=(0 300 2500 12000 50000)      # to move in (moving up pays the difference)
ROOM_RENT=(0 60 300 1200 4000)          # every week (paid when you go up, from your purse or the vault)
ROOM_CAP=(0 20 35 50 70)                # room chest: items
ROOM_REST=(0 10 15 20 25)               # Well Rested: % more experience from kills
ROOM_DESC=("" "a slanted roof, a narrow bed and a window full of stars"
           "a real fireplace, a soft bed and room for a little collection"
           "two rooms in one, with velvet chairs and a view over the town"
           "the finest rooms the guild has: a hall for your legend")
# layouts: # wall  . floor  < the door  B bed  C chest  D display  K bookshelf (collection book)  G guestbook
#          F fireplace  P plant  T chair  L lantern  A banner
ROOM_LAY=(""
  '##############/#B..D....D..F#/#............#/#C..........K#/#............#/#P..D....D..G#/#............#/######<#######'
  '####################/#B.F....D..D..D...K#/#..................#/#C.................#/#....D........D....#/#P.......TT.......L#/#....D........D....#/#..................#/#P......D.....G...P#/#########<##########'
  '############################/#F...D...D...D...D...D....K#/#..........................#/#B.........................#/#...D......T..T.......D....#/#C.........................#/#...D...................D..#/#L.........................#/#...D.......A..A........D..#/#..........................#/#P....D....D....G....D....P#/#############<##############'
  '####################################/#F...D...D...D...D...D...D...D....K#/#..................................#/#B..............D..................#/#..................................#/#C...D......T..T......T..T......D..#/#..................................#/#L...D....A................A....D..#/#..................................#/#P...D......T..T......T..T......D..#/#..................................#/#L.................................#/#..D....D....D....G...D....D....D..#/#P................................P#/#################<##################')
ROOM_NDSP=()
for (( _i = 0; _i < ${#ROOM_LAY[@]}; _i++ )); do _r=${ROOM_LAY[_i]//[^D]/}; ROOM_NDSP[_i]=${#_r}; done; unset _i _r
NROOM=$(( ${#ROOM_NAME[@]} - 1 ))
declare -A FURN_E=([B]=🛌 [C]=📦 [D]=🔲 [F]=🔥 [P]=🪴 [K]=📚 [G]=📒 [T]=🪑 [L]=🏮 [A]=🚩)
declare -A FURN_G=([B]=B [C]='=' [D]=o [F]='*' [P]='&' [K]='%' [G]='?' [T]=h [L]=i [A]='!')
declare -A FURN_C=([B]="1;38;5;217" [C]="1;38;5;180" [D]="38;5;244" [F]="1;38;5;202" [P]="1;38;5;70" [K]="1;38;5;137"
                   [G]="1;38;5;229" [T]="38;5;137" [L]="1;38;5;220" [A]="1;38;5;160")
declare -A FURN_SAY=([F]="The fire crackles. You could sit here for hours."
                     [P]="A healthy plant. Somebody from the inn waters it while you are away."
                     [T]="A comfortable chair. It knows the shape of you by now."
                     [L]="The lantern burns low and warm."
                     [A]="A banner with your colors. The innkeeper had it stitched for you.")
RM_PED=239                              # the stone a display stands on (HD background)
REST_MS=1800000                         # Well Rested lasts 30 minutes

# --- achievements of the housing update -----------------------------------------------------------------
ACH50=${#ACH[@]}
ACH+=("Homeowner:Rent a room at an inn:" "Grand Host:Rent the Hero's Hall:the Host"
      "Collector:Discover 20 collectables:" "Curator:Discover 50 collectables:the Curator"
      "Master Collector:Discover every collectable:the Collector"
      "Trophy Hunter:Every dungeon trophy:the Trophy Hunter" "Titanslayer:Every trophy of the titans:the Titanslayer"
      "Curious:Every curio of the realm:the Curious" "Lucky Angler:Every angler's treasure:the Lucky"
      "Rockhound:Every prospector's find:the Rockhound" "Keeper of Tales:Every relic of the story:Keeper of Tales"
      "Exhibitor:Show 20 things in your room at once:" "Good Company:Five visitors signed your guestbook:the Hospitable")
NACH=${#ACH[@]}

RUMORS+=("Every inn has rooms upstairs - rent one and the whole guild keeps it for you, in every town."
         "Bosses sometimes leave a trophy behind. Put it on a display in your room and let your friends stare."
         "They say a chicken went missing in the Greenfield Meadows. Some say it went on an adventure."
         "Sleep in your own bed and you wake up Well Rested: more experience from every fight."
         "Fishermen pull up the strangest things. Boots, mostly. But not only boots.")

# ---------------------------------------------------------------------------
#  Module 01g - v6.0 data: more of everything. Two new creatures and a rare
#  elite for every land, four dungeons for the gaps (levels 2, 8, 16, 26),
#  four world bosses, eight townsfolk with eight questlines, twenty uniques,
#  two weapon kinds, six materials for levels 20-29 (ore, herbs, fish), and
#  54 collectables - among them a hunter's trophy for every rare elite.
#  Pure data, appended to the tables before it (indexes never move).
# ---------------------------------------------------------------------------
X60_EL=()                                                  # "type el weak resist ability range": set after the classifier ran
m6() {  # var name glyph color level hp% dmg% aggro move atk emoji  el weak resist ability range
  m4 "$1" "$2" "$3" "$4" "$5" 0 "$6" "$7" "$8" "$9" "${10}" "${11}"
  X60_EL+=("${!1} ${12} ${13} ${14} ${15:--} ${16:-0}")
}

# --- two new creatures for every land --------------------------------------------------------------------
#   var       name                 gly color          lvl  hp% dmg% ag move  atk  emoji  el wk rs ability rng
m6 G_HOG     "Thornhog"            h "38;5;137"         1  100  100  4  520 1100 🦔     0 1 -1 bleed
m6 G_BEETLE  "Meadow Beetle"       b "38;5;106"         2   90  100  3  640 1100 🪲     0 1 -1 -
m6 L_SNAP    "Lake Snapper"        s "38;5;65"          3  130  100  4  760 1300 🐢     2 1 2 -
m6 L_MOTH    "Silver Moth"         m "1;38;5;252"       2   70  100  5  380  900 🦋     6 0 6 -
m6 W_SPRITE  "Forest Sprite"       f "1;38;5;120"       4   70  100  6  400 1000 🧚     6 4 5 -     4
m6 W_BADGER  "Dire Badger"         B "38;5;245"         5  120  110  5  480 1100 🦡     0 1 -1 bleed
m6 M_LURK    "Bog Lurker"          L "38;5;64"          6  130  105  5  700 1300 🐊     3 1 3 poison
m6 M_HAG     "Marsh Hag"           H "1;38;5;101"       7   85  110  7  520 1200 🧙     3 1 3 weaken 5
m6 F_GNOLL   "Gnoll Raider"        g "38;5;179"         8  100  105  7  420 1000 🐕     0 1 -1 bleed
m6 F_GOLEM   "Boulder Golem"       G "38;5;250"         9  160  110  4  860 1600 🗿     0 6 0 stun
m6 P_LION    "Mountain Lion"       l "1;38;5;180"      11  100  110  8  330 1000 🦁     0 1 -1 bleed
m6 P_GRIF    "Griffon"             G "1;38;5;223"      12  110  105  8  340 1100 🦅     6 0 6 -
m6 S_GULL    "Giant Gull"          g "1;38;5;255"      10   80  100  8  320  900 🐦     0 1 -1 -
m6 S_CRAB    "Tide Crab"           c "1;38;5;209"      11  140  105  5  640 1300 🦀     2 1 2 chill
m6 D_VIPER   "Sand Viper"          v "38;5;178"        13   90  110  8  360 1000 🐍     3 1 3 poison
m6 D_DJINN   "Dust Djinn"          J "1;38;5;223"      15  100  110  8  420 1100 🧞     6 2 6 -     5
m6 T_LEOP    "Snow Leopard"        l "1;38;5;255"      16  100  110  8  320 1000 🐆     2 1 2 bleed
m6 T_REV     "Frost Revenant"      R "1;38;5;153"      18  120  110  6  560 1300 🧟     2 1 2 chill
m6 A_FIEND   "Cinder Fiend"        f "1;38;5;202"      19  100  110  7  420 1100 😈     1 2 1 burn
m6 A_BRUTE   "Obsidian Brute"      O "1;38;5;240"      20  160  110  5  760 1600 🗿     1 2 1 stun
m6 I_SHARK   "Reef Shark"          S "1;38;5;67"       21  110  110  7  380 1000 🦈     0 6 2 bleed
m6 I_SIREN   "Coral Siren"         s "1;38;5;210"      22   85  110  8  480 1200 🧜     2 1 2 chill 5
m6 C_BEETLE  "Shard Beetle"        b "1;38;5;147"      22  120  105  5  560 1200 🪲     6 0 6 -
m6 C_PRISM   "Prism Elemental"     P "1;38;5;159"      24  100  110  7  480 1100 💎     6 0 6 weaken 4
m6 J_PANTH   "Jungle Panther"      p "1;38;5;58"       23  100  110  9  300 1000 🐆     0 1 -1 bleed
m6 J_TOAD    "Venom Toad"          t "1;38;5;112"      24  110  105  6  560 1200 🐸     3 1 3 poison
m6 B_RATTLE  "Rattlesnake"         r "38;5;180"        25   90  110  8  360 1000 🐍     3 1 3 poison
m6 B_BISON   "Badlands Bison"      B "1;38;5;94"       26  170  110  5  640 1500 🦬     0 1 -1 stun
m6 R_STALK   "Rift Stalker"        s "1;38;5;99"       28  100  110  9  340 1000 👾     4 5 4 weaken
m6 R_HOUND   "Nightmare Hound"     h "1;38;5;54"       29  110  110  9  330 1000 🐕     4 5 4 bleed
m6 K_CROW    "Hollow Scarecrow"    S "1;38;5;172"      31  120  105  6  620 1300 🎃     4 1 3 weaken
m6 K_WEAVER  "Duskweaver Spider"   w "1;38;5;95"       32  100  110  8  380 1000 🐜     3 1 3 poison
m6 N_COURT   "Drowned Courtier"    C "1;38;5;73"       32  110  105  7  560 1200 🧟     4 5 3 weaken
m6 N_GOLEM   "Coral Golem"         G "1;38;5;210"      33  170  110  5  800 1600 🤖     2 1 2 stun
m6 Q_TBIRD   "Thunderbird"         T "1;38;5;229"      33  100  110  9  330 1000 🦅     6 0 6 stun  4
m6 Q_YETI    "Avalanche Yeti"      Y "1;38;5;255"      34  160  110  6  620 1500 ⛄     2 1 2 chill
m6 Y_MYCON   "Myconid Guard"       M "1;38;5;139"      34  140  105  6  640 1300 🍄     3 1 3 poison
m6 Y_MOTH    "Glowmoth"            m "1;38;5;228"      35   80  110  9  340  900 🦋     6 0 6 weaken 4
m6 V_HATCH   "Drake Hatchling"     d "1;38;5;208"      36   90  105  8  360 1000 🦎     1 2 1 burn
m6 V_WYVERN  "Flame Wyvern"        W "1;38;5;196"      37  130  110  8  380 1100 🐉     1 2 1 burn
m6 O_ARCHER  "Skeletal Archer"     a "1;38;5;252"      37   90  110  9  480 1100 💀     4 5 3 bleed 6
m6 O_VULT    "Carrion Vulture"     v "1;38;5;95"       38  100  110  9  320 1000 🦅     4 5 3 drain
m6 Z_WISP    "Starlit Wisp"        w "1;38;5;225"      39   80  115 10  360  900 💫     6 4 6 weaken 5
m6 Z_BEHEM   "Crater Behemoth"     B "1;38;5;177"      40  180  115  5  820 1700 🦏     6 4 6 stun
WORLD_TYPES+=($G_HOG $G_BEETLE $L_SNAP $L_MOTH $W_SPRITE $W_BADGER $M_LURK $M_HAG $F_GNOLL $F_GOLEM $P_LION $P_GRIF
              $S_GULL $S_CRAB $D_VIPER $D_DJINN $T_LEOP $T_REV $A_FIEND $A_BRUTE $I_SHARK $I_SIREN $C_BEETLE $C_PRISM
              $J_PANTH $J_TOAD $B_RATTLE $B_BISON $R_STALK $R_HOUND $K_CROW $K_WEAVER $N_COURT $N_GOLEM $Q_TBIRD $Q_YETI
              $Y_MYCON $Y_MOTH $V_HATCH $V_WYVERN $O_ARCHER $O_VULT $Z_WISP $Z_BEHEM)
ZONES+=("$G_HOG 64 43 100 60 5" "$G_BEETLE 64 43 100 60 5" "$L_SNAP 10 36 52 60 4" "$L_MOTH 10 36 52 60 4"
        "$W_SPRITE 4 4 68 28 4" "$W_BADGER 4 4 68 28 4" "$M_LURK 106 40 156 60 4" "$M_HAG 106 40 156 60 3"
        "$F_GNOLL 100 24 156 38 5" "$F_GOLEM 100 24 156 38 3" "$P_LION 104 3 156 23 4" "$P_GRIF 104 3 156 23 3"
        "$S_GULL 5 64 62 76 4" "$S_CRAB 5 64 62 76 4" "$D_VIPER 62 66 158 97 5" "$D_DJINN 62 66 158 97 3"
        "$T_LEOP 162 2 237 45 5" "$T_REV 162 2 237 45 4" "$A_FIEND 162 52 237 97 5" "$A_BRUTE 162 52 237 97 3"
        "$I_SHARK 5 100 115 148 4" "$I_SIREN 5 100 115 148 4" "$C_BEETLE 242 2 357 48 5" "$C_PRISM 242 2 357 48 4"
        "$J_PANTH 242 52 357 98 5" "$J_TOAD 242 52 357 98 5" "$B_RATTLE 122 101 236 147 5" "$B_BISON 122 101 236 147 4"
        "$R_STALK 243 102 357 147 5" "$R_HOUND 243 102 357 147 5" "$K_CROW 122 151 237 198 5" "$K_WEAVER 122 151 237 198 5"
        "$N_COURT 2 150 118 198 5" "$N_GOLEM 2 150 118 198 3" "$Q_TBIRD 362 2 477 47 5" "$Q_YETI 362 2 477 47 4"
        "$Y_MYCON 362 52 477 97 5" "$Y_MOTH 362 52 477 97 5" "$V_HATCH 362 102 477 147 6" "$V_WYVERN 362 102 477 147 4"
        "$O_ARCHER 242 152 357 197 5" "$O_VULT 242 152 357 197 4" "$Z_WISP 362 152 477 197 5" "$Z_BEHEM 362 152 477 197 3")
UNDEAD+="$T_REV $K_CROW $N_COURT $O_ARCHER "
QI_NAME+=([$G_HOG]="Thornhog Quill" [$G_BEETLE]="Beetle Shell" [$L_SNAP]="Snapper Shell" [$L_MOTH]="Silver Wing"
  [$W_SPRITE]="Sprite Dust" [$W_BADGER]="Badger Pelt" [$M_LURK]="Lurker Tooth" [$M_HAG]="Hag's Wart" [$F_GNOLL]="Gnoll Ear"
  [$F_GOLEM]="Golem Core" [$P_LION]="Lion Mane" [$P_GRIF]="Griffon Feather" [$S_GULL]="Gull Egg" [$S_CRAB]="Crab Claw"
  [$D_VIPER]="Viper Fang" [$D_DJINN]="Djinn Lamp" [$T_LEOP]="Leopard Pelt" [$T_REV]="Frozen Heart" [$A_FIEND]="Cinder Horn"
  [$A_BRUTE]="Obsidian Shard" [$I_SHARK]="Shark Tooth" [$I_SIREN]="Siren Scale" [$C_BEETLE]="Shard Carapace"
  [$C_PRISM]="Prism Core" [$J_PANTH]="Panther Claw" [$J_TOAD]="Toad Venom" [$B_RATTLE]="Rattle" [$B_BISON]="Bison Horn"
  [$R_STALK]="Rift Eye" [$R_HOUND]="Nightmare Fang" [$K_CROW]="Scarecrow Hat" [$K_WEAVER]="Dusk Silk" [$N_COURT]="Courtly Ring"
  [$N_GOLEM]="Living Coral" [$Q_TBIRD]="Thunder Plume" [$Q_YETI]="Yeti Fur" [$Y_MYCON]="Myconid Cap" [$Y_MOTH]="Glowing Dust"
  [$V_HATCH]="Hatchling Scale" [$V_WYVERN]="Wyvern Fang" [$O_ARCHER]="Bone Arrow" [$O_VULT]="Vulture Feather"
  [$Z_WISP]="Star Mote" [$Z_BEHEM]="Crater Horn")

# --- four dungeons for the gaps: levels 2, 8, 16 and 26 ----------------------------------------------------
#   var       name                          gly color                   lvl boss hp%  dmg% ag move atk  emoji
m4 E_MATRIA  "Plague Rat Matriarch"         R "1;38;5;180;48;5;58"     3 2  420 120  8 560 1200 🐀
m4 B_RATKING "Rattigan the Rat King"        K "1;38;5;231;48;5;94"     4 1 1500 115  9 560 1200 🐀
m4 E_ENFORC  "Red Hand Enforcer"            E "1;38;5;196;48;5;52"     9 2  400 120  9 480 1100 🤠
m4 B_ROURKE  "Rourke Red-Hand"              R "1;38;5;231;48;5;88"    10 1 1500 118 10 480 1100 🤠
m4 E_HUSCARL "Rimebound Huscarl"            H "1;38;5;153;48;5;24"    17 2  420 120  9 560 1300 🧟
m4 B_HRIM    "Queen Hrimgard"               Q "1;38;5;231;48;5;25"    18 1 1700 118 10 600 1200 👸
m4 E_SLAG    "Slag Golem"                   G "1;38;5;208;48;5;52"    27 2  460 120  9 760 1500 🤖
m4 B_GORRAK  "Foreman Gorrak the Molten"    G "1;38;5;231;48;5;130"   28 1 1800 120 10 600 1300 👹
X60_EL+=("$E_HUSCARL 2 1 2 chill 0" "$B_HRIM 2 1 2 chill 5" "$E_SLAG 1 2 1 stun 0" "$B_GORRAK 1 2 1 burn 0" "$E_ENFORC 0 1 -1 bleed 0"
         "$B_ROURKE 0 1 -1 bleed 0" "$E_MATRIA 3 1 3 poison 0" "$B_RATKING 3 1 3 poison 0")
D60=$NDT
D_NAME+=("Cellar of the Old Mill" "Red Hand Hideout" "Hrimgard's Tomb" "The Cinderdeep Mine")
D_REQ+=(2 8 16 26)
D_POOL+=("0 1 $G_HOG $G_BEETLE" "6 $F_GNOLL $F_GOLEM $X_OGRE" "35 36 $T_LEOP $T_REV" "$X_LIZARD $B_RATTLE $B_BISON $B_RATTLE")
D_BOSS+=($B_RATKING $B_ROURKE $B_HRIM $B_GORRAK) D_ELITE+=($E_MATRIA $E_ENFORC $E_HUSCARL $E_SLAG)
D_ENTX+=(25 138 175 176) D_ENTY+=(57 26 20 139)
D_WHERE+=("Silverlake, by the old mill on the western shore" "Stormcrag Foothills, north of Ironwood Camp"
          "Frostfang Tundra, west of Frosthold" "Scorched Badlands, south of Redrock Outpost")
D_WALL+=("38;5;137" "38;5;124" "38;5;153" "38;5;130") D_FLOOR+=("38;5;94" "38;5;52" "38;5;24" "38;5;236")
D_WE_X+=(🟫 🟥 🟦 ⬛) D_W+=(60 76 84 104) D_H+=(24 28 32 36) D_ROOMS+=(8 10 12 14) D_CHESTS+=(2 2 3 3)
NDT=${#D_NAME[@]}

# --- four world bosses for the gaps ----------------------------------------------------------------------
m4 W_GRUMB   "Old Grumblegut"               G "1;38;5;231;48;5;64"     4 w 1800 105  8 800 1500 🐸
m4 W_GORE    "Gorehorn the Mammoth"         M "1;38;5;231;48;5;67"    17 w 2000 110 10 700 1500 🦣
m4 W_VESPER  "Vesper the Jade Panther"      V "1;38;5;231;48;5;22"    23 w 1900 112 10 380 1000 🐆
m4 W_RUIN    "Ruin, the Star Devourer"      R "1;38;5;16;48;5;177"    40 w 2400 118 10 600 1200 🐙
X60_EL+=("$W_GRUMB 3 1 3 poison 0" "$W_GORE 2 1 2 stun 0" "$W_VESPER 3 1 3 bleed 0" "$W_RUIN 4 5 4 weaken 5")
WB60=${#WB_LIST[@]}
WB_LIST+=($W_GRUMB $W_GORE $W_VESPER $W_RUIN)
WB_RECT+=("10 36 52 60" "162 2 237 45" "242 52 357 98" "362 152 477 197")
WB_ADDS+=("$X_LEECH $X_LEECH $L_SNAP" "35 35 $T_LEOP" "$J_PANTH $J_PANTH $J_TOAD" "$SF_SPAWN $SF_SPAWN $SF_HORROR")

# --- a rare elite for every land ------------------------------------------------------------------------------
R60=${#M_NAME[@]}
add_rares "Big Bertha:$G_HOG:4:79:57" "Old Snapjaw:$L_SNAP:5:25:57" "The Grey Badger:$W_BADGER:7:46:28" \
          "Granny Mirewart:$M_HAG:9:124:57" "Gnasher Skullsplitter:$F_GNOLL:10:138:26" "Silvermane:$P_LION:13:141:18" \
          "King Crab:$S_CRAB:12:31:70" "The Sultan of Sand:$D_DJINN:16:83:83" "Whitefang the Elder:$T_LEOP:18:175:20" \
          "Pyreheart:$A_FIEND:21:199:87" "Mother of Sharks:$I_SHARK:23:90:111" "The Living Prism:$C_PRISM:25:308:45" \
          "Shadowmaw:$J_PANTH:26:273:78" "Old Thunderhide:$B_BISON:27:176:139" "The Unmaker:$R_STALK:30:305:124" \
          "The Pumpkin King:$K_CROW:33:205:166" "Lady Brine:$N_COURT:34:32:188" "Stormcrown:$Q_TBIRD:35:419:6" \
          "Grandfather Glowcap:$Y_MYCON:36:430:53" "Cinderwing:$V_WYVERN:38:424:143" "The Hollow Archer:$O_ARCHER:39:297:193" \
          "The Devourer's Eye:$Z_BEHEM:40:418:172"
NRARE=${#RARE_T[@]}
NM=${#M_NAME[@]}

# --- elements: the old classifier names the old creatures, then the new ones get theirs (and their rares too) ---
classify_monsters; classify4                                # (the only run: 01d and 01e leave it to this one)
declare -A _new=()
for _e in "${X60_EL[@]}"; do
  read -r _t _a _b _c _d _f <<< "$_e"; _new[$_t]=1
  M_EL[_t]=$_a M_WK[_t]=$_b M_RS[_t]=$_c M_AB[_t]=${_d/-/} M_RNG[_t]=$_f
done
for _t in "${RARE_T[@]}"; do
  _b=${RARE_BASE[$_t]}; [[ -n ${_new[$_b]} ]] || continue
  M_EL[_t]=${M_EL[_b]} M_WK[_t]=${M_WK[_b]} M_RS[_t]=${M_RS[_b]} M_AB[_t]=${M_AB[_b]} M_RNG[_t]=${M_RNG[_b]}
done
unset _e _t _a _b _c _d _f _new

# --- six materials for levels 20-29 (54-59), and their nodes --------------------------------------------------
M60=${#MAT_NAME[@]}
MAT_NAME+=("Cobalt Ore" "Adamantite Ore" "Sungrass" "Nightshade" "Reef Snapper" "Glacier Char")
MAT_VAL+=(40 52 36 48 42 55) MAT_RARE+=(0 1 0 1 0 1)
NMAT=${#MAT_NAME[@]}
MAT_PK+=(1 1 2 2 0 0)
MAT_GRP[1]+="$M60 $(( M60 + 1 )) " MAT_GRP[2]+="$(( M60 + 2 )) $(( M60 + 3 )) " MAT_GRP[0]+="$(( M60 + 4 )) $(( M60 + 5 )) "
N60=${#M_NAME[@]}
M_NAME+=("Cobalt Vein" "Adamantite Vein" "Sungrass" "Nightshade") M_GLY+=(◆ ◆ ♣ ♣)
M_COL+=("1;38;5;27" "1;38;5;135" "1;38;5;220" "1;38;5;91")
M_LVL+=(22 26 22 26) M_HP+=(3 3 3 3) M_DMG+=(0 0 0 0) M_XP+=(34 38 34 38) M_GOLD+=(0 0 0 0)
M_AGGRO+=(0 0 0 0) M_MOVE+=(900 900 900 900) M_ATK+=(1000 1000 1000 1000) M_BOSS+=(0 0 0 0) M_KIND+=(3 3 3 3)
MEMO_X[N60]=🔵 MEMO_X[N60+1]=🟣 MEMO_X[N60+2]=🌾 MEMO_X[N60+3]=🍇
for (( _i = 0; _i < 4; _i++ )); do
  NODE_MAT[$(( N60 + _i ))]=$(( M60 + _i )) NODE_PK[$(( N60 + _i ))]=$(( _i < 2 ? 1 : 2 )); NODE_T+=($(( N60 + _i )))
  M_EL[N60+_i]=0 M_WK[N60+_i]=-1 M_RS[N60+_i]=-1 M_AB[N60+_i]="" M_RNG[N60+_i]=0 M_HEALR[N60+_i]=0 M_SUMM[N60+_i]=0
done; unset _i
NM=${#M_NAME[@]}
ZONES+=("$N60 242 2 357 48 6" "$N60 5 100 115 148 3" "$(( N60 + 1 )) 122 101 236 147 6" "$(( N60 + 1 )) 243 102 357 147 4"
        "$(( N60 + 2 )) 242 52 357 98 6" "$(( N60 + 2 )) 5 100 115 148 3" "$(( N60 + 3 )) 243 102 357 147 5" "$(( N60 + 3 )) 122 101 236 147 3")
FISHW[sea]+=" $(( M60 + 4 )):20:0" FISHW[ice]+=" $(( M60 + 5 )):24:1" FISHW[lava]+=" $(( M60 + 5 )):26:1"
FORGE_X=("8:$M60:6 5:2" "9:$(( M60 + 1 )):6 $M60:3")      # the forge: tiers 8 and 9 without waiting for level 30
ALCH_X=("gh3:3x Greater health potion:$(( M60 + 2 )):2 6:1" "gm3:3x Greater mana potion:$(( M60 + 3 )):2 7:1"
        "swift:Elixir of Swiftness:$(( M60 + 2 )):1 $(( M60 + 3 )):1")

# --- two weapon kinds (30, 31) ------------------------------------------------------------------------------
WK_NAME+=("Hand Cannon" Runestone) WK_E+=(🔫 🪨) WK_CLS+=(24 168) WK_DMG+=(114 104) WK_BT+=(crit mp) WK_BV+=(4 12)

# --- eight townsfolk, each with work and a questline ---------------------------------------------------------
NPC60=${#M_NAME[@]}
#     x   y  role        "Full Name"                short   gly color emoji home
n45  73  29 questgiver  "Farmer Hesk"               Hesk     H 150 👨 Hearthmoor
n45 117  36 questgiver  "Warden Brannoc"            Brannoc  B 108 💂 "Ironwood Camp"
n45 108  78 questgiver  "Sheikha Amira"             Amira    A 222 👳 "Oasis of Kadar"
n45 196  17 questgiver  "Skald Ragna"               Ragna    R 153 👱 Frosthold
n45  52 116 questgiver  "Admiral Vane"              Vane     V  75 🧔 "Port Coral"
n45 298  17 questgiver  "Gemcutter Pell"            Pell     P 147 🧐 Shardhaven
n45 302  67 questgiver  "Elder Moku"                Moku     M  71 👴 "Jadeleaf Village"
n45 183 111 questgiver  "Prospector Dusty"          Dusty    D 180 🤠 "Redrock Outpost"
for (( _i = 0; _i < 8; _i++ )); do                         # (townsfolk are no monsters - the classifier never saw them)
  _t=$(( NPC60 + _i )); M_LVL[_t]=$(( 5 + _i * 3 )) M_EL[_t]=0 M_WK[_t]=-1 M_RS[_t]=-1 M_AB[_t]="" M_RNG[_t]=0 M_HEALR[_t]=0 M_SUMM[_t]=0
done; unset _i _t
Q_HESK=$NPC60 Q_BRAN=$(( NPC60 + 1 )) Q_AMIRA=$(( NPC60 + 2 )) Q_RAGNA=$(( NPC60 + 3 ))
Q_VANE=$(( NPC60 + 4 )) Q_PELL=$(( NPC60 + 5 )) Q_MOKU=$(( NPC60 + 6 )) Q_DUSTY=$(( NPC60 + 7 ))
NM=${#M_NAME[@]}
N_QK+=([$Q_HESK]="$G_HOG $G_BEETLE $L_SNAP $L_MOTH" [$Q_BRAN]="$F_GNOLL $F_GOLEM $P_LION $P_GRIF"
       [$Q_AMIRA]="$D_VIPER $D_DJINN $S_GULL $S_CRAB" [$Q_RAGNA]="$T_LEOP $T_REV $A_FIEND $A_BRUTE"
       [$Q_VANE]="$I_SHARK $I_SIREN" [$Q_PELL]="$C_BEETLE $C_PRISM" [$Q_MOKU]="$J_PANTH $J_TOAD" [$Q_DUSTY]="$B_RATTLE $B_BISON $R_STALK $R_HOUND")
N_QD+=([$Q_HESK]=$D60 [$Q_BRAN]=$(( D60 + 1 )) [$Q_RAGNA]=$(( D60 + 2 )) [$Q_DUSTY]=$(( D60 + 3 )))
N_QT+=([$Q_HESK]=$Q_BRAN [$Q_BRAN]=$Q_AMIRA [$Q_AMIRA]=$Q_RAGNA [$Q_RAGNA]=$Q_VANE [$Q_VANE]=$Q_PELL [$Q_PELL]=$Q_MOKU
       [$Q_MOKU]=$Q_DUSTY [$Q_DUSTY]=$Q_HESK)

# --- uniques 46-65 ------------------------------------------------------------------------------------------------
U60=$NUQ
U_NAME+=("Rattigan's Crown" "Squeaky Shiv" "Red Hand Cutlass" "Bandit King's Bandana" "Hrimgard's Frostcrown" "Rimeheart Plate"
         "Gorrak's Slag Hammer" "Cinderdeep Lantern" "Grumblegut's Toadstool Ring" "Gorehorn Tusk Axe" "Vesper's Shadow Fang"
         "Eye of Ruin" "Hesk's Lucky Pitchfork" "Warden's Oath" "Lamp of the Djinn" "Saga of the Frost Queen"
         "Admiral's Spyglass" "Prismheart" "Jade Fever Fetish" "Dusty's Lucky Pickaxe")
U_SLOT+=(H W W H H A  W O J W W J  W O O O  J J O W)
U_KIND+=(3 5 0 4 3 3  2 3 0 1 5 1  4 0 3 1  2 1 6 1)
U_TIER+=(2 2 4 4 7 7  9 9 2 7 8 12  2 4 5 6  7 8 8 9)
U_BT+=(crit crit crit crit mp hp  hp light hp crit crit dmg  hp arm mp mp  crit mp dmg crit)
U_FL+=("It is made of bottle caps and it is magnificent." "It squeaks when it stabs. It always stabs."
       "Every notch on the blade is a stolen purse." "Smells of campfire and other people's gold."
       "Snowflakes never melt on it." "Cold enough to keep your heart from racing."
       "Still glowing from the deep furnaces." "Its flame has burned for a hundred years underground."
       "Covered in tiny mushrooms. They are friendly." "The mammoth wanted it back. It did not get it back."
       "Bite marks and all." "It saw the stars being eaten. It remembers."
       "Three prongs, three wishes, all for a good harvest." "The oath is carved on the inside: hold the line."
       "Rub it and something sighs inside." "Every page tells of a winter that never ended."
       "Spots a ship on the horizon - or a shark." "A crystal that breaks the light into every color of courage."
       "Smells of the jungle and of fever dreams." "It has found more gold than any map.")
NUQ=${#U_NAME[@]}
U_DROP+=("$B_RATKING:$U60:30" "$B_RATKING:$(( U60 + 1 )):30" "$B_ROURKE:$(( U60 + 2 )):25" "$B_ROURKE:$(( U60 + 3 )):25"
         "$B_HRIM:$(( U60 + 4 )):25" "$B_HRIM:$(( U60 + 5 )):25" "$B_GORRAK:$(( U60 + 6 )):25" "$B_GORRAK:$(( U60 + 7 )):25"
         "$W_GRUMB:$(( U60 + 8 )):25" "$W_GORE:$(( U60 + 9 )):25" "$W_VESPER:$(( U60 + 10 )):25" "$W_RUIN:$(( U60 + 11 )):25")

# --- scouting spots for the questlines ----------------------------------------------------------------------
SP60=${#SPT_NAME[@]}
for _s in "the Old Scarecrow Field:88:52" "the Burned Wagon:126:30" "the Whispering Dune:96:88" "Hrimgard's Cairn:184:12" \
          "the Siren Rocks:80:128" "the Prism Falls:320:31" "the Fever Pools:284:88" "Dead Man's Gulch:160:132"; do
  IFS=: read -r _n _x _y <<< "$_s"; SPT_NAME+=("$_n") SPT_X+=("$_x") SPT_Y+=("$_y")
done; unset _s _n _x _y
NSPOT=${#SPT_NAME[@]}

# --- eight questlines ----------------------------------------------------------------------------------------------
_r6() { printf -v "$1" '%d' "$(( R60 + $2 ))"; }           # rare n of v6.0
_r6 RR_BERTHA 0; _r6 RR_GNASH 4; _r6 RR_SULTAN 7; _r6 RR_WHITE 8; _r6 RR_SHARKS 10; _r6 RR_PRISM 11; _r6 RR_SHADOW 12; _r6 RR_THUNDER 13
ql_add "The Mill Rats" "$Q_HESK" 0 2
qs_add K.$G_HOG.6 "Thornhogs dig up my turnips every night. Six of them, and I might have a harvest this year." \
  "The field is quiet. But the hogs were running FROM something, west of here." 150
qs_add E.$SP60 "My old scarecrow field has been strange lately. Things move there at night. Have a look, will you?" \
  "Somebody has been sleeping in the scarecrow. Somebody small, with a tail." 150
qs_add C.$G_BEETLE.5 "The beetles have eaten half my grain. Bring me five shells - my wife makes buttons out of them." \
  "Fine buttons! The beetles came from the old mill on the lake, by the look of the mud." 200
qs_add D.$D60 "The Cellar of the Old Mill, on the western shore of Silverlake. Rats as big as dogs, they say, and a king among them. Clear it out." \
  "Rattigan the Rat King is no more. The cellar smells better already. A little." 300
qs_add B.$RR_BERTHA "One more: Big Bertha, the biggest thornhog in the meadows, south of my farm. She ate my fence. The whole fence." \
  "Big Bertha topples like a hay bale. Hesk wipes a tear. 'She was a good pig, in her way.'" 300 \
  "Hesk offers you his grandfather's pitchfork - or a share of the harvest money." \
  "Take the Lucky Pitchfork|Take the harvest money" \
  "uq:$(( U60 + 12 )),rep:0:300|gold:400,rep:0:600,pot:3" \
  "'It never missed a turnip,' Hesk says proudly.|Hesk counts the coins twice. 'Worth every one.'"
ql_add "The Red Hand" "$Q_BRAN" 1 8
qs_add K.$F_GNOLL.8 "Gnoll raiders on the north road, eight of them at least. Thin them out before the next caravan." \
  "The road is quieter. The gnolls wore red handprints on their shields." 300
qs_add E.$(( SP60 + 1 )) "A wagon burned north-west of camp last night. Find it - and anything that tells us who did it." \
  "The wagon is ash. A red hand is painted on a rock nearby, still wet." 300
qs_add C.$F_GOLEM.5 "The bandits use boulder golems as guards. Bring me five golem cores - Garrick can sell them to the mages." \
  "Five cores, humming softly. Garrick will be delighted." 350
qs_add D.$(( D60 + 1 )) "The Red Hand Hideout is north of camp in the foothills. Rourke Red-Hand leads them. End it." \
  "Rourke Red-Hand falls. The Red Hand is just a hand now." 450
qs_add B.$RR_GNASH "Gnasher Skullsplitter guards the hideout's door and he's still out there. Bring me his skull. Or at least proof." \
  "Gnasher howls one last time and falls. Brannoc takes off his helmet in respect - for a moment." 500 \
  "Brannoc offers you his old shield, or a word for you with the Frontier Wardens." \
  "Take the Warden's Oath|Take the Wardens' thanks" \
  "uq:$(( U60 + 13 )),rep:1:400|rep:1:1000,gold:800" \
  "'Hold the line,' he says, and hands it over.|'The Wardens will remember your name,' Brannoc says."
ql_add "Winds of the Djinn" "$Q_AMIRA" 2 13
qs_add K.$D_VIPER.8 "Sand vipers nest in the well paths. Eight of them, before another child gets bitten." \
  "The wells are safe again. The vipers fled from the dunes in the south." 350
qs_add E.$(( SP60 + 2 )) "The dunes south of the oasis whisper at night. My grandmother said they whisper when a djinn is angry. Listen." \
  "You hear it too: a voice in the wind, laughing." 350
qs_add C.$D_DJINN.5 "Dust djinn carry little lamps. Bring me five - we will learn whose they are." \
  "Every lamp bears the same seal: the Sultan of Sand." 400
qs_add T.47 "Nadia the spice trader has traded with djinn for years. Show her the seal." \
  "Nadia whistles. 'The Sultan. He was imprisoned in a lamp for a thousand years. Someone let him out.'" 400
qs_add B.$RR_SULTAN "The Sultan of Sand rides the storms south of the oasis. Put him back - one way or another." \
  "The Sultan dissolves into a sigh of sand. His lamp lies in the dune, warm and empty." 600 \
  "The empty lamp: keep it, or let Amira seal it in the oasis well forever?" \
  "Keep the Lamp of the Djinn|Seal it in the well" \
  "uq:$(( U60 + 14 )),rep:2:300|rep:2:1200,gold:900" \
  "The lamp hums softly in your hand.|The well water tastes sweeter ever since."
ql_add "The Frost Queen's Saga" "$Q_RAGNA" 3 16
qs_add K.$T_LEOP.8 "Snow leopards stalk our hunters. Eight of them, and I will sing your name tonight." \
  "Ragna sings. It is a very long song, and you are in all of it." 400
qs_add C.$T_REV.6 "Frost revenants rise from the old queen's tomb. Bring me six of their frozen hearts - we burn them in the longhouse." \
  "The hearts hiss in the fire. In the steam you see a crowned woman, weeping ice." 450
qs_add E.$(( SP60 + 3 )) "Hrimgard's Cairn stands north-west of Frosthold. The saga says the queen's crown was buried there. Is it still?" \
  "The cairn is open. Footprints lead west - towards the tomb." 450
qs_add D.$(( D60 + 2 )) "Hrimgard's Tomb lies west of Frosthold. The Frost Queen has woken. Put her back to sleep." \
  "Queen Hrimgard falls, and the long winter of the saga is finally over." 600
qs_add B.$RR_WHITE "Whitefang the Elder, the oldest leopard of the tundra, guarded the queen's tomb. He prowls there still." \
  "Whitefang lies down in the snow, almost gently. Ragna writes the last verse." 600 \
  "Ragna offers you the saga itself, bound in leather - or a place in the Northern Clans' songs." \
  "Take the Saga of the Frost Queen|Be sung by the clans" \
  "uq:$(( U60 + 15 )),rep:3:300|rep:3:1200,gem:2" \
  "Every page smells of snow.|They sing it in Frosthold to this day."
ql_add "Siren Song" "$Q_VANE" 4 21
qs_add K.$I_SHARK.8 "Reef sharks have taken three of my sailors this month. Eight of them for the navy." \
  "The water is safer. The sharks were following the sound of singing." 500
qs_add E.$(( SP60 + 4 )) "The Siren Rocks lie south-east of Port Coral. Ships wreck there every week. See what sings." \
  "On the rocks: broken masts, and a voice so beautiful you nearly walk into the sea." 500
qs_add C.$I_SIREN.6 "Siren scales, six of them. Wax will not stop the song - but sirens fear their own scales." \
  "The scales shimmer and hum. Vane nails one above every ship's door." 550
qs_add T.124 "Rosa of the Rum House was a siren hunter once. Ask her what calls the sirens together." \
  "Rosa goes pale. 'Only one thing: the Mother of Sharks. She feeds the sirens, and they feed her.'" 550
qs_add B.$RR_SHARKS "The Mother of Sharks hunts off the eastern shore of the isles. End her, Admiral's orders." \
  "The Mother of Sharks sinks into the deep. That night, nobody sings on the Siren Rocks." 700 \
  "Vane offers you his own spyglass - or a captain's share of the navy's reward." \
  "Take the Admiral's Spyglass|Take the captain's share" \
  "uq:$(( U60 + 16 )),rep:4:300|rep:4:1200,gold:1500" \
  "'Keep an eye on the horizon,' Vane grins.|Vane salutes you. So does the whole harbor."
ql_add "Fractured Light" "$Q_PELL" 3 22
qs_add K.$C_BEETLE.8 "Shard beetles gnaw the crystals off my cliffs. Eight of them, if you please." \
  "The cliffs ring clear again. But the light in them is broken." 500
qs_add G.$M60.4 "I need cobalt to mend the broken light. Four pieces of cobalt ore - the veins glitter in these highlands." \
  "Cobalt! Pell grinds it into a fine blue dust and blows it into the light. It flickers." 500
qs_add E.$(( SP60 + 5 )) "The Prism Falls, east of Shardhaven: the light breaks there first. Find out why." \
  "At the falls the rainbows are wrong - they bend towards something in the crystal." 550
qs_add C.$C_PRISM.6 "Prism elementals carry pieces of the broken light. Six prism cores, and I can read it." \
  "Pell reads the cores and frowns. 'Something is alive in the crystal. Something made of light.'" 550
qs_add B.$RR_PRISM "The Living Prism wanders the highlands, east of here. It is breaking all the light. Stop it." \
  "The Living Prism shatters into a thousand colors - and the light in the cliffs heals." 700 \
  "Pell offers you the heart of the Prism - or to cut gems for you." \
  "Take the Prismheart|Have gems cut for you" \
  "uq:$(( U60 + 17 )),rep:3:300|gem:3,rep:3:800" \
  "It throws a little rainbow wherever you go.|Pell's gems are the finest in the highlands."
ql_add "The Jade Fever" "$Q_MOKU" 4 22
qs_add K.$J_TOAD.8 "Venom toads poison our streams. Eight of them, and the children can drink again." \
  "The streams clear. But the fever in the village does not." 500
qs_add G.$(( M60 + 2 )).5 "The fever needs sungrass. Five bundles - it grows in the clearings of the jungle." \
  "Moku brews the sungrass into a bitter tea. The children sleep, at last." 500
qs_add C.$J_PANTH.6 "The fever came with the panthers. Their claws are poisoned. Bring me six - I will make the cure." \
  "The claws are black with something that is not poison. Something older." 550
qs_add E.$(( SP60 + 6 )) "The Fever Pools, east of the village. The panthers drink there. Find out what is in the water." \
  "In the pools: a shadow with green eyes, watching you, and gone." 550
qs_add B.$RR_SHADOW "Shadowmaw, the panther of the pools. The fever is his. End it." \
  "Shadowmaw's eyes go dark. In the village, the fever breaks." 700 \
  "Moku offers you his old fetish - or the blessing of the village." \
  "Take the Jade Fever Fetish|Take the village's blessing" \
  "uq:$(( U60 + 18 )),rep:4:300|rep:4:1200,pot:5" \
  "It rattles softly when danger is near.|The village names a well after you."
ql_add "Cinderdeep" "$Q_DUSTY" 2 24
qs_add K.$B_RATTLE.8 "Rattlesnakes in my claim, eight of them. Get 'em out before I lose another mule." \
  "The claim is quiet. Too quiet. Dusty swears the ground is warm." 600
qs_add C.$B_BISON.6 "Bison horns, six of 'em. Best digging tools in the badlands - and I've got digging to do." \
  "Dusty fits the horns to his picks. 'Now we're mining.'" 600
qs_add E.$(( SP60 + 7 )) "Dead Man's Gulch, west of here. The old Cinderdeep crew went in there and never came back. Look around." \
  "In the gulch: tools, lanterns, and footprints leading south into a mine shaft that glows." 650
qs_add D.$(( D60 + 3 )) "The Cinderdeep Mine, south of Redrock. Foreman Gorrak still runs it - he just isn't alive anymore. Fire him." \
  "Foreman Gorrak melts into his own slag. The furnaces of Cinderdeep go cold." 800
qs_add B.$RR_THUNDER "Old Thunderhide, the biggest bison you ever saw, guards the mine road. He trampled my wagon. Twice." \
  "Old Thunderhide falls like a landslide. Dusty throws his hat in the air." 800 \
  "Dusty offers you his lucky pickaxe - or a share in the Cinderdeep claim." \
  "Take Dusty's Lucky Pickaxe|Take a share in the claim" \
  "uq:$(( U60 + 19 )),rep:2:300|gold:2500,rep:2:600" \
  "'Found my first nugget with that,' Dusty says.|'Partners!' Dusty shakes your hand until it hurts."
unset -f _r6
NQL=${#QL_NAME[@]}

# --- collectables: trophies of the new bosses and a hunter's trophy for every rare elite ---------------------------
#   (set 6: name and story come from the rare itself; the sprite is its kind's, filled in once the sprites exist)
cl 0 1 🧀 'q' $D60         "Rattigan's Cheese Throne"   "A throne carved from a single wheel of cheese. Half eaten."
cl 0 1 ✋ 'H' $(( D60 + 1 )) "The Red Hand"              "A painted wooden hand. The bandits saluted it every morning."
cl 0 2 🧊 '*' $(( D60 + 2 )) "Hrimgard's Snowflake"       "A snowflake as big as your palm. It has never melted."
cl 0 3 🪔 'L' $(( D60 + 3 )) "Gorrak's Mining Lamp"       "It still burns, deep down. Nobody refills it."
cl 1 1 🍄 'T' $WB60          "Grumblegut's Toadstool"     "The toad wore it as a hat. It was a very proud toad."
cl 1 2 🦣 'M' $(( WB60 + 1 )) "Gorehorn's Tusk"           "Ivory, as long as a spear and twice as heavy."
cl 1 2 🐾 'p' $(( WB60 + 2 )) "Vesper's Paw Print"        "Pressed in jade. Nobody saw her make it."
cl 1 3 🌌 'R' $(( WB60 + 3 )) "A Bit of Ruin"             "A pebble of nothing. Stars are missing from it."
CS_NAME+=("Hunter's Trophies") CS_E+=(🎯) CS_HOW+=("taken from the rare elites of every land")
_fl=("Proof that it hunts no more." "Taken from the hunter's own hunting ground." "The bounty boards still talk about it."
     "Hung over the fireplace, it still looks angry." "Every scratch on it is a story.")
for _t in "${RARE_T[@]}"; do                              # "Grimfang the Elder Wolf" -> "Grimfang's Trophy"
  _n=${M_NAME[_t]%% the *}; _n=${_n#The }
  if [[ $_n == *s ]]; then _n="$_n' Trophy"; else _n="$_n's Trophy"; fi
  cl 6 $(( M_LVL[_t] >= 30 ? 3 : 2 )) "" "${M_GLY[_t]}" "$_t" "$_n" "${_fl[_t % 5]}"
done; unset _t _n _fl
col_index
ACH+=("Big Game Hunter:Slay 50 rare elites:the Big Game Hunter" "Huntmaster:Every hunter's trophy:the Huntmaster"
      "Hoarder:Discover 100 collectables:the Hoarder" "Pathfinder:Finish 25 questlines:the Pathfinder"
      "Dungeon Lord:Clear 250 dungeons:the Dungeon Lord")
ACH60=$NACH NACH=${#ACH[@]}

RUMORS+=("Farmer Hesk swears rats as big as dogs live under the old mill on Silverlake. He is usually right about rats."
         "The Red Hand gang hides in the foothills north of Ironwood Camp. Their leader paints his hand red. Every morning."
         "Frosthold's skalds sing of Queen Hrimgard, who wanted winter to last forever. Some say she is waking up."
         "Deep under the Scorched Badlands, the Cinderdeep Mine still glows. The miners never came back up."
         "Every land has a rare elite of its own now - and every rare elite a trophy for your room."
         "Cobalt and adamantite glitter in the highlands and the badlands. The smiths forge fine things from them."
         "Something called the Star Devourer was seen over Starfall Crater. The stars above it are going out, one by one.")

# ---------------------------------------------------------------------------
#  Module 02 - network: a hub relays every line to every connection; the
#  python3 and socat hubs also bind each connection to one sender id and let
#  only the world server (secret token) speak as "srv".
#  Line protocol: SM1|TYPE|from|fields...   (see docs/PROTOCOL.md)
# ---------------------------------------------------------------------------
HUB_PID="" HUB_DIR="" HUB_TOOL="" WS_PID="" net_up=0 net_buf=""

read -r -d '' PY_HUB <<'PY'
# Relay hub with anti-spoofing: every connection is bound to the first sender
# id it uses, and only the world server (which proves itself with a secret
# token from the environment) may speak as "srv".
import asyncio, os, sys
TOKEN = os.environ.get("SHELLMMO_HUB_TOKEN", "").encode()
MAXBUF = 1 << 20
clients = set()
ids = {}          # writer -> bound sender id (b"srv" for the world server)
# --- interest management (v6.3): in the open world a player only gets the monsters near them -------
# The hub remembers every monster of W (from MON/MMOV/MHP) and where every player is (from their POS).
# Monster lines go to the players in range; a monster that comes into range (it walks in, or the
# player walks up to it) is sent as a full MON line; MDIE goes to everybody who knows the monster.
R_IN, R_OUT, BK = 50, 58, 16
mons = {}         # mid -> [type, x, y, hp, max, champ]
grid = {}         # (bx, by) -> set of mids
where = {}        # writer -> [map, x, y] (from the player's own POS)
near = {}         # writer -> mids in range (they get every update)
known = {}        # writer -> mids the player has heard of (they get MDIE)
MONT = (b"MON", b"MMOV", b"MHP", b"MDIE", b"MATK")
def mon_line(mid):
    t, x, y, hp, mx, ch = mons[mid]
    return b"SM1|MON|srv|W|%s|%s|%d|%d|%s|%s|%s\n" % (mid, t, x, y, hp, mx, ch)
def mon_put(mid, x, y):
    old = mons.get(mid)
    if old:
        grid.get((old[1] // BK, old[2] // BK), set()).discard(mid)
    grid.setdefault((x // BK, y // BK), set()).add(mid)
def around(x, y, r):
    out = []
    for bx in range((x - r) // BK, (x + r) // BK + 1):
        for by in range((y - r) // BK, (y + r) // BK + 1):
            for mid in grid.get((bx, by), ()):
                m = mons[mid]
                if abs(m[1] - x) <= r and abs(m[2] - y) <= r:
                    out.append(mid)
    return out
def player_moved(c, f):
    """f = POS fields after the type: id name cls lvl map x y ..."""
    try:
        mp, x, y = f[4], int(f[5]), int(f[6])
    except (IndexError, ValueError):
        return []
    old = where.get(c)
    where[c] = [mp, x, y]
    if old is None or old[0] != mp:
        near[c] = set(); known[c] = set()
    if mp != b"W":
        return []
    nr = near[c]
    keep = {m for m in nr if m in mons and abs(mons[m][1] - x) <= R_OUT and abs(mons[m][2] - y) <= R_OUT}
    new = [m for m in around(x, y, R_IN) if m not in keep]
    keep.update(new); near[c] = keep; known[c].update(new)
    return [mon_line(m) for m in new]
def monster_dest(typ, f, line, dest):
    """f = fields after the type: srv map mid ...; returns [(writer, line)]"""
    if len(f) < 3:
        return [(c, line) for c in dest]
    mp, mid = f[1], f[2]
    full = None
    if mp == b"W":
        try:
            if typ == b"MON" and len(f) >= 8:
                x, y = int(f[4]), int(f[5]); mon_put(mid, x, y); mons[mid] = [f[3], x, y, f[6], f[7], f[8] if len(f) > 8 else b"0"]
                full = line
            elif typ == b"MMOV" and len(f) >= 5:
                x, y = int(f[3]), int(f[4])
                if len(f) >= 9:
                    mon_put(mid, x, y); mons[mid] = [f[5], x, y, f[6], f[7], f[8]]
                elif mid in mons:
                    mon_put(mid, x, y); mons[mid][1:3] = [x, y]
            elif typ == b"MHP" and mid in mons and len(f) >= 4:
                mons[mid][3] = f[3]
        except ValueError:
            pass
    out = []
    for c in dest:
        w = where.get(c)
        if w is None or ids.get(c) == b"srv" or mp != b"W":     # (instances are small: everybody gets them)
            out.append((c, line)); continue
        if w[0] != mp:
            continue
        nr, kn = near[c], known[c]
        if typ == b"MDIE":
            if mid in kn:
                out.append((c, line)); kn.discard(mid); nr.discard(mid)
            continue
        if typ == b"MATK" and len(f) >= 4 and f[3] == ids.get(c):
            out.append((c, line)); continue
        m = mons.get(mid)
        if m is None:
            out.append((c, line)); continue
        dx, dy = abs(m[1] - w[1]), abs(m[2] - w[2])
        if mid in nr:
            if dx <= R_OUT and dy <= R_OUT:
                out.append((c, line))
            else:
                nr.discard(mid)
        elif dx <= R_IN and dy <= R_IN and typ in (b"MON", b"MMOV"):
            nr.add(mid); kn.add(mid)
            out.append((c, full or mon_line(mid)))
    if typ == b"MDIE" and mp == b"W" and mid in mons:
        m = mons.pop(mid); grid.get((m[1] // BK, m[2] // BK), set()).discard(mid)
    return out
async def handle(reader, writer):
    clients.add(writer)
    me = None
    try:
        while True:
            try:
                line = await reader.readline()
            except (ValueError, asyncio.LimitOverrunError):
                break
            if not line:
                break
            if len(line) > 2048 or not line.endswith(b"\n"):
                continue
            p = line[:-1].split(b"|", 3)
            if len(p) < 3 or p[0] != b"SM1":
                continue
            frm = p[2]
            if p[1] == b"AUTH":
                if TOKEN and frm == b"srv" and len(p) == 4 and p[3] == TOKEN:
                    me = b"srv"
                continue
            if me is None and frm != b"srv":
                me = frm
            if frm != me:
                continue
            ids[writer] = me
            # private lines: ALOAD/ASAVE (hero data, passwords) go to the world server only,
            # AR<id> (the server's answer) to that one player only
            typ = p[1]
            if typ in (b"ALOAD", b"ASAVE"):
                if me == b"srv":
                    continue
                dest = [c for c in clients if ids.get(c) == b"srv"]
            elif typ[:2] == b"AR" and len(typ) == 8:
                if me != b"srv":
                    continue
                dest = [c for c in clients if ids.get(c) == typ[2:]]
            else:
                dest = list(clients)
            if me == b"srv" and typ in MONT:
                sends = monster_dest(typ, line[:-1].split(b"|")[2:], line, dest)
            else:
                sends = [(c, line) for c in dest]
                if typ == b"POS" and me != b"srv":
                    sends += [(writer, l) for l in player_moved(writer, line[:-1].split(b"|")[2:])]
            for c, l in sends:
                try:
                    if c.transport.get_write_buffer_size() > MAXBUF:
                        raise ConnectionError("client too slow")
                    c.write(l)
                except Exception:
                    clients.discard(c)
                    c.close()
    except Exception:
        pass
    finally:
        clients.discard(writer)
        ids.pop(writer, None)
        for d in (where, near, known):
            d.pop(writer, None)
        try:
            writer.close()
        except Exception:
            pass
async def watchdog(pid):          # the game that started this hub is gone (kill -9): do not stay behind
    while True:
        await asyncio.sleep(2)
        try:
            os.kill(pid, 0)
        except ProcessLookupError:
            os._exit(0)
        except Exception:
            pass
async def main():
    if len(sys.argv) > 3 and sys.argv[3].isdigit():
        asyncio.get_running_loop().create_task(watchdog(int(sys.argv[3])))
    server = await asyncio.start_server(handle, (sys.argv[2] if len(sys.argv) > 2 else None) or None, int(sys.argv[1]))
    async with server:
        await server.serve_forever()
try:
    asyncio.run(main())
except KeyboardInterrupt:
    pass
PY

pick_hub_tool() {  # python3 and socat hubs enforce sender ids; the ncat broker relays blindly
  if [[ $SHELLMMO_HUB =~ ^(ncat|python3|socat)$ ]] && command -v "$SHELLMMO_HUB" >/dev/null 2>&1; then HUB_TOOL=$SHELLMMO_HUB
  elif command -v python3 >/dev/null 2>&1; then HUB_TOOL=python3
  elif command -v socat >/dev/null 2>&1; then HUB_TOOL=socat
  elif command -v ncat >/dev/null 2>&1; then HUB_TOOL=ncat
  elif command -v nc >/dev/null 2>&1 && nc --version 2>&1 | grep -qi ncat; then HUB_TOOL=nc
  else return 1; fi
  if [[ $HUB_TOOL == @(python3|socat) && -z $SHELLMMO_HUB_TOKEN ]]; then
    local t=""
    [[ -r /dev/urandom ]] && t=$(od -An -N16 -tx1 /dev/urandom 2>/dev/null)
    t=${t//[^0-9a-f]/}
    (( ${#t} >= 16 )) || printf -v t '%04x%04x%04x%04x' $RANDOM $RANDOM $RANDOM $RANDOM
    export SHELLMMO_HUB_TOKEN=$t
  fi
}

alive() { [[ -n $1 ]] && kill -0 "$1" 2>/dev/null; }

start_hub() {
  local run=() i
  command -v setsid >/dev/null 2>&1 && run=(setsid)
  case $HUB_TOOL in
    ncat|nc) "${run[@]}" "$HUB_TOOL" --broker -l ${NET_BIND:+"$NET_BIND"} "$NET_PORT" </dev/null >/dev/null 2>&1 & ;;
    python3) "${run[@]}" python3 -I -c "$PY_HUB" "$NET_PORT" "$NET_BIND" "$$" </dev/null >/dev/null 2>&1 & ;;
    socat)
      [[ -n $HUB_DIR ]] || HUB_DIR=$(mktemp -d)
      : > "$HUB_DIR/log"
      "${run[@]}" socat "TCP-LISTEN:$NET_PORT,reuseaddr,fork${NET_BIND:+,bind=$NET_BIND}" "EXEC:bash $SELF --hub-handler $HUB_DIR/log" \
        </dev/null >/dev/null 2>&1 & ;;
  esac
  HUB_PID=$!
  disown "$HUB_PID" 2>/dev/null
  for (( i = 0; i < 30; i++ )); do
    sleep 0.1
    alive "$HUB_PID" || return 1
    (exec 3<>"/dev/tcp/${NET_BIND:-127.0.0.1}/$NET_PORT") 2>/dev/null && return 0
  done
  return 1
}

start_world_server() {
  local run=()
  command -v setsid >/dev/null 2>&1 && run=(setsid)
  mkdir -p "$DATA_DIR"
  "${run[@]}" bash "$SELF" --world-server "$NET_PORT" </dev/null >>"$DATA_DIR/server.log" 2>&1 &
  WS_PID=$!
  disown "$WS_PID" 2>/dev/null           # (no "Killed" notice from bash on top of the game if it dies)
}

kill_tree() {
  [[ -n $1 ]] || return
  kill -TERM -- "-$1" 2>/dev/null
  pkill -TERM -P "$1" 2>/dev/null
  kill -TERM "$1" 2>/dev/null
}

stop_all() {
  kill_tree "$WS_PID"; WS_PID=""
  kill_tree "$HUB_PID"; HUB_PID=""
  [[ -n $HUB_DIR ]] && rm -rf "$HUB_DIR"
}

net_connect() {
  timeout 2 bash -c 'exec 3<>"/dev/tcp/$0/$1"' "$NET_HOST" "$NET_PORT" 2>/dev/null || return 1
  { exec 7<>"/dev/tcp/$NET_HOST/$NET_PORT"; } 2>/dev/null || return 1
  net_up=1 net_buf=""
  # the world server proves to the hub that it may speak as "srv"
  [[ $MODE == @(world|server) && -n $SHELLMMO_HUB_TOKEN ]] && send AUTH srv "$SHELLMMO_HUB_TOKEN"
  return 0
}

send() {   # TYPE fields... (joined with |)
  (( net_up )) || return 1
  local IFS='|'
  printf 'SM1|%s\n' "$*" >&7 2>/dev/null && return 0
  net_lost
  return 1
}

# read up to $1 complete lines, calling on_line for each
net_poll() {
  local line rc n=0 max=${1:-200}
  while (( net_up && n < max )) && read -t 0 -u 7 2>/dev/null; do
    IFS= read -r -t 0.02 -u 7 line; rc=$?
    if (( rc == 0 )); then on_line "$net_buf$line"; net_buf=""
    elif (( rc > 128 )); then net_buf+=$line; break
    else net_lost; return; fi
    n=$(( n + 1 ))
  done
  (( ${#net_buf} > 4096 )) && net_buf=""
}

# ---------------------------------------------------------------------------
#  Module 03 - world server: authoritative for monsters, NPCs, loot, parties,
#  party quests, the wanted list, weather, the clock and dungeon instances.
#  Clients own their character. Monsters think in a timer wheel (ai_tick).
# ---------------------------------------------------------------------------
declare -A SP_NAME=() SP_MAP=() SP_X=() SP_Y=() SP_LVL=() SP_DEAD=() SP_SEEN=() SP_PARTY=() SP_WANTED=() SP_CLS=()
declare -A OCC=() AL=() RS=() PT_LEADER=() PT_MEMBERS=() PT_INST=() PT_QUESTS=() INV_FROM=() PLIST=()
declare -A IN_TYPE=() IN_SEED=() IN_PARTY=() IN_EMPTY=() IN_SCALE=() IN_DONE=() IN_MONS=() SOLO_INST=() DREQ_T=() SYNC_T=() SYNC_PEND=()
MX=() MY=() MT=() MHP=() MMAX=() MMAP=() MALIVE=() MHX=() MHY=() MNEXT=() MFRZ=() MAGG=()
MRESP=() MZONE=() MATKN=() MSCALE=() MWR=() MCON=() MPH=()
NMON=0 NPARTY=0 NINST=0 WB_MID=-1 WB_NEXT=0 WB_GONE=0 WB_PING=0 WBS_AT=0 WBS_M=-1 WBS_X=0 WBS_Y=0 WBS_D=0
SRV_CLK0=0 NIGHT=0 WS_T=() WS_E=() WS_N=()
declare -A GATH_T=()

slog() { printf '[%(%H:%M:%S)T] %s\n' -1 "$*"; }

mon_state() { send MON srv "${MMAP[$1]}" "$1" "${MT[$1]}" "${MX[$1]}" "${MY[$1]}" "${MHP[$1]}" "${MMAX[$1]}" $(( ${MCH[$1]:--1} + 1 )); }

champ_roll() {  # mid: now and then a monster is a champion (MCH = affix, -1 = none): more HP, XP, loot
  local m=$1 t=${MT[$1]} p=4
  MCH[m]=-1 MMAX[m]=$(( M_HP[t] * MSCALE[m] / 100 ))
  (( M_KIND[t] == 0 && M_BOSS[t] == 0 && MZONE[m] != -2 && MZONE[m] != -4 )) || return
  [[ ${MMAP[m]} == D* ]] && p=8
  (( RANDOM % 100 < p )) || return
  MCH[m]=$(( RANDOM % NCHP ))
  MMAX[m]=$(( MMAX[m] * (MCH[m] == 6 ? 3 : 2) ))
}

in_safe() { [[ $1 == W ]] && in_safe_xy "$2" "$3"; }

spawn_mon() {  # map type x y zone scale [wander] -> MID
  local m=$NMON
  NMON=$(( NMON + 1 ))
  MMAP[m]=$1 MT[m]=$2 MX[m]=$3 MY[m]=$4 MHX[m]=$3 MHY[m]=$4 MZONE[m]=$5 MSCALE[m]=$6 MWR[m]=${7:-3}
  MMAX[m]=$(( M_HP[$2] * $6 / 100 )); champ_roll "$m"; MHP[m]=${MMAX[m]}
  MALIVE[m]=1 MNEXT[m]=0 MFRZ[m]=0 MAGG[m]="" MATKN[m]=0 MRESP[m]=0 MCON[m]="" MPH[m]=0 MHEALT[m]=0
  if (( M_KIND[$2] >= 3 )); then MNEXT[m]=4000000000000   # resource nodes and chests never think
  else wake "$m"; fi
  OCC["$1:$3:$4"]=$m; AL[$m]=1
  [[ $1 == W ]] || IN_MONS[$1]+=" $m"                      # instance monsters are freed with their dungeon
  MID=$m
}

free_tile() {  # x1 y1 x2 y2 map [ore|herb] -> SX SY   (nodes: open ground, ore right next to a mountain)
  local i x y n=40 r a b
  [[ -n $6 ]] && n=300
  for (( i = 0; i < n; i++ )); do
    x=$(( $1 + RANDOM % ($3 - $1 + 1) )) y=$(( $2 + RANDOM % ($4 - $2 + 1) ))
    m_walk "$5" "$x" "$y" || continue
    in_safe "$5" "$x" "$y" && continue
    [[ -n ${OCC[$5:$x:$y]} ]] && continue
    if [[ -n $6 ]]; then                                 # never block roads, bridges or narrow passes
      [[ $T == [.,\"*%SsNnAKJDEqMHB] ]] || continue
      a=${MAPROW[$5:$(( y - 1 ))]:x-1:3}${MAPROW[$5:$y]:x-1:1}${MAPROW[$5:$y]:x+1:1}${MAPROW[$5:$(( y + 1 ))]:x-1:3}
      b=${a//[^.,\":=_*%SsNnIAKJDEqMHB]/}; (( ${#b} >= 5 )) || continue
      if [[ $6 == ore ]]; then
        r=${MAPROW[$5:$(( y - 1 ))]:x:1}${MAPROW[$5:$(( y + 1 ))]:x:1}${MAPROW[$5:$y]:x-1:1}${MAPROW[$5:$y]:x+1:1}
        [[ $r == *[\^RCV]* ]] || continue
      fi
    fi
    SX=$x SY=$y; return 0
  done
  return 1
}

zone_tile() {  # zone index -> SX SY
  local z=(${ZONES[$1]}) o=""
  if (( z[0] >= NODE0 && z[0] < NODE0 + 6 )); then o=ore; elif (( z[0] >= NODE0 && z[0] < NODE0 + 12 )); then o=herb; fi
  free_tile "${z[1]}" "${z[2]}" "${z[3]}" "${z[4]}" W "$o"
}

spawn_world() {
  local zi z c n
  for zi in "${!ZONES[@]}"; do
    z=(${ZONES[zi]})
    for (( c = 0; c < z[5]; c++ )); do
      zone_tile "$zi" && spawn_mon W "${z[0]}" "$SX" "$SY" "$zi" 100
    done
  done
  for n in "${NPC_SPAWNS[@]}"; do
    z=($n); spawn_mon W "${z[0]}" "${z[1]}" "${z[2]}" -3 100 "${z[3]}"
  done
  slog "spawned $NMON monsters and NPCs in the open world"
}

srv_sync() {  # map: resend every living monster of a map
  [[ $1 =~ ^(W|D[0-9]+)$ ]] || return
  local m
  for m in "${!AL[@]}"; do [[ ${MMAP[m]} == "$1" ]] && mon_state "$m"; done
}

sync_flush() {  # a full resync is ~500 lines to everyone: at most one per map per second
  local map
  for map in "${!SYNC_PEND[@]}"; do
    (( NOW - ${SYNC_T[$map]:-0} >= 1000 )) || continue
    unset "SYNC_PEND[$map]"; SYNC_T[$map]=$NOW
    srv_sync "$map"
  done
}

party_send() {
  local p=$1
  send PARTY srv "$p" "${PT_LEADER[$p]}" "${PT_MEMBERS[$p]// /,}"
  send PQUEST srv "$p" "${PT_QUESTS[$p]// /,}"
}

set_wanted() {  # id ms (0 clears) - only ever extends a running sentence
  local until=$(( NOW + $2 ))
  if (( $2 > 0 )); then
    [[ -z ${SP_WANTED[$1]} ]] && slog "${SP_NAME[$1]} is now wanted"
    (( until > ${SP_WANTED[$1]:-0} + 3000 )) || return
    SP_WANTED[$1]=$until
    send WANTED srv "$1" $(( $2 / 1000 ))
  elif [[ -n ${SP_WANTED[$1]} ]]; then
    unset "SP_WANTED[$1]"; send WANTED srv "$1" 0
  fi
}

srv_hello() {  # id name
  local p
  SP_NAME[$1]=${2//[^A-Za-z0-9_-]/} SP_SEEN[$1]=$NOW
  SP_MAP[$1]=${SP_MAP[$1]:-W} SP_X[$1]=${SP_X[$1]:-$SPAWN_X} SP_Y[$1]=${SP_Y[$1]:-$SPAWN_Y}
  SP_LVL[$1]=${SP_LVL[$1]:-1} SP_DEAD[$1]=0
  slog "+ ${SP_NAME[$1]} ($1) joined"
  SYNC_PEND[W]=1; sync_flush
  for p in "${!PT_LEADER[@]}"; do party_send "$p"; done
  for p in "${!SP_WANTED[@]}"; do send WANTED srv "$p" $(( (SP_WANTED[$p] - NOW) / 1000 )); done
  send CLOCK srv $(( (NOW - SRV_CLK0) % DAYLEN ))
  for p in "${!WS_T[@]}"; do [[ -n ${WS_T[p]} ]] && send WEATHER srv "$p" "${WS_T[p]}" $(( (WS_E[p] - NOW) / 1000 )); done
  if (( WB_MID >= 0 && MALIVE[WB_MID] )); then
    region_of "${MX[WB_MID]}" "${MY[WB_MID]}" nosafe
    send WBOSS srv "$WB_MID" "${MT[WB_MID]}" "${MX[WB_MID]}" "${MY[WB_MID]}"
    send INFO srv "$1" "World boss: ${M_NAME[${MT[WB_MID]}]} is roaming the $RNAME! Check your map [m]."
  fi
}

srv_drop() {
  acc_forget "$1"
  [[ -n ${SP_NAME[$1]} ]] || return
  slog "- ${SP_NAME[$1]} ($1) left"
  srv_pleave "$1"
  unset "SP_NAME[$1]" "SP_MAP[$1]" "SP_X[$1]" "SP_Y[$1]" "SP_LVL[$1]" "SP_DEAD[$1]" "SP_SEEN[$1]" "INV_FROM[$1]" "SP_WANTED[$1]" "GATH_T[$1]" "SP_CLS[$1]" "SOLO_INST[$1]" "DREQ_T[$1]"
}

roll_item() {  # type [player] [level] [champion] -> ITEM  (gear leans towards what the player's class can use)
  local t=$1 tier r rr k s u a
  ITEM=""
  tier_for "${3:-${M_LVL[t]}}"; tier=$TF
  r=$(( RANDOM % 100 ))
  if (( M_BOSS[t] == 1 )); then                         # bosses sometimes carry their unique
    for u in "${U_DROP[@]}"; do
      a=(${u//:/ })
      (( a[0] == t && RANDOM % 100 < a[2] )) && { ITEM="U.${a[1]}"; return; }
    done
  fi
  if (( M_KIND[t] == 4 )); then                          # treasure chests: always gear, often rare
    rr=$(( RANDOM % 100 )); if (( rr < 50 )); then rr=1; elif (( rr < 88 )); then rr=2; else rr=3; fi
  elif (( M_BOSS[t] )); then
    (( tier < MAXTIER )) && tier=$(( tier + 1 ))
    rr=$(( RANDOM % 100 )); if (( rr < 45 )); then rr=1; elif (( rr < 85 )); then rr=2; else rr=3; fi
  elif (( r < 12 + (M_KIND[t] ? 25 : 0) || ${4:-0} )); then
    rr=$(( RANDOM % 100 )); if (( rr < 70 )); then rr=0; elif (( rr < 93 )); then rr=1; elif (( rr < 99 )); then rr=2; else rr=3; fi
    (( ${4:-0} && rr < 3 )) && rr=$(( rr + 1 ))
  elif (( r < 24 )); then
    if (( RANDOM % 2 )); then ITEM=H; else ITEM=M; fi; return
  else
    return
  fi
  local wbt=0; [[ " ${WB_LIST[*]} " == *" $t "* ]] && wbt=1
  if (( RANDOM % 100 < (M_BOSS[t] ? (wbt ? 25 : 12) : 4) )); then   # v1.8: bags
    k=$(( RANDOM % 100 ))
    if (( M_BOSS[t] && wbt )); then if (( k < 50 )); then k=3; elif (( k < 85 )); then k=4; else k=5; fi
    elif (( M_BOSS[t] )); then if (( k < 55 )); then k=2; elif (( k < 90 )); then k=3; else k=4; fi
    elif (( k < 70 )); then k=0; else k=1; fi
    ITEM="B.$k"; return
  fi
  k=$(( RANDOM % 100 ))
  if (( k < 34 )); then s=W; elif (( k < 56 )); then s=A; elif (( k < 72 )); then s=H; elif (( k < 86 )); then s=O; else s=J; fi
  kind_pick "$s" "${SP_CLS[${2:-_}]}"
  ITEM="$s.$KP.$tier.$rr"
  k=$(( RANDOM % 100 ))                                  # v3.0: sockets for gems
  case $rr in
    0) (( k < 10 )) && ITEM+=".__" ;;
    1) (( k < 25 )) && ITEM+=".__" ;;
    2) if (( k < 15 )); then ITEM+=".____"; elif (( k < 45 )); then ITEM+=".__"; fi ;;
    3) if (( k < 20 )); then ITEM+=".______"; elif (( k < 60 )); then ITEM+=".____"; else ITEM+=".__"; fi ;;
  esac
}

gem_drop() {  # type player champion [level]: bosses, rares, champions and chests sometimes drop a gem
  local t=$1 l=${4:-${M_LVL[$1]}} c=0 g
  if (( M_KIND[t] == 4 )); then c=45; elif (( M_BOSS[t] == 1 )); then c=60; elif (( M_BOSS[t] == 2 )); then c=70
  elif (( $3 )); then c=35; else c=1; fi
  (( RANDOM % 100 < c )) || return
  g=1; (( l >= 12 )) && g=2; (( l >= 22 )) && g=3
  (( g > 1 && RANDOM % 3 == 0 )) && g=$(( g - 1 ))
  (( l >= 38 && RANDOM % 100 < (M_BOSS[t] == 1 ? 12 : 3) )) && g=4          # v4.5: perfect gems
  gem_mat $(( RANDOM % 6 )) "$g"
  send LOOT srv "$2" "g$GM"
}

boss_summon() {  # mid: a dungeon boss calls its minions
  local m=$1 t=${MT[$1]} map=${MMAP[$1]} i pool
  pool=(${D_POOL[${IN_TYPE[$map]:-0}]})
  for i in 1 2; do
    free_tile $(( MX[m] - 3 )) $(( MY[m] - 3 )) $(( MX[m] + 3 )) $(( MY[m] + 3 )) "$map" || continue
    spawn_mon "$map" "${pool[RANDOM % ${#pool[@]}]}" "$SX" "$SY" -1 "${MSCALE[m]}"; MAGG[MID]=${MAGG[m]}
    MDS[MID]=${MDS[m]:-100} MADD[MID]=$m
    mon_state "$MID"
  done
  if (( ${M_RAID[$t]:-0} )) && (( MPH[m] == 1 )); then
    send BOSS srv "$map" "${M_NAME[t]} hides behind a shield of night - kill her guards!" "${MX[m]}" "${MY[m]}"
  else send BOSS srv "$map" "${M_NAME[t]} calls its servants!" "${MX[m]}" "${MY[m]}"; fi
}

los() {  # map x1 y1 x2 y2 -> 0 if nothing blocks the line; LCELLS = the cells in between
  local map=$1 x=$2 y=$3 tx=$4 ty=$5 dx dy sx sy err e2 n=0
  dx=$(( tx > x ? tx - x : x - tx )) dy=$(( ty > y ? ty - y : y - ty )); sx=$(( x < tx ? 1 : -1 )) sy=$(( y < ty ? 1 : -1 ))
  err=$(( dx - dy )) LCELLS=""
  while (( n++ < 20 )); do
    e2=$(( 2 * err ))
    (( e2 > -dy )) && { err=$(( err - dy )); x=$(( x + sx )); }
    (( e2 < dx )) && { err=$(( err + dx )); y=$(( y + sy )); }
    (( x == tx && y == ty )) && return 0
    blocks_shot "$map" "$x" "$y" && return 1
    LCELLS+="$x,$y "
  done
  return 1
}

mon_healer() {  # mid: heal the most wounded friend within 5 steps
  local m=$1 map=${MMAP[$1]} x y o best="" bp=100 p
  for (( y = MY[m] - 5; y <= MY[m] + 5; y++ )); do
    for (( x = MX[m] - 5; x <= MX[m] + 5; x++ )); do
      o=${OCC[$map:$x:$y]}; [[ -n $o ]] || continue
      (( M_KIND[MT[o]] == 0 && MHP[o] < MMAX[o] )) || continue
      p=$(( MHP[o] * 100 / MMAX[o] )); (( p < bp )) && { bp=$p; best=$o; }
    done
  done
  [[ -n $best ]] && (( bp < 80 )) || return 1
  MHP[best]=$(( MHP[best] + MMAX[best] / 4 )); (( MHP[best] > MMAX[best] )) && MHP[best]=${MMAX[best]}
  send MHP srv "$map" "$best" "${MHP[best]}" ""
  send FX srv "$map" holy "${MX[best]},${MY[best]}"
  MHEALT[m]=$(( NOW + 5000 ))
  return 0
}

pq_progress() {  # pid type|D.dtype  -> advance party quests, pay out finished ones
  local p=$1 q f out=() changed=0 m
  [[ -n ${PT_QUESTS[$p]} ]] || return
  for q in ${PT_QUESTS[$p]}; do
    IFS=. read -r -a f <<< "$q"
    if [[ ( ${f[0]} == K && $2 != [DT].* && ${f[1]} == "$2" ) || ( ${f[0]} == [DT] && $2 == "${f[0]}.${f[1]}" ) ]]; then
      f[3]=$(( f[3] + 1 )); changed=1
      if (( f[3] >= f[2] )); then
        send QDONE srv "$p" $(( f[4] * 125 / 100 )) $(( f[5] * 125 / 100 )) "${f[0]}.${f[1]}.${f[2]}.${f[2]}.${f[4]}.${f[5]}"
        slog "party $p finished quest $q"
        continue
      fi
      q="${f[0]}.${f[1]}.${f[2]}.${f[3]}.${f[4]}.${f[5]}"
    fi
    out+=("$q")
  done
  (( changed )) || return
  PT_QUESTS[$p]="${out[*]}"
  send PQUEST srv "$p" "${PT_QUESTS[$p]// /,}"
}

mon_die() {  # mid killer
  local m=$1 k=$2 t=${MT[$1]} map=${MMAP[$1]} rec=() p pid xp gold dt
  MALIVE[m]=0; unset "AL[$m]" "OCC[$map:${MX[m]}:${MY[m]}]"
  send MDIE srv "$map" "$m" "${SP_NAME[$k]}"
  if (( M_KIND[t] == 3 )); then MRESP[m]=$(( NOW + 45000 + RANDOM % 45000 )); RS[$m]=1; return; fi
  if (( MZONE[m] == -2 )); then wb_die "$m" "$k"; return; fi
  if (( M_KIND[t] == 4 )); then                          # a treasure chest: whoever opens it gets the lot
    dt=${IN_TYPE[$map]:-0}
    roll_item "$t" "$k" $(( D_REQ[dt] + 3 ))
    send REW srv "$k" $(( 20 * D_REQ[dt] + 20 )) $(( 40 * D_REQ[dt] + 30 + RANDOM % (20 * D_REQ[dt] + 20) )) "$ITEM" "$t"
    gem_drop "$t" "$k" 0 "${D_REQ[dt]}"
    return
  fi
  pid=${SP_PARTY[$k]}
  if [[ -n $pid ]]; then
    for p in ${PT_MEMBERS[$pid]}; do
      [[ ${SP_MAP[$p]} == "$map" ]] || continue
      if [[ $map == W ]]; then
        cheb $(( ${SP_X[$p]:-0} - MX[m] )) $(( ${SP_Y[$p]:-0} - MY[m] )); (( D <= 30 )) || continue
      fi
      rec+=("$p")
    done
  fi
  (( ${#rec[@]} )) || rec=("$k")
  xp=$(( M_XP[t] * MSCALE[m] / 100 )) gold=$(( M_GOLD[t] * MSCALE[m] / 100 ))
  local champ=$(( ${MCH[m]:--1} >= 0 ))
  (( champ )) && xp=$(( xp * 3 )) gold=$(( gold * 3 ))
  [[ $map == W ]] && (( NIGHT )) && [[ $UNDEAD == *" $t "* ]] && xp=$(( xp * 125 / 100 ))
  if (( ${#rec[@]} > 1 )); then xp=$(( xp * 80 / 100 )) gold=$(( gold * 60 / 100 + 1 )); fi
  local ml=""; (( ${IN_MYTH[$map]:-0} )) && ml=$MYTH_LVL
  for p in "${rec[@]}"; do
    roll_item "$t" "$p" "$ml" "$champ"
    send REW srv "$p" "$xp" "$gold" "$ITEM" "$t" "$champ"
    gem_drop "$t" "$p" "$champ" "$ml"
  done
  (( ${IN_MYTH[$map]:-0} >= 7 && ${IN_AFC[$map]:-0} == 0 && M_BOSS[t] == 0 )) && myth_bolster "$m"
  (( M_BOSS[t] == 2 && MZONE[m] >= 0 )) && send ANN srv "${SP_NAME[$k]} has slain the rare ${M_NAME[t]}!"
  [[ -n $pid ]] && pq_progress "$pid" "$t"
  if (( MZONE[m] >= 0 )); then
    MRESP[m]=$(( NOW + 20000 + RANDOM % 20000 )); RS[$m]=1
    (( M_BOSS[t] == 2 )) && MRESP[m]=$(( NOW + 240000 + RANDOM % 120000 ))    # rare elites take their time
  elif (( MZONE[m] == -3 )); then
    MRESP[m]=$(( NOW + 90000 )); RS[$m]=1
    set_wanted "$k" 180000
    send ANN srv "${SP_NAME[$k]} murdered ${N_FULL[$t]}! The guards of Hearthmoor are hunting ${SP_NAME[$k]}."
    slog "NPC $t killed by ${SP_NAME[$k]}"
  fi
  if (( M_BOSS[t] )) && [[ $map == D* && -n ${IN_TYPE[$map]} ]] && (( t == D_BOSS[${IN_TYPE[$map]}] )); then
    IN_DONE[$map]=1; dt=${IN_TYPE[$map]}
    send DCLEAR srv "$map" "${M_NAME[t]}"
    if (( ${IN_MYTH[$map]:-0} )); then myth_finish "$map"
    elif (( dt == RAID_DT )); then raid_finish "$map"
    else send ANN srv "${SP_NAME[$k]}'s group cleared the ${D_NAME[dt]}!"; fi
    [[ -n ${IN_PARTY[$map]} && -n ${PT_LEADER[${IN_PARTY[$map]}]} ]] && pq_progress "${IN_PARTY[$map]}" "D.$dt"
    slog "instance $map cleared"
  fi
}

srv_hit() {  # from map mid dmg freeze
  local id=$1 map=$2 m=$3 dmg=$4 fr=$5 cap
  isnum "$m" && isnum "$dmg" && isnum "$fr" || return
  (( m < NMON && MALIVE[m] )) || return
  [[ ${MMAP[m]} == "$map" ]] || return
  if (( M_KIND[MT[m]] == 3 )); then                     # gathering a resource node
    (( NOW - ${GATH_T[$id]:-0} >= 800 )) || return
    GATH_T[$id]=$NOW MHP[m]=$(( MHP[m] - 1 ))
    if (( MHP[m] <= 0 )); then mon_die "$m" "$id"; else send MHP srv "$map" "$m" "${MHP[m]}" ""; fi
    return
  fi
  cap=$(( (${SP_LVL[$id]:-1} + 5) * 70 ))
  (( dmg > cap )) && dmg=$cap
  (( ${MCH[m]:--1} == 2 )) && dmg=$(( dmg * 60 / 100 ))   # armored champion
  (( ${MEV[m]:-0} )) && INV_PART[$id]=1                    # v4.5: a defender of the town
  if (( ${M_RAID[${MT[m]}]:-0} && MPH[m] == 1 )) && raid_adds_alive "$m"; then dmg=$(( dmg / 5 )); fi   # shielded
  MHP[m]=$(( MHP[m] - dmg ))
  if [[ -z ${MAGG[m]} ]] || (( RANDOM % 4 == 0 )); then MAGG[m]=$id; fi
  if (( M_KIND[MT[m]] == 1 || M_KIND[MT[m]] == 2 )); then
    MAGG[m]=$id
    set_wanted "$id" 120000
  fi
  if (( fr > 0 )); then
    (( fr > 4000 )) && fr=4000
    (( M_BOSS[MT[m]] )) && fr=$(( fr / 3 ))
    MFRZ[m]=$(( NOW + fr ))
  fi
  if (( MZONE[m] == -2 )); then
    [[ "${MCON[m]} " == *" $id "* ]] || MCON[m]+=" $id"
    if (( MHP[m] > 0 && MPH[m] < 2 && MHP[m] * 3 < MMAX[m] * (2 - MPH[m]) )); then MPH[m]=$(( MPH[m] + 1 )); wb_adds "$m"; fi
  elif (( M_SUMM[MT[m]] )) && [[ $map == D* ]]; then         # dungeon bosses call for help at 2/3 and 1/3
    if (( MHP[m] > 0 && MPH[m] < 2 && MHP[m] * 3 < MMAX[m] * (2 - MPH[m]) )); then MPH[m]=$(( MPH[m] + 1 )); boss_summon "$m"; fi
  fi
  if (( MHP[m] <= 0 )); then mon_die "$m" "$id"
  else send MHP srv "$map" "$m" "${MHP[m]}" "${SP_NAME[$id]}"; fi
}

player_at() {  # map x y -> 0 if a living player stands there
  local p
  for p in ${PLIST[$1]}; do (( ${SP_X[$p]} == $2 && ${SP_Y[$p]} == $3 )) && return 0; done
  return 1
}

mon_step() {  # mid tx ty
  local m=$1 x=${MX[$1]} y=${MY[$1]} map=${MMAP[$1]} dx dy sx sy c nx ny civ=${M_KIND[${MT[$1]}]} cand
  dx=$(( $2 - x )) dy=$(( $3 - y ))
  sx=$(( dx > 0 ? 1 : (dx < 0 ? -1 : 0) )) sy=$(( dy > 0 ? 1 : (dy < 0 ? -1 : 0) ))
  if (( (dx < 0 ? -dx : dx) >= (dy < 0 ? -dy : dy) )); then cand="$sx,0 0,$sy"; else cand="0,$sy $sx,0"; fi
  (( RANDOM % 3 == 0 )) && cand+=" 0,1 1,0 0,-1 -1,0"
  for c in $cand; do
    nx=$(( x + ${c%,*} )) ny=$(( y + ${c#*,} ))
    (( nx == x && ny == y )) && continue
    m_walk "$map" "$nx" "$ny" || continue
    (( civ == 0 )) && in_safe "$map" "$nx" "$ny" && continue
    [[ -n ${OCC[$map:$nx:$ny]} ]] && continue
    player_at "$map" "$nx" "$ny" && continue
    unset "OCC[$map:$x:$y]"; OCC["$map:$nx:$ny"]=$m
    MX[m]=$nx MY[m]=$ny
    send MMOV srv "$map" "$m" "$nx" "$ny" "${MT[m]}" "${MHP[m]}" "${MMAX[m]}" $(( ${MCH[m]:--1} + 1 ))   # v6.3: full state (interest management)
    return 0
  done
  return 1
}

mon_hit() {  # mid target dmg: MATK with the element and maybe a status effect (v3.0)
  local m=$1 t=${MT[$1]} ab=${M_AB[${MT[$1]}]} c=${MCH[$1]:--1} ch=22 eff=""
  case $c in 3) ab=burn ;; 4) ab=chill ;; 5) ab=poison ;; 7) ab=stun ;; 8) ab=weaken ;; esac   # v4.0: storming, cursed
  (( (c >= 3 && c <= 5) || c == 8 )) && ch=55; (( c == 7 )) && ch=25; (( M_BOSS[t] )) && ch=30
  [[ -n $ab ]] && (( RANDOM % 100 < ch )) && eff=$ab
  send MATK srv "${MMAP[m]}" "$m" "$2" "$3" "${M_EL[t]}" "$eff"
  if (( c == 0 && MHP[m] < MMAX[m] )); then                  # vampiric champion
    MHP[m]=$(( MHP[m] + $3 * 30 / 100 + 1 )); (( MHP[m] > MMAX[m] )) && MHP[m]=${MMAX[m]}
    send MHP srv "${MMAP[m]}" "$m" "${MHP[m]}" ""
  fi
  if [[ ${M_AB[t]} == drain ]]; then
    MHP[m]=$(( MHP[m] + $3 / 2 )); (( MHP[m] > MMAX[m] )) && MHP[m]=${MMAX[m]}
  fi
}

mon_attack() {  # mid target
  local m=$1 t=${MT[$1]} map=${MMAP[$1]} dmg q cells="" i j
  dmg=$(( M_DMG[t] * (85 + RANDOM % 31) / 100 ))
  (( ${MCH[m]:--1} >= 0 )) && dmg=$(( dmg * (MCH[m] == 6 ? 140 : 125) / 100 ))
  [[ $map == W ]] && (( NIGHT )) && [[ $UNDEAD == *" $t "* ]] && dmg=$(( dmg * 130 / 100 ))
  if [[ $map == D* ]]; then                                        # v4.5: mythic and raid
    dmg=$(( dmg * ${MDS[m]:-100} / 100 ))
    (( ${IN_MYTH[$map]:-0} >= 7 && ${IN_AFC[$map]:-0} == 1 && M_BOSS[t] == 0 && MHP[m] * 10 < MMAX[m] * 3 )) && dmg=$(( dmg * 150 / 100 ))
    if (( ${M_RAID[$t]:-0} )); then raid_attack "$m" "$2" "$dmg"; return; fi
  fi
  if (( MZONE[m] == -2 )); then
    MATKN[m]=$(( MATKN[m] + 1 ))
    if (( MATKN[m] % 3 == 0 && WBS_AT == 0 )); then     # telegraphed slam around the target
      WBS_X=${SP_X[$2]} WBS_Y=${SP_Y[$2]} WBS_M=$m WBS_D=$(( dmg * 2 )) WBS_AT=$(( NOW + 1400 ))
      for (( j = -2; j <= 2; j++ )); do for (( i = -2; i <= 2; i++ )); do cells+="$(( WBS_X + i )),$(( WBS_Y + j )) "; done; done
      send FX srv "$map" warn "$cells"
      send BOSS srv "$map" "${M_NAME[t]} raises its fists - get out of the marked area!" "$WBS_X" "$WBS_Y"
      return
    fi
    mon_hit "$m" "$2" "$dmg"; return
  fi
  if (( M_BOSS[t] )); then
    MATKN[m]=$(( MATKN[m] + 1 ))
    if (( MATKN[m] % 4 == 0 )); then
      for (( j = -2; j <= 2; j++ )); do for (( i = -2; i <= 2; i++ )); do cells+="$(( MX[m] + i )),$(( MY[m] + j )) "; done; done
      send FX srv "$map" fire "$cells"
      send BOSS srv "$map" "${M_NAME[t]} unleashes a devastating blast!"
      for q in ${PLIST[$map]}; do
        cheb $(( ${SP_X[$q]} - MX[m] )) $(( ${SP_Y[$q]} - MY[m] ))
        (( D <= 2 )) && send MATK srv "$map" "$m" "$q" $(( dmg * 80 / 100 )) "${M_EL[t]}" ""
      done
      return
    fi
  fi
  mon_hit "$m" "$2" "$dmg"
}

mon_think() {  # mid
  local m=$1 map=${MMAP[$1]} t=${MT[$1]} x=${MX[$1]} y=${MY[$1]} tgt="" best=999 p ag leash kind near=999 dx dy
  kind=${M_KIND[t]} ag=${M_AGGRO[t]}
  (( kind >= 3 )) && { MNEXT[m]=4000000000000; return; }
  p=${MAGG[m]}
  if [[ -n $p && ${SP_MAP[$p]} == "$map" && ${SP_DEAD[$p]:-1} == 0 ]] && { (( kind > 0 )) || [[ -z ${PSAFE[$p]} ]]; }; then
    cheb $(( ${SP_X[$p]} - x )) $(( ${SP_Y[$p]} - y )); (( D <= ag + 10 )) && { tgt=$p; best=$D; }
  fi
  if [[ -z $tgt ]]; then
    for p in ${PLIST[$map]}; do                        # (distance inlined: this loop is the server's hottest)
      (( dx = ${SP_X[$p]} - x, dx < 0 && (dx = -dx), dy = ${SP_Y[$p]} - y, dy < 0 && (dy = -dy), D = dx > dy ? dx : dy ))
      (( D < near )) && near=$D
      (( D <= ag && D < best )) || continue
      if (( kind == 0 )); then
        [[ -n ${PSAFE[$p]} ]] && continue
      elif (( kind == 2 )); then
        [[ -n ${SP_WANTED[$p]} ]] || continue          # guards only hunt outlaws
      else
        continue                                       # civilians only fight back
      fi
      best=$D tgt=$p
    done
    if [[ -z $tgt ]] && (( near > 28 && MHP[m] >= MMAX[m] )); then   # nobody near: sleep until someone could be
      near=$(( (near - 28) * 100 )); (( near < 1500 )) && near=1500; (( near > 15000 )) && near=15000
      MNEXT[m]=$(( NOW + near )); return
    fi
  fi
  leash=14; [[ $map == D* ]] && leash=40; (( MZONE[m] == -2 )) && leash=22
  (( kind == 1 )) && leash=8; (( kind == 2 )) && leash=30
  cheb $(( x - MHX[m] )) $(( y - MHY[m] ))
  (( D > leash )) && tgt=""
  if [[ -z $tgt ]]; then
    MAGG[m]=""
    if (( D > MWR[m] && D > 0 )); then
      mon_step "$m" "${MHX[m]}" "${MHY[m]}"
    elif (( MWR[m] > 0 && RANDOM % 3 == 0 )); then
      mon_step "$m" $(( MHX[m] + RANDOM % (2 * MWR[m] + 1) - MWR[m] )) $(( MHY[m] + RANDOM % (2 * MWR[m] + 1) - MWR[m] ))
    fi
    if (( MHP[m] < MMAX[m] )); then
      MHP[m]=$(( MHP[m] + MMAX[m] / 8 + 1 )); (( MHP[m] > MMAX[m] )) && MHP[m]=${MMAX[m]}
      send MHP srv "$map" "$m" "${MHP[m]}" ""
    fi
    MNEXT[m]=$(( NOW + 600 + RANDOM % 900 ))
    return
  fi
  MAGG[m]=$tgt
  if (( M_HEALR[t] && NOW >= MHEALT[m] )) && mon_healer "$m"; then MNEXT[m]=$(( NOW + M_ATK[t] )); return; fi
  dx=$(( ${SP_X[$tgt]} - x )) dy=$(( ${SP_Y[$tgt]} - y ))
  if (( (dx < 0 ? -dx : dx) + (dy < 0 ? -dy : dy) == 1 )); then   # orthogonal neighbours only
    mon_attack "$m" "$tgt"
    MNEXT[m]=$(( NOW + M_ATK[t] ))
    (( (MZONE[m] == -2 || M_BOSS[t] == 1) && MHP[m] * 4 < MMAX[m] )) && MNEXT[m]=$(( NOW + M_ATK[t] * 65 / 100 ))   # enraged
  else
    cheb "$dx" "$dy"
    if (( M_RNG[t] && D >= 2 && D <= M_RNG[t] )) && los "$map" "$x" "$y" "${SP_X[$tgt]}" "${SP_Y[$tgt]}"; then
      local fk=(slash fire frost poison bone holy sound)        # a bolt flies
      send FX srv "$map" "${fk[M_EL[t]]}" "$LCELLS${SP_X[$tgt]},${SP_Y[$tgt]}"
      mon_attack "$m" "$tgt"
      MNEXT[m]=$(( NOW + M_ATK[t] * 12 / 10 ))
    else
      mon_step "$m" "${SP_X[$tgt]}" "${SP_Y[$tgt]}"
      MNEXT[m]=$(( NOW + M_MOVE[t] ))
      (( ${MCH[m]:--1} == 9 )) && MNEXT[m]=$(( NOW + M_MOVE[t] * 55 / 100 ))       # swift champion
    fi
  fi
  (( ${MCH[m]:--1} == 1 )) && MNEXT[m]=$(( NOW + (MNEXT[m] - NOW) * 6 / 10 ))     # frenzied champion
}

ai_tick() {
  local id m
  local s cur=$(( NOW / 150 )) from list
  PLIST=() PSAFE=()
  for id in "${!SP_NAME[@]}"; do
    [[ ${SP_DEAD[$id]:-0} == 0 ]] || continue
    PLIST[${SP_MAP[$id]}]+=" $id"
    [[ ${SP_MAP[$id]} == W ]] && in_safe_xy "${SP_X[$id]}" "${SP_Y[$id]}" && PSAFE[$id]=1   # once per tick, not per monster
  done
  (( WH_LAST < 0 )) && WH_LAST=$(( cur - 1 ))
  from=$(( WH_LAST + 1 )); WH_LAST=$cur                  # from here on, wake-ups land in later slots
  for (( s = from; s <= cur; s++ )); do
    [[ -n ${WHEEL[s]} ]] || continue
    list=${WHEEL[s]}; unset "WHEEL[s]"
    for m in $list; do
      [[ -n ${AL[$m]} ]] && (( MSLOT[m] == s )) || continue     # dead, or woken again since
      if (( MNEXT[m] > NOW )); then wake "$m"; continue; fi    # due later in this slot: next one
      if [[ -z ${PLIST[${MMAP[m]}]} ]]; then MNEXT[m]=$(( NOW + 1500 )); wake "$m"; continue; fi
      if (( NOW < MFRZ[m] )); then MNEXT[m]=${MFRZ[m]}; wake "$m"; continue; fi
      mon_think "$m"
      (( MNEXT[m] < 4000000000000 )) && wake "$m"
    done
  done
  (( WBS_AT && NOW >= WBS_AT )) && wb_slam
  (( ${#AOE_Q[@]} )) && aoe_tick
}

# Monsters sleep in a timer wheel of 150 ms slots: a tick only touches the ones whose turn it is.
WHEEL=() WH_LAST=-1 MSLOT=()
declare -A PSAFE=()       # players standing in a town this tick
declare -A IN_MYTH=() IN_T0=() IN_LIM=() IN_AFC=() INV_PART=()   # v4.5: mythic level, start, limit, affix C of an instance
MDS=() MADD=() MEV=() AOE_Q=() INV_NEXT=0 INV_WAVE=0 INV_END=0 INV_MONS="" INV_TOWN=-1 INV_T=()
wake() {  # mid: schedule its next think at MNEXT (never into a slot that is already done)
  local s=$(( MNEXT[$1] / 150 ))
  (( s <= WH_LAST )) && s=$(( WH_LAST + 1 ))
  WHEEL[s]+=" $1"; MSLOT[$1]=$s
}
wake_check() {  # safety net: anything alive that fell out of the wheel goes back in
  local m
  for m in "${!AL[@]}"; do
    (( MNEXT[m] < NOW - 3000 && M_KIND[MT[m]] < 3 )) && { MNEXT[m]=$NOW; wake "$m"; }
  done
}

# --- world bosses -----------------------------------------------------------------
wb_slam() {
  local p cells="" i j m=$WBS_M
  WBS_AT=0
  (( m >= 0 && MALIVE[m] )) || return
  for (( j = -2; j <= 2; j++ )); do for (( i = -2; i <= 2; i++ )); do cells+="$(( WBS_X + i )),$(( WBS_Y + j )) "; done; done
  send FX srv W fire "$cells"
  for p in ${PLIST[W]}; do
    cheb $(( ${SP_X[$p]} - WBS_X )) $(( ${SP_Y[$p]} - WBS_Y ))
    (( D <= 2 )) && send MATK srv W "$m" "$p" "$WBS_D"
  done
}

wb_adds() {  # mid: the boss calls for help
  local m=$1 t=${MT[$1]} i a k=0 types
  for i in "${!WB_LIST[@]}"; do [[ ${WB_LIST[i]} == "$t" ]] && k=$i; done
  types=(${WB_ADDS[k]})
  for a in "${types[@]}"; do
    free_tile $(( MX[m] - 3 )) $(( MY[m] - 3 )) $(( MX[m] + 3 )) $(( MY[m] + 3 )) W || continue
    spawn_mon W "$a" "$SX" "$SY" -4 100 4; MAGG[MID]=${MAGG[m]}
    mon_state "$MID"
  done
  send BOSS srv W "${M_NAME[t]} calls for help - minions rush in!" "${MX[m]}" "${MY[m]}"
}

wb_spawn() {
  local id n=0 sum=0 mx=0 i t best="" bs=999 sc r a scale
  for id in "${!SP_NAME[@]}"; do n=$(( n + 1 )); sum=$(( sum + ${SP_LVL[$id]:-1} )); (( ${SP_LVL[$id]:-1} > mx )) && mx=${SP_LVL[$id]:-1}; done
  if (( n == 0 )); then WB_NEXT=$(( NOW + 60000 )); return; fi
  for i in "${!WB_LIST[@]}"; do
    t=${WB_LIST[i]}
    (( M_LVL[t] <= mx + 4 )) || continue
    sc=$(( M_LVL[t] - sum / n )); sc=$(( (sc < 0 ? -sc : sc) + RANDOM % 4 ))
    (( sc < bs )) && { bs=$sc; best=$i; }
  done
  [[ -n $best ]] || best=0
  t=${WB_LIST[best]} a=(${WB_RECT[best]})
  free_tile "${a[0]}" "${a[1]}" "${a[2]}" "${a[3]}" W || { WB_NEXT=$(( NOW + 20000 )); return; }
  scale=$(( 100 + 60 * (n - 1) )); (( scale > 400 )) && scale=400
  spawn_mon W "$t" "$SX" "$SY" -2 "$scale" 4; WB_MID=$MID
  WB_GONE=$(( NOW + 900000 )) WB_PING=0
  mon_state "$MID"
  region_of "$SX" "$SY" nosafe
  send ANN srv "The ground trembles... ${M_NAME[t]} (level ${M_LVL[t]}) has appeared in the $RNAME! Everyone who fights it shares the loot."
  slog "world boss ${M_NAME[t]} spawned at $SX,$SY (scale $scale%)"
}

wb_die() {  # mid killer: every contributor nearby gets full XP, gold and a boss item
  local m=$1 k=$2 t=${MT[$1]} p rec=()
  for p in ${MCON[m]}; do
    [[ -n ${SP_NAME[$p]} && ${SP_MAP[$p]} == W ]] || continue
    cheb $(( ${SP_X[$p]} - MX[m] )) $(( ${SP_Y[$p]} - MY[m] )); (( D <= 60 )) && rec+=("$p")
  done
  (( ${#rec[@]} )) || rec=("$k")
  for p in "${rec[@]}"; do
    roll_item "$t" "$p"
    send REW srv "$p" "${M_XP[t]}" "${M_GOLD[t]}" "$ITEM" "$t"
  done
  WB_NEXT=$(( NOW + 480000 )) WB_MID=-1
  send WBOSS srv -1 0 0 0
  send ANN srv "${M_NAME[t]} has been slain! ${SP_NAME[$k]} landed the final blow - ${#rec[@]} hero(es) share the spoils."
  slog "world boss ${M_NAME[t]} killed (${#rec[@]} contributors)"
}

wb_second() {
  if (( WB_MID < 0 || ! MALIVE[WB_MID] )); then
    (( WB_NEXT > 0 && NOW >= WB_NEXT )) && wb_spawn
    return
  fi
  local m=$WB_MID
  if (( NOW >= WB_GONE )); then
    MALIVE[m]=0; unset "AL[$m]" "OCC[W:${MX[m]}:${MY[m]}]"
    send MDIE srv W "$m" "-"; send WBOSS srv -1 0 0 0
    send ANN srv "${M_NAME[${MT[m]}]} grows tired of waiting and vanishes..."
    WB_MID=-1 WB_NEXT=$(( NOW + 300000 ))
    return
  fi
  if (( NOW >= WB_PING )); then WB_PING=$(( NOW + 4000 )); send WBOSS srv "$m" "${MT[m]}" "${MX[m]}" "${MY[m]}"; fi
}

# --- weather & clock ------------------------------------------------------------
weather_second() {
  local i k kinds
  for i in "${!WEA_REG[@]}"; do
    if [[ -n ${WS_T[i]} ]]; then
      (( NOW >= WS_E[i] )) || continue
      send WEATHER srv "$i" - 0
      WS_T[i]="" WS_N[i]=$(( NOW + 240000 + (RANDOM << 15 | RANDOM) % 360000 ))
    elif (( NOW >= ${WS_N[i]:-0} )); then
      kinds=(${WEA_KIND[i]}); k=${kinds[RANDOM % ${#kinds[@]}]}
      WS_T[i]=$k WS_E[i]=$(( NOW + 120000 + (RANDOM << 15 | RANDOM) % 120000 ))
      send WEATHER srv "$i" "$k" $(( (WS_E[i] - NOW) / 1000 ))
      slog "weather: $k over ${WEA_REG[i]}"
    fi
  done
}

clock_second() {
  local gm=$(( (NOW - SRV_CLK0) % DAYLEN / GMIN ))
  NIGHT=$(( gm >= 1260 || gm < 300 ))
  (( NOW >= ${CLK_NEXT:-0} )) && { CLK_NEXT=$(( NOW + 10000 )); send CLOCK srv $(( (NOW - SRV_CLK0) % DAYLEN )); }
}

srv_invite() {  # from targetname
  local from=$1 want=${2,,} id tid="" pid n
  for id in "${!SP_NAME[@]}"; do [[ ${SP_NAME[$id],,} == "$want" && $id != "$from" ]] && tid=$id; done
  if [[ -z $tid ]]; then send INFO srv "$from" "No player named '$2' is online."; return; fi
  pid=${SP_PARTY[$from]}
  if [[ -n $pid ]]; then
    if [[ ${PT_LEADER[$pid]} != "$from" ]]; then send INFO srv "$from" "Only the party leader can invite."; return; fi
    n=(${PT_MEMBERS[$pid]}); (( ${#n[@]} >= 4 )) && { send INFO srv "$from" "Your party is full (max 4)."; return; }
  fi
  if [[ -n ${SP_PARTY[$tid]} && ${SP_PARTY[$tid]} == "$pid" ]]; then send INFO srv "$from" "${SP_NAME[$tid]} is already in your party."; return; fi
  INV_FROM[$tid]=$from
  send PINV srv "$tid" "${SP_NAME[$from]}"
  send INFO srv "$from" "You invited ${SP_NAME[$tid]} to your party."
}

srv_accept() {
  local id=$1 from=${INV_FROM[$1]} pid n
  unset "INV_FROM[$id]"
  if [[ -z $from || -z ${SP_NAME[$from]} ]]; then send INFO srv "$id" "You have no pending party invite."; return; fi
  [[ -n ${SP_PARTY[$id]} ]] && srv_pleave "$id"
  pid=${SP_PARTY[$from]}
  if [[ -z $pid ]]; then
    NPARTY=$(( NPARTY + 1 )); pid="p$NPARTY"
    PT_LEADER[$pid]=$from PT_MEMBERS[$pid]=$from SP_PARTY[$from]=$pid PT_QUESTS[$pid]=""
  fi
  n=(${PT_MEMBERS[$pid]})
  if (( ${#n[@]} >= 4 )); then send INFO srv "$id" "That party is full."; return; fi
  PT_MEMBERS[$pid]+=" $id"; SP_PARTY[$id]=$pid
  party_send "$pid"
  slog "party $pid: ${PT_MEMBERS[$pid]}"
}

srv_pleave() {
  local id=$1 pid=${SP_PARTY[$1]} m rest=()
  [[ -n $pid ]] || return
  unset "SP_PARTY[$id]"
  for m in ${PT_MEMBERS[$pid]}; do [[ $m == "$id" ]] || rest+=("$m"); done
  if (( ${#rest[@]} <= 1 )); then
    for m in "${rest[@]}"; do unset "SP_PARTY[$m]"; done
    unset "PT_LEADER[$pid]" "PT_MEMBERS[$pid]" "PT_INST[$pid]" "PT_QUESTS[$pid]"
    send PARTY srv "$pid" "" ""
  else
    PT_MEMBERS[$pid]="${rest[*]}"
    [[ ${PT_LEADER[$pid]} == "$id" ]] && PT_LEADER[$pid]=${rest[0]}
    party_send "$pid"
  fi
}

srv_qadd() {  # from code  (party leader accepts a quest for the whole party)
  local id=$1 q=$2 pid=${SP_PARTY[$1]} n e
  [[ $q =~ ^[KDT]\.(0|[1-9][0-9]{0,2})\.([1-9][0-9]?)\.0\.(0|[1-9][0-9]{0,5})\.(0|[1-9][0-9]{0,5})$ ]] || return
  if [[ -z $pid ]]; then send INFO srv "$id" "You are not in a party."; return; fi
  if [[ ${PT_LEADER[$pid]} != "$id" ]]; then send INFO srv "$id" "Only the party leader can accept party quests."; return; fi
  n=(${PT_QUESTS[$pid]})
  (( ${#n[@]} >= 3 )) && { send INFO srv "$id" "Your party already has 3 quests."; return; }
  for e in "${n[@]}"; do [[ ${e%.*.*.*.*} == "${q%.*.*.*.*}" ]] && { send INFO srv "$id" "Your party already has that quest."; return; }; done
  PT_QUESTS[$pid]+=" $q"; PT_QUESTS[$pid]=${PT_QUESTS[$pid]# }
  send PQUEST srv "$pid" "${PT_QUESTS[$pid]// /,}"
  slog "party $pid accepted quest $q"
}

make_instance() {  # dtype pid mythic-level ids...
  local dt=$1 pid=$2 mk=${3:-0} map seed n scale pool i j a cnt csv
  shift 3
  NINST=$(( NINST + 1 )); map="D$NINST"
  seed=$(( ((RANDOM << 15) | RANDOM) & 0x7fffffff ))
  gen_dungeon "$map" "$dt" "$seed"
  n=$#; scale=$(( 100 + 70 * (n - 1) )); (( dt == RAID_DT )) && scale=$(( 100 + 90 * (n - 1) ))
  IN_TYPE[$map]=$dt IN_SEED[$map]=$seed IN_PARTY[$map]=$pid IN_EMPTY[$map]=0 IN_SCALE[$map]=$scale IN_DONE[$map]=0
  IN_MYTH[$map]=$mk IN_T0[$map]=$NOW IN_LIM[$map]=0; myth_afx; IN_AFC[$map]=$MC
  (( mk )) && { myth_limit "$dt"; IN_LIM[$map]=$MYL; }
  if [[ -n $pid ]]; then PT_INST[$pid]=$map; else SOLO_INST[$1]=$map; fi
  pool=(${D_POOL[dt]})
  for (( i = 1; i < ${#DG_ROOMS[@]}; i++ )); do
    a=(${DG_ROOMS[i]})
    cnt=$(( 2 + RANDOM % 2 + (n > 2 ? 1 : 0) ))
    (( i == ${#DG_ROOMS[@]} - 1 )) && cnt=2
    for (( j = 0; j < cnt; j++ )); do
      free_tile "${a[0]}" "${a[1]}" $(( a[0] + a[2] - 1 )) $(( a[1] + a[3] - 1 )) "$map" || continue
      inst_mon "$map" "${pool[RANDOM % ${#pool[@]}]}" "$SX" "$SY" "$scale" "$mk"
    done
  done
  if (( ${#DG_ROOMS[@]} > 3 )); then                      # v2.0: an elite guards the middle of the dungeon
    a=(${DG_ROOMS[${#DG_ROOMS[@]} / 2]})
    free_tile "${a[0]}" "${a[1]}" $(( a[0] + a[2] - 1 )) $(( a[1] + a[3] - 1 )) "$map" && inst_mon "$map" "${D_ELITE[dt]}" "$SX" "$SY" "$scale" "$mk"
  fi
  for (( j = 0; j < ${D_CHESTS[dt]:-2}; j++ )); do        # ... and treasure chests hide in the side rooms
    i=$(( 1 + RANDOM % (${#DG_ROOMS[@]} - 2) )); a=(${DG_ROOMS[i]})
    free_tile "${a[0]}" "${a[1]}" $(( a[0] + a[2] - 1 )) $(( a[1] + a[3] - 1 )) "$map" && spawn_mon "$map" "$CHEST" "$SX" "$SY" -1 100 0
  done
  [[ -n ${OCC[$map:$DG_BX:$DG_BY]} ]] && unset "OCC[$map:$DG_BX:$DG_BY]"
  inst_mon "$map" "${D_BOSS[dt]}" "$DG_BX" "$DG_BY" "$scale" "$mk"
  csv="$*"; csv=${csv// /,}
  send DSTART srv "$map" "$dt" "$seed" "$scale" "$csv" "$mk" "${IN_LIM[$map]}" 0
  srv_sync "$map"
  slog "instance $map (${D_NAME[dt]}, seed $seed, scale $scale%) for: $csv"
}

srv_dreq() {  # from dtype [mythic level]
  local id=$1 dt=$2 mk=${3:-0} pid ex m ids=() far=0
  [[ $dt =~ ^(0|[1-9][0-9]?)$ ]] && (( dt < NDT )) || return
  [[ $mk =~ ^(0|[1-9][0-9]?)$ ]] && (( mk <= MYTH_MAX )) || mk=0          # (no "08": octal)
  (( mk && (mk < 2 || ${SP_LVL[$id]:-1} < MAXLVL || dt == RAID_DT) )) && mk=0
  (( NOW - ${DREQ_T[$id]:-0} >= 1500 )) || return          # one request per 1.5 s per player
  DREQ_T[$id]=$NOW
  pid=${SP_PARTY[$id]}
  ex=${SOLO_INST[$id]}; [[ -n $pid ]] && ex=${PT_INST[$pid]}
  # re-entering resumes your running instance - unless its boss is already dead
  if [[ -n $ex && ${IN_TYPE[$ex]} == "$dt" && ${IN_DONE[$ex]} == 0 ]]; then
    send DSTART srv "$ex" "$dt" "${IN_SEED[$ex]}" "${IN_SCALE[$ex]}" "$id" "${IN_MYTH[$ex]:-0}" "${IN_LIM[$ex]:-0}" $(( NOW - ${IN_T0[$ex]:-$NOW} ))
    srv_sync "$ex"; return
  fi
  if (( ${#IN_TYPE[@]} >= ${SHELLMMO_MAX_INST:-40} )); then
    send INFO srv "$id" "The dungeons are overcrowded right now - try again in a minute."; return
  fi
  if [[ -n $pid ]]; then
    if [[ ${PT_LEADER[$pid]} != "$id" ]]; then
      send INFO srv "$id" "Only your party leader (${SP_NAME[${PT_LEADER[$pid]}]}) can open a new dungeon."; return
    fi
    for m in ${PT_MEMBERS[$pid]}; do
      [[ ${SP_MAP[$m]} == W && ${SP_DEAD[$m]:-0} == 0 ]] || { [[ $m != "$id" ]] && far=1; continue; }
      cheb $(( ${SP_X[$m]} - D_ENTX[dt] )) $(( ${SP_Y[$m]} - D_ENTY[dt] ))
      if (( D <= 20 )) || [[ $m == "$id" ]]; then ids+=("$m"); else far=1; fi
    done
  fi
  (( ${#ids[@]} )) || ids=("$id")
  make_instance "$dt" "$pid" "$mk" "${ids[@]}"
  (( far )) && send PINFO srv "$pid" "The party entered the ${D_NAME[dt]}. Walk into its entrance to join them."
}

close_instance() {
  local map=$1 m y p
  for m in ${IN_MONS[$map]}; do
    unset "AL[$m]" "RS[$m]" "OCC[$map:${MX[m]}:${MY[m]}]" "MX[m]" "MY[m]" "MT[m]" "MHP[m]" "MMAX[m]" "MMAP[m]" "MALIVE[m]" \
      "MHX[m]" "MHY[m]" "MNEXT[m]" "MFRZ[m]" "MAGG[m]" "MRESP[m]" "MZONE[m]" "MATKN[m]" "MSCALE[m]" "MWR[m]" "MCON[m]" "MPH[m]" "MSLOT[m]" "MCH[m]" "MHEALT[m]" \
      "MDS[m]" "MADD[m]"
  done
  for (( y = 0; y < ${MAPH[$map]:-0}; y++ )); do unset "MAPROW[$map:$y]"; done
  for p in "${!PT_INST[@]}"; do [[ ${PT_INST[$p]} == "$map" ]] && unset "PT_INST[$p]"; done
  for p in "${!SOLO_INST[@]}"; do [[ ${SOLO_INST[$p]} == "$map" ]] && unset "SOLO_INST[$p]"; done
  unset "IN_TYPE[$map]" "IN_SEED[$map]" "IN_PARTY[$map]" "IN_EMPTY[$map]" "IN_SCALE[$map]" "IN_DONE[$map]" "IN_MONS[$map]" "MAPW[$map]" "MAPH[$map]" \
    "IN_MYTH[$map]" "IN_T0[$map]" "IN_LIM[$map]" "IN_AFC[$map]"
  send DEND srv "$map"
  slog "instance $map closed"
}

srv_second() {
  local m id map cnt z
  for m in "${!RS[@]}"; do
    (( NOW >= MRESP[m] )) || continue
    if (( MZONE[m] == -3 )); then            # NPCs come back home
      [[ -n ${OCC[W:${MHX[m]}:${MHY[m]}]} ]] && continue
      SX=${MHX[m]} SY=${MHY[m]}
    else
      zone_tile "${MZONE[m]}" || continue
      MHX[m]=$SX MHY[m]=$SY
    fi
    unset "RS[$m]"
    champ_roll "$m"
    MX[m]=$SX MY[m]=$SY MHP[m]=${MMAX[m]} MALIVE[m]=1 MAGG[m]="" MNEXT[m]=0 MFRZ[m]=0
    (( M_BOSS[MT[m]] == 2 )) && { region_of "$SX" "$SY" nosafe; send ANN srv "Hunters whisper that ${M_NAME[MT[m]]} roams the $RNAME again."; }
    OCC["W:$SX:$SY"]=$m; AL[$m]=1
    (( M_KIND[MT[m]] < 3 )) && wake "$m"
    mon_state "$m"
    (( MZONE[m] == -3 )) && send ANN srv "${N_FULL[${MT[m]}]} is back in business."
  done
  for id in "${!SP_WANTED[@]}"; do (( NOW >= SP_WANTED[$id] )) && set_wanted "$id" 0; done
  for id in "${!SP_NAME[@]}"; do
    (( NOW - ${SP_SEEN[$id]:-0} > 15000 )) && srv_drop "$id"
  done
  for id in "${!ACC_NAME[@]}"; do               # logged in but never entered the world (or gone): forget after ten minutes
    [[ -z ${SP_NAME[$id]} ]] && (( NOW - ${ACC_SEEN[$id]:-0} > 600000 )) && acc_forget "$id"
  done
  for map in "${!IN_TYPE[@]}"; do
    cnt=0
    for id in "${!SP_NAME[@]}"; do [[ ${SP_MAP[$id]} == "$map" ]] && cnt=$(( cnt + 1 )); done
    if (( cnt > 0 )); then IN_EMPTY[$map]=0
    elif (( IN_EMPTY[$map] == 0 )); then IN_EMPTY[$map]=$NOW
    elif (( NOW - IN_EMPTY[$map] > 30000 )); then close_instance "$map"
    fi
  done
  wb_second; weather_second; clock_second; inv_second
  (( NOW / 1000 % 10 == 0 )) && wake_check
}

srv_line() {
  local line=$1 tag typ from a b c d e f g h i
  case $line in SM1\|*\|srv\|*) return ;; esac
  (( ${#line} <= 2048 )) || return
  IFS='|' read -r tag typ from a b c d e f g h i <<< "$line"
  [[ $tag == SM1 && $from =~ ^[0-9a-f]{6}$ ]] || return
  case $typ in                                        # v6.2: heroes live on the server
    ALOAD) srv_aload "$from" "$a" "$b" "$c"; return ;;
    ASAVE) srv_asave "$from" "$a" "$b" "$c"; return ;;
  esac
  if (( ACCT_ON )); then                              # nobody plays without logging in, and only as the hero they logged in as
    [[ -n ${ACC_NAME[$from]} ]] || { acc_nudge "$from"; return; }
    ACC_SEEN[$from]=$NOW
    case $typ in HELLO|POS) [[ ${a//[^A-Za-z0-9_-]/} == "${ACC_NAME[$from]}" ]] || return ;; esac
  fi
  case $typ in
    HELLO) srv_hello "$from" "$a" ;;
    POS)   # name cls lvl map x y hp maxhp dead sym col
      isnum "$c" && isnum "$e" && isnum "$f" && [[ $d =~ ^(W|D[0-9]+|H[0-9]{1,8})$ ]] || return   # v5.0: H = a room at the inn
      (( c <= 99 && e <= 999 && f <= 999 )) || return
      [[ -n ${SP_NAME[$from]} ]] || srv_hello "$from" "$a"
      SP_LVL[$from]=$c SP_MAP[$from]=$d SP_X[$from]=$e SP_Y[$from]=$f SP_SEEN[$from]=$NOW
      [[ $b =~ ^[0-9]$ ]] && (( b < NCLS )) && SP_CLS[$from]=$b
      if [[ ${i:0:1} == 1 ]]; then
        if [[ ${SP_DEAD[$from]} != 1 ]]; then
          set_wanted "$from" 0                                    # death pays for your crimes
          (( ${IN_MYTH[$d]:-0} )) && { IN_T0[$d]=$(( ${IN_T0[$d]} - 5000 )); send BOSS srv "$d" "${SP_NAME[$from]} has fallen - the clock loses 5 seconds!" 0 0; }
        fi
        SP_DEAD[$from]=1
      else SP_DEAD[$from]=0; fi ;;
    BYE)    srv_drop "$from" ;;
    HIT)    srv_hit "$from" "$a" "$b" "$c" "$d" ;;
    INV)    srv_invite "$from" "$b" ;;
    PACC)   srv_accept "$from" ;;
    PLEAVE) srv_pleave "$from" ;;
    QADD)   srv_qadd "$from" "$a" ;;
    QTALK)  isnum "$a" && [[ -n ${SP_PARTY[$from]} ]] && pq_progress "${SP_PARTY[$from]}" "T.$a" ;;
    DREQ)   srv_dreq "$from" "$a" "$b" ;;
    SYNC)   [[ $a =~ ^(W|D[0-9]+)$ ]] && { SYNC_PEND[$a]=1; sync_flush; } ;;
  esac
}

server_main() {
  local line rc next_ai=0 next_sec=0 tries=0 i
  trap '' PIPE
  trap 'slog "world server stopping"; exit 0' INT TERM
  on_line() { srv_line "$1"; }
  net_lost() { net_up=0; exec 7>&- 2>/dev/null; slog "lost connection to the hub"; }
  load_world
  ACCT_ON=1; [[ $SHELLMMO_OPEN == 1 ]] && ACCT_ON=0       # SHELLMMO_OPEN=1: no logins (old tests)
  (( ACCT_ON )) && acc_init
  slog "shellmmorpg world server v$VERSION - map ${MAPW[W]}x${MAPH[W]} - port $NET_PORT"
  NET_HOST=127.0.0.1
  until net_connect; do
    tries=$(( tries + 1 )); (( tries > 50 )) && { slog "hub not reachable, giving up"; exit 1; }
    sleep 0.2
  done
  now_ms; WH_LAST=$(( NOW / 150 - 1 )); spawn_world; WB_NEXT=$(( NOW + ${SHELLMMO_WB_DELAY:-150000} ))
  SRV_CLK0=$(( NOW - ${SHELLMMO_CLOCK:-480} * GMIN ))      # the world wakes up at 08:00
  for i in "${!WEA_REG[@]}"; do WS_T[i]="" WS_N[i]=$(( NOW + ${SHELLMMO_WEATHER_DELAY:-30000} + (RANDOM << 15 | RANDOM) % 300000 )); done
  send ANN srv "World server online."
  while :; do
    if (( ! net_up )); then
      if [[ $MODE == server ]] && ! alive "$HUB_PID"; then         # v6.3: the dedicated server brings its hub back
        slog "the hub is gone - restarting it"; start_hub && slog "hub restarted"
      fi
      sleep 1; net_connect && { slog "reconnected"; tries=0; continue; }
      tries=$(( tries + 1 )); (( tries > 60 )) && exit 1
      continue
    fi
    IFS= read -r -t 0.04 -u 7 line; rc=$?
    now_ms
    if (( rc == 0 )); then on_line "$net_buf$line"; net_buf=""; net_poll 400
    elif (( rc > 128 )); then net_buf+=$line
    else net_lost; fi
    now_ms
    if (( NOW >= next_ai )); then next_ai=$(( NOW + 150 )); ai_tick; (( ${#SYNC_PEND[@]} )) && sync_flush; fi
    if (( NOW >= next_sec )); then next_sec=$(( NOW + 1000 )); srv_second; fi
  done
}

# ---------------------------------------------------------------------------
#  Module 03b - v4.5 world server: mythic dungeons (scaling, affixes, the clock,
#  rewards), the raid boss Nyxara, invasions, delayed area attacks, loot that
#  is handed out directly (LOOT i:<code>).
# ---------------------------------------------------------------------------

inst_mon() {  # map type x y party-scale mythic-level: a monster of an instance
  local map=$1 t=$2 sc=$5 mk=${6:-0} md=100
  if (( mk )); then
    myth_scale "$t" "$mk" "$sc"; sc=$MSC md=$MDSC
  fi
  spawn_mon "$map" "$t" "$3" "$4" -1 "$sc"
  MDS[MID]=$md
  if (( mk >= 4 && M_BOSS[t] == 0 && M_KIND[t] == 0 && RANDOM % 3 == 0 )); then   # this week's champion affix
    myth_afx; MCH[MID]=$MB
  fi
}

myth_scale() {  # type key-level party-scale -> MSC (health, xp, gold %) MDSC (damage %)
  local t=$1 k=$2 h d
  base_stats "${M_LVL[t]}"; h=$BH d=$BD
  base_stats "$MYTH_LVL"
  MSC=$(( $3 * BH / h * (100 + 12 * k) / 100 )) MDSC=$(( 100 * BD / d * (100 + 6 * k) / 100 ))
  myth_afx
  if (( MA == 0 && M_BOSS[t] == 0 )); then MSC=$(( MSC * 130 / 100 )) MDSC=$(( MDSC * 115 / 100 ))       # fortified
  elif (( MA == 1 && M_BOSS[t] )); then MSC=$(( MSC * 140 / 100 )) MDSC=$(( MDSC * 120 / 100 )); fi     # tyrannical
}

myth_bolster() {  # mid that just died: its friends nearby grow stronger
  local m=$1 map=${MMAP[$1]} o
  for o in ${IN_MONS[$map]}; do
    (( MALIVE[o] && M_BOSS[MT[o]] == 0 && M_KIND[MT[o]] == 0 )) || continue
    cheb $(( MX[o] - MX[m] )) $(( MY[o] - MY[m] )); (( D <= 6 )) || continue
    MHP[o]=$(( MHP[o] + MMAX[o] / 5 )); (( MHP[o] > MMAX[o] )) && MHP[o]=${MMAX[o]}
    MDS[o]=$(( ${MDS[o]:-100} + 15 ))
    send MHP srv "$map" "$o" "${MHP[o]}" ""
  done
}

srv_loot() {  # player slot tier rarity sockets -> sends LOOT i:<code> (gear for the player's class)
  local p=$1 s=$2 r
  [[ $s == "?" ]] && { r=$(( RANDOM % 100 )); if (( r < 34 )); then s=W; elif (( r < 56 )); then s=A; elif (( r < 72 )); then s=H; elif (( r < 86 )); then s=O; else s=J; fi; }
  kind_pick "$s" "${SP_CLS[$p]:-0}"
  ITEM="$s.$KP.$3.$4"
  (( $5 > 0 )) && { ITEM+=.; for (( r = 0; r < $5; r++ )); do ITEM+=__; done; }
  send LOOT srv "$p" "i:$ITEM"
}

myth_finish() {  # map: the boss of a mythic dungeon is dead
  local map=$1 k=${IN_MYTH[$1]} el=$(( NOW - ${IN_T0[$1]} )) lim=${IN_LIM[$1]} up=0 val p r n=0 names=""
  (( el <= lim )) && up=1; (( el <= lim * 6 / 10 )) && up=2
  val=$(( 20 + 6 * k )); (( up )) && val=$(( val * 3 / 2 ))
  for p in "${!SP_NAME[@]}"; do
    [[ ${SP_MAP[$p]} == "$map" ]] || continue
    n=$(( n + 1 )); names+="${SP_NAME[$p]}, "
    send MDONE srv "$p" "$k" "$up" $(( el / 1000 )) "$val"
    r=2; (( RANDOM % 100 < 5 + 2 * k )) && r=3
    srv_loot "$p" "?" 12 "$r" $(( r == 3 ? 3 : 1 + RANDOM % 2 ))
    (( RANDOM % 100 < 10 + 3 * k )) && { gem_mat $(( RANDOM % 6 )) 4; send LOOT srv "$p" "g$GM"; }
  done
  if (( up )); then send ANN srv "${names%, } completed ${D_NAME[${IN_TYPE[$map]}]} on Mythic +$k in time!"
  else send ANN srv "${names%, } completed ${D_NAME[${IN_TYPE[$map]}]} on Mythic +$k (too slow)."; fi
}

# --- the raid boss -----------------------------------------------------------------------------------------------
raid_adds_alive() {  # boss mid -> 0 if one of her guards still lives
  local o
  for o in ${IN_MONS[${MMAP[$1]}]}; do (( MALIVE[o] && ${MADD[o]:--1} == $1 )) && return 0; done
  return 1
}
aoe_add() {  # map x y radius delay dmg element mid: marked ground, then the blow
  local c="" i j
  for (( j = -$4; j <= $4; j++ )); do for (( i = -$4; i <= $4; i++ )); do c+="$(( $2 + i )),$(( $3 + j )) "; done; done
  send FX srv "$1" warn "$c"
  AOE_Q+=("$(( NOW + $5 )) $1 $2 $3 $4 $6 $7 $8")
}
aoe_tick() {
  local i a q c j k
  for i in "${!AOE_Q[@]}"; do
    a=(${AOE_Q[i]})
    (( NOW >= a[0] )) || continue
    unset "AOE_Q[i]"
    c=""; for (( j = -a[4]; j <= a[4]; j++ )); do for (( k = -a[4]; k <= a[4]; k++ )); do c+="$(( a[2] + k )),$(( a[3] + j )) "; done; done
    send FX srv "${a[1]}" fire "$c"
    for q in ${PLIST[${a[1]}]}; do
      cheb $(( ${SP_X[$q]} - a[2] )) $(( ${SP_Y[$q]} - a[3] ))
      (( D <= a[4] )) && send MATK srv "${a[1]}" "${a[7]}" "$q" "${a[5]}" "${a[6]}" ""
    done
  done
  AOE_Q=("${AOE_Q[@]}")
}
raid_attack() {  # boss target damage: Nyxara's three phases
  local m=$1 t=${MT[$1]} map=${MMAP[$1]} dmg=$3 q n=0
  (( NOW - ${IN_T0[$map]:-$NOW} > 480000 )) && dmg=$(( dmg * 2 ))       # 8 minutes: the eclipse devours everything
  MATKN[m]=$(( MATKN[m] + 1 ))
  if (( MHP[m] * 3 < MMAX[m] && MATKN[m] % 5 == 0 )); then                # phase 3: total eclipse - run!
    send BOSS srv "$map" "${M_NAME[t]}: TOTAL ECLIPSE! Get away from her!" "${MX[m]}" "${MY[m]}"
    aoe_add "$map" "${MX[m]}" "${MY[m]}" 4 2200 $(( dmg * 35 / 10 )) 4 "$m"; return
  fi
  if (( MATKN[m] % 3 == 0 )); then                                        # eclipse meteors on everyone
    send BOSS srv "$map" "${M_NAME[t]} calls down the dark stars - move!" "${MX[m]}" "${MY[m]}"
    for q in ${PLIST[$map]}; do
      (( n++ < 5 )) || break
      aoe_add "$map" "${SP_X[$q]}" "${SP_Y[$q]}" 1 1800 $(( dmg * 22 / 10 )) 6 "$m"
    done
    return
  fi
  mon_hit "$m" "$2" "$dmg"
}
raid_finish() {  # map: Nyxara is dead
  local map=$1 p names=""
  for p in "${!SP_NAME[@]}"; do
    [[ ${SP_MAP[$p]} == "$map" ]] || continue
    names+="${SP_NAME[$p]}, "
    srv_loot "$p" "?" 12 3 3
    (( RANDOM % 100 < 40 )) && send LOOT srv "$p" "i:U.${RAID_UQ[RANDOM % ${#RAID_UQ[@]}]}"
    (( RANDOM % 2 )) && { gem_mat $(( RANDOM % 6 )) 4; send LOOT srv "$p" "g$GM"; }
  done
  send ANN srv "${names%, } brought down Nyxara, Queen of the Eclipse! The sky is clear again."
}

# --- invasions: now and then the Horde marches on a town ------------------------------------------------------------
inv_towns() {  # -> INV_T: "x y questgiver" of every town that has someone to give quests
  local t w a
  INV_T=()
  for t in "${!N_ROLE[@]}"; do
    [[ -n ${N_QK[$t]} && -n ${N_HOME[$t]} ]] || continue
    for w in "${WAYSTONES[@]}"; do a=($w); [[ ${a[0]//_/ } == "${N_HOME[$t]}" ]] && { INV_T+=("${a[1]} ${a[2]} $t"); break; }; done
  done
}
inv_second() {  # once a second
  local n=0 p m alive=0
  if (( INV_TOWN < 0 )); then
    (( INV_NEXT )) || INV_NEXT=$(( NOW + ${SHELLMMO_INV_DELAY:-2400000} + RANDOM % 900000 ))
    (( NOW >= INV_NEXT )) || return
    for p in "${!SP_NAME[@]}"; do [[ ${SP_MAP[$p]} == W ]] && n=$(( n + 1 )); done
    (( n )) || { INV_NEXT=$(( NOW + 120000 )); return; }
    inv_start; return
  fi
  for m in $INV_MONS; do (( MALIVE[m] )) && alive=$(( alive + 1 )); done
  if (( NOW >= INV_END )); then
    for m in $INV_MONS; do (( MALIVE[m] )) && { MALIVE[m]=0; unset "AL[$m]" "OCC[W:${MX[m]}:${MY[m]}]"; send MDIE srv W "$m" "-"; }; done
    send ANN srv "The Horde has sacked ${N_HOME[${INV_Q}]}... it will be rebuilt, but nobody is paid for a defeat."
    inv_end; return
  fi
  (( alive )) && return
  if (( INV_WAVE < 3 )); then INV_WAVE=$(( INV_WAVE + 1 )); inv_wave; return; fi
  inv_win
}
inv_start() {
  local a
  (( ${#INV_T[@]} )) || inv_towns
  (( ${#INV_T[@]} )) || { INV_NEXT=$(( NOW + 600000 )); return; }
  INV_TOWN=$(( RANDOM % ${#INV_T[@]} )); a=(${INV_T[INV_TOWN]})
  INV_X=${a[0]} INV_Y=${a[1]} INV_Q=${a[2]} INV_WAVE=1 INV_END=$(( NOW + 720000 )) INV_MONS="" INV_PART=()
  send ANN srv "THE HORDE MARCHES ON ${N_HOME[$INV_Q]^^}! Defend the town - three waves, twelve minutes."
  inv_wave
}
inv_wave() {  # spawns the next wave around the town
  local k=(${N_QK[$INV_Q]}) n i tries t
  case $INV_WAVE in 1) n=8 ;; 2) n=10 ;; *) n=4 ;; esac
  INV_MONS=""
  for (( i = 0; i < n + (INV_WAVE == 3); i++ )); do
    t=${k[RANDOM % ${#k[@]}]}
    (( INV_WAVE == 3 && i == n )) && t=${D_ELITE[${N_QD[$INV_Q]:-0}]}
    for (( tries = 0; tries < 25; tries++ )); do
      free_tile $(( INV_X - 16 )) $(( INV_Y - 12 )) $(( INV_X + 16 )) $(( INV_Y + 12 )) W || continue
      in_safe_xy "$SX" "$SY" || break
    done
    (( tries < 25 )) || continue
    spawn_mon W "$t" "$SX" "$SY" -4 $(( INV_WAVE == 3 && i == n ? 300 : 120 )) 6
    MEV[MID]=1; INV_MONS+=" $MID"
    (( INV_WAVE == 2 && i < 3 )) && { MCH[MID]=$(( RANDOM % NCHP )); MMAX[MID]=$(( MMAX[MID] * 2 )) MHP[MID]=${MMAX[MID]}; }
    mon_state "$MID"
  done
  case $INV_WAVE in
    1) send ANN srv "The first wave reaches ${N_HOME[$INV_Q]}!" ;;
    2) send ANN srv "A second wave, with champions, storms ${N_HOME[$INV_Q]}!" ;;
    3) send ANN srv "The warlord of the Horde himself attacks ${N_HOME[$INV_Q]}!" ;;
  esac
}
inv_win() {
  local p l
  for p in "${!INV_PART[@]}"; do
    [[ -n ${SP_NAME[$p]} ]] || continue
    l=${SP_LVL[$p]:-1}
    send EVREW srv "$p" 25 $(( 40 * l * l + 400 )) $(( 30 * l + 200 ))
    tier_for "$l"; srv_loot "$p" "?" "$TF" 2 1
  done
  send ANN srv "${N_HOME[$INV_Q]} is saved! The defenders are paid in valor."
  inv_end
}
inv_end() { INV_TOWN=-1 INV_WAVE=0 INV_MONS="" INV_NEXT=$(( NOW + ${SHELLMMO_INV_DELAY:-2400000} + RANDOM % 900000 )); }

# ---------------------------------------------------------------------------
#  Module 03c - heroes live on the server (v6.2). A client logs in with
#  ALOAD name password; the server answers privately (AR<id>) with the saved
#  hero in chunks (DATA) or NONE (a new hero: it is created by the first
#  ASAVE). ASAVE sends the hero's save text in chunks of at most 1400
#  characters, newlines written as the unit separator (\x1f).
#  The hub delivers ALOAD/ASAVE to the world server only and AR<id> to the
#  player <id> only (python3 and socat hubs).
# ---------------------------------------------------------------------------
ACC_DIR="$DATA_DIR/chars" ACCT_ON=0 ACC_HASHER="" ACC_CHUNK=1400 ACC_MAXCH=60 ACC_STALE=8000
declare -A ACC_NAME=() ACC_NEW=() ACC_PASS=() ACC_BUF=() ACC_NS=() ACC_SEEN=() ACC_FAIL=() ACC_LOCK=() ACC_RATE=() ACC_SVN=() ACC_SVT=()
US=$'\x1f'

acc_init() {
  mkdir -p "$ACC_DIR" && chmod 700 "$ACC_DIR" 2>/dev/null
  if command -v sha256sum >/dev/null 2>&1; then ACC_HASHER="sha256sum"
  elif command -v shasum >/dev/null 2>&1; then ACC_HASHER="shasum -a 256"
  else ACC_HASHER="cksum"; fi
}

acc_hash() {  # salt password -> AH
  AH=$(printf '%s:%s' "$1" "$2" | $ACC_HASHER 2>/dev/null); AH=${AH%% *}
  [[ -n $AH ]] || AH=none
}

valid_pass() { local LC_ALL=C; [[ ${#1} -ge 4 && ${#1} -le 32 && $1 != *[^\ -{}-~]* ]]; }   # printable ASCII, no |

acc_reply() { send "AR$1" srv "${@:2}"; }

acc_valid_text() {  # a hero's save text: version line, KEY=printable lines, sane size
  local LC_ALL=C line n=0
  (( ${#1} > 0 && ${#1} <= 60000 )) || return 1
  [[ $1 == version=2* ]] || return 1
  while IFS= read -r line; do
    n=$(( n + 1 ))
    [[ $line =~ ^[A-Za-z][A-Za-z0-9_]*=[\ -~]*$ ]] || return 1
  done <<< "$1"
  (( n <= 400 )) && [[ $1 == *$'\n'CLS=[0-9]* ]]
}

acc_online() {  # name id -> 0 if somebody else is logged in as that name right now (stale sessions are dropped)
  local i
  for i in "${!ACC_NAME[@]}"; do
    [[ $i != "$2" && ${ACC_NAME[$i],,} == "${1,,}" ]] || continue
    if (( NOW - ${ACC_SEEN[$i]:-0} > ACC_STALE )); then srv_drop "$i"; acc_forget "$i"; continue; fi
    return 0
  done
  return 1
}

declare -A ACC_NUDGE=()
acc_nudge() {  # a player we do not know (the server restarted, or the session timed out): please log in again
  (( NOW - ${ACC_NUDGE[$1]:-0} >= 5000 )) || return
  ACC_NUDGE[$1]=$NOW
  (( ${#ACC_NUDGE[@]} > 500 )) && ACC_NUDGE=()
  acc_reply "$1" AUTH
}

acc_kick() {  # name new-id: end every other session of that hero
  local i
  for i in "${!ACC_NAME[@]}"; do
    [[ $i != "$2" && ${ACC_NAME[$i],,} == "${1,,}" ]] || continue
    acc_reply "$i" DENY KICK "$1 logged in somewhere else."
    slog "! $1 ($i) taken over by $2"
    srv_drop "$i"; acc_forget "$i"
  done
}

acc_forget() { unset "ACC_NAME[$1]" "ACC_NEW[$1]" "ACC_PASS[$1]" "ACC_BUF[$1]" "ACC_NS[$1]" "ACC_SEEN[$1]" "ACC_RATE[$1]" "ACC_SVN[$1]" "ACC_SVT[$1]"; }

srv_aload() {  # id name password [keep]
  local id=$1 name=$2 pw=$3 keep=$4 key salt hsh nm n total i txt chunk
  [[ $name =~ ^[A-Za-z0-9_-]{1,12}$ ]] || { acc_reply "$id" DENY NAME "Names are 1-12 letters, digits, _ or -."; return; }
  valid_pass "$pw" || { acc_reply "$id" DENY PASS "The password needs 4-32 characters (not |)."; return; }
  key=${name,,}
  (( NOW - ${ACC_RATE[$id]:-0} >= 700 )) || { acc_reply "$id" DENY LOCK "Slow down."; return; }
  ACC_RATE[$id]=$NOW
  (( NOW >= ${ACC_LOCK[$key]:-0} )) || { acc_reply "$id" DENY LOCK "Too many wrong passwords - try again in a minute."; return; }
  if [[ ! -r $ACC_DIR/$key.pw ]] && acc_online "$name" "$id"; then acc_reply "$id" DENY ONLINE "Somebody is creating $name right now."; return; fi
  ACC_SEEN[$id]=$NOW
  if [[ -r $ACC_DIR/$key.pw ]]; then
    read -r salt hsh nm < "$ACC_DIR/$key.pw"
    acc_hash "$salt" "$pw"
    if [[ $AH != "$hsh" ]]; then
      ACC_FAIL[$key]=$(( ${ACC_FAIL[$key]:-0} + 1 ))
      (( ACC_FAIL[$key] >= 5 )) && { ACC_LOCK[$key]=$(( NOW + 60000 )) ACC_FAIL[$key]=0; slog "! too many wrong passwords for $name ($id)"; }
      acc_reply "$id" DENY PASS "Wrong password."; return
    fi
    ACC_FAIL[$key]=0
    [[ $nm == "$name" ]] || { acc_reply "$id" DENY NAME "That hero is called $nm."; return; }
    if acc_online "$name" "$id"; then                # v6.3: the right password takes the hero over (quit and came straight back,
      if [[ $keep == keep ]]; then                    # or a session hanging somewhere) - but a reconnect never kicks anybody
        acc_reply "$id" DENY ONLINE "$name is playing somewhere else."; return
      fi
      acc_kick "$name" "$id"
    fi
    ACC_NAME[$id]=$name; unset "ACC_NEW[$id]" "ACC_PASS[$id]"
    slog "login: $name ($id)"
    if [[ $keep == keep ]]; then acc_reply "$id" OK; return; fi
    if [[ -r $ACC_DIR/$key.char ]]; then
      txt=$(<"$ACC_DIR/$key.char"); txt=${txt//$'\n'/$US}
      total=$(( (${#txt} + ACC_CHUNK - 1) / ACC_CHUNK ))
      for (( n = 1; n <= total; n++ )); do acc_reply "$id" DATA "$n" "$total" "${txt:(n-1)*ACC_CHUNK:ACC_CHUNK}"; done
      return
    fi
    ACC_NEW[$id]=0                               # the password exists but the hero never got saved: create it
    acc_reply "$id" NONE; return
  fi
  ACC_NAME[$id]=$name ACC_NEW[$id]=1 ACC_PASS[$id]=$pw
  slog "new hero: $name ($id)"
  acc_reply "$id" NONE
}

srv_asave() {  # id n total chunk
  local id=$1 n=$2 total=$3 chunk=$4 key text salt tmp
  [[ -n ${ACC_NAME[$id]} ]] || return
  isnum "$n" && isnum "$total" && (( n >= 1 && n <= total && total <= ACC_MAXCH && ${#chunk} <= ACC_CHUNK + 20 )) || return
  local LC_ALL=C
  [[ $chunk == *[^\ -~"$US"]* ]] && return
  ACC_SEEN[$id]=$NOW
  if (( n == 1 )); then ACC_BUF[$id]=$chunk ACC_NS[$id]=1
  elif (( ${ACC_NS[$id]:-0} == n - 1 )); then ACC_BUF[$id]+=$chunk ACC_NS[$id]=$n
  else unset "ACC_BUF[$id]" "ACC_NS[$id]"; return; fi
  (( n == total )) || return
  text=${ACC_BUF[$id]//$US/$'\n'}; unset "ACC_BUF[$id]" "ACC_NS[$id]"
  if (( NOW - ${ACC_SVT[$id]:-0} > 10000 )); then ACC_SVT[$id]=$NOW ACC_SVN[$id]=0; fi
  (( ++ACC_SVN[$id] <= 30 )) || { acc_reply "$id" BAD "saving too often"; return; }
  acc_valid_text "$text" || { acc_reply "$id" BAD "not a hero"; slog "! bad save from ${ACC_NAME[$id]} ($id)"; return; }
  key=${ACC_NAME[$id],,}
  if [[ -n ${ACC_NEW[$id]} && ! -r $ACC_DIR/$key.pw ]]; then
    printf -v salt '%04x%04x%04x' $RANDOM $RANDOM $RANDOM
    acc_hash "$salt" "${ACC_PASS[$id]}"
    printf '%s %s %s\n' "$salt" "$AH" "${ACC_NAME[$id]}" > "$ACC_DIR/$key.pw.tmp" && mv -f "$ACC_DIR/$key.pw.tmp" "$ACC_DIR/$key.pw" && chmod 600 "$ACC_DIR/$key.pw"
  fi
  [[ -r $ACC_DIR/$key.pw ]] || { acc_reply "$id" BAD "no such hero"; return; }
  unset "ACC_NEW[$id]" "ACC_PASS[$id]"
  tmp="$ACC_DIR/$key.char.tmp"
  if printf '%s\n' "$text" > "$tmp" && mv -f "$tmp" "$ACC_DIR/$key.char"; then acc_reply "$id" ACK
  else acc_reply "$id" BAD "the server could not write"; slog "! cannot write $ACC_DIR/$key.char"; fi
}

# ---------------------------------------------------------------------------
#  Module 04 - client: character (save/load), combat, skills, items, NPCs,
#  shops, quests, parties and the handlers for everything the network sends
# ---------------------------------------------------------------------------
declare -A OP_NAME=() OP_MAP=() OP_X=() OP_Y=() OP_CLS=() OP_LVL=() OP_HP=() OP_MAX=() OP_DEAD=() OP_SEEN=()
declare -A OP_MNT=() OP_SYM=() OP_COL=() OP_SAY=() OP_SAYT=() OP_WANTED=() CM_POS=() EXPL=() ATK_NPC=() GLY=()
CM_T=() CM_X=() CM_Y=() CM_HP=() CM_MAX=()
LOG_T=() LOG_C=() CHL_T=() CHL_C=() FX_X=() FX_Y=() FX_K=() FX_E=() INV=() QUESTS=() OFFERS=() PQ_CODES=()
PARTY_IDS=() SKCD=(0 0 0) DOT_M=() DOT_D=() DOT_N=() DOT_T=()
printf -v MY_ID '%06x' $(( ((RANDOM << 15) | RANDOM) & 0xffffff ))
CUR_MAP=W CUR_DT=-1 PX=$SPAWN_X PY=$SPAWN_Y FDX=0 FDY=1 DEAD=0 TARGET="" MY_PARTY="" PARTY_LEADER=""
next_move=0 next_attack=0 buff_until=0 anthem_until=0 str_until=0 iron_until=0 swift_until=0 immune_until=0
last_hurt=0 dead_until=0 clear_until=0 dreq_until=0 home_ready=0 last_pos=0 WANTED_UNTIL=0 MY_SAYT=0 MY_SAY=""
POS_DIRTY=1 MAP_DIRTY=1 NEED_FULL=1 UI="" SHOP="" CHATTING=0 CHAT_BUF="" WX=$SPAWN_X WY=$SPAWN_Y TAGS_ON=1
LRX=12 LRY=6 OFFER_LVL=0 LASTDMG=0 QSRC=board OFFER_SRC="" EXPW="" SEEN="" WAYS="" LAST_CHUNK=-1 WM_Z=0 WM_X=0 WM_Y=0
ARW=(↑ ↗ → ↘ ↓ ↙ ← ↖)

# colors
N=$'\e[0m' B=$'\e[1m' DIM=$'\e[2m'
K_SYS=$'\e[38;5;245m' K_CHAT=$'\e[38;5;255m' K_PARTY=$'\e[38;5;84m' K_WHISP=$'\e[38;5;213m'
K_HIT=$'\e[38;5;223m' K_HURT=$'\e[38;5;203m' K_LOOT=$'\e[38;5;220m' K_ANN=$'\e[1;38;5;214m' K_GOOD=$'\e[38;5;120m'
K_FRAME=$'\e[38;5;240m' K_NPC=$'\e[38;5;117m'

# terrain palette (every tile resets attributes so backgrounds never bleed)
Z_DOT=$'\e[0;38;5;22m.' Z_COM=$'\e[0;38;5;28m,' Z_TG=$'\e[0;38;5;64m"' Z_FLW=$'\e[0;38;5;211m*'
Z_TREE=$'\e[0;38;5;35mT' Z_WAT=$'\e[0;38;5;45;48;5;18m~' Z_MTN=$'\e[0;38;5;250m^' Z_ROAD=$'\e[0;38;5;137m.'
Z_BRG=$'\e[0;38;5;130m=' Z_SWP=$'\e[0;38;5;100m%' Z_ENT=$'\e[0;1;38;5;196m>' Z_EXT=$'\e[0;1;38;5;201m<'
Z_QST=$'\e[0;1;38;5;226m!' Z_FTN=$'\e[0;1;38;5;51mo' Z_FIRE=$'\e[0;1;38;5;202m*' Z_MEM=$'\e[0;38;5;237m'
Z_SAND=$'\e[0;38;5;180m.' Z_DUNE=$'\e[0;38;5;179m,' Z_CACT=$'\e[0;38;5;71mY' Z_SNOW=$'\e[0;38;5;255m.'
Z_DRIFT=$'\e[0;38;5;252m,' Z_PINE=$'\e[0;38;5;30mT' Z_ICE=$'\e[0;38;5;195;48;5;31m.' Z_ASH=$'\e[0;38;5;242m.'
Z_LAVA=$'\e[0;1;38;5;214;48;5;124m~' Z_ROCK=$'\e[0;38;5;238m^' Z_WAY=$'\e[0;1;38;5;201m&' Z_FOG=$'\e[0;38;5;238m' COMP_DIM=0
Z_CRYF=$'\e[0;38;5;183m.' Z_CRYS=$'\e[0;1;38;5;141m^' Z_JUNG=$'\e[0;38;5;34m,' Z_JTREE=$'\e[0;1;38;5;40mT'
Z_BAD=$'\e[0;38;5;166m.' Z_MESA=$'\e[0;38;5;130m^' Z_VOIDF=$'\e[0;38;5;97m.' Z_CHASM=$'\e[0;38;5;201;48;5;53m~'   # v2.0 lands
Z_AUT=$'\e[0;38;5;172m.' Z_ATREE=$'\e[0;1;38;5;166mT' Z_MYC=$'\e[0;38;5;139m,' Z_SHROOM=$'\e[0;1;38;5;170mT'          # v4.0 lands
Z_HGT=$'\e[0;38;5;109m.' Z_CRAG=$'\e[0;1;38;5;67m^' Z_BONE=$'\e[0;38;5;187m.'
set_palette() {  # dungeon type, -1 for the open world, -2 for a room at the inn (v5.0)
  Z_EXT=$'\e[0;1;38;5;201m<' Z2_EXT=$'\e[0;48;5;53m🌀'
  if (( $1 == -2 )); then
    Z_WALL=$'\e[0;38;5;137m#' Z_FLR=$'\e[0;38;5;94m.' Z_EXT=$'\e[0;1;38;5;180m<'
    Z2_WALL=$'\e[0;48;5;58m🟫' Z2_FLR=$'\e[0;48;5;94m  ' Z2_EXT=$'\e[0;48;5;94m🚪'
  elif (( $1 < 0 )); then
    Z_WALL=$'\e[0;38;5;244m#' Z_FLR=$'\e[0;38;5;239m.'
    Z2_WALL=$'\e[0;48;5;94m🧱' Z2_FLR=$'\e[0;48;5;102m  '
  else
    Z_WALL=$'\e[0;'"${D_WALL[$1]}m#" Z_FLR=$'\e[0;'"${D_FLOOR[$1]}m."
    Z2_WALL=$'\e[0;48;5;235m'"${D_WE[$1]:-🧱}" Z2_FLR=$'\e[0;'"${D_FLOOR[$1]/38;5/48;5}m  "
    Z2_z=$'\e[0;'"${D_FLOOR[$1]/38;5/48;5}m🦴"
  fi
  Z_FURN=$Z_FLR Z2_FURN=$Z2_FLR                  # "+": furniture stands here (rooms only), drawn on top
  declare -F tbg_build >/dev/null && tbg_build
  declare -F tiles_init >/dev/null && tiles_init
}
set_palette -1

colorize1() {   # CZ in place (classic ASCII, 1 column per tile)
  CZ=${CZ//'.'/$Z_DOT};  CZ=${CZ//','/$Z_COM};  CZ=${CZ//'"'/$Z_TG};   CZ=${CZ//'*'/$Z_FLW}
  CZ=${CZ//'T'/$Z_TREE}; CZ=${CZ//'~'/$Z_WAT};  CZ=${CZ//'^'/$Z_MTN};  CZ=${CZ//'#'/$Z_WALL}
  CZ=${CZ//'_'/$Z_FLR};  CZ=${CZ//':'/$Z_ROAD}; CZ=${CZ//'='/$Z_BRG};  CZ=${CZ//'%'/$Z_SWP}
  CZ=${CZ//'>'/$Z_ENT};  CZ=${CZ//'<'/$Z_EXT};  CZ=${CZ//'Q'/$Z_QST};  CZ=${CZ//'O'/$Z_FTN}
  CZ=${CZ//'F'/$Z_FIRE}
  CZ=${CZ//'S'/$Z_SAND}; CZ=${CZ//'s'/$Z_DUNE}; CZ=${CZ//'Y'/$Z_CACT}; CZ=${CZ//'N'/$Z_SNOW}
  CZ=${CZ//'n'/$Z_DRIFT}; CZ=${CZ//'P'/$Z_PINE}; CZ=${CZ//'I'/$Z_ICE};  CZ=${CZ//'A'/$Z_ASH}
  CZ=${CZ//'L'/$Z_LAVA}; CZ=${CZ//'R'/$Z_ROCK}; CZ=${CZ//'Z'/$Z_WAY}
  CZ=${CZ//K/$Z_CRYF}; CZ=${CZ//C/$Z_CRYS}; CZ=${CZ//J/$Z_JUNG}; CZ=${CZ//W/$Z_JTREE}
  CZ=${CZ//D/$Z_BAD}; CZ=${CZ//V/$Z_MESA}; CZ=${CZ//E/$Z_VOIDF}; CZ=${CZ//G/$Z_CHASM}
  CZ=${CZ//q/$Z_AUT}; CZ=${CZ//y/$Z_ATREE}; CZ=${CZ//M/$Z_MYC}; CZ=${CZ//U/$Z_SHROOM}
  CZ=${CZ//H/$Z_HGT}; CZ=${CZ//X/$Z_CRAG}; CZ=${CZ//B/$Z_BONE}; CZ=${CZ//'+'/$Z_FURN}
}

# glyphs for everything that moves (spliced between colorized terrain segments)
for (( t = 0; t < NM; t++ )); do GLY[m$t]=$'\e[0;'"${M_COL[t]}m${M_GLY[t]}"; done
declare -A FXG=([fire]=$'\e[0;1;38;5;202m*' [frost]=$'\e[0;1;38;5;117m*' [holy]=$'\e[0;1;38;5;228m+'
                [slash]=$'\e[0;1;38;5;231mx' [poison]=$'\e[0;1;38;5;118m%' [bone]=$'\e[0;1;38;5;255m/'
                [sound]=$'\e[0;1;38;5;213m~')
for k in "${!FXG[@]}"; do GLY[f$k]=${FXG[$k]}; done

LSPAN=()
for (( dy = -LRY; dy <= LRY; dy++ )); do isqrt $(( LRX * LRX * (LRY * LRY - dy * dy) / (LRY * LRY) )); LSPAN[dy+LRY]=$R; done

logm() {
  LOG_T+=("$1"); LOG_C+=("${2:-$K_SYS}")
  if (( ${#LOG_T[@]} > 80 )); then LOG_T=("${LOG_T[@]:20}"); LOG_C=("${LOG_C[@]:20}"); fi
}
chatm() {
  CHL_T+=("$1"); CHL_C+=("${2:-$K_CHAT}")
  if (( ${#CHL_T[@]} > 60 )); then CHL_T=("${CHL_T[@]:20}"); CHL_C=("${CHL_C[@]:20}"); fi
}

valid_sym() {  # single printable ASCII char, not the protocol separator
  local c
  [[ ${#1} == 1 ]] || return 1
  printf -v c '%d' "'$1"
  (( c >= 33 && c <= 126 && c != 124 ))
}

player_glyph() {  # id sym col dead   (HD: class sprite on the player's own color)
  if [[ $4 == 1 ]]; then GLY[p$1]=$'\e[0;38;5;240m'"$2" GLYH[p$1]=$'\e[0;48;5;238m💀'
  else GLY[p$1]=$'\e[0;1;38;5;'"${P_COLC[$3]}m$2" GLYH[p$1]=$'\e[0;48;5;'"${P_COLC[$3]}m"
    if [[ -n ${OP_MNT[$1]} ]]; then GLYH[p$1]+=${MNT_E[${OP_MNT[$1]}]}; else GLYH[p$1]+=${CEMO[${OP_CLS[$1]:-0}]}; fi; fi
}

# --- character ---------------------------------------------------------------
CHAR_VARS=(CLS LVL XP GOLD HP MP POT_H POT_M POT_GH POT_GM EL_STR EL_IRON EL_SWIFT SCROLL BREW EQW EQA EQO EQH EQJ WX WY KILLS DEATHS COLR
           MEAL1 MEAL2 TON_FROST TON_FIRE TON_VEIL BANKG BANKCAP STORY STORY_P STORY_SEEN ALLYN ALLIES)
CHAR_FILE="$DATA_DIR/$MY_NAME.char"

migrate_gear() {  # pre-1.6 saves: W.t.r / A.t.r become the class' own weapon and armor kind
  local i c p
  up() { local IFS=.; p=($1); if (( ${#p[@]} == 3 )); then if [[ ${p[0]} == W ]]; then c="W.${DEFW[CLS]}.${p[1]}.${p[2]}"; else c="A.${DEFA[CLS]}.${p[1]}.${p[2]}"; fi; else c=$1; fi; }
  [[ -n $EQW ]] && { up "$EQW"; EQW=$c; }
  [[ -n $EQA ]] && { up "$EQA"; EQA=$c; }
  for i in "${!INV[@]}"; do up "${INV[i]}"; INV[i]=$c; done
}

calc_stats() {  # base stats of the class + everything worn (gear your class can't use does nothing) + talents + gems
  local w=0 a=0 c shield=0
  B_CRIT=0 B_HP=0 B_MP=0 B_ARM=0 B_DMG=0 B_LIGHT=0
  for c in "$EQW" "$EQA" "$EQO" "$EQH" "$EQJ"; do
    [[ -n $c ]] || continue
    item_stats "$c"; [[ $ICLS == *"$CLS"* ]] || continue
    if [[ $IK == W ]]; then w=$IVAL; else a=$(( a + IVAL )); fi
    case $IBT in
      crit) B_CRIT=$(( B_CRIT + IBV )) ;; hp) B_HP=$(( B_HP + IBV )) ;; mp) B_MP=$(( B_MP + IBV )) ;;
      arm) B_ARM=$(( B_ARM + IBV )) ;; dmg) B_DMG=$(( B_DMG + IBV )) ;; light) B_LIGHT=$(( B_LIGHT + IBV )) ;;
    esac
  done
  tal_calc; gem_bonus
  B_HP=$(( B_HP + TB_HP + G_HP )) B_MP=$(( B_MP + TB_MP + G_MP )) B_CRIT=$(( B_CRIT + TB_CRIT + G_CRIT ))
  B_DMG=$(( B_DMG + TB_DMG + G_DMG )) B_ARM=$(( B_ARM + TB_ARM + G_ARM ))
  [[ $EQO == O.0.* ]] && { item_stats "$EQO"; [[ $ICLS == *"$CLS"* ]] && shield=1; }
  RES=$(( TB_RES + G_RES )); (( RES > 60 )) && RES=60
  DODGE=$(( 3 + TB_DODGE )); (( DODGE > 35 )) && DODGE=35
  BLOCK=0; (( shield )) && BLOCK=$(( 10 + TB_BLOCK ))
  CDMG=$(( 200 + TB_CDMG ))
  MAXHP=$(( (C_HP0[CLS] + C_HPL[CLS] * LVL) * (100 + B_HP) / 100 ))
  MAXMP=$(( (C_MP0[CLS] + C_MPL[CLS] * LVL) * (100 + B_MP) / 100 ))
  ATK=$(( (w + 4 + LVL * 2) * C_DMG[CLS] / 100 * (100 + B_DMG) / 100 ))
  ARMOR=$(( a + B_ARM + C_ARM[CLS] + LVL / 2 ))
  CRIT=$(( 10 + B_CRIT )); (( CRIT > 75 )) && CRIT=75
  XPNEXT=$(( 30 * LVL * LVL + 70 * LVL ))
  (( LVL >= MAXLVL )) && { para_next "$PARA"; XPNEXT=$PNX; }   # v4.5: paragon
  (( HP > MAXHP )) && HP=$MAXHP; (( MP > MAXMP )) && MP=$MAXMP
}

new_char() {
  CLS=$1 LVL=1 XP=0 GOLD=25 POT_H=3 POT_M=2 POT_GH=0 POT_GM=0 EL_STR=0 EL_IRON=0 EL_SWIFT=0 SCROLL=0 BREW=0
  EQW="W.${DEFW[CLS]}.1.0" EQA="A.${DEFA[CLS]}.1.0" EQO="" EQH="" EQJ="" KILLS=0 DEATHS=0 WX=$SPAWN_X WY=$SPAWN_Y
  STORY=0 STORY_P=0 STORY_SEEN=0 ALLYN=0 ALLIES="" ALLY=-1; aly_fix
  TAL=000000000000 QLS="" QLP=() QLC="" REP=(); rep_fix; ql_fix; v45_reset
  INV=() QUESTS=() BAGS=10 BAGEQ=(- - -) BANK=() BANKG=0 BANKCAP=30 MEAL1=1 MEAL2=0 TON_FROST=0 TON_FIRE=0 TON_VEIL=0 PROF_LV=(1 1 1) PROF_XP=(0 0 0); mats_zero
  calc_stats; HP=$MAXHP MP=$MAXMP
}

char_text() {   # the hero as save text (what is stored: a file in tests, on the server in the game)
  local k
  echo "version=2"
  for k in "${CHAR_VARS[@]}"; do echo "$k=${!k}"; done
  echo "SYM=$SYM"
  echo "EXPW=$EXPW"
  echo "SEEN=$SEEN"
  echo "WAYS=$WAYS"
  echo "INV=${INV[*]}"
  echo "BAGEQ=${BAGEQ[*]}"
  echo "BANK=${BANK[*]}"
  echo "BANKM=${BANKM[*]}"
  echo "QUESTS=${QUESTS[*]}"
  echo "PROF=${PROF_LV[0]} ${PROF_XP[0]} ${PROF_LV[1]} ${PROF_XP[1]} ${PROF_LV[2]} ${PROF_XP[2]}"
  echo "MATS=${MATS[*]}"
  echo "TAL=$TAL"
  echo "QLS=$QLS"
  echo "QLP=${QLP[*]}"
  echo "QLC=$QLC"
  echo "REP=${REP[*]}"
  v45_save
  if (( CHAR_REMOTE )); then echo "SCI=${SC_ITEMS[*]}"; echo "SCG=$SC_G"; echo "SCM=${SC_M[*]}"; fi
}

save_char() {
  local tmp="$CHAR_FILE.tmp" IFS=$' \t\n' text   # traps can fire inside "IFS= read" - never join with empty IFS
  [[ -n $CLS ]] || return
  if [[ $CUR_MAP == W ]]; then WX=$PX WY=$PY; fi
  ALLYN=$(( ALLY + 1 ))
  if (( CHAR_REMOTE )); then                                # v6.2: heroes live on the server
    if (( net_up )); then text=$(char_text); acct_send_save "$text" && SAVE_LOST=0 || SAVE_LOST=1; else SAVE_LOST=1; fi
    return
  fi
  char_text > "$tmp" 2>/dev/null && mv -f "$tmp" "$CHAR_FILE"
}

load_char() {
  local k v x ok=0 text
  if (( CHAR_REMOTE )); then text=$CHAR_TEXT; [[ -n $text ]] || return 1
  else [[ -r $CHAR_FILE ]] || return 1; text=$(<"$CHAR_FILE"); fi
  SC_ITEMS=() SC_G=0 SC_M=(); for (( x = 0; x < NMAT; x++ )); do SC_M[x]=0; done
  CLS="" EQW="" EQA="" EQO="" EQH="" EQJ="" INV=() QUESTS=() SYM="@" COLR="" EXPW="" SEEN="" WAYS=""
  POT_GH=0 POT_GM=0 EL_STR=0 EL_IRON=0 EL_SWIFT=0 SCROLL=0 BREW=0 BAGS=10 BAGEQ=(- - -) BANK=() BANKG=0 BANKCAP=30
  BANKM=(); for (( x = 0; x < NMAT; x++ )); do BANKM[x]=0; done
  local bageq=""
  STORY=0 STORY_P=0 STORY_SEEN=0 ALLYN=0 ALLIES="" ALLY=-1 TAL=000000000000 QLS="" QLP=() QLC="" REP=(); v45_reset
  MEAL1=0 MEAL2=0 TON_FROST=0 TON_FIRE=0 TON_VEIL=0 PROF_LV=(1 1 1) PROF_XP=(0 0 0); mats_zero
  while IFS='=' read -r k v; do
    case $k in
      version) ok=1 ;;
      SYM)    valid_sym "$v" && SYM=$v ;;
      EXPW|SEEN|WAYS) [[ $v =~ ^[01]{1,2000}$ ]] && printf -v "$k" '%s' "$v" ;;
      ALLIES) [[ $v =~ ^[01]{1,16}$ ]] && ALLIES=$v ;;
      EQW|EQA|EQO|EQH|EQJ) { valid_item "${v%!}" || [[ $v =~ ^[WA]\.[1-7]\.[0-3]$ ]]; } && printf -v "$k" '%s' "$v" ;;
      INV)    for x in $v; do { valid_item "${x%!}" || [[ $x =~ ^[WA]\.[1-7]\.[0-3]$ ]]; } && INV+=("$x"); done ;;
      BAGEQ)  bageq=$v ;;
      BANK)   for x in $v; do valid_item "${x%!}" && BANK+=("$x"); done ;;
      BANKM)  x=0; for k in $v; do [[ $k =~ ^[0-9]{1,6}$ ]] && (( x < NMAT )) && BANKM[x]=$(( 10#$k )); x=$(( x + 1 )); done ;;
      QUESTS) for x in $v; do [[ $x =~ ^[KDTCGEB](\.(0|[1-9][0-9]{0,8})){5}$ ]] && QUESTS+=("$x"); done ;;
      TAL)    [[ $v =~ ^[0-5]{12}$ ]] && TAL=$v ;;
      QLS)    [[ $v =~ ^[0-9x]{1,64}$ ]] && QLS=$v ;;
      QLC)    [[ $v =~ ^[-ab]{1,64}$ ]] && QLC=$v ;;
      QLP)    x=0; for k in $v; do [[ $k =~ ^[0-9]{1,4}$ ]] && QLP[x]=$(( 10#$k )); x=$(( x + 1 )); done ;;
      REP)    x=0; for k in $v; do [[ $k =~ ^-?[0-9]{1,5}$ ]] && (( x < NFAC )) && { if [[ $k == -* ]]; then REP[x]=$(( -10#${k#-} )); else REP[x]=$(( 10#$k )); fi; }; x=$(( x + 1 )); done ;;
      PROF)   if [[ $v =~ ^([0-9]{1,2})\ ([0-9]{1,4})\ ([0-9]{1,2})\ ([0-9]{1,4})\ ([0-9]{1,2})\ ([0-9]{1,4})$ ]]; then
                for x in 0 1 2; do
                  PROF_LV[x]=$(( 10#${BASH_REMATCH[x * 2 + 1]} )) PROF_XP[x]=$(( 10#${BASH_REMATCH[x * 2 + 2]} ))
                  (( PROF_LV[x] >= 1 && PROF_LV[x] <= PROF_MAX )) || PROF_LV[x]=1
                done
              fi ;;
      MATS)   x=0; for k in $v; do [[ $k =~ ^[0-9]{1,5}$ ]] && (( x < NMAT )) && MATS[x]=$(( 10#$k )); x=$(( x + 1 )); done ;;
      CLS|LVL|XP|GOLD|HP|MP|POT_H|POT_M|POT_GH|POT_GM|EL_STR|EL_IRON|EL_SWIFT|SCROLL|BREW|WX|WY|KILLS|DEATHS|COLR|MEAL1|MEAL2|TON_FROST|TON_FIRE|TON_VEIL|BAGS|BANKG|BANKCAP|STORY|STORY_P|STORY_SEEN|ALLYN)
        [[ $v =~ ^[0-9]{1,12}$ ]] && printf -v "$k" '%d' "$(( 10#$v ))" ;;
      SCI)    SC_ITEMS=(); for x in $v; do valid_item "${x%!}" && SC_ITEMS+=("$x"); done; SC_ITEMS=("${SC_ITEMS[@]:0:SC_CAP}") ;;
      SCG)    [[ $v =~ ^[0-9]{1,12}$ ]] && SC_G=$(( 10#$v )) ;;
      SCM)    x=0; for k in $v; do [[ $k =~ ^[0-9]{1,6}$ ]] && (( x < NMAT )) && SC_M[x]=$(( 10#$k )); x=$(( x + 1 )); done ;;
      *) v45_load_kv "$k" "$v" ;;
    esac
  done <<< "$text"
  (( ok )) && [[ $CLS =~ ^[0-9]$ ]] && (( CLS < NCLS )) || return 1
  (( LVL >= 1 && LVL <= 50 )) || LVL=1
  if [[ -z $COLR ]] || (( COLR >= ${#P_COLC[@]} )); then name_color "$MY_NAME"; COLR=$NCI; fi
  if [[ -n $bageq ]]; then           # v1.8 bag slots
    BAGEQ=($bageq); BAGEQ=("${BAGEQ[@]:0:3}")
    for x in 0 1 2; do [[ ${BAGEQ[x]} == [0-5] ]] || BAGEQ[x]=-; done
  elif (( BAGS == 15 )); then BAGEQ=(2 - -)   # v1.7 backpack upgrades become real bags
  elif (( BAGS == 20 )); then BAGEQ=(3 - -); fi
  bag_cap
  aly_fix; (( STORY <= NST )) || STORY=$NST; ALLY=$(( ALLYN - 1 )); { (( ALLY >= 0 )) && aly_has "$ALLY"; } || ALLY=-1
  (( BANKCAP == 30 || BANKCAP == 40 || BANKCAP == 50 || BANKCAP == 60 )) || BANKCAP=30
  INV=("${INV[@]:0:BAGS}") QUESTS=("${QUESTS[@]:0:3}") BANK=("${BANK[@]:0:BANKCAP}")
  migrate_gear
  QLS=${QLS:0:NQL}; while (( ${#QLS} < NQL )); do QLS+="0"; done        # questlines added later start fresh
  QLC=${QLC:0:NQL}; while (( ${#QLC} < NQL )); do QLC+=-; done
  rep_fix; ql_fix; v45_fix
  calc_stats
  (( HP < 1 )) && HP=$MAXHP
  return 0
}

gain_xp() {
  XP=$(( XP + $1 ))
  while (( XP >= XPNEXT && LVL < MAXLVL )); do
    XP=$(( XP - XPNEXT )); LVL=$(( LVL + 1 )); calc_stats; HP=$MAXHP MP=$MAXMP
    logm "${EMJ[lvl]}*** LEVEL UP! You are now level $LVL. ***" "$K_ANN"
    ft_add "$PX" $(( PY - 2 )) "LEVEL UP!" $'\e[0;1;5;38;5;16;48;5;220m' 
    send EVT "$MY_ID" "$MY_NAME" "reached level $LVL!"
    story_levelup
    save_char
  done
  (( LVL >= MAXLVL )) && para_xp
}

add_item() {  # code
  item_name "$1" "$CLS"
  if (( ${#INV[@]} >= BAGS )) && [[ -z $IUQ && $IK != C ]]; then   # a unique (or a collectable) is too precious to auto-sell: it squeezes in
    GOLD=$(( GOLD + ISELL ))
    logm "Bags full - auto-sold $INAME for ${ISELL}g" "$K_LOOT"
  else
    INV+=("$1"); NEWG[$1]=1
    if [[ -n $IUQ ]]; then
      item_icon "$1" "$CLS"; bonus_txt
      logm "${EMJ[loot]}UNIQUE LOOT: $II${II:+ }$INAME (${IVAL:++$IVAL }$BTX) - there is only one of these!" $'\e['"${ICOL}m"
      send EVT "$MY_ID" "$MY_NAME" "found the unique $INAME!"
      return
    fi
    if [[ $IK == B ]]; then
      item_icon "$1" "$CLS"
      logm "${EMJ[loot]}Loot: $II${II:+ }$INAME - a bag with $IVAL slots! Put it on in [i]." $'\e['"${ICOL}m"
      return
    fi
    if [[ $IK == C ]]; then
      item_icon "$1" "$CLS"; col_mark "$IKD"
      logm "${EMJ[loot]}Collectable: $II${II:+ }$INAME (${CS_NAME[${CL_SET[IKD]}]})" $'\e['"${ICOL}m"
      return
    fi
    local lab=dmg nv=$IVAL nm=$INAME col=$ICOL up="" ok=1 cl=$ICLS; [[ $IK != W ]] && lab=armor
    bonus_txt; local bt=$BTX
    [[ $cl == *"$CLS"* ]] || ok=0
    eq_of "$IK"; local cur=$EQC
    if (( ! ok )); then cls_list "$cl"; up="  (for $CLT)"
    elif [[ -z $cur ]]; then up="  - NEW SLOT! equip it with [i]"
    else item_stats "$cur"; (( nv > IVAL )) && up="  - UPGRADE! equip it with [i]"; fi
    (( nv )) || { lab=""; nv=""; }
    item_icon "$1" "$CLS"
    logm "${EMJ[loot]}Loot: $II${II:+ }$nm (${nv:++$nv $lab }$bt)$up" $'\e['"${col}m"
  fi
}

reward() {  # xp gold item mtype
  local i f done=() xp=$1
  (( NOW < REST_UNTIL )) && xp=$(( xp * (100 + REST_PCT) / 100 ))      # v5.0: Well Rested
  gain_xp "$xp"; GOLD=$(( GOLD + $2 )); KILLS=$(( KILLS + 1 ))
  logm "${EMJ[xp]}+$xp XP  ${EMJ[gold]}+$2 gold" "$K_GOOD"
  ft_add "$PX" $(( PY - 1 )) "+${xp}xp" $'\e[0;1;38;5;220;48;5;234m'
  case $3 in
    H) POT_H=$(( POT_H + 1 )); ci h; logm "${EMJ[loot]}Loot: ${CI}Health Potion" "$K_LOOT" ;;
    M) POT_M=$(( POT_M + 1 )); ci m; logm "${EMJ[loot]}Loot: ${CI}Mana Potion" "$K_LOOT" ;;
    *.*.*.*|B.[0-5]|U.*) valid_item "$3" && add_item "$3" ;;
  esac
  (( M_KIND[$4] == 4 )) && logm "${EMJ[loot]}You open the treasure chest!" "$K_ANN"
  story_event K "$4"
  qev_kill "$4"
  if has_cap onkill; then heal_self $(( MAXHP * 6 / 100 )); MP=$(( MP + MAXMP * 4 / 100 )); (( MP > MAXMP )) && MP=$MAXMP; fi
  has_cap frenzy && { (( FRENZY < 3 )) && FRENZY=$(( FRENZY + 1 )); FRENZY_T=$(( NOW + 6000 )); }
  for i in "${!QUESTS[@]}"; do
    IFS=. read -r -a f <<< "${QUESTS[i]}"
    [[ ${f[0]} == K && ${f[1]} == "$4" ]] || continue
    f[3]=$(( f[3] + 1 ))
    QUESTS[i]="${f[0]}.${f[1]}.${f[2]}.${f[3]}.${f[4]}.${f[5]}"
    (( f[3] >= f[2] )) && done=("$i" "${done[@]}")
  done
  for i in "${done[@]}"; do quest_done "$i"; done
}

init_where() {  # where each monster / NPC lives -> MW_NAME MW_X MW_Y
  local z a t d p
  MW_NAME=() MW_X=() MW_Y=() ZR=()
  for z in "${ZONES[@]}"; do
    a=($z); t=${a[0]}
    ZR[t]+="${a[1]} ${a[2]} ${a[3]} ${a[4]} "                       # v3.0: zone rectangles per monster type
    [[ -n ${MW_NAME[t]} ]] && continue
    MW_X[t]=$(( (a[1] + a[3]) / 2 )) MW_Y[t]=$(( (a[2] + a[4]) / 2 ))
    region_of "${MW_X[t]}" "${MW_Y[t]}" nosafe; MW_NAME[t]=$RNAME
  done
  for (( d = 0; d < NDT; d++ )); do
    for t in ${D_POOL[d]} ${D_BOSS[d]} ${D_ELITE[d]}; do
      [[ -n ${MW_NAME[t]} ]] && continue
      MW_NAME[t]="${D_NAME[d]}" MW_X[t]=${D_ENTX[d]} MW_Y[t]=${D_ENTY[d]}
    done
  done
  for p in "${NPC_SPAWNS[@]}"; do
    a=($p); t=${a[0]}; [[ -n ${MW_NAME[t]} ]] && continue
    region_of "${a[1]}" "${a[2]}"; MW_NAME[t]=$RNAME MW_X[t]=${a[1]} MW_Y[t]=${a[2]}
  done
  for p in "${!WB_LIST[@]}"; do
    t=${WB_LIST[p]} a=(${WB_RECT[p]})
    MW_X[t]=$(( (a[0] + a[2]) / 2 )) MW_Y[t]=$(( (a[1] + a[3]) / 2 ))
    region_of "${MW_X[t]}" "${MW_Y[t]}" nosafe; MW_NAME[t]="$RNAME (world boss)"
  done
}

quest_info() {  # code -> QTXT QSHORT QGLY QWHERE QTX QTY
  local f=(${1//./ }) a i best=999999 d2 cx cy
  QTX="" QTY=""
  case ${f[0]} in
    K) QTXT="Slay ${f[2]} ${M_NAME[f[1]]}s (${f[3]}/${f[2]})" QSHORT="${M_NAME[f[1]]}s ${f[3]}/${f[2]}"
       QGLY="${GLYP[m${f[1]}]}$N" QWHERE=${MW_NAME[f[1]]:-somewhere} QTX=${MW_X[f[1]]} QTY=${MW_Y[f[1]]}
       a=(${ZR[f[1]]})                                                 # nearest zone of that monster (or the one I'm in)
       for (( i = 0; i < ${#a[@]}; i += 4 )); do
         if (( PX >= a[i] && PX <= a[i+2] && PY >= a[i+1] && PY <= a[i+3] )) && [[ $CUR_MAP == W ]]; then QTX=$PX QTY=$PY; break; fi
         cx=$(( (a[i] + a[i+2]) / 2 )) cy=$(( (a[i+1] + a[i+3]) / 2 )) d2=$(( (cx - PX) * (cx - PX) + (cy - PY) * (cy - PY) ))
         (( d2 < best )) && { best=$d2; QTX=$cx QTY=$cy; }
       done ;;
    D) QTXT="Clear the ${D_NAME[f[1]]}" QSHORT="Clear ${D_NAME[f[1]]}" QGLY="$Z_ENT$N"; (( TW2 )) && QGLY=🚪
       QWHERE=${D_WHERE[f[1]]} QTX=${D_ENTX[f[1]]} QTY=${D_ENTY[f[1]]} ;;
    T) QTXT="Bring a letter to ${N_FULL[${f[1]}]}" QSHORT="Letter for ${M_NAME[f[1]]}" QGLY="${GLYP[m${f[1]}]}$N"
       QWHERE=${N_HOME[${f[1]}]:-${MW_NAME[f[1]]}} QTX=${MW_X[f[1]]} QTY=${MW_Y[f[1]]} ;;
    C) qitem "${f[1]}"; QTXT="Collect ${f[2]} ${QIN}s from ${M_NAME[f[1]]}s (${f[3]}/${f[2]})" QSHORT="${QIN}s ${f[3]}/${f[2]}"
       QGLY="${GLYP[m${f[1]}]}$N" QWHERE=${MW_NAME[f[1]]:-somewhere} QTX=${MW_X[f[1]]} QTY=${MW_Y[f[1]]} ;;
    B) QTXT="Bounty: slay ${M_NAME[f[1]]}" QSHORT="Bounty: ${M_NAME[f[1]]}" QGLY="${GLYP[m${f[1]}]}$N"
       QWHERE=${MW_NAME[f[1]]:-somewhere} QTX=${MW_X[f[1]]} QTY=${MW_Y[f[1]]} ;;
    E) QTXT="Scout ${SPT_NAME[f[1]]}" QSHORT="Scout ${SPT_NAME[f[1]]#the }" QGLY="${K_LOOT}x$N"; (( TW2 )) && QGLY=🧭
       region_of "${SPT_X[f[1]]}" "${SPT_Y[f[1]]}" nosafe; QWHERE=$RNAME QTX=${SPT_X[f[1]]} QTY=${SPT_Y[f[1]]} ;;
    G) QTXT="Deliver ${f[2]} ${MAT_NAME[f[1]]} to a quest board (${MATS[f[1]]}/${f[2]})" QSHORT="${MAT_NAME[f[1]]} ${MATS[f[1]]}/${f[2]}"
       mat_icon "${f[1]}"; QGLY=${MI:-$K_LOOT*$N}; QWHERE="any quest board" ;;
  esac
}
quest_text() { quest_info "$1"; }

track() {  # QTX QTY -> TRK: arrow + distance from me (empty inside dungeons)
  local dx dy ax ay ar
  TRK=""
  [[ $CUR_MAP == W && -n $QTX ]] || return
  dx=$(( QTX - PX )) dy=$(( QTY - PY )); ax=${dx#-} ay=${dy#-}
  if (( ax <= 3 && ay <= 3 )); then TRK="here"; return; fi
  if (( ax > 2 * ay )); then ar=$(( dx > 0 ? 2 : 6 ))
  elif (( ay > 2 * ax )); then ar=$(( dy > 0 ? 4 : 0 ))
  elif (( dx > 0 )); then ar=$(( dy > 0 ? 3 : 1 ))
  else ar=$(( dy > 0 ? 5 : 7 )); fi
  cheb "$dx" "$dy"; TRK="${ARW[ar]} ${D}m"
}

con_col() {  # level -> CC (grey/green/yellow/orange/red relative to you)
  local d=$(( $1 - LVL ))
  if (( d <= -5 )); then CC=$'\e[38;5;245m'; elif (( d <= -2 )); then CC=$'\e[38;5;120m'
  elif (( d <= 1 )); then CC=$'\e[38;5;227m'; elif (( d <= 3 )); then CC=$'\e[38;5;214m'; else CC=$'\e[38;5;196m'; fi
}

turnin_for() {  # npc type -> 0 if one of my (party) quests wants a letter delivered there
  local q
  for q in "${QUESTS[@]}" "${PQ_CODES[@]}"; do [[ $q == "T.$1."* ]] && return 0; done
  return 1
}

explore_here() {  # fog of war on the world map + waystone attunement
  [[ $CUR_MAP == W ]] || return
  local cx=$(( PX / 8 )) cy=$(( PY / 8 )) c i j k w a
  for w in "${!WAYSTONES[@]}"; do
    [[ ${WAYS:w:1} == 1 ]] && continue
    a=(${WAYSTONES[w]}); cheb $(( a[1] - PX )) $(( a[2] - PY ))
    if (( D <= 3 )); then
      WAYS="${WAYS:0:w}1${WAYS:w+1}"
      logm "Waystone attuned: ${a[0]//_/ }. Touch any waystone (&) to travel here." "$K_GOOD"
    fi
  done
  c=$(( cy * NCHX + cx )); (( c == LAST_CHUNK )) && return; LAST_CHUNK=$c
  for (( j = cy - 1; j <= cy + 1; j++ )); do for (( i = cx - 1; i <= cx + 1; i++ )); do
    (( i >= 0 && j >= 0 && i < NCHX && j < NCHY )) || continue
    k=$(( j * NCHX + i )); [[ ${EXPW:k:1} == 1 ]] || EXPW="${EXPW:0:k}1${EXPW:k+1}"
  done; done
}

init_explore() {
  local z
  NCHX=$(( (MAPW[W] + 7) / 8 )) NCHY=$(( (MAPH[W] + 7) / 8 ))
  printf -v z '%*s' $(( NCHX * NCHY )) ''; z=${z// /0}
  local ow=0 oh=0                                            # the map grew: keep what was explored
  (( ${#EXPW} == 390 && NCHX * NCHY != 390 )) && ow=30 oh=13   # v2.0: 240x100 -> 360x150
  (( ${#EXPW} == 855 && NCHX * NCHY != 855 )) && ow=45 oh=19   # v4.0: 360x150 -> 480x200
  if (( ow )); then
    local i j old=$EXPW; EXPW=$z
    for (( j = 0; j < oh; j++ )); do for (( i = 0; i < ow; i++ )); do
      [[ ${old:j*ow+i:1} == 1 ]] && EXPW="${EXPW:0:j*NCHX+i}1${EXPW:j*NCHX+i+1}"
    done; done
  fi
  (( ${#EXPW} == NCHX * NCHY )) || EXPW=$z
  printf -v z '%*s' "$NM" ''; z=${z// /0}
  (( ${#SEEN} < NM )) && SEEN+=${z:${#SEEN}}          # new creatures: keep what was already discovered
  SEEN=${SEEN:0:NM}
  printf -v z '%*s' "${#WAYSTONES[@]}" ''; z=${z// /0}
  (( ${#WAYS} < ${#WAYSTONES[@]} )) && WAYS+=${z:${#WAYS}}
  WAYS=${WAYS:0:${#WAYSTONES[@]}}
}

way_travel() {  # index
  local i=$1 a cost
  (( i >= 0 && i < ${#WAYSTONES[@]} )) && [[ ${WAYS:i:1} == 1 ]] || return
  cost=$(( 10 + LVL * 3 ))
  (( GOLD >= cost )) || { logm "Travel costs $cost gold." "$K_HURT"; return; }
  a=(${WAYSTONES[i]})
  GOLD=$(( GOLD - cost ))
  PX=${a[1]} PY=$(( a[2] + 1 ))
  p_walk W "$PX" "$PY" || { PX=$(( a[1] + 1 )) PY=${a[2]}; }
  p_walk W "$PX" "$PY" || { PX=$(( a[1] - 1 )) PY=${a[2]}; }
  UI="" POS_DIRTY=1 MAP_DIRTY=1
  logm "The waystone hums - you arrive at ${a[0]//_/ } (-${cost}g)." "$K_GOOD"
  explore_here
}

quest_done() {
  local f; IFS=. read -r -a f <<< "${QUESTS[$1]}"
  quest_text "${QUESTS[$1]}"
  logm "${EMJ[quest]}QUEST COMPLETE: ${QTXT%% (*} - +${f[4]} XP +${f[5]} gold" "$K_ANN"
  unset "QUESTS[$1]"; QUESTS=("${QUESTS[@]}")
  GOLD=$(( GOLD + f[5] )); gain_xp "${f[4]}"
  quest_rep "${f[0]}.${f[1]}"
}

gen_offers() {  # QSRC = board or the NPC type of a quest giver
  local cand=() t i need dt=-1 d tgt=""
  OFFERS=() OFFER_LVL=$LVL OFFER_SRC=$QSRC
  if [[ $QSRC == board ]]; then
    for t in "${WORLD_TYPES[@]}"; do (( M_LVL[t] >= LVL - 2 && M_LVL[t] <= LVL + 2 )) && cand+=("$t"); done
    (( ${#cand[@]} )) || cand=(43)
    for d in 0 1 2; do (( LVL >= D_REQ[d] )) && dt=$d; done
    if (( LVL < 6 )); then tgt=25; elif (( LVL < 10 )); then tgt=26; else tgt=46; fi
  else
    cand=(${N_QK[$QSRC]}); dt=${N_QD[$QSRC]:--1}; tgt=${N_QT[$QSRC]}
    (( ${#cand[@]} )) || cand=(0)
  fi
  for i in 0 1; do
    t=${cand[RANDOM % ${#cand[@]}]}; need=$(( 6 + RANDOM % 9 ))
    OFFERS+=("K.$t.$need.0.$(( need * M_XP[t] * 3 / 2 )).$(( need * M_GOLD[t] * 2 ))")
  done
  if (( dt >= 0 )); then
    t=${D_BOSS[dt]}; OFFERS+=("D.$dt.1.0.$(( M_XP[t] )).$(( M_GOLD[t] ))")
  fi
  [[ -n $tgt ]] && OFFERS+=("T.$tgt.1.0.$(( 60 * LVL + 150 )).$(( 25 * LVL + 40 ))")
  # v3.0: collect, bounty, scout, deliver - one or two of them
  t=${cand[RANDOM % ${#cand[@]}]}; need=$(( 4 + RANDOM % 5 ))
  (( M_BOSS[t] == 0 )) && OFFERS+=("C.$t.$need.0.$(( need * M_XP[t] * 2 )).$(( need * M_GOLD[t] * 3 ))")
  local r best="" bd=99 s
  for r in "${RARE_T[@]}"; do
    d=$(( M_LVL[r] - LVL )); (( d < 0 )) && d=$(( -d * 2 ))
    (( d < bd )) && { bd=$d; best=$r; }
  done
  (( bd <= 6 )) && OFFERS+=("B.$best.1.0.$(( M_XP[best] * 2 )).$(( M_GOLD[best] ))")
  if (( RANDOM % 2 )); then
    best="" bd=999
    for (( s = 0; s < NSPOT; s++ )); do
      region_of "${SPT_X[s]}" "${SPT_Y[s]}" nosafe; r=${RLVL%%-*}; [[ $r =~ ^[0-9]+$ ]] || continue
      d=$(( r - LVL )); (( d < 0 )) && d=$(( -d ))
      (( d * 10 + RANDOM % 10 < bd )) && { bd=$(( d * 10 )); best=$s; }
    done
    [[ -n $best ]] && OFFERS+=("E.$best.1.0.$(( 40 * LVL + 120 )).$(( 15 * LVL + 30 ))")
  else
    r=$(( LVL / 5 )); (( r > 5 )) && r=5
    s=$(( (RANDOM % 2) * 6 + r )); need=$(( 3 + RANDOM % 4 ))
    OFFERS+=("G.$s.$need.0.$(( need * MAT_VAL[s] * 6 + 30 * LVL )).$(( need * MAT_VAL[s] * 3 ))")
  fi
}

pq_to_personal() {
  local q n=0
  for q in "${PQ_CODES[@]}"; do
    (( ${#QUESTS[@]} < 3 )) || break
    QUESTS+=("$q"); n=$(( n + 1 ))
  done
  (( n )) && logm "Your party quests carry on as personal quests." "$K_PARTY"
  PQ_CODES=()
}

# --- monsters & NPCs mirror (current map only) ------------------------------
# CM_POS["x,y"] -> mid, CMR[y] -> " mid  mid " (who is on that row: frames and skills only look at nearby rows)
CMR=()
cm_set() {  # mid type x y hp max
  if [[ -n ${CM_T[$1]} ]]; then unset "CM_POS[${CM_X[$1]},${CM_Y[$1]}]"; CMR[CM_Y[$1]]=${CMR[CM_Y[$1]]/" $1 "/}; fi
  CM_T[$1]=$2 CM_X[$1]=$3 CM_Y[$1]=$4 CM_HP[$1]=$5 CM_MAX[$1]=$6
  CM_POS["$3,$4"]=$1; CMR[$4]+=" $1 "
}
cm_move() {  # mid x y
  unset "CM_POS[${CM_X[$1]},${CM_Y[$1]}]"; CMR[CM_Y[$1]]=${CMR[CM_Y[$1]]/" $1 "/}
  CM_X[$1]=$2 CM_Y[$1]=$3; CM_POS["$2,$3"]=$1; CMR[$3]+=" $1 "
}
cm_del() {
  [[ -n ${CM_T[$1]} ]] || return
  CMR[CM_Y[$1]]=${CMR[CM_Y[$1]]/" $1 "/}
  unset "CM_POS[${CM_X[$1]},${CM_Y[$1]}]" "CM_T[$1]" "CM_X[$1]" "CM_Y[$1]" "CM_HP[$1]" "CM_MAX[$1]" "ATK_NPC[$1]" "CM_CH[$1]" "FROZEN[$1]"
}
mons_rect() {  # x1 y1 x2 y2 -> MR: every monster/NPC inside the rectangle
  local y m
  MR=()
  for (( y = ($2 < 0 ? 0 : $2); y <= $4; y++ )); do
    for m in ${CMR[y]}; do (( CM_X[m] >= $1 && CM_X[m] <= $3 )) && MR+=("$m"); done
  done
}
cm_clear() {
  CM_T=() CM_X=() CM_Y=() CM_HP=() CM_MAX=(); CM_POS=() ATK_NPC=() CMR=() CM_CH=() FROZEN=()
  FX_X=() FX_Y=() FX_K=() FX_E=() DOT_M=() DOT_D=() DOT_N=() DOT_T=(); TARGET=""
}
mon_at() { MID=${CM_POS[$1,$2]}; [[ -n $MID ]]; }
hostile() {  # mid -> 0 if it is fair game
  local t=${CM_T[$1]}
  [[ -n $t ]] || return 1
  (( M_KIND[t] == 0 || M_KIND[t] == 4 )) && return 0
  [[ -n ${ATK_NPC[$1]} ]] && return 0
  (( M_KIND[t] == 2 && NOW < WANTED_UNTIL )) && return 0
  return 1
}

in_party() { local p; for p in "${PARTY_IDS[@]}"; do [[ $p == "$1" ]] && return 0; done; return 1; }

party_near() {  # range -> NEAR ids (party members on my map, alive, in range)
  local p; NEAR=()
  for p in "${PARTY_IDS[@]}"; do
    [[ $p == "$MY_ID" || ${OP_MAP[$p]} != "$CUR_MAP" || ${OP_DEAD[$p]} == 1 ]] && continue
    cheb $(( ${OP_X[$p]:-0} - PX )) $(( ${OP_Y[$p]:-0} - PY )); (( D <= $1 )) && NEAR+=("$p")
  done
}

party_txt() {  # NEAR (party members in reach) -> PTXT " and 2 allies"
  if (( ${#NEAR[@]} == 1 )); then PTXT=" and 1 ally"; elif (( ${#NEAR[@]} > 1 )); then PTXT=" and ${#NEAR[@]} allies"; else PTXT=""; fi
}

# --- combat -------------------------------------------------------------------
add_fx() {  # kind "x,y x,y ..." [broadcast]
  local c
  [[ -n $1 && -n ${FXG[$1]} ]] || return                       # (an empty kind from the network: no bash error)
  for c in $2; do
    [[ $c =~ ^-?(0|[1-9][0-9]{0,3}),-?(0|[1-9][0-9]{0,3})$ ]] || continue
    FX_X+=("${c%,*}"); FX_Y+=("${c#*,}"); FX_K+=("$1"); FX_E+=($(( NOW + ${FXD[$1]:-280} )))
  done
  if (( ${#FX_E[@]} > 120 )); then
    FX_X=("${FX_X[@]:60}"); FX_Y=("${FX_Y[@]:60}"); FX_K=("${FX_K[@]:60}"); FX_E=("${FX_E[@]:60}")
  fi
  [[ $3 == 1 ]] && send FX "$MY_ID" "$CUR_MAP" "$1" "$2"
  MAP_DIRTY=1
}

ring() {  # r -> RING cells around me
  local i j; RING=""
  for (( j = -$1; j <= $1; j++ )); do for (( i = -$1; i <= $1; i++ )); do
    (( i == 0 && j == 0 )) || RING+="$(( PX + i )),$(( PY + j )) "
  done; done
}

dmg_mult() {
  DM=100
  (( NOW < buff_until )) && DM=$(( DM + 40 ))
  (( NOW < anthem_until )) && DM=$(( DM + 20 ))
  (( NOW < str_until )) && DM=$(( DM + 30 ))
  (( NOW < fed_until && fed_lvl == 2 )) && DM=$(( DM + 10 ))
}

deal() {  # mid pct freeze [quiet]   (DEAL_EL element, CASTK skill index or -1)
  local m=$1 d crit="" t=${CM_T[$1]} mul cc=${CRIT:-10} wk=""
  [[ -n $t ]] || return
  dmg_mult
  (( NOW < PS_UNTIL[5] )) && DM=$(( DM * 75 / 100 ))          # weakened
  d=$(( ATK * $2 / 100 * DM / 100 ))
  mul=$(( 100 + ${TB_EL[DEAL_EL]:-0} ))
  if (( CASTK >= 0 )); then mul=$(( mul + ${TB_SK[CASTK]:-0} )); else mul=$(( mul + ${TB_MELEE:-0} )); fi
  has_cap execute && (( CM_HP[m] * 100 < CM_MAX[m] * 30 )) && mul=$(( mul + 60 ))
  has_cap shatter && (( NOW < ${FROZEN[$m]:-0} )) && mul=$(( mul + 50 ))
  d=$(( d * mul / 100 ))
  el_mult "$t" "$DEAL_EL"; d=$(( d * EM / 100 ))
  (( EM > 100 )) && wk=" (weak to ${EL_NAME[DEAL_EL]})"; (( EM < 100 )) && wk=" (resists ${EL_NAME[DEAL_EL]})"
  d=$(( d * (85 + RANDOM % 31) / 100 )); (( d < 1 )) && d=1
  has_cap toxic && [[ " ${DOT_M[*]} " == *" $m "* ]] && cc=$(( cc + 25 ))
  (( EVPROC )) && { cc=100; EVPROC=0; }
  if (( RANDOM % 100 < cc )); then
    d=$(( d * CDMG / 100 )); crit=" - CRITICAL!"
    has_cap critreset && { SKCD[0]=$(( SKCD[0] - 1000 )) SKCD[1]=$(( SKCD[1] - 1000 )) SKCD[2]=$(( SKCD[2] - 1000 )); }
  fi
  (( $3 > 0 )) && FROZEN[$m]=$(( NOW + $3 ))
  (( TB_LS > 0 )) && heal_self $(( d * TB_LS / 100 )) q
  (( CASTK >= 0 )) && has_cap smiteheal && SMH=$(( SMH + d / 5 ))
  has_cap ignite && (( DEAL_EL == 1 && ! DOTK )) && dot_add "$m" $(( d * 30 / 100 )) 3
  has_cap bleed0 && (( CASTK == 0 && ! DOTK )) && dot_add "$m" $(( d * 40 / 100 )) 4
  send HIT "$MY_ID" "$CUR_MAP" "$m" "$d" "$3"
  CM_HP[$m]=$(( CM_HP[$m] - d )); (( CM_HP[$m] < 0 )) && CM_HP[$m]=0
  TARGET=$m LASTDMG=$d HITF[$m]=$NOW
  if [[ -n $crit ]]; then ft_add "${CM_X[$m]}" "${CM_Y[$m]}" "$d!" $'\e[0;1;38;5;226;48;5;52m'
  else ft_add "${CM_X[$m]}" "${CM_Y[$m]}" "$d" $'\e[0;1;38;5;231;48;5;234m'; fi
  [[ $4 == q ]] || { mname "$m"; logm "You hit $MN for $d$crit$wk" "$K_HIT"; }
}

dot_add() { DOT_M+=("$1"); DOT_D+=($(( $2 * (100 + ${TB_DOT:-0}) / 100 ))); DOT_N+=("$3"); DOT_T+=($(( NOW + 1000 ))); }

dot_tick() {
  local i m d
  for i in "${!DOT_M[@]}"; do
    (( NOW >= DOT_T[i] )) || continue
    m=${DOT_M[i]}
    if [[ -n ${CM_T[$m]} ]]; then
      d=${DOT_D[i]}; (( d < 1 )) && d=1
      send HIT "$MY_ID" "$CUR_MAP" "$m" "$d" 0
      CM_HP[$m]=$(( CM_HP[$m] - d )); (( CM_HP[$m] < 0 )) && CM_HP[$m]=0
      add_fx poison "${CM_X[$m]},${CM_Y[$m]}" 1
      ft_add "${CM_X[$m]}" "${CM_Y[$m]}" "$d" $'\e[0;38;5;118;48;5;234m' 
      DOT_N[i]=$(( DOT_N[i] - 1 )); DOT_T[i]=$(( DOT_T[i] + 1000 ))
      (( DOT_N[i] > 0 )) && continue
    fi
    unset "DOT_M[i]" "DOT_D[i]" "DOT_N[i]" "DOT_T[i]"
  done
}

melee() {
  (( NOW < next_attack )) && return
  stunned && return
  mount_off quiet; last_att=$NOW
  next_attack=$(( NOW + 650 - (NOW < FRENZY_T ? FRENZY * 60 : 0) ))
  CASTK=-1 DEAL_EL=0
  deal "$1" 100 0
  add_fx slash "${CM_X[$1]},${CM_Y[$1]}" 1
}

mons_within() {  # r -> MLIST (hostile only) sorted by distance
  local m i j t
  MLIST=() MDIST=()
  mons_rect $(( PX - $1 )) $(( PY - $1 )) $(( PX + $1 )) $(( PY + $1 ))
  for m in "${MR[@]}"; do
    cheb $(( CM_X[m] - PX )) $(( CM_Y[m] - PY ))
    (( D <= $1 )) || continue
    hostile "$m" || continue
    MLIST+=("$m"); MDIST+=("$D")
  done
  for (( i = 1; i < ${#MLIST[@]}; i++ )); do
    for (( j = i; j > 0 && MDIST[j-1] > MDIST[j]; j-- )); do
      t=${MLIST[j]}; MLIST[j]=${MLIST[j-1]}; MLIST[j-1]=$t
      t=${MDIST[j]}; MDIST[j]=${MDIST[j-1]}; MDIST[j-1]=$t
    done
  done
}

trace_line() {  # range [pierce] -> LHIT (first) LHITS (all) LCELLS; friendly NPCs stop shots
  local i x=$PX y=$PY
  LHIT="" LHITS=() LCELLS=""
  for (( i = 1; i <= $1; i++ )); do
    x=$(( x + FDX )) y=$(( y + FDY ))
    blocks_shot "$CUR_MAP" "$x" "$y" && break
    LCELLS+="$x,$y "
    if mon_at "$x" "$y"; then
      hostile "$MID" || break
      [[ -z $LHIT ]] && LHIT=$MID
      LHITS+=("$MID")
      [[ $2 == pierce ]] || break
    fi
  done
}

adj_target() {  # -> ADJ: hostile foe in front of me, else the nearest adjacent one
  local nx=$(( PX + FDX )) ny=$(( PY + FDY ))
  if mon_at "$nx" "$ny" && hostile "$MID"; then ADJ=$MID; return 0; fi
  mons_within 1; (( ${#MLIST[@]} )) || return 1
  ADJ=${MLIST[0]}
}

dash() {  # max dx dy -> moves me, returns steps; stops before monsters
  local i n=0 nx ny
  DASH_HIT=""
  for (( i = 0; i < $1; i++ )); do
    nx=$(( PX + $2 )) ny=$(( PY + $3 ))
    if mon_at "$nx" "$ny"; then hostile "$MID" && DASH_HIT=$MID; break; fi
    p_walk "$CUR_MAP" "$nx" "$ny" || break
    [[ $T == [\<\>] ]] && break
    PX=$nx PY=$ny; n=$(( n + 1 ))
  done
  DSTEPS=$n
  (( n )) && { POS_DIRTY=1; MAP_DIRTY=1; }
}

heal_amount() { HEALV=$(( (18 + LVL * 7) * (100 + TB_HEAL) / 100 )); }
heal_self() {  # amount [q: no floating number]
  local h=$1; (( HP + h > MAXHP )) && h=$(( MAXHP - HP ))
  HP=$(( HP + h )); POS_DIRTY=1
  (( h > 0 )) && [[ $2 != q ]] && ft_add "$PX" "$PY" "+$h" $'\e[0;1;38;5;120;48;5;234m'
}

cast() {  # skill index 0..2
  local k=$1 s=$(( CLS * 3 + $1 )) m p c sx=$PX sy=$PY
  (( DEAD )) && return
  stunned && return
  if (( NOW < SKCD[k] )); then logm "${S_NAME[s]} is not ready yet."; return; fi
  local cost=$(( S_MP[s] * (100 - TB_MPC) / 100 ))
  if (( MP < cost )); then logm "Not enough mana for ${S_NAME[s]} ($cost)."; return; fi
  CASTK=$k DEAL_EL=${S_EL[s]} SMH=0
  mount_off quiet; last_att=$NOW
  case $s in
    0)  mons_within 1; (( ${#MLIST[@]} )) || { logm "Nothing in reach to cleave."; return; }
        for m in "${MLIST[@]}"; do deal "$m" 120 0; done; ring 1; add_fx slash "$RING" 1 ;;
    1)  dash 4 "$FDX" "$FDY"
        c=""; for (( m = 0; m <= DSTEPS; m++ )); do c+="$(( sx + FDX * m )),$(( sy + FDY * m )) "; done
        if [[ -n $DASH_HIT ]]; then deal "$DASH_HIT" 170 1500; c+="${CM_X[$DASH_HIT]},${CM_Y[$DASH_HIT]}"
        elif (( DSTEPS == 0 )); then logm "No room to charge."; return; fi
        add_fx slash "$c" 1 ;;
    2)  buff_until=$(( NOW + 12000 )); party_near 10
        for p in "${NEAR[@]}"; do send BUFF "$MY_ID" "$MY_NAME" "$p" 12000 fury; done
        ring 1; add_fx holy "$RING" 1; party_txt; logm "BATTLE CRY! You$PTXT deal +40% damage." "$K_GOOD" ;;
    3)  trace_line 8; add_fx fire "$LCELLS" 1
        if [[ -n $LHIT ]]; then
          local tx=${CM_X[$LHIT]} ty=${CM_Y[$LHIT]}
          deal "$LHIT" 220 0
          mons_rect $(( tx - 1 )) $(( ty - 1 )) $(( tx + 1 )) $(( ty + 1 ))
          for m in "${MR[@]}"; do
            [[ $m == "$LHIT" ]] && continue
            hostile "$m" || continue
            cheb $(( CM_X[m] - tx )) $(( CM_Y[m] - ty )); (( D <= 1 )) && deal "$m" 60 0
          done
          c=""; for p in -1 0 1; do for m in -1 0 1; do c+="$(( tx + m )),$(( ty + p )) "; done; done; add_fx fire "$c" 1
        fi ;;
    4)  mons_within 2; for m in "${MLIST[@]}"; do deal "$m" 90 3000; done; ring 2; add_fx frost "$RING" 1 ;;
    5)  dash 5 "$FDX" "$FDY"
        (( DSTEPS )) || { logm "Something blocks your blink."; return; }
        add_fx frost "$sx,$sy $PX,$PY" 1 ;;
    6)  trace_line 7; add_fx slash "$LCELLS" 1; [[ -n $LHIT ]] && deal "$LHIT" 115 0 ;;
    7)  mons_within 6; (( ${#MLIST[@]} )) || { logm "No targets for Multishot."; return; }
        c=""; for m in "${MLIST[@]:0:3}"; do deal "$m" 85 0; c+="${CM_X[$m]},${CM_Y[$m]} "; done; add_fx slash "$c" 1 ;;
    8)  dash 3 $(( -FDX )) $(( -FDY )); immune_until=$(( NOW + 2000 ))
        add_fx frost "$sx,$sy $PX,$PY" 1; logm "You leap away - immune for 2s." "$K_GOOD" ;;
    9)  trace_line 5; add_fx holy "$LCELLS" 1; [[ -n $LHIT ]] && deal "$LHIT" 140 0 ;;
    10) heal_amount; heal_self "$HEALV"; party_near 8
        for p in "${NEAR[@]}"; do send HEAL "$MY_ID" "$MY_NAME" "$p" "$HEALV"; done
        ring 1; add_fx holy "$RING" 1; party_txt; logm "You heal yourself$PTXT for $HEALV." "$K_GOOD" ;;
    11) mons_within 3; for m in "${MLIST[@]}"; do deal "$m" 110 0; done
        heal_amount; HEALV=$(( HEALV / 2 )); heal_self "$HEALV"; party_near 6
        for p in "${NEAR[@]}"; do send HEAL "$MY_ID" "$MY_NAME" "$p" "$HEALV"; done
        ring 3; add_fx holy "$RING" 1 ;;
    12) adj_target || { logm "Nobody in reach to backstab."; return; }
        deal "$ADJ" 260 0; add_fx slash "${CM_X[$ADJ]},${CM_Y[$ADJ]}" 1 ;;
    13) adj_target || { logm "Nobody in reach to poison."; return; }
        deal "$ADJ" 80 0; dot_add "$ADJ" $(( ATK * 45 / 100 )) 5
        add_fx poison "${CM_X[$ADJ]},${CM_Y[$ADJ]}" 1; logm "${M_NAME[CM_T[$ADJ]]} is poisoned." "$K_GOOD" ;;
    14) mons_within 7; (( ${#MLIST[@]} )) || { logm "No shadows to step into."; return; }
        m=${MLIST[0]}
        local tx=${CM_X[$m]} ty=${CM_Y[$m]} best="" bx by d2 o
        for o in "1 0" "-1 0" "0 1" "0 -1"; do
          set -- $o; bx=$(( tx + $1 )) by=$(( ty + $2 ))
          p_walk "$CUR_MAP" "$bx" "$by" && [[ $T != [\<\>] ]] && ! mon_at "$bx" "$by" || continue
          d2=$(( (bx - PX) * (bx - PX) + (by - PY) * (by - PY) ))
          [[ -z $best || $d2 -gt ${best%% *} ]] && best="$d2 $bx $by $(( -$1 )) $(( -$2 ))"
        done
        [[ -n $best ]] || { logm "No room behind your target."; return; }
        set -- $best; PX=$2 PY=$3 FDX=$4 FDY=$5 POS_DIRTY=1 MAP_DIRTY=1
        immune_until=$(( NOW + 1000 ))
        add_fx poison "$sx,$sy $PX,$PY" 1; deal "$m" 120 0 ;;
    15) adj_target || { logm "Nothing in reach to strike."; return; }
        deal "$ADJ" 160 0; heal_self $(( MAXHP * 8 / 100 )); add_fx holy "${CM_X[$ADJ]},${CM_Y[$ADJ]}" 1 ;;
    16) immune_until=$(( NOW + 4000 )); ring 1; add_fx holy "$RING" 1
        logm "DIVINE SHIELD - nothing can touch you for 4s." "$K_GOOD" ;;
    17) mons_within 2; for m in "${MLIST[@]}"; do deal "$m" 90 0; done
        HEALV=$(( 10 + LVL * 3 )); heal_self "$HEALV"; party_near 4
        for p in "${NEAR[@]}"; do send HEAL "$MY_ID" "$MY_NAME" "$p" "$HEALV"; done
        ring 2; add_fx holy "$RING" 1 ;;
    18) trace_line 9 pierce; add_fx bone "$LCELLS" 1
        for m in "${LHITS[@]}"; do deal "$m" 140 0; done ;;
    19) trace_line 6; add_fx poison "$LCELLS" 1
        if [[ -n $LHIT ]]; then deal "$LHIT" 150 0; heal_self $(( LASTDMG / 2 )); logm "You drain $(( LASTDMG / 2 )) life." "$K_GOOD"; fi ;;
    20) mons_within 3; (( ${#MLIST[@]} )) || { logm "No one to infect."; return; }
        for m in "${MLIST[@]}"; do dot_add "$m" $(( ATK * 40 / 100 )) 6; done
        ring 3; add_fx poison "$RING" 1; logm "PLAGUE spreads to ${#MLIST[@]} foes." "$K_GOOD" ;;
    21) trace_line 6 pierce; add_fx sound "$LCELLS" 1
        for m in "${LHITS[@]}"; do deal "$m" 110 0; done ;;
    22) mons_within 3; for m in "${MLIST[@]}"; do deal "$m" 40 4000 q; done
        ring 3; add_fx sound "$RING" 1; logm "Your LULLABY puts ${#MLIST[@]} foes to sleep." "$K_GOOD" ;;
    23) anthem_until=$(( NOW + 15000 )); party_near 10
        for p in "${NEAR[@]}"; do send BUFF "$MY_ID" "$MY_NAME" "$p" 15000 anthem; done
        ring 1; add_fx sound "$RING" 1; party_txt; logm "ANTHEM! You$PTXT are faster and deal +20% damage." "$K_GOOD" ;;
    # v4.0: the druid
    24) trace_line 6; add_fx poison "$LCELLS" 1
        [[ -n $LHIT ]] && { deal "$LHIT" 130 0; dot_add "$LHIT" $(( ATK * 30 / 100 )) 4; } ;;
    25) mons_within 3; (( ${#MLIST[@]} )) || { logm "Nothing close enough to entangle."; return; }
        for m in "${MLIST[@]}"; do deal "$m" 60 3500; done
        ring 3; add_fx poison "$RING" 1; logm "Roots hold ${#MLIST[@]} foes fast." "$K_GOOD" ;;
    26) heal_amount; heal_self "$HEALV"; party_near 8
        for p in "${NEAR[@]}"; do send HEAL "$MY_ID" "$MY_NAME" "$p" "$HEALV"; done
        ring 2; add_fx holy "$RING" 1; party_txt; logm "Wild Growth heals you$PTXT for $HEALV." "$K_GOOD" ;;
    # v4.0: the monk
    27) adj_target || { logm "Nobody in reach of your fists."; return; }
        deal "$ADJ" 70 0 q; deal "$ADJ" 70 0 q; deal "$ADJ" 70 0; add_fx slash "${CM_X[$ADJ]},${CM_Y[$ADJ]}" 1 ;;
    28) dash 4 "$FDX" "$FDY"
        c=""; for (( m = 0; m <= DSTEPS; m++ )); do c+="$(( sx + FDX * m )),$(( sy + FDY * m )) "; done
        if [[ -n $DASH_HIT ]]; then deal "$DASH_HIT" 160 1500; c+="${CM_X[$DASH_HIT]},${CM_Y[$DASH_HIT]}"
        elif (( DSTEPS == 0 )); then logm "No room to jump."; return; fi
        add_fx slash "$c" 1 ;;
    29) heal_self $(( MAXHP * 22 / 100 )); immune_until=$(( NOW + 1500 ))
        ring 1; add_fx holy "$RING" 1; logm "Inner peace: you heal, and nothing touches you for 1.5s." "$K_GOOD" ;;
  esac
  # v3.0: talents bend the rules a little
  has_cap clearcast && (( RANDOM % 100 < 20 )) && { cost=0; logm "Clearcasting - that one was free." "$K_GOOD"; }
  MP=$(( MP - cost )); SKCD[k]=$(( NOW + S_CD[s] * (100 - TB_CD[k] - TB_CDALL) / 100 )); POS_DIRTY=1
  (( k == 2 )) && has_cap echo && (( RANDOM % 100 < 30 )) && { SKCD[2]=$NOW; logm "Encore! ${S_NAME[s]} is ready again." "$K_GOOD"; }
  if (( k == 0 )) && has_cap chain && [[ -n $TARGET && -n ${CM_T[$TARGET]} ]]; then
    local cm; mons_within 6
    for cm in "${MLIST[@]}"; do [[ $cm == "$TARGET" ]] && continue; deal "$cm" 60 0; add_fx bone "${CM_X[$cm]},${CM_Y[$cm]}" 1; break; done
  fi
  if (( SMH > 0 )); then
    heal_self "$SMH"; party_near 8; for p in "${NEAR[@]}"; do send HEAL "$MY_ID" "$MY_NAME" "$p" "$SMH"; done
  fi
  case $s in 10|11|15|17|26|29) pst_clear all ;; esac     # holy magic (and nature, and calm) cleanses
  CASTK=-1 DEAL_EL=0
}

take_damage() {  # dmg source [mid] [element] [effect]
  (( DEAD )) && return
  [[ -n $3 ]] && (( M_KIND[${CM_T[$3]:-0}] > 0 )) && ATK_NPC[$3]=1     # fight back against angry NPCs
  [[ -n $3 ]] && ALY_LAST=$3
  if (( NOW < immune_until )); then logm "You evade $2's attack!" "$K_GOOD"; return; fi
  (( RIDING )) && { mount_off quiet; logm "You are thrown from your mount!" "$K_HURT"; }
  local a=$ARMOR d el=${4:-0} r=$RES tag=""
  if (( RANDOM % 100 < DODGE )); then
    logm "You dodge $2's attack!" "$K_GOOD"; ft_add "$PX" "$PY" "dodge" $'\e[0;38;5;250;48;5;234m'
    has_cap evasion && EVPROC=1
    return
  fi
  (( NOW < iron_until )) && a=$(( ARMOR * 3 / 2 ))
  if (( el == 0 )); then d=$(( $1 * 100 / (100 + a * 5) ))
  else                                                       # magic: half the armor, resistances count
    (( el == 1 && NOW < fireward_until )) && r=$(( r + 25 ))
    (( el == 2 && NOW < frost_until )) && r=$(( r + 25 ))
    d=$(( $1 * 100 / (100 + a * 5 / 2) * (100 - r) / 100 )); tag=" ${EL_NAME[el]}"
  fi
  if (( BLOCK && RANDOM % 100 < BLOCK )); then d=$(( d / 2 )); tag+=" (blocked)"; fi
  (( d < 1 )) && d=1
  if (( BARRIER > 0 )); then
    if (( BARRIER >= d )); then BARRIER=$(( BARRIER - d )); logm "Your shield absorbs $d." "$K_GOOD"; return; fi
    d=$(( d - BARRIER )); BARRIER=0
  fi
  if [[ -n $3 ]] && (( TB_THORNS > 0 && el == 0 )) && [[ -n ${CM_T[$3]} ]] && hostile "$3"; then
    send HIT "$MY_ID" "$CUR_MAP" "$3" $(( d * TB_THORNS / 100 + 1 )) 0
  fi
  HP=$(( HP - d )); last_hurt=$NOW; POS_DIRTY=1 MAP_DIRTY=1
  logm "$2 hits you for $d$tag" "$K_HURT"
  ft_add "$PX" "$PY" "-$d" $'\e[0;1;38;5;203;48;5;234m' 
  if (( HP <= 0 )); then die_now "$2"; return; fi
  [[ -n $5 ]] && pst_apply "$5" "$1"
}

respawn() {
  DEAD=0 HP=$MAXHP MP=$MAXMP; PS_UNTIL=(0 0 0 0 0 0)
  [[ $CUR_MAP != W ]] && leave_instance quiet
  PX=$SPAWN_X PY=$SPAWN_Y POS_DIRTY=1 MAP_DIRTY=1
  logm "You wake up by the fountain of Hearthmoor." "$K_GOOD"
}

use_item() {  # h m gh gm str iron swift recall brew
  (( DEAD )) && return
  case $1 in
    h)  if (( POT_H > 0 )); then POT_H=$(( POT_H - 1 )); heal_self $(( MAXHP * (40 + TB_POT) / 100 )); pst_clear; logm "You drink a health potion." "$K_GOOD"
        elif (( POT_GH > 0 )); then use_item gh
        else logm "No health potions left. Mara sells them in Hearthmoor."; fi ;;
    m)  if (( POT_M > 0 )); then POT_M=$(( POT_M - 1 )); MP=$(( MP + MAXMP * 50 / 100 )); logm "You drink a mana potion." "$K_GOOD"
        elif (( POT_GM > 0 )); then use_item gm
        else logm "No mana potions left. Mara sells them in Hearthmoor."; fi ;;
    gh) (( POT_GH > 0 )) || return; POT_GH=$(( POT_GH - 1 )); heal_self $(( MAXHP * (80 + TB_POT) / 100 )); pst_clear; logm "You drink a greater health potion." "$K_GOOD" ;;
    gm) (( POT_GM > 0 )) || return; POT_GM=$(( POT_GM - 1 )); MP=$(( MP + MAXMP * 80 / 100 )); logm "You drink a greater mana potion." "$K_GOOD" ;;
    str)   (( EL_STR > 0 )) || return; EL_STR=$(( EL_STR - 1 )); str_until=$(( NOW + 90000 )); logm "Elixir of Strength: +30% damage for 90s." "$K_GOOD" ;;
    iron)  (( EL_IRON > 0 )) || return; EL_IRON=$(( EL_IRON - 1 )); iron_until=$(( NOW + 90000 )); logm "Elixir of Iron Skin: +50% armor for 90s." "$K_GOOD" ;;
    swift) (( EL_SWIFT > 0 )) || return; EL_SWIFT=$(( EL_SWIFT - 1 )); swift_until=$(( NOW + 60000 )); logm "Elixir of Swiftness: you move faster for 60s." "$K_GOOD" ;;
    recall) (( SCROLL > 0 )) || return; SCROLL=$(( SCROLL - 1 )); home_ready=0; recall ;;
    brew)  (( BREW > 0 )) || return; BREW=$(( BREW - 1 )); HP=$MAXHP MP=$MAXMP str_until=$(( NOW + 120000 ))
           logm "Hermit's Brew! Fully restored and +30% damage for 120s." "$K_GOOD" ;;
    meal1) (( MEAL1 > 0 )) || return; local m2=$MEAL2; MEAL2=0; eat; MEAL2=$m2 ;;
    meal2) (( MEAL2 > 0 )) || return; eat ;;
    tfrost) (( TON_FROST > 0 )) || return; TON_FROST=$(( TON_FROST - 1 )); frost_until=$(( NOW + 300000 ))
            logm "Frost Tonic: the cold can't slow you down for 5 minutes." "$K_GOOD" ;;
    tfire)  (( TON_FIRE > 0 )) || return; TON_FIRE=$(( TON_FIRE - 1 )); fireward_until=$(( NOW + 300000 ))
            logm "Fire Ward Tonic: burning ash can't hurt you for 5 minutes." "$K_GOOD" ;;
    tveil)  (( TON_VEIL > 0 )) || return; TON_VEIL=$(( TON_VEIL - 1 )); veil_until=$(( NOW + 300000 ))
            logm "Sand Veil: your eyes pierce storms and darkness for 5 minutes." "$K_GOOD" ;;
  esac
  (( MP > MAXMP )) && MP=$MAXMP
  POS_DIRTY=1
}

# --- moving, dungeons ---------------------------------------------------------
init_fog() {
  local y blank
  printf -v blank '%*s' "${MAPW[$1]}" ''
  for (( y = 0; y < MAPH[$1]; y++ )); do EXPL["$1:$y"]=$blank; done
}

enter_instance() {  # map dt seed
  WX=${D_ENTX[$2]} WY=$(( D_ENTY[$2] + 1 ))
  gen_dungeon "$1" "$2" "$3"
  drop_vrows "$1"
  mount_off quiet
  CUR_MAP=$1 CUR_DT=$2 PX=$DG_SX PY=$DG_SY clear_until=0 UI=""
  cm_clear; init_fog "$1"; set_palette "$2"
  POS_DIRTY=1 MAP_DIRTY=1
  logm "You descend into the ${D_NAME[$2]}. Somewhere in the dark waits its master..." "$K_ANN"
}

leave_instance() {
  local old=$CUR_MAP y
  [[ $old == W ]] && return
  drop_vrows "$old"
  for (( y = 0; y < ${MAPH[$old]:-0}; y++ )); do unset "MAPROW[$old:$y]" "EXPL[$old:$y]"; done
  CUR_MAP=W CUR_DT=-1 PX=$WX PY=$WY clear_until=0
  cm_clear; set_palette -1
  [[ $old == H* ]] && room_left
  send SYNC "$MY_ID" W
  POS_DIRTY=1 MAP_DIRTY=1 NEED_FULL=1
  if [[ $1 != quiet ]]; then
    if [[ $old == H* ]]; then logm "You go back down to the taproom." "$K_SYS"; else logm "You climb back into the daylight." "$K_GOOD"; fi
  fi
}

dungeon_enter() {
  local d
  for (( d = 0; d < NDT; d++ )); do
    (( PX == D_ENTX[d] && PY == D_ENTY[d] )) || continue
    if (( LVL < D_REQ[d] )); then logm "A cold voice whispers: the ${D_NAME[d]} is for level ${D_REQ[d]}+." "$K_HURT"; return; fi
    if (( LVL >= MAXLVL || d == RAID_DT )); then [[ $UI == dgate ]] || dgate_open "$d"; return; fi   # v4.5: normal or mythic?
    (( NOW < dreq_until )) && return
    dreq_until=$(( NOW + 4000 ))
    send DREQ "$MY_ID" "$d"
    logm "You open the gate to the ${D_NAME[d]}..." "$K_SYS"
  done
}

rest() {
  HP=$MAXHP MP=$MAXMP POS_DIRTY=1; pst_clear all
  logm "$1" "$K_GOOD"
}

try_move() {  # dx dy
  local nx=$(( PX + $1 )) ny=$(( PY + $2 ))
  FDX=$1 FDY=$2
  (( DEAD || NOW < next_move )) && return
  stunned && return
  if mon_at "$nx" "$ny" && (( M_KIND[${CM_T[$MID]}] == 3 )); then gather_start "$MID"; return; fi
  (( FISH_ST )) && fish_stop
  GATH_MID=""
  if mon_at "$nx" "$ny"; then
    if hostile "$MID"; then melee "$MID"; else talk_open "$MID"; fi
    next_move=$(( NOW + 150 )); return
  fi
  if [[ $CUR_MAP == H* && -n ${RM_AT[$nx,$ny]} ]]; then room_use "${RM_AT[$nx,$ny]}"; next_move=$(( NOW + 250 )); return; fi   # v5.0
  tile "$CUR_MAP" "$nx" "$ny"
  case $T in
    Q) qev_board; QSRC=board; [[ ${#OFFERS[@]} -gt 0 && $OFFER_LVL == "$LVL" && $OFFER_SRC == board ]] || gen_offers; UI=quest; MAP_DIRTY=1; return ;;
    Z) UI=way MAP_DIRTY=1; explore_here; return ;;
    O) logm "The fountain glitters. Press [?] for help, [m] for the world map."; next_move=$(( NOW + 500 )); return ;;
    F) CRAFT=cook UI=craft MAP_DIRTY=1; return ;;
  esac
  p_walk "$CUR_MAP" "$nx" "$ny" || return
  local ox=$PX oy=$PY
  PX=$nx PY=$ny POS_DIRTY=1 MAP_DIRTY=1
  aly_follow "$ox" "$oy"
  explore_here
  if (( NOW < anthem_until || NOW < swift_until )); then next_move=$(( NOW + 75 )); else next_move=$(( NOW + 110 )); fi
  [[ $CW == snow ]] && (( NOW >= frost_until )) && next_move=$(( next_move + 120 ))   # wading through the blizzard
  (( NOW < PS_UNTIL[3] )) && next_move=$(( next_move + 110 ))                        # chilled
  (( TB_SPEED || (NOW < FRENZY_T && FRENZY) )) && next_move=$(( NOW + (next_move - NOW) * (100 - TB_SPEED - (NOW < FRENZY_T ? FRENZY * 5 : 0)) / 100 ))
  mount_delay
  if [[ $T == '>' && $CUR_MAP == W ]]; then dungeon_enter
  elif [[ $T == '<' && $CUR_MAP != W ]]; then leave_instance; fi
}

melee_any() {
  adj_target && melee "$ADJ"
}

recall() {
  if (( NOW < home_ready )); then logm "Your hearthstone is still cooling down ($(( (home_ready - NOW) / 1000 ))s)."; return; fi
  (( DEAD )) && return
  home_ready=$(( NOW + 60000 ))
  [[ $CUR_MAP != W ]] && leave_instance quiet
  PX=$SPAWN_X PY=$SPAWN_Y POS_DIRTY=1 MAP_DIRTY=1
  logm "You crush your hearthstone and appear in Hearthmoor." "$K_GOOD"
  explore_here
}

# --- NPCs, shops ------------------------------------------------------------------
pick_line() {  # "a|b|c" -> LINE   (nothing to say: "" - a modulo by zero here once ended the whole game)
  local IFS='|' arr
  arr=($1); LINE=""
  (( ${#arr[@]} )) && LINE=${arr[RANDOM % ${#arr[@]}]}
}

talk_open() {  # mid
  local t=${CM_T[$1]} role
  role=${N_ROLE[$t]}
  TALK_MID=$1 TALK_T=$t TALK_CONFIRM=0 UI=talk MAP_DIRTY=1
  if (( NOW < WANTED_UNTIL )) && [[ $role == @(general|smith|alchemist|inn|guard|villager|merc|bank) ]]; then
    LINE="Murderer! I'll have nothing to do with you. GUARDS!"
  else
    pick_line "${N_SAY[$role]}"
  fi
  if story_npc "$t"; then TALK_LINE=$LINE; story_event T "$t"; return; fi
  TALK_LINE=$LINE
  ql_talk "$t" && return
  if (( STORY < NST )) && [[ ${ST_OBJ[STORY]} == "T.$t" ]]; then LINE="I have something to tell you, friend - but come back when you are level ${ST_LVL[STORY]}."; fi
  local i f q done=()
  for i in "${!QUESTS[@]}"; do
    [[ ${QUESTS[i]} == "T.$t."* ]] && done=("$i" "${done[@]}")
  done
  for i in "${done[@]}"; do quest_done "$i"; LINE="A letter for me? Thank you, friend - here's something for your trouble."; done
  for q in "${PQ_CODES[@]}"; do
    [[ $q == "T.$t."* ]] && { send QTALK "$MY_ID" "$t"; LINE="Ah, the letter your party carries! Many thanks."; break; }
  done
  TALK_LINE=$LINE
}

shop_build() {  # role -> SH_ID SH_LABEL SH_PRICE
  local t r
  SH_ID=() SH_LABEL=() SH_PRICE=()
  tier_for "$LVL"; t=$TF; r=$(( t < MAXTIER ? t + 1 : MAXTIER ))
  shi() { SH_ID+=("$1"); SH_LABEL+=("$2"); SH_PRICE+=("$3"); }
  shg() {  # gear code price
    item_name "$1" "$CLS"; bonus_txt
    if (( IVAL )); then local l=dmg; [[ $IK != W ]] && l=arm; shi "$1" "$INAME  (+$IVAL $l, $BTX)" "$2"
    else shi "$1" "$INAME  ($BTX)" "$2"; fi
  }
  case $1 in
    general)
      shi h "Health potion  (+40% HP)" 20; shi m "Mana potion  (+50% MP)" 20; shi recall "Scroll of Recall  (instant /home)" 40
      shi B.0 "" 150; shi B.1 "" 400 ;;
    smith)
      shg "W.${DEFW[CLS]}.$t.0" $(( 30 * t * t + 20 )); shg "A.${DEFA[CLS]}.$t.0" $(( 30 * t * t + 20 ))
      shg "W.${ALTW[CLS]}.$r.1" $(( 90 * r * r + 60 )); shg "A.${DEFA[CLS]}.$r.1" $(( 90 * r * r + 60 ))
      shg "H.${DEFH[CLS]}.$t.0" $(( 20 * t * t + 15 )); shg "O.${DEFO[CLS]}.$t.0" $(( 20 * t * t + 15 ))
      reforge_info "$EQW"; shi rfw "Reforge your weapon  ($RFTXT)" "$RFCOST"
      reforge_info "$EQA"; shi rfa "Reforge your armor  ($RFTXT)" "$RFCOST" ;;
    alchemist)
      shi gh "Greater health potion  (+80% HP)" 60; shi gm "Greater mana potion  (+80% MP)" 60
      shi str "Elixir of Strength  (+30% dmg, 90s)" 120; shi iron "Elixir of Iron Skin  (+50% armor, 90s)" 120
      shi swift "Elixir of Swiftness  (faster, 60s)" 90; shi h "Health potion" 25; shi m "Mana potion" 25 ;;
    trader)
      shi gh "Greater health potion" 75
      shg "J.0.$t.1" $(( 40 * t * t + 60 )); shg "J.1.$t.1" $(( 40 * t * t + 60 ))
      shg "J.2.$t.1" $(( 40 * t * t + 60 )); shg "J.3.$t.1" $(( 40 * t * t + 60 )); shg "O.3.$t.0" $(( 15 * t * t + 30 ))
      shg "W.${DEFW[CLS]}.$t.0" $(( (30 * t * t + 20) * 13 / 10 )); shi B.1 "" 450; shi B.2 "" 950 ;;
    hermit)
      shi brew "Hermit's Brew  (full restore, +30% dmg 120s)" 150; shi gm "Greater mana potion" 55
      shi swift "Elixir of Swiftness" 80 ;;
    spice)
      shi h "Health potion" 28; shi gh "Greater health potion" 70
      shi tfire "Fire Ward Tonic  (ash rain immunity, 5 min)" 90; shi tfrost "Frost Tonic  (no blizzard slow, 5 min)" 90
      shi tveil "Sand Veil  (see far in storms and at night)" 110; shi swift "Elixir of Swiftness" 95
      shi B.2 "" 950; shi B.3 "" 1900 ;;
    questgiver)
      shi h "Health potion" 30; shi m "Mana potion" 30
      case $TALK_T in
        46) shi tveil "Sand Veil  (see far in storms and at night)" 120; shi recall "Scroll of Recall" 50 ;;
        49) shi tfrost "Frost Tonic  (no blizzard slow, 5 min)" 95; shi gh "Greater health potion" 75; shi B.3 "" 1850 ;;
        52) shi tfire "Fire Ward Tonic  (ash rain immunity, 5 min)" 95; shi gm "Greater mana potion" 75; shi B.4 "" 4200 ;;
        $(( NPC1 + 1 ))) shi gh "Greater health potion" 80; shi gm "Greater mana potion" 80; shi recall "Scroll of Recall" 60; shi B.3 "" 2000 ;;
        $(( NPC1 + 5 ))) shi gm "Greater mana potion" 80; shi tfrost "Frost Tonic  (no blizzard slow, 5 min)" 95
                         shi iron "Elixir of Iron Skin  (+50% armor, 90s)" 130; shi B.4 "" 4500 ;;
        $(( NPC1 + 10 ))) shi gh "Greater health potion" 80; shi str "Elixir of Strength  (+30% dmg, 90s)" 130
                          shi swift "Elixir of Swiftness" 95; shi B.4 "" 4500 ;;
        $(( NPC1 + 14 ))) shi gh "Greater health potion" 80; shi tfire "Fire Ward Tonic  (ash rain immunity, 5 min)" 95
                          shi tveil "Sand Veil  (see far in storms and at night)" 115; shi B.4 "" 4400 ;;
        $(( NPC1 + 19 ))) shi gh "Greater health potion" 90; shi gm "Greater mana potion" 90; shi brew "Hermit's Brew  (full restore, +30% dmg 120s)" 180
                          shi str "Elixir of Strength  (+30% dmg, 90s)" 140; shi B.5 "" 15000 ;;
      esac ;;
  esac
  local i; rep_disc "$TALK_T"                         # v3.0: reputation brings discounts
  (( DISC )) && for i in "${!SH_PRICE[@]}"; do SH_PRICE[i]=$(( SH_PRICE[i] * (100 - DISC) / 100 )); done
}

fish_value() { local f; FISHN=0 FISHV=0; for (( f = 12; f < NMAT; f++ )); do FISHN=$(( FISHN + MATS[f] )) FISHV=$(( FISHV + MATS[f] * MAT_VAL[f] )); done; }

reforge_info() {  # code -> RFCOST RFCHANCE RFTXT
  item_stats "$1"
  if (( IRR >= 3 )); then RFCOST=0 RFCHANCE=0 RFTXT="already legendary"; return; fi
  RFCOST=$(( 60 * IT * IT * (IRR + 1) + 50 ))
  RFCHANCE=$(( IRR == 0 ? 80 : (IRR == 1 ? 55 : 30) ))
  RFTXT="${RAR_NAME[IRR+1]}, ${RFCHANCE}% chance"
}

junk_value() {  # -> JUNK (count) JVAL, items worse or equal to what you wear
  local c cur
  JUNK=0 JVAL=0
  for c in "${INV[@]}"; do
    is_junk "$c" && { JUNK=$(( JUNK + 1 )); JVAL=$(( JVAL + JS )); }
  done
}

eq_of() { case $1 in W) EQC=$EQW ;; A) EQC=$EQA ;; O) EQC=$EQO ;; H) EQC=$EQH ;; *) EQC=$EQJ ;; esac; }   # slot -> EQC

is_junk() {  # code -> 0 if unusable for my class or not better than what I wear there; JS = sell value
  local v b
  item_stats "$1"; JS=$ISELL
  [[ $1 == *! || $IK == [BC] || -n $IUQ ]] && return 1
  [[ $ICLS == *"$CLS"* ]] || return 0
  v=$IVAL b=$IBV; eq_of "$IK"; [[ -n $EQC ]] || return 1
  item_stats "$EQC"
  (( v < IVAL || (v == IVAL && b <= IBV) ))
}

shop_key() {
  local i id price c keep=() total=0 cur
  shop_build "$SHOP"
  case $1 in
    [1-9])
      i=$(( $1 - 1 )); (( i < ${#SH_ID[@]} )) || return
      id=${SH_ID[i]} price=${SH_PRICE[i]}
      if [[ $id == rf? ]]; then
        local code=$EQW; [[ $id == rfa ]] && code=$EQA
        reforge_info "$code"
        (( RFCOST > 0 )) || { logm "That one is already legendary."; return; }
        (( GOLD >= RFCOST )) || { logm "Brom wants $RFCOST gold for that." "$K_HURT"; return; }
        GOLD=$(( GOLD - RFCOST ))
        if (( RANDOM % 100 < RFCHANCE )); then
          code="$IK.$IKD.$IT.$(( IRR + 1 ))"
          if [[ $id == rfw ]]; then EQW=$code; else EQA=$code; fi
          calc_stats; item_name "$code" "$CLS"
          logm "SUCCESS! Brom hands you a $INAME." "$K_ANN"
        else
          logm "The metal cracks... Brom shrugs. Better luck next time." "$K_HURT"
        fi
        return
      fi
      (( GOLD >= price )) || { logm "You need $price gold." "$K_HURT"; return; }
      case $id in
        B.*) bag_buy "$id" || return ;;
        [WAOHJ].*) (( ${#INV[@]} < BAGS )) || { logm "Your bags are full - sell something first." "$K_HURT"; return; }
                INV+=("$id"); NEWG[$id]=1; item_name "$id" "$CLS"; logm "Bought $INAME. Equip it in your inventory [i]." "$K_LOOT" ;;
        h) POT_H=$(( POT_H + 1 )) ;; m) POT_M=$(( POT_M + 1 )) ;; gh) POT_GH=$(( POT_GH + 1 )) ;; gm) POT_GM=$(( POT_GM + 1 )) ;;
        str) EL_STR=$(( EL_STR + 1 )) ;; iron) EL_IRON=$(( EL_IRON + 1 )) ;; swift) EL_SWIFT=$(( EL_SWIFT + 1 )) ;;
        recall) SCROLL=$(( SCROLL + 1 )) ;; brew) BREW=$(( BREW + 1 )) ;;
        tfire) TON_FIRE=$(( TON_FIRE + 1 )) ;; tfrost) TON_FROST=$(( TON_FROST + 1 )) ;; tveil) TON_VEIL=$(( TON_VEIL + 1 )) ;;
      esac
      GOLD=$(( GOLD - price ))
      [[ $id == [WAOHJB].* ]] || logm "Bought: ${SH_LABEL[i]%%  (*} (${price}g)" "$K_LOOT" ;;
    j|J)
      junk_value; (( JUNK )) || { logm "No junk in your bags - everything beats what you wear."; return; }
      for c in "${INV[@]}"; do is_junk "$c" || keep+=("$c"); done
      INV=("${keep[@]}"); GOLD=$(( GOLD + JVAL )); logm "Sold $JUNK junk items for $JVAL gold." "$K_LOOT" ;;
    c|C)                                                         # v5.0: collectables you already own once
      [[ $SHOP == @(general|trader|spice) ]] || return
      col_dupes; (( ${#DUP[@]} )) || { logm "No duplicate collectables in your bags - lock one with [l] to keep it."; return; }
      for c in "${!INV[@]}"; do [[ " ${DUP[*]} " == *" $c "* ]] || keep+=("${INV[c]}"); done
      GOLD=$(( GOLD + DUPV )); logm "Sold ${#DUP[@]} duplicate collectables for $DUPV gold." "$K_LOOT"; INV=("${keep[@]}") ;;
    f|F)
      [[ $SHOP == @(general|trader|spice) ]] || return
      fish_value; (( FISHN )) || { logm "You have no fish to sell."; return; }
      for (( c = 12; c < NMAT; c++ )); do MATS[c]=0; done
      GOLD=$(( GOLD + FISHV )); logm "Sold $FISHN fish for $FISHV gold." "$K_LOOT" ;;
    s|S)
      (( ${#INV[@]} )) || { logm "Nothing to sell."; return; }
      for c in "${INV[@]}"; do if [[ $c == *! || $c == C.* ]]; then keep+=("$c"); else item_stats "$c"; total=$(( total + ISELL )); fi; done
      (( ${#INV[@]} > ${#keep[@]} )) || { logm "Everything in your bags is locked (or a collectable)."; return; }
      GOLD=$(( GOLD + total )); logm "Sold $(( ${#INV[@]} - ${#keep[@]} )) items for $total gold." "$K_LOOT"; INV=("${keep[@]}") ;;
  esac
}

talk_key() {
  local role=${N_ROLE[$TALK_T]} name=${N_FULL[$TALK_T]}
  [[ -n ${CM_T[$TALK_MID]} ]] || { UI=""; return; }
  case $1 in
    1)
      if (( NOW < WANTED_UNTIL )) && [[ $role == @(general|smith|alchemist|inn|guard|villager|bank) ]]; then
        TALK_LINE="I said get lost, murderer!"; return
      fi
      case $role in
        inn)   rest "${N_FULL[$TALK_T]} serves you a hot stew. HP and MP fully restored."; TALK_LINE="There you go. Come back anytime!" ;;
        merc)  UI=allyshop ;;
        stable) STABLE_SRC=talk UI=stable ;;
        valor) UI=valor ;;
        medic) rest "Senna patches you up. HP and MP fully restored."; TALK_LINE="All done. Try not to get stabbed again." ;;
        guard|villager) ;;
        bank) bank_open ;;
        *) SHOP=$role UI=shop ;;
      esac ;;
    2) TALK_LINE=${RUMORS[RANDOM % ${#RUMORS[@]}]} ;;
    4) case $role in
         smith) CRAFT=forge UI=craft ;; alchemist|hermit) CRAFT=alch UI=craft ;; inn) CRAFT=cook UI=craft ;;
       esac ;;
    5) ql_key ;;
    6) ql_for_npc "$TALK_T" && UI=wares ;;
    7) [[ $role == smith ]] && jewel_open ;;
    8) [[ $role == inn ]] && tal_reset ;;
    9) [[ $role == inn ]] || return                             # v5.0: rooms upstairs
       if (( NOW < WANTED_UNTIL )); then TALK_LINE="No rooms for murderers. Out!"; return; fi
       UI=inn ;;
    3) [[ -n ${N_QK[$TALK_T]}${N_QD[$TALK_T]} ]] || return
       QSRC=$TALK_T
       [[ ${#OFFERS[@]} -gt 0 && $OFFER_LVL == "$LVL" && $OFFER_SRC == "$QSRC" ]] || gen_offers
       UI=quest ;;
    x|X)
      if (( TALK_CONFIRM )); then
        ATK_NPC[$TALK_MID]=1; UI=""; next_attack=0; melee "$TALK_MID"
        logm "You attack $name! The guards will hear of this." "$K_HURT"
      else
        TALK_CONFIRM=1
      fi ;;
  esac
}

quest_key() {
  [[ $1 == [1-9] ]] || return
  local i=$(( $1 - 1 )) keep fresh
  (( i >= 0 && i < ${#OFFERS[@]} )) || return
  if [[ -n $MY_PARTY ]]; then
    if [[ $PARTY_LEADER != "$MY_ID" ]]; then
      logm "Only your party leader (${OP_NAME[$PARTY_LEADER]:-?}) can accept quests for the party." "$K_HURT"; return
    fi
    (( ${#PQ_CODES[@]} < 3 )) || { logm "Your party already has 3 quests." "$K_HURT"; return; }
    send QADD "$MY_ID" "${OFFERS[i]}"
  else
    (( ${#QUESTS[@]} < 3 )) || { logm "You can only track 3 quests at once." "$K_HURT"; return; }
    QUESTS+=("${OFFERS[i]}"); quest_text "${OFFERS[i]}"
    logm "Quest accepted: ${QTXT%% (*}" "$K_ANN"
  fi
  keep=("${OFFERS[@]}"); gen_offers; fresh=${OFFERS[i]}; OFFERS=("${keep[@]}"); OFFERS[i]=$fresh
}

# --- chat ---------------------------------------------------------------------
find_player() {  # name -> FOUND id (same map, any distance) or empty
  local id want=${1,,}
  FOUND=""
  for id in "${!OP_NAME[@]}"; do [[ ${OP_NAME[$id],,} == "$want" ]] && FOUND=$id; done
}

chat_submit() {
  clean_text "$CHAT_BUF"; local t=$CLEAN id list="" a b c i
  t=${t#"${t%%[![:space:]]*}"}
  [[ -n $t ]] || return
  case $t in
    "/p "*)  [[ -n $MY_PARTY ]] || { logm "You are not in a party. /invite <name>"; return; }
             send PCHAT "$MY_ID" "$MY_NAME" "${t#/p }"; chatm "[party] $MY_NAME: ${t#/p }" "$K_PARTY" ;;
    "/w "*)  a=${t#/w }; b=${a#* }; a=${a%% *}
             [[ -n $a && $b != "$a" ]] || { logm "Usage: /w <name> <message>"; return; }
             send WHISP "$MY_ID" "$MY_NAME" "$a" "$b"; chatm "[to $a] $b" "$K_WHISP" ;;
    "/invite "*) send INV "$MY_ID" "$MY_NAME" "${t#/invite }" ;;
    /accept) send PACC "$MY_ID" ;;
    /leave)  send PLEAVE "$MY_ID"; logm "You leave your party." ;;
    "/me "*) send EMOTE "$MY_ID" "$MY_NAME" "${t#/me }"; chatm "* $MY_NAME ${t#/me }" "$K_WHISP" ;;
    /home)   recall ;;
    /trade)  trade_cmd "" ;;
    "/trade "*) a=${t#/trade }; trade_cmd "${a%% *}" ;;
    "/give "*)
      a=${t#/give }; b=${a#* }; a=${a%% *}
      find_player "$a"
      [[ -n $FOUND ]] || { logm "Nobody called '$a' is online."; return; }
      cheb $(( ${OP_X[$FOUND]:-999} - PX )) $(( ${OP_Y[$FOUND]:-999} - PY ))
      [[ ${OP_MAP[$FOUND]} == "$CUR_MAP" ]] && (( D <= 3 )) || { logm "${OP_NAME[$FOUND]} must stand right next to you."; return; }
      if [[ $b =~ ^#([1-9]|1[0-9]|20)$ ]]; then
        i=$(( ${b#\#} - 1 )); (( i < ${#INV[@]} )) || { logm "You have no item #${b#\#}."; return; }
        c=${INV[i]%!}; unset "INV[i]"; INV=("${INV[@]}")
        send GIVE "$MY_ID" "$MY_NAME" "${OP_NAME[$FOUND]}" I "$c"
        item_name "$c" "$CLS"; logm "You hand $INAME to ${OP_NAME[$FOUND]}." "$K_LOOT"
      elif isnum "$b" && (( b > 0 )); then
        (( b <= GOLD )) || { logm "You only have $GOLD gold."; return; }
        GOLD=$(( GOLD - b )); send GIVE "$MY_ID" "$MY_NAME" "${OP_NAME[$FOUND]}" G "$b"
        logm "You give $b gold to ${OP_NAME[$FOUND]}." "$K_LOOT"
      else
        logm "Usage: /give <name> <gold>   or   /give <name> #<item number>"
      fi ;;
    "/symbol "*)
      a=${t#/symbol }
      if valid_sym "$a"; then SYM=$a; POS_DIRTY=1 MAP_DIRTY=1; logm "Your symbol is now $SYM."; else logm "Pick one printable character, e.g. /symbol &"; fi ;;
    "/color "*)
      a=${t#/color }; b=""
      for i in "${!P_COLN[@]}"; do [[ ${P_COLN[i]} == "${a,,}" || $a == "$(( i + 1 ))" ]] && b=$i; done
      if [[ -n $b ]]; then COLR=$b; POS_DIRTY=1 MAP_DIRTY=1; logm "Your color is now ${P_COLN[b]}."
      else logm "Colors: ${P_COLN[*]}  (or 1-${#P_COLN[@]})"; fi ;;
    /who)
      list="$SYM $MY_NAME (${C_NAME[CLS]} $LVL)"
      for id in "${!OP_NAME[@]}"; do list+=", ${OP_SYM[$id]:-@} ${OP_NAME[$id]} (${C_NAME[${OP_CLS[$id]:-0}]} ${OP_LVL[$id]})"; done
      logm "Online: $list" ;;
    /help)   logm "/p party  /w name msg  /invite /accept /leave  /trade name  /give name gold|#item  /symbol c  /color c  /who  /me  /home" ;;
    /*)      logm "Unknown command ${t%% *} - try /help" ;;
    *)       send CHAT "$MY_ID" "$MY_NAME" "$t"; chatm "$MY_NAME: $t" "$K_CHAT"; MY_SAY=$t MY_SAYT=$(( NOW + 5000 )) MAP_DIRTY=1 ;;
  esac
}

chat_key() {
  local k=$1 rest
  case $k in
    ''|$'\r') CHATTING=0; chat_submit; CHAT_BUF="" ;;
    $'\e')    rest=""; read -rsn5 -t 0.01 rest; [[ -z $rest ]] && { CHATTING=0; CHAT_BUF=""; } ;;
    $'\x7f'|$'\b') CHAT_BUF=${CHAT_BUF%?} ;;
    *) if [[ $k != [[:cntrl:]] ]] && (( ${#CHAT_BUF} < 180 )); then CHAT_BUF+=$k; fi ;;
  esac
}

# --- network messages -----------------------------------------------------------
send_pos() {
  local al=-1; (( ALLY >= 0 )) && [[ $ALY_MAP == "$CUR_MAP" ]] && al=$ALLY
  local mt=-; (( RIDING )) && mt=$MNT_CUR
  send POS "$MY_ID" "$MY_NAME" "$CLS" "$LVL" "$CUR_MAP" "$PX" "$PY" "$HP" "$MAXHP" "$DEAD" "$SYM" "$COLR" "$al" "$AX" "$AY" "$mt"
  last_pos=$NOW POS_DIRTY=0
}

op_del() {
  unset "OP_NAME[$1]" "OP_MAP[$1]" "OP_X[$1]" "OP_Y[$1]" "OP_CLS[$1]" "OP_LVL[$1]" "OP_HP[$1]" "OP_MAX[$1]" \
        "OP_DEAD[$1]" "OP_SEEN[$1]" "OP_SYM[$1]" "OP_COL[$1]" "OP_SAY[$1]" "OP_SAYT[$1]" "OP_WANTED[$1]" "GLY[p$1]" \
        "OP_ALY[$1]" "OP_AX[$1]" "OP_AY[$1]" "OP_MNT[$1]" "GLYH[p$1]"
  MAP_DIRTY=1
}

num() { [[ ${#1} -le 9 && $1 == @(0|[1-9]*([0-9])) ]]; }           # = isnum, without a second call

valid_quest() {  # format + range check (K: monster type, D: dungeon, T: known NPC; C B E G: v3.0)
  [[ $1 =~ ^([KDTCBEG])\.(0|[1-9][0-9]{0,8})(\.(0|[1-9][0-9]{0,8})){4}$ ]] || return 1
  local k=${BASH_REMATCH[1]} t=${BASH_REMATCH[2]}
  case $k in
    K|C|B) (( t < NM )) && [[ ${M_KIND[t]} == 0 ]] ;;
    D) (( t < NDT )) ;;
    T) (( t < NM )) && [[ -n ${N_FULL[$t]} ]] ;;
    E) (( t < NSPOT )) ;;
    G) (( t < NFISHE )) ;;
  esac
}

cli_srv() {  # typ fields...
  local typ=$1 a=$2 b=$3 c=$4 d=$5 e=$6 f=$7 g=$8 h=$9 x n old new q list=()
  case $typ in
    "AR$MY_ID") case $a in
                  ACK)  acct_acked ;;
                  AUTH) acct_nudged ;;                                  # v6.3: the server forgot us (it restarted)
                  OK)   acct_back ;;
                  DENY) if [[ $b == KICK ]]; then acct_kicked "$c"; else logm "The server refused the login: $c" "$K_HURT"; fi ;;
                  BAD) ACK_PEND=0; logm "The server did not accept your save: $b" "$K_HURT" ;;
                esac ;;
    MON)  [[ $a == "$CUR_MAP" ]] && num "$b" && num "$c" && num "$d" && num "$e" && num "$f" && num "$g" || return
          (( c < NM )) || return
          [[ ${SEEN:c:1} == 0 ]] && SEEN="${SEEN:0:c}1${SEEN:c+1}"
          cm_set "$b" "$c" "$d" "$e" "$f" "$g"; MAP_DIRTY=1
          CM_CH[$b]=0; [[ $h =~ ^[1-9][0-9]?$ ]] && (( h <= NCHP )) && CM_CH[$b]=$h ;;
    MMOV) num "$b" && [[ $a == "$CUR_MAP" ]] && num "$c" && num "$d" || return
          if [[ -z ${CM_T[$b]} ]]; then                      # v6.3: a monster we have not heard of (it walked into range)
            num "$e" && num "$f" && num "$g" && (( e < NM )) || return
            [[ ${SEEN:e:1} == 0 ]] && SEEN="${SEEN:0:e}1${SEEN:e+1}"
            cm_set "$b" "$e" "$c" "$d" "$f" "$g"
            CM_CH[$b]=0; [[ $h =~ ^[1-9][0-9]?$ ]] && (( h <= NCHP )) && CM_CH[$b]=$h
          else cm_move "$b" "$c" "$d"; fi
          (( c - PX < VW / 2 + 2 && PX - c < VW / 2 + 2 && d - PY < VH / 2 + 2 && PY - d < VH / 2 + 2 )) && MAP_DIRTY=1 ;;
    MHP)  num "$b" && [[ $a == "$CUR_MAP" && -n ${CM_T[$b]} ]] && num "$c" || return
          CM_HP[$b]=$c ;;
    MDIE) num "$b" && [[ $a == "$CUR_MAP" && -n ${CM_T[$b]} ]] || return
          x=${CM_T[$b]}
          if [[ $c != - ]] && (( M_KIND[x] != 3 )) && [[ $c == "$MY_NAME" || $TARGET == "$b" ]]; then logm "${M_NAME[x]} dies." "$K_HIT"; fi
          [[ $TARGET == "$b" ]] && TARGET=""
          [[ $UI == @(talk|shop) && $TALK_MID == "$b" ]] && UI=""
          cm_del "$b"; MAP_DIRTY=1 ;;
    MATK) [[ $a == "$CUR_MAP" && $c == "$MY_ID" ]] && num "$b" && num "$d" || return
          [[ $e =~ ^[0-6]$ ]] || e=0
          [[ $f == @(poison|bleed|burn|chill|stun|weaken) ]] || f=""
          mname "$b"; take_damage "$d" "$MN" "$b" "$e" "$f" ;;
    LOOT) [[ $a == "$MY_ID" ]] || return
          if [[ $b =~ ^g([0-9]{1,3})$ ]]; then x=${BASH_REMATCH[1]}; (( x < NMAT )) && gem_kq "$x" && gem_get "$x"
          elif [[ $b =~ ^i:(.{3,40})$ ]] && x=${BASH_REMATCH[1]} && valid_item "$x"; then   # v4.5: mythic, raid and invasion rewards
            if (( ${#INV[@]} >= BAGS )); then logm "Your bags are full - a reward was lost!" "$K_HURT"
            else INV+=("$x"); NEWG[$x]=1; item_name "$x" "$CLS"; logm "${EMJ[loot]}Reward: $INAME" $'\e['"${ICOL}m"; fi
          fi ;;
    REW)  [[ $a == "$MY_ID" ]] && num "$b" && num "$c" && num "$e" || return
          (( e < NM )) || return
          reward "$b" "$c" "$d" "$e"; dly_kill "$e" "${f:-0}"; col_kill "$e" "${f:-0}" ;;
    MDONE) [[ $a == "$MY_ID" ]] && num "$b" && num "$c" && num "$d" && num "$e" || return
          (( b <= MYTH_MAX && c <= 2 && e <= 5000 )) && myth_done "$b" "$c" "$d" "$e" ;;
    EVREW) [[ $a == "$MY_ID" ]] && num "$b" && num "$c" && num "$d" || return
          (( b <= 500 && c <= 999999 && d <= 99999 )) || return
          INVK=$(( INVK + 1 )); logm "The town is saved - thank you, defender!" "$K_ANN"
          valor_add "$b" invasion; GOLD=$(( GOLD + d )); gain_xp "$c"; dly_ev inv; ach_check ;;
    PARTY)
      [[ $a =~ ^p[0-9]+$ ]] || return
      if [[ ",$c," == *",$MY_ID,"* ]]; then
        [[ $MY_PARTY != "$a" ]] && logm "You are now in a party. Talk with /p, leave with /leave." "$K_PARTY"
        MY_PARTY=$a PARTY_LEADER=$b; IFS=, read -r -a PARTY_IDS <<< "$c"
      elif [[ $MY_PARTY == "$a" ]]; then
        MY_PARTY="" PARTY_LEADER="" PARTY_IDS=()
        logm "You are no longer in a party." "$K_PARTY"
        pq_to_personal
      fi
      MAP_DIRTY=1 ;;
    PQUEST)
      [[ $a == "$MY_PARTY" && -n $a ]] || return
      IFS=, read -r -a list <<< "$b"
      new=()
      for q in "${list[@]}"; do valid_quest "$q" && new+=("$q"); done
      for q in "${new[@]}"; do
        old=0; for x in "${PQ_CODES[@]}"; do [[ ${x%.*.*.*.*} == "${q%.*.*.*.*}" ]] && old=1; done
        (( old )) || { quest_text "$q"; logm "New party quest: ${QTXT%% (*}  (+25% rewards for everyone)" "$K_PARTY"; }
      done
      PQ_CODES=("${new[@]:0:3}") ;;
    QDONE)
      [[ $a == "$MY_PARTY" && -n $a ]] && num "$b" && num "$c" && valid_quest "$d" || return
      old=0; for x in "${PQ_CODES[@]}"; do [[ ${x%.*.*.*.*} == "${d%.*.*.*.*}" ]] && old=1; done
      (( old && b <= 100000 && c <= 100000 )) || return
      for x in "${!PQ_CODES[@]}"; do [[ ${PQ_CODES[x]%.*.*.*.*} == "${d%.*.*.*.*}" ]] && { unset "PQ_CODES[x]"; break; }; done
      PQ_CODES=("${PQ_CODES[@]}")
      quest_text "$d"
      logm "${EMJ[quest]}PARTY QUEST COMPLETE: ${QTXT%% (*} - +$b XP +$c gold" "$K_ANN"
      GOLD=$(( GOLD + c )); gain_xp "$b" ;;
    PINFO) [[ $a == "$MY_PARTY" && -n $a ]] || return; clean_text "$b"; logm "$CLEAN" "$K_PARTY" ;;
    WANTED)
      [[ $a =~ ^[0-9a-f]{6}$ ]] && [[ $b =~ ^-?[0-9]{1,6}$ ]] || return
      n=$(( 10#${b#-} )); [[ $b == -* ]] && n=0
      if [[ $a == "$MY_ID" ]]; then
        if (( n > 0 )); then
          (( NOW >= WANTED_UNTIL )) && logm "You are WANTED! The guards of Hearthmoor will attack you on sight." "$K_HURT"
          WANTED_UNTIL=$(( NOW + n * 1000 ))
        else
          (( WANTED_UNTIL > NOW )) && logm "You are no longer wanted." "$K_GOOD"
          WANTED_UNTIL=0
        fi
      elif (( n > 0 )); then OP_WANTED[$a]=$(( NOW + n * 1000 ))
      else unset "OP_WANTED[$a]"; fi
      MAP_DIRTY=1 ;;
    PINV) [[ $a == "$MY_ID" ]] || return
          logm "${b//[^A-Za-z0-9_-]/} invites you to a party - type /accept to join." "$K_PARTY"; printf '\a' ;;
    INFO) [[ $a == "$MY_ID" ]] || return; clean_text "$b"; logm "$CLEAN" "$K_SYS" ;;
    DSTART)
      [[ $a =~ ^D[0-9]+$ && $b =~ ^(0|[1-9][0-9]?)$ ]] && (( b < NDT )) && num "$c" || return
      [[ ",$e," == *",$MY_ID,"* ]] || return
      enter_instance "$a" "$b" "$c"
      IN_MK=0 IN_LIM=0 IN_T0=$NOW                               # v4.5: mythic level, time limit (ms), time already used
      if [[ $f =~ ^(0|[1-9][0-9]?)$ && $g =~ ^(0|[1-9][0-9]{0,6})$ ]] && (( f <= MYTH_MAX )); then   # (no leading zeros: octal)
        IN_MK=$f IN_LIM=$g; [[ $h =~ ^(0|[1-9][0-9]{0,6})$ ]] && IN_T0=$(( NOW - h ))
        (( IN_MK )) && { myth_txt "$IN_MK"; logm "MYTHIC $MYT - the clock is running: $(( IN_LIM / 60000 )) minutes!" "$K_ANN"; }
      fi ;;
    DCLEAR)
      [[ $a == "$CUR_MAP" ]] || return
      logm "VICTORY! ${b//[^A-Za-z ]/} has fallen. You return to the surface in 10 seconds." "$K_ANN"
      DCLR=$(( DCLR + 1 )); dly_ev dungn; (( D_REQ[CUR_DT] >= 30 )) && dly_ev dung
      clear_until=$(( NOW + 10000 ))
      for x in "${!QUESTS[@]}"; do [[ ${QUESTS[x]} == "D.$CUR_DT."* ]] && quest_done "$x" && break; done
      qev_dungeon "$CUR_DT"
      story_event D "$CUR_DT" ;;
    DEND) [[ $a == "$CUR_MAP" ]] && leave_instance ;;
    ANN)  clean_text "$a"; logm "$CLEAN" "$K_ANN" ;;
    BOSS) [[ $a == "$CUR_MAP" ]] || return
          if num "$c" && num "$d"; then cheb $(( c - PX )) $(( d - PY )); (( D <= 40 )) || return; fi
          clean_text "$b"; logm "$CLEAN" "$K_HURT" ;;
    CLOCK) num "$a" && (( a < DAYLEN )) || return
           [[ -z $CLK_OFF ]] && DAYPH=""
           CLK_OFF=$(( a - NOW )) ;;
    WEATHER)
      [[ $a =~ ^[0-9]$ && $b =~ ^(-|rain|storm|fog|sand|snow|ash)$ ]] && (( a < NCLS )) && num "$c" || return
      local wr=${WEA_REG[a]//_/ } here=0
      [[ $CUR_MAP == W ]] && { RNAME=""; region_of "$PX" "$PY" nosafe; [[ $RNAME == "$wr" ]] && here=1; }
      if [[ $b == - ]]; then
        (( here && ${WTH_E[a]:-0} > NOW )) && logm "The ${WEA_LABEL[${WTH_K[a]}],,} over the $wr clears up." "$K_SYS"
        WTH_K[a]="" WTH_E[a]=0
      else
        (( c > 600 )) && c=600
        (( ${WTH_E[a]:-0} > NOW )) || {
          if (( here )); then logm "${WEA_START[$b]} the $wr!" "$K_ANN"
          elif [[ $b == @(sand|snow|ash|storm) ]]; then logm "${WEA_START[$b]} the $wr." "$K_SYS"; fi
          [[ $b == ash ]] && ASH_HINT=0
        }
        WTH_K[a]=$b WTH_E[a]=$(( NOW + c * 1000 ))
      fi
      MAP_DIRTY=1 ;;
    WBOSS)
      if num "$a" && num "$b" && num "$c" && num "$d" && (( b < NM )); then WB_CID=$a WB_CT=$b WB_CX=$c WB_CY=$d
      else WB_CID=""; fi ;;
    FX)   [[ $a == "$CUR_MAP" ]] && add_fx "$b" "$c" ;;
  esac
}

cli_line() {
  local line=$1 tag typ from a b c d e f g h i j k l q r nm
  (( ${#line} <= 2048 )) || return
  if [[ $line == SM1\|@(MON|MMOV|MHP|MDIE|MATK)\|srv\|* ]]; then   # most of what the server says is about other maps:
    r=${line#SM1|*|srv|}; [[ ${r%%|*} == "$CUR_MAP" ]] || return     # drop it before parsing (v6.0: ~10x faster)
  fi
  IFS='|' read -r tag typ from a b c d e f g h i j k l q r <<< "$line"
  [[ $tag == SM1 && $from != "$MY_ID" ]] || return
  if [[ $from == srv ]]; then LAST_SRV=$NOW; cli_srv "$typ" "$a" "$b" "$c" "$d" "$e" "$f" "$g" "$h"; return; fi
  [[ $from =~ ^[0-9a-f]{6}$ ]] || return
  nm=${a//[^A-Za-z0-9_-]/}; nm=${nm:0:12}; [[ -n $nm ]] || nm=anon
  case $typ in
    HELLO) [[ -z ${OP_NAME[$from]} ]] && logm "$nm has entered the world." "$K_SYS"
           OP_NAME[$from]=$nm OP_SEEN[$from]=$NOW ;;
    POS)   # name cls lvl map x y hp max dead sym col ally ax ay|mount
      [[ $b =~ ^[0-9]$ && $d =~ ^(W|D[0-9]+|H[0-9]{1,8})$ ]] && (( b < NCLS )) && num "$c" && num "$e" && num "$f" && num "$g" && num "$h" || return
      [[ -z ${OP_NAME[$from]} ]] && logm "$nm is here." "$K_SYS"
      valid_sym "$j" || j=@
      if isnum "$k" && (( k < ${#P_COLC[@]} )); then :; else name_color "$nm"; k=$NCI; fi
      OP_NAME[$from]=$nm OP_CLS[$from]=$b OP_LVL[$from]=$c OP_MAP[$from]=$d OP_X[$from]=$e OP_Y[$from]=$f
      OP_HP[$from]=$g OP_MAX[$from]=$h OP_DEAD[$from]=${i:0:1} OP_SEEN[$from]=$NOW OP_SYM[$from]=$j OP_COL[$from]=$k
      if [[ $l =~ ^(0|[1-9][0-9]?)$ ]] && (( l < NALY )) && num "$q" && num "${r%%|*}"; then OP_ALY[$from]=$l OP_AX[$from]=$q OP_AY[$from]=${r%%|*}
      else unset "OP_ALY[$from]"; fi
      x=""; [[ $r == *"|"* ]] && { x=${r#*|}; x=${x%%|*}; }
      if [[ $x =~ ^[0-9]$ ]] && (( x < NMNT )); then OP_MNT[$from]=$x; else unset "OP_MNT[$from]"; fi
      player_glyph "$from" "$j" "$k" "${i:0:1}"
      [[ $d == "$CUR_MAP" ]] && MAP_DIRTY=1 ;;
    BYE)   [[ -n ${OP_NAME[$from]} ]] && logm "$nm has left the world." "$K_SYS"; op_del "$from" ;;
    CHAT)  clean_text "$b"; [[ -n $CLEAN ]] || return
           chatm "$nm: $CLEAN" "$K_CHAT"; OP_SAY[$from]=$CLEAN OP_SAYT[$from]=$(( NOW + 5000 )) MAP_DIRTY=1
           [[ ${CLEAN,,} == *"${MY_NAME,,}"* ]] && printf '\a' ;;
    PCHAT) in_party "$from" || return; clean_text "$b"; chatm "[party] $nm: $CLEAN" "$K_PARTY" ;;
    WHISP) [[ ${b,,} == "${MY_NAME,,}" ]] || return; clean_text "$c"; chatm "[$nm whispers] $CLEAN" "$K_WHISP"; printf '\a' ;;
    EMOTE) clean_text "$b"; chatm "* $nm $CLEAN" "$K_WHISP" ;;
    EVT)   clean_text "$b"; logm "* $nm $CLEAN" "$K_SYS" ;;
    HEAL)  [[ $b == "$MY_ID" ]] && num "$c" && (( ! DEAD )) || return
           (( c > 2000 )) && c=2000
           heal_self "$c"; logm "$nm heals you for $c." "$K_GOOD" ;;
    BUFF)  [[ $b == "$MY_ID" ]] && num "$c" || return
           (( c > 16000 )) && c=16000
           if [[ $d == anthem ]]; then anthem_until=$(( NOW + c )); logm "$nm's anthem quickens your step! (faster, +20% damage)" "$K_GOOD"
           else buff_until=$(( NOW + c )); logm "$nm's battle cry fills you with fury! (+40% damage)" "$K_GOOD"; fi ;;
    GIVE)  [[ ${b,,} == "${MY_NAME,,}" ]] || return
           if [[ $c == G ]] && num "$d" && (( d <= 10000000 )); then GOLD=$(( GOLD + d )); logm "$nm gives you $d gold." "$K_LOOT"
           elif [[ $c == I ]] && valid_item "$d"; then logm "$nm hands you something." "$K_LOOT"; add_item "$d"; fi ;;
    FX)    [[ $a == "$CUR_MAP" ]] && add_fx "$b" "$c" ;;
    TREQ|TACC|TOFF|TOK|TCAN) trade_msg "$typ" "$from" "$nm" "$b" "$c" "$d" "$e" "$f" ;;
    RASK|RHAS|RREQ|ROOM|RNO|RSIGN) room_msg "$typ" "$from" "$nm" "$b" "$c" "$d" "$e" ;;     # v5.0: visiting rooms
  esac
}

# ---------------------------------------------------------------------------
#  Module 04b - world life (since v1.3): day & night, light, weather, world
#  bosses, professions (fishing, mining, herbalism), crafting and trading
# ---------------------------------------------------------------------------
CLK_OFF="" GM=480 DAYPH="" CW="" CW_I=-1 NR=0 WR=0 LITMODE=0 LITR="" PZ=0 ASH_HINT=0
WTH_K=() WTH_E=() LGX=() LGY=() LGR=() SRX1=() SRY1=() SRX2=() SRY2=() LIT=() SRCX=() SRCY=() SRCR=()
WB_CID="" WB_CT=0 WB_CX=0 WB_CY=0
PROF_LV=(1 1 1) PROF_XP=(0 0 0) MATS=()
MEAL1=0 MEAL2=0 TON_FROST=0 TON_FIRE=0 TON_VEIL=0
fed_until=0 fed_lvl=0 frost_until=0 fireward_until=0 veil_until=0 ash_next=0
GATH_MID="" GATH_END=0 GATH_T0=0 CRAFT=""
FISH_ST=0 FISH_BITE=0 FISH_T0=0 FISH_END=0 FISH_MAT=0 FISH_REQ=1 FISH_ZS=0 FISH_ZW=3 FISH_P=1500 FISH_POOL="" FISH_W=27 FPOS=0
TR_WITH="" TR_OUT="" TR_OUT_T=0 TR_PG=0 TR_MYI=() TR_MYG=0 TR_THI=() TR_THG=0 TR_MYSEQ=0 TR_THSEQ=0 TR_MYOK=0 TR_THOK=0
TR_INPUT="" TR_BUF=""
declare -A TR_IN=() TR_MYM=() TR_THM=() SPANC=() WEA_IDX=()
for i in "${!WEA_REG[@]}"; do WEA_IDX[${WEA_REG[i]//_/ }]=$i; done
mats_zero() { local i; MATS=(); for (( i = 0; i < NMAT; i++ )); do MATS[i]=0; done; }
mats_zero

FXG[warn]=$'\e[0;1;5;38;5;196;48;5;52m!' FXG[bolt]=$'\e[0;1;38;5;229;48;5;61m|'
declare -A FXD=([warn]=1500 [bolt]=380) FXP=([warn]=7)
GLY[fwarn]=${FXG[warn]} GLY[fbolt]=${FXG[bolt]}
GLY[zrain]=$'\e[0;38;5;75m'"'" GLY[zstorm]=$'\e[0;38;5;111m/' GLY[zsnow]=$'\e[0;1;38;5;231m*'
GLY[zsand]=$'\e[0;38;5;180m~' GLY[zash]=$'\e[0;38;5;209m.'
PSX=() PSY=()
for (( i = 0; i < 48; i++ )); do PSX[i]=$(( RANDOM % 997 )) PSY[i]=$(( RANDOM % 991 )); done

# --- clock & light ----------------------------------------------------------------
clock_now() {  # -> GM (game minute 0..1439), NR (night sight radius, 0 = daylight)
  local ph
  if [[ -z $CLK_OFF ]]; then GM=480; else GM=$(( ((NOW + CLK_OFF) % DAYLEN + DAYLEN) % DAYLEN / GMIN )); fi
  if (( GM >= 420 && GM < 1140 )); then NR=0 ph=day
  elif (( GM >= 1140 && GM < 1260 )); then NR=$(( 22 - (GM - 1140) * 16 / 120 )) ph=dusk
  elif (( GM >= 300 && GM < 420 )); then NR=$(( 6 + (GM - 300) * 16 / 120 )) ph=dawn
  else NR=6 ph=night; fi
  [[ $ph == "$DAYPH" ]] && return
  if [[ -n $DAYPH ]]; then
    case $ph in
      dusk)  logm "The sun sets. Torches are lit in the towns." "$K_SYS" ;;
      night) logm "Night falls. The dead grow restless - undead hit harder, but give more XP." "$K_HURT" ;;
      dawn)  logm "Dawn breaks over the land." "$K_GOOD" ;;
    esac
  fi
  DAYPH=$ph
}

clock_txt() {  # -> CLKT "☀ 14:20"
  local ic="☀"
  (( NR > 0 )) && ic="☾"
  if (( TW2 )); then ic="🌞"; (( NR > 0 )) && ic="🌙"; fi
  printf -v CLKT '%s %02d:%02d' "$ic" $(( GM / 60 )) $(( GM % 60 ))
}

weather_now() {  # -> CW (weather where I stand), WR (sight radius it leaves me, 0 = clear)
  CW="" WR=0 CW_I=-1
  [[ $CUR_MAP == W ]] || return
  RNAME=""; region_of "$PX" "$PY" nosafe
  local i=${WEA_IDX[$RNAME]}
  [[ -n $i ]] && (( ${WTH_E[i]:-0} > NOW )) || return
  CW=${WTH_K[i]} CW_I=$i
  case $CW in fog) WR=8 ;; sand) WR=4 ;; snow) WR=9 ;; esac
  (( WR && NOW < veil_until )) && WR=$(( WR * 2 ))
}

init_lights() {  # campfires and waystones glow at night -> LGX LGY LGR; lit streets -> SRX1 SRY1 SRX2 SRY2
  local y x row a s
  LGX=() LGY=() LGR=()
  for (( y = 0; y < MAPH[W]; y++ )); do
    row=${MAPROW[W:$y]}
    [[ $row == *[FZ]* ]] || continue
    for (( x = 0; x < ${#row}; x++ )); do
      case ${row:x:1} in F) LGX+=("$x") LGY+=("$y") LGR+=(5) ;; Z) LGX+=("$x") LGY+=("$y") LGR+=(2) ;; esac
    done
  done
  SRX1=() SRY1=() SRX2=() SRY2=()
  for s in "${SAFE_RECTS[@]}"; do a=($s); SRX1+=("${a[0]}") SRY1+=("${a[1]}") SRX2+=("${a[2]}") SRY2+=("${a[3]}"); done
}

span() {  # r dy -> SP: half width of a light ellipse (ASCII cells are twice as high as wide), -1 outside
  local k="$1:$2"
  SP=${SPANC[$k]}
  [[ -n $SP ]] && return
  if (( $2 * $2 > $1 * $1 )); then SP=-1
  elif (( TW == 2 )); then isqrt $(( $1 * $1 + $1 - $2 * $2 )); SP=$R
  else isqrt $(( 4 * ($1 * $1 + $1 - $2 * $2) )); SP=$R; fi
  SPANC[$k]=$SP
}

build_lit() {  # cx0 cy0 -> LIT[ry]: lit spans "a:b ..." of every view row (sorted, merged)
  local cx0=$1 cy0=$2 n=0 i j p s a x y ry dy lst t o lo hi cl ch wl=0 wh=-1 nr=$NR
  LIT=() SRCX=() SRCY=() SRCR=()
  if (( NR > 0 )); then
    (( NOW < veil_until )) && nr=$(( NR * 3 / 2 ))
    nr=$(( nr + ${B_LIGHT:-0} ))                  # lanterns
    SRCX[0]=$(( PX - cx0 )) SRCY[0]=$(( PY - cy0 )) SRCR[0]=$nr; n=1
    for p in "${!OP_MAP[@]}"; do                  # everybody carries a torch
      [[ ${OP_MAP[$p]} == W ]] || continue
      x=$(( ${OP_X[$p]} - cx0 )) y=$(( ${OP_Y[$p]} - cy0 ))
      (( x > -12 && x < VW + 12 && y > -6 && y < VH + 6 )) && { SRCX[n]=$x SRCY[n]=$y SRCR[n]=5; n=$(( n + 1 )); }
    done
    for (( i = 0; i < ${#LGX[@]}; i++ )); do
      x=$(( LGX[i] - cx0 )) y=$(( LGY[i] - cy0 ))
      (( x > -12 && x < VW + 12 && y > -6 && y < VH + 6 )) && { SRCX[n]=$x SRCY[n]=$y SRCR[n]=${LGR[i]}; n=$(( n + 1 )); }
    done
  fi
  for (( ry = 0; ry < VH; ry++ )); do
    lst=()
    if (( NR > 0 )); then
      for (( i = 0; i < n; i++ )); do
        dy=$(( ry - SRCY[i] )); (( dy <= SRCR[i] && -dy <= SRCR[i] )) || continue
        span "${SRCR[i]}" "$dy"; (( SP >= 0 )) && lst+=("$(( SRCX[i] - SP )) $(( SRCX[i] + SP ))")
      done
      y=$(( cy0 + ry ))
      for (( j = 0; j < ${#SRX1[@]}; j++ )); do    # streets are lit
        (( y >= SRY1[j] && y <= SRY2[j] && SRX2[j] >= cx0 && SRX1[j] < cx0 + VW )) && lst+=("$(( SRX1[j] - cx0 )) $(( SRX2[j] - cx0 ))")
      done
    else
      lst=("0 $(( VW - 1 ))")
    fi
    if (( WR > 0 )); then                         # storms only let you see close around you
      dy=$(( ry - PY + cy0 )); wl=0 wh=-1
      if (( dy <= WR && -dy <= WR )); then span "$WR" "$dy"; wl=$(( PX - cx0 - SP )) wh=$(( PX - cx0 + SP )); fi
    fi
    for (( i = 1; i < ${#lst[@]}; i++ )); do       # sort by start
      t=${lst[i]}; j=$(( i - 1 ))
      while (( j >= 0 && ${lst[j]% *} > ${t% *} )); do lst[j+1]=${lst[j]}; j=$(( j - 1 )); done
      lst[j+1]=$t
    done
    o="" cl=0 ch=0 p=0
    for t in "${lst[@]}" "99999 99999"; do
      lo=${t% *} hi=${t#* }
      if (( p && lo <= ch + 1 )); then (( hi > ch )) && ch=$hi; continue; fi
      if (( p )); then
        (( cl < 0 )) && cl=0; (( ch > VW - 1 )) && ch=$(( VW - 1 ))
        if (( WR > 0 )); then (( cl < wl )) && cl=$wl; (( ch > wh )) && ch=$wh; fi
        (( cl <= ch )) && o+="$cl:$ch "
      fi
      cl=$lo ch=$hi p=1
    done
    LIT[ry]=$o
  done
  if (( NR > 0 )); then Z_DARK=$'\e[0;38;5;60m' Z_DARKBG=$'\e[0;48;5;233m'
  else case $CW in
    sand) Z_DARK=$'\e[0;38;5;94m' Z_DARKBG=$'\e[0;48;5;58m' ;;
    snow) Z_DARK=$'\e[0;38;5;250m' Z_DARKBG=$'\e[0;48;5;245m' ;;
    *)    Z_DARK=$'\e[0;38;5;243m' Z_DARKBG=$'\e[0;48;5;238m' ;;
  esac; fi
  (( TW == 2 )) && Z_DARK="${Z_DARK%m}${Z_DARKBG#$'\e[0'}"
}

is_lit() {  # x (screen) -> 0 if inside a lit span of the current row
  local iv
  for iv in $LITR; do (( $1 >= ${iv%:*} && $1 <= ${iv#*:} )) && return 0; done
  return 1
}


add_particles() {  # weather drifting over the view (behind everything else)
  local i n=0 x y k
  case $CW in
    rain) n=30 k=zrain ;; storm) n=44 k=zstorm ;; snow) n=34 k=zsnow ;; sand) n=42 k=zsand ;; ash) n=26 k=zash ;; *) return ;;
  esac
  (( TW2 )) && n=$(( n / 3 ))                    # emoji particles are big - fewer of them
  for (( i = 0; i < n; i++ )); do
    case $CW in
      rain)  x=$(( (PSX[i] + NOW / 500) % VW )) y=$(( (PSY[i] + NOW / 55) % VH )) ;;
      storm) x=$(( (PSX[i] + NOW / 70) % VW )) y=$(( (PSY[i] + NOW / 45) % VH )) ;;
      snow)  x=$(( (PSX[i] + NOW / 900 + (NOW / 400 + i) % 3) % VW )) y=$(( (PSY[i] + NOW / 260) % VH )) ;;
      sand)  x=$(( (PSX[i] + NOW / 30) % VW )) y=$(( (PSY[i] + NOW / 600) % VH )) ;;
      ash)   x=$(( (PSX[i] - NOW / 700 % VW + VW) % VW )) y=$(( (PSY[i] + NOW / 380) % VH )) ;;
    esac
    RI[y]+="$(( x * 10 + 8 )):1:$k "
  done
}

weather_hazard() {  # every second: ash burns, lightning flashes
  [[ -n $CW ]] && (( ! DEAD )) || return
  case $CW in
    ash)
      in_safe_xy "$PX" "$PY" && return
      (( NOW >= fireward_until && NOW >= ash_next )) || return
      ash_next=$(( NOW + 2000 ))
      (( ASH_HINT )) || { ASH_HINT=1; logm "The burning ash sears your skin! A Fire Ward Tonic protects you (alchemists, Ser Kael, Nadia)." "$K_HURT"; }
      take_damage $(( MAXHP * 4 / 100 + 3 )) "Burning ash" ;;
    storm)
      (( RANDOM % 4 == 0 )) || return
      local x=$(( PX + RANDOM % 41 - 20 )) y=$(( PY - 3 - RANDOM % 5 )) c="" i
      for (( i = 0; i < 4; i++ )); do c+="$(( x + (RANDOM % 3) - 1 )),$(( y + i )) "; done
      add_fx bolt "$c" ;;
  esac
}

# --- professions ------------------------------------------------------------------
prof_next() { PN=$(( 6 * $1 + 10 )); }

prof_gain() {  # kind xp
  local k=$1
  (( PROF_LV[k] >= PROF_MAX )) && return
  PROF_XP[k]=$(( PROF_XP[k] + $2 ))
  prof_next "${PROF_LV[k]}"
  while (( PROF_XP[k] >= PN && PROF_LV[k] < PROF_MAX )); do
    PROF_XP[k]=$(( PROF_XP[k] - PN )); PROF_LV[k]=$(( PROF_LV[k] + 1 ))
    logm "Your ${PROF_NAME[k]} skill rises to ${PROF_LV[k]}!" "$K_ANN"
    prof_next "${PROF_LV[k]}"
  done
  (( PROF_LV[k] >= PROF_MAX )) && PROF_XP[k]=0
}

node_prof() { if (( $1 < NODE0 + 6 )); then NPK=1; else NPK=2; fi; }   # type -> NPK (1 mining, 2 herbalism)

gather_start() {  # mid
  local m=$1 t=${CM_T[$1]}
  [[ $GATH_MID == "$m" ]] && return
  node_prof "$t"
  if (( PROF_LV[NPK] < M_LVL[t] )); then
    logm "You need ${PROF_NAME[NPK]} ${M_LVL[t]} for ${M_NAME[t]} (you have ${PROF_LV[NPK]})." "$K_HURT"
    next_move=$(( NOW + 400 )); return
  fi
  fish_stop quiet
  GATH_MID=$m GATH_T0=$NOW GATH_END=$(( NOW + 1700 - PROF_LV[NPK] * 25 ))
  MAP_DIRTY=1
}

gather_tick() {
  local m=$GATH_MID t mat n=1 xp
  [[ -n $m ]] || return
  t=${CM_T[$m]}
  if [[ -z $t ]]; then GATH_MID=""; logm "Someone else got there first."; return; fi
  cheb $(( CM_X[m] - PX )) $(( CM_Y[m] - PY )); (( D <= 1 )) || { GATH_MID=""; return; }
  MAP_DIRTY=1
  (( NOW >= GATH_END )) || return
  GATH_MID=""
  node_prof "$t"; mat=${NODE_MAT[$t]:-$(( t - NODE0 ))}
  (( PROF_LV[NPK] >= M_LVL[t] + 6 && RANDOM % 3 == 0 )) && n=2
  MATS[mat]=$(( MATS[mat] + n )); MAT_NEW[mat]=$(( ${MAT_NEW[mat]:-0} + n ))
  xp=${M_XP[t]}; (( PROF_LV[NPK] >= M_LVL[t] + 10 )) && xp=$(( xp / 4 + 1 ))
  send HIT "$MY_ID" "$CUR_MAP" "$m" 1 0
  mat_icon "$mat"
  logm "+$n $MI${MI:+ }${MAT_NAME[mat]}   (${PROF_NAME[NPK]} ${PROF_LV[NPK]}, ${MATS[mat]} in your bag)" "$K_LOOT"
  prof_gain "$NPK" "$xp"; dly_ev gath; col_find 4
}

fish_stop() { (( FISH_ST )) || return; FISH_ST=0 MAP_DIRTY=1; [[ $1 == quiet ]] || logm "You reel in your line."; }

gather_key() {  # [g]: gather the node next to me, or fish
  local d x y
  (( DEAD )) && return
  for d in "$FDX,$FDY" "0,1" "0,-1" "1,0" "-1,0"; do
    x=$(( PX + ${d%,*} )) y=$(( PY + ${d#*,} ))
    if mon_at "$x" "$y" && (( M_KIND[${CM_T[$MID]}] == 3 )); then gather_start "$MID"; return; fi
  done
  fish_start
}

fish_start() {
  local x y d e f req rar cond pool="" minr=99 kind wt=""
  [[ $CUR_MAP == W ]] || { logm "There is nothing to fish down here."; return; }
  for d in "$FDX,$FDY" "0,1" "0,-1" "1,0" "-1,0" "0,0"; do
    x=$(( PX + ${d%,*} )) y=$(( PY + ${d#*,} ))
    tile W "$x" "$y"; [[ $T == [~LI] ]] && { wt=$T; break; }
  done
  if [[ -z $wt ]]; then logm "Stand next to water (~) to fish - or walk into an ore vein ◆ or herb ♣ to gather it."; return; fi
  if [[ $wt == L ]]; then kind=lava; elif [[ $wt == I ]]; then kind=ice
  else RNAME=""; region_of "$x" "$y" nosafe; kind=${WATER_OF[${RNAME// /_}]:-fresh}; fi
  for e in ${FISHW[$kind]}; do
    IFS=: read -r f req rar cond <<< "$e"
    (( req < minr )) && minr=$req
    (( PROF_LV[0] >= req )) || continue
    [[ $cond == night ]] && (( NR == 0 )) && continue
    pool+="$f:$rar:$req "
  done
  [[ -n $pool ]] || { logm "The fish here are too wily for you - you need Fishing $minr." "$K_HURT"; return; }
  GATH_MID=""
  FISH_POOL=$pool FISH_ST=1 FISH_BITE=$(( NOW + 1800 + RANDOM % 4000 ))
  [[ $CW == @(rain|storm) ]] && FISH_BITE=$(( NOW + 900 + RANDOM % 2200 ))
  [[ $kind == lava ]] && logm "You cast a fireproof line into the lava..." || logm "You cast your line... strike with [space] when it bites."
  MAP_DIRTY=1
}

fish_tick() {
  (( FISH_ST )) || return
  MAP_DIRTY=1
  if (( FISH_ST == 1 && NOW >= FISH_BITE )); then
    local e w tot=0 r rar mul=1 pick=""
    [[ $CW == @(rain|storm) ]] && mul=3
    for e in $FISH_POOL; do rar=${e#*:}; rar=${rar%:*}; w=$(( rar == 0 ? 70 : (rar == 1 ? 25 : 7 * mul) )); tot=$(( tot + w )); done
    r=$(( RANDOM % tot ))
    for e in $FISH_POOL; do
      rar=${e#*:}; rar=${rar%:*}; w=$(( rar == 0 ? 70 : (rar == 1 ? 25 : 7 * mul) ))
      (( r < w )) && { pick=$e; break; }; r=$(( r - w ))
    done
    [[ -n $pick ]] || pick=${FISH_POOL%% *}
    FISH_MAT=${pick%%:*} FISH_REQ=${pick##*:} rar=${MAT_RARE[${pick%%:*}]}
    FISH_ZW=$(( 4 + PROF_LV[0] / 6 - rar )); (( FISH_ZW < 2 )) && FISH_ZW=2
    FISH_ZS=$(( RANDOM % (FISH_W - FISH_ZW) ))
    FISH_P=$(( 1500 - rar * 250 ))
    FISH_ST=2 FISH_T0=$NOW FISH_END=$(( NOW + 4500 ))
    printf '\a'
  elif (( FISH_ST == 2 && NOW >= FISH_END )); then
    FISH_ST=0; logm "The fish got away..." "$K_HURT"
  fi
}

fish_pos() {
  local p=$(( (NOW - FISH_T0) % (2 * FISH_P) ))
  if (( p < FISH_P )); then FPOS=$(( p * (FISH_W - 1) / FISH_P )); else FPOS=$(( (2 * FISH_P - p) * (FISH_W - 1) / FISH_P )); fi
}

fish_strike() {
  if (( FISH_ST == 1 )); then FISH_ST=0; logm "Too early - you yanked the hook out of the water." "$K_HURT"; return; fi
  fish_pos
  local f=$FISH_MAT rar=${MAT_RARE[$FISH_MAT]}
  FISH_ST=0 MAP_DIRTY=1
  if (( FPOS >= FISH_ZS && FPOS < FISH_ZS + FISH_ZW )); then
    MATS[f]=$(( MATS[f] + 1 )); MAT_NEW[f]=$(( ${MAT_NEW[f]:-0} + 1 )); mat_icon "$f"
    if (( rar == 2 )); then logm "You caught a $MI${MI:+ }${MAT_NAME[f]}! A rare catch!" "$K_ANN"; else logm "You caught a $MI${MI:+ }${MAT_NAME[f]}." "$K_LOOT"; fi
    prof_gain 0 $(( (rar == 0 ? 8 : (rar == 1 ? 13 : 26)) + FISH_REQ )); dly_ev fish; col_find 3
  else
    logm "Missed! The ${MAT_NAME[f]} slips off the hook." "$K_HURT"
  fi
}

draw_overlay() {  # fishing / gathering box at the bottom of the map
  local msg plain bar i c r=$(( VH + 1 )) t tot
  if [[ -n $GATH_MID && -n ${CM_T[$GATH_MID]} ]]; then
    t=${CM_T[$GATH_MID]}; node_prof "$t"; tot=$(( GATH_END - GATH_T0 ))
    pbar $(( NOW - GATH_T0 )) "$tot" 16 $'\e[38;5;220m'
    plain=" ${PROF_NAME[NPK]}: ${M_NAME[t]}  "
    out+=$'\e['"$r;$(( 2 + (MW - ${#plain} - 17) / 2 ))H"$'\e[0;1;38;5;231;48;5;236m'"$plain$PB"$'\e[48;5;236m '"$N"
  fi
  (( FISH_ST )) || return
  if (( FISH_ST == 1 )); then
    plain="  ~  your float bobs on the water...  ~  "
    out+=$'\e['"$r;$(( 2 + (MW - ${#plain}) / 2 ))H"$'\e[0;38;5;153;48;5;24m'"$plain$N"
    return
  fi
  fish_pos; bar=""
  for (( i = 0; i < FISH_W; i++ )); do
    if (( i >= FISH_ZS && i < FISH_ZS + FISH_ZW )); then c=$'\e[48;5;34m'; else c=$'\e[48;5;24m'; fi
    if (( i == FPOS )); then bar+="$c"$'\e[1;38;5;231m▲'; else bar+="$c "; fi
  done
  plain=" BITE! [space] when ▲ is in the green "
  out+=$'\e['"$(( r - 1 ));$(( 2 + (MW - ${#plain}) / 2 ))H"$'\e[0;1;5;38;5;16;48;5;226m'"$plain$N"
  out+=$'\e['"$r;$(( 2 + (MW - FISH_W - 2) / 2 ))H"$'\e[0;38;5;231;48;5;236m['"$bar"$'\e[0;38;5;231;48;5;236m]'"$N"
}

# --- crafting -----------------------------------------------------------------------
craft_build() {  # CRAFT (forge|alch|cook) -> RC_ID RC_LAB RC_NEED RC_GOLD
  local o t f
  RC_ID=() RC_LAB=() RC_NEED=() RC_GOLD=()
  rc() { RC_ID+=("$1"); RC_LAB+=("$2"); RC_NEED+=("$3"); RC_GOLD+=("${4:-0}"); }
  case $CRAFT in
    forge)
      forge_kinds
      for (( o = 0; o < 6; o++ )); do
        t=$(( o + 2 ))
        item_name "W.$FWK.$t.0" "$CLS"; item_icon "W.$FWK.$t.0" "$CLS"; rc "W.$FWK.$t" "${II:0:2}${II:+ }$INAME" "$o:6" $(( 15 * t * t ))
        item_name "A.$FAK.$t.0" "$CLS"; item_icon "A.$FAK.$t.0" "$CLS"; rc "A.$FAK.$t" "${II:0:2}${II:+ }$INAME" "$o:6" $(( 15 * t * t ))
      done
      local fr                                              # v4.5: titanite and starmetal, tiers 8-12
      for fr in "${FORGE_X[@]}" "8:$M45:4 5:4" "9:$M45:6" "10:$M45:8 5:6" "11:$(( M45 + 1 )):6 $M45:4" "12:$(( M45 + 1 )):10 $M45:6"; do
        t=${fr%%:*}
        item_name "W.$FWK.$t.0" "$CLS"; item_icon "W.$FWK.$t.0" "$CLS"; rc "W.$FWK.$t" "${II:0:2}${II:+ }$INAME" "${fr#*:}" $(( 15 * t * t ))
        item_name "A.$FAK.$t.0" "$CLS"; item_icon "A.$FAK.$t.0" "$CLS"; rc "A.$FAK.$t" "${II:0:2}${II:+ }$INAME" "${fr#*:}" $(( 15 * t * t ))
      done ;;
    alch)
      local e I_hp2 I_mp2 I_gh I_gm I_str I_iron I_swift I_tfrost I_tfire I_tveil       # consumable icons
      for e in hp2 mp2 gh gm str iron swift tfrost tfire tveil; do ci "$e"; printf -v "I_$e" '%s' "$CI"; done
      rc hp2 "${I_hp2}2x Health potion" "6:2"; rc mp2 "${I_mp2}2x Mana potion" "7:2"
      rc gh "${I_gh}Greater health potion" "8:2 6:1"; rc gm "${I_gm}Greater mana potion" "8:2 7:1"
      rc str "${I_str}Elixir of Strength" "9:3"; rc iron "${I_iron}Elixir of Iron Skin" "10:2 8:1"
      rc swift "${I_swift}Elixir of Swiftness" "11:1 7:1 6:1"
      rc tfrost "${I_tfrost}Frost Tonic (no blizzard slow)" "10:2"
      rc tfire "${I_tfire}Fire Ward Tonic (ash immunity)" "11:2"
      rc tveil "${I_tveil}Sand Veil (see far in storms/night)" "9:2 7:1"
      rc gh3 "${I_gh}3x Greater health potion" "$(( M45 + 2 )):2"; rc gm3 "${I_gm}3x Greater mana potion" "$(( M45 + 2 )):1 $(( M45 + 3 )):1"
      rc grand "${I_str}Grand Elixir (Strength + Iron Skin + Swiftness)" "$(( M45 + 3 )):3 $(( M45 + 2 )):1"
      local x xi xl xn                                      # v6.0: cobalt-era herbs
      for x in "${ALCH_X[@]}"; do IFS=: read -r xi xl xn <<< "$x"; ci "$xi"; rc "$xi" "$CI$xl" "$xn"; done ;;
    cook)
      for f in ${MAT_GRP[0]}; do                            # (only fish - v4.5 fix: gems were "cookable")
        if (( MAT_RARE[f] == 2 )); then ci meal2; rc "c$f" "${MAT_NAME[f]} -> $CI${CI:+ }Fisherman's Feast" "$f:1"
        else ci meal1; rc "c$f" "${MAT_NAME[f]} -> $CI${CI:+ }Grilled Fish" "$f:1"; fi
      done ;;
  esac
}

craft_can() {  # index -> 0 if I have everything; NEEDC (colored) NEEDP (plain)
  local i=$1 e mat cnt ok=0 col
  NEEDC="" NEEDP=""
  for e in ${RC_NEED[i]}; do
    mat=${e%:*} cnt=${e#*:}
    if (( MATS[mat] >= cnt )); then col=$K_GOOD; else col=$K_HURT; ok=1; fi
    local mg=""; (( TW2 )) && mg=${MAT_I[mat]}
    NEEDC+="$col$cnt $mg$col${MAT_NAME[mat]} (${MATS[mat]})$N " NEEDP+="$cnt $mg${MAT_NAME[mat]} (${MATS[mat]}) "
  done
  if (( RC_GOLD[i] > 0 )); then
    if (( GOLD >= RC_GOLD[i] )); then col=$K_LOOT; else col=$K_HURT; ok=1; fi
    NEEDC+="$col${RC_GOLD[i]}g$N" NEEDP+="${RC_GOLD[i]}g"
  fi
  return $ok
}

craft_do() {  # index
  local i=$1 id e r k t
  (( i >= 0 && i < ${#RC_ID[@]} )) || return
  craft_can "$i" || { logm "You are missing something for ${RC_LAB[i]%% (*}." "$K_HURT"; return; }
  id=${RC_ID[i]}
  if [[ $id == [WAOHJ].* ]] && (( ${#INV[@]} >= BAGS )); then logm "Your bags are full - make room first." "$K_HURT"; return; fi
  for e in ${RC_NEED[i]}; do MATS[${e%:*}]=$(( MATS[${e%:*}] - ${e#*:} )); done
  GOLD=$(( GOLD - RC_GOLD[i] ))
  case $id in
    [WAOHJ].*)
      r=$(( RANDOM % 100 )); if (( r < 60 )); then r=1; elif (( r < 92 )); then r=2; else r=3; fi
      INV+=("$id.$r"); NEWG[$id.$r]=1; item_name "$id.$r" "$CLS"
      logm "The anvil rings - you forged a $INAME! (+$IVAL)  Equip it with [i]." $'\e['"${ICOL}m" ;;
    hp2) POT_H=$(( POT_H + 2 )) ;; mp2) POT_M=$(( POT_M + 2 )) ;; gh) POT_GH=$(( POT_GH + 1 )) ;; gm) POT_GM=$(( POT_GM + 1 )) ;;
    str) EL_STR=$(( EL_STR + 1 )) ;; iron) EL_IRON=$(( EL_IRON + 1 )) ;; swift) EL_SWIFT=$(( EL_SWIFT + 1 )) ;;
    tfrost) TON_FROST=$(( TON_FROST + 1 )) ;; tfire) TON_FIRE=$(( TON_FIRE + 1 )) ;; tveil) TON_VEIL=$(( TON_VEIL + 1 )) ;;
    gh3) POT_GH=$(( POT_GH + 3 )) ;; gm3) POT_GM=$(( POT_GM + 3 )) ;;
    grand) EL_STR=$(( EL_STR + 1 )) EL_IRON=$(( EL_IRON + 1 )) EL_SWIFT=$(( EL_SWIFT + 1 )) ;;
    c*) if (( MAT_RARE[${id#c}] == 2 )); then MEAL2=$(( MEAL2 + 1 )); else MEAL1=$(( MEAL1 + 1 )); fi ;;
  esac
  [[ $id == [WAOHJ].* ]] || logm "Made: ${RC_LAB[i]%% (*}" "$K_LOOT"
}

forge_kinds() {  # FWK / FAK: weapon and armor kind the forge makes (only what my class can use)
  [[ -n $FWK && ${WK_CLS[FWK]} == *"$CLS"* ]] || FWK=${DEFW[CLS]}
  [[ -n $FAK && ${AK_CLS[FAK]} == *"$CLS"* ]] || FAK=${DEFA[CLS]}
}

forge_cycle() {  # W|A: next kind my class may use
  local n i k
  forge_kinds
  if [[ $1 == W ]]; then n=${#WK_NAME[@]} k=$FWK; else n=${#AK_NAME[@]} k=$FAK; fi
  for (( i = 1; i <= n; i++ )); do
    k=$(( (k + 1) % n ))
    if [[ $1 == W ]]; then [[ ${WK_CLS[k]} == *"$CLS"* ]] && { FWK=$k; return; }
    else [[ ${AK_CLS[k]} == *"$CLS"* ]] && { FAK=$k; return; }; fi
  done
}

craft_key() {
  local keys=abcdefghijkl i n=0 f
  if [[ $CRAFT == forge ]]; then
    case $1 in x|X) forge_cycle W; return ;; y|Y) forge_cycle A; return ;; esac
  fi
  craft_build
  if [[ $1 == z && $CRAFT == cook ]]; then
    for (( f = 12; f < NMAT; f++ )); do
      while (( MATS[f] > 0 )); do
        MATS[f]=$(( MATS[f] - 1 )) n=$(( n + 1 ))
        if (( MAT_RARE[f] == 2 )); then MEAL2=$(( MEAL2 + 1 )); else MEAL1=$(( MEAL1 + 1 )); fi
      done
    done
    if (( n )); then logm "You cook $n fish. Food: $MEAL1 Grilled Fish, $MEAL2 Fisherman's Feast - eat with [u]." "$K_LOOT"
    else logm "You have no fish. Press [g] next to water to fish."; fi
    return
  fi
  [[ $1 == [a-l] ]] || return
  i=${keys%%"$1"*}; craft_do "${#i}"
}

ui_craft() {
  local i keys=abcdefghijkl title t lw
  craft_build
  case $CRAFT in
    forge) title="FORGE - turn 6 ore into Rare, Epic or Legendary gear" ;;
    alch)  title="ALCHEMY - brew potions and tonics from herbs" ;;
    cook)  title="CAMPFIRE - cook your fish" ;;
  esac
  ui "  $title" "$K_LOOT$B"
  ui "  You have ${EMJ[gold]}$GOLD gold." "$K_SYS"
  ui ""
  local mxn=0
  for i in "${!RC_ID[@]}"; do craft_can "$i"; dispw "$NEEDP"; (( DW > mxn )) && mxn=$DW; done
  for i in "${!RC_ID[@]}"; do
    craft_can "$i"
    if [[ $CRAFT == cook ]]; then
      (( MATS[${RC_ID[i]#c}] > 0 )) || continue
      uix "  [${keys:i:1}] ${RC_LAB[i]}   ${K_SYS}x${MATS[${RC_ID[i]#c}]}$N" "  [x] ${RC_LAB[i]}   x${MATS[${RC_ID[i]#c}]}"
    else
      lw=$(( VW - 8 - mxn )); (( lw > 38 )) && lw=38; (( lw < 16 )) && lw=16
      t=${RC_LAB[i]}; dispw "$t"; while (( DW > lw )); do t=${t:0:${#t}-1}; dispw "$t"; done
      padr "$t" "$lw"; t=$PADS
      uix "  [${keys:i:1}] $t $NEEDC" "  [x] $t $NEEDP"
    fi
  done
  ui ""
  case $CRAFT in
    cook)  ui "  Grilled Fish: heals 35%, Well Fed 5 min (double regeneration)." "$K_SYS"
           ui "  Fisherman's Feast: heals 70%, Well Fed+ 10 min (+10% damage)." "$K_SYS"
           ui "  [a-j] cook one   [z] cook everything   [esc] close   - eat with [u]" "$K_SYS" ;;
    forge) ui "  [x] weapon type: ${WK_NAME[FWK]}   [y] armor type: ${AK_NAME[FAK]}   (what a ${C_NAME[CLS]} can use)" "$K_LOOT"
           ui "  Ore comes from veins (◆) next to mountains - see [p] professions." "$K_SYS"
           ui "  [a-l] forge   [esc] close" "$K_SYS" ;;
    alch)  ui "  Herbs (♣) grow in the wild - see [p] professions." "$K_SYS"
           ui "  [a-j] brew   [esc] close" "$K_SYS" ;;
  esac
}

ui_prof() {
  local k i c line plain cols=3 rows w nm g t idx x
  ui "  PROFESSIONS" "$K_LOOT$B"
  for k in 0 1 2; do
    prof_next "${PROF_LV[k]}"; pbar "${PROF_XP[k]}" "$PN" 12 $'\e[38;5;220m'
    case $k in 0) t="[g] next to water ~" ;; 1) t="walk into ore veins ◆" ;; 2) t="walk into herbs ♣" ;; esac
    printf -v line '  %-10s Lv %-2d ' "${PROF_NAME[k]}" "${PROF_LV[k]}"
    if (( PROF_LV[k] >= PROF_MAX )); then uix "$line${K_GOOD}MASTER$N         ${K_SYS}$t$N" "$line MASTER         $t"
    else uix "$line$PB $(printf '%3d/%-3d' "${PROF_XP[k]}" "$PN") ${K_SYS}$t$N" "$line############ 000/000 $t"; fi
  done
  ui ""
  ui "  MATERIALS" "$B"
  local ml=(${MAT_GRP[1]} ${MAT_GRP[2]} ${MAT_GRP[0]}) nml
  nml=${#ml[@]}; rows=$(( (nml + cols - 1) / cols )); w=$(( (VW - 4) / cols ))
  for (( i = 0; i < rows; i++ )); do
    line="  " plain="  "
    for (( c = 0; c < cols; c++ )); do
      x=$(( c * rows + i )); (( x < nml )) || continue; idx=${ml[x]}
      if (( TW2 )); then g=${MAT_I[idx]}; elif mat_node "$idx"; then g="${GLYP[m$MNT_T]}$N"; else g="$FISHG$N"; fi
      printf -v nm '%-*s' $(( w - 1 - ${#PLX} )) "${MAT_NAME[idx]:0:w-7} ${MATS[idx]}"
      if (( MATS[idx] > 0 )); then line+="$g $nm"; else line+="$g ${K_SYS}$nm$N"; fi
      plain+="$PLX $nm"
    done
    uix "$line" "$plain"
  done
  ui "  Food: $MEAL1 grilled fish, $MEAL2 feasts   Tonics: $TON_FROST frost, $TON_FIRE fire ward, $TON_VEIL veil" "$K_SYS"
  ui ""
  ui "  Cook fish at campfires (*) and inns, forge ore at smiths, brew herbs at" "$K_SYS"
  ui "  alchemists. Rain makes fish bite faster and rare fish more common." "$K_SYS"
  ui "  WHERE TO FIND" "$B"
  w=$(( (VW - 4) / 2 ))
  local half=$(( (${#NODE_T[@]} + 1) / 2 ))
  for (( i = 0; i < half; i++ )); do
    line="  " plain="  "
    for c in 0 "$half"; do
      t=${NODE_T[i + c]}; [[ -n $t ]] || continue; node_prof "$t"
      printf -v nm '%-*s' $(( w - 2 - ${#PLX} )) "${M_NAME[t]} ${PROF_NAME[NPK]:0:1}${M_LVL[t]} - ${MW_NAME[t]}"
      nm="${nm:0:w-2-${#PLX}} "
      line+="${GLYP[m$t]}$N $nm" plain+="$PLX $nm"
    done
    uix "$line" "$plain"
  done
  ui "  Fish: Minnow/Trout in rivers, Silverscale in forests and Silverlake, Moonfin" "$K_SYS"
  ui "  (Silverlake, night), Mudfish (swamp), Sea Bass/Swordfish (coast), Golden" "$K_SYS"
  ui "  Koi (oasis), Ice Pike (frozen lakes), Lava Eel (lava!). From 30: Abyssal Eel" "$K_SYS"
  ui "  (sea, swamp), Storm Trout (ice), Magma Carp (lava), Starfish of Ys (sea, night)  [esc]" "$K_SYS"
}

# --- food & tonics --------------------------------------------------------------------
eat() {  # best food first
  (( DEAD )) && return
  if (( MEAL2 > 0 )); then
    MEAL2=$(( MEAL2 - 1 )); heal_self $(( MAXHP * 70 / 100 )); MP=$(( MP + MAXMP * 40 / 100 ))
    fed_until=$(( NOW + 600000 )) fed_lvl=2
    logm "A Fisherman's Feast! Well Fed: double regeneration and +10% damage for 10 min." "$K_GOOD"
  elif (( MEAL1 > 0 )); then
    MEAL1=$(( MEAL1 - 1 )); heal_self $(( MAXHP * 35 / 100 )); MP=$(( MP + MAXMP * 20 / 100 ))
    (( NOW < fed_until && fed_lvl == 2 )) || { fed_until=$(( NOW + 300000 )) fed_lvl=1; }
    logm "Grilled fish! Well Fed: double regeneration for 5 min." "$K_GOOD"
  else
    logm "No food. Fish with [g] next to water, then cook at a campfire (*) or inn."
  fi
  (( MP > MAXMP )) && MP=$MAXMP
  POS_DIRTY=1
}

# --- trading ----------------------------------------------------------------------------
trade_cmd() {  # /trade name
  local a=$1
  [[ -n $a ]] || { [[ -n $TR_WITH ]] && UI=trade MAP_DIRTY=1 || logm "Usage: /trade <name>"; return; }
  find_player "$a"
  [[ -n $FOUND ]] || { logm "Nobody called '$a' is online."; return; }
  [[ -z $TR_WITH ]] || { logm "You are already trading with ${OP_NAME[$TR_WITH]}."; UI=trade MAP_DIRTY=1; return; }
  cheb $(( ${OP_X[$FOUND]:-999} - PX )) $(( ${OP_Y[$FOUND]:-999} - PY ))
  [[ ${OP_MAP[$FOUND]} == "$CUR_MAP" ]] && (( D <= 6 )) || { logm "${OP_NAME[$FOUND]} is too far away to trade (max 6 steps)."; return; }
  if (( NOW - ${TR_IN[$FOUND]:-0} < 60000 )); then
    unset "TR_IN[$FOUND]"
    send TACC "$MY_ID" "$MY_NAME" "$FOUND"
    trade_open "$FOUND"
  else
    TR_OUT=$FOUND TR_OUT_T=$NOW
    send TREQ "$MY_ID" "$MY_NAME" "$FOUND"
    logm "You ask ${OP_NAME[$FOUND]} to trade..." "$K_SYS"
  fi
}

trade_open() {
  TR_WITH=$1 TR_OUT="" TR_PG=0 TR_MYI=() TR_MYG=0 TR_THI=() TR_THG=0 TR_MYSEQ=0 TR_THSEQ=0 TR_MYOK=0 TR_THOK=0 TR_INPUT="" TR_BUF=""
  TR_MYM=() TR_THM=()
  fish_stop quiet; GATH_MID=""
  UI=trade MAP_DIRTY=1
  logm "Trade opened with ${OP_NAME[$1]}. Both sides must accept with [y]." "$K_LOOT"
}

trade_close() {  # [msg]
  [[ -n $TR_WITH ]] || return
  [[ -n $1 ]] && logm "$1" "$K_SYS"
  TR_WITH="" TR_INPUT=""
  [[ $UI == trade ]] && { UI=""; NEED_FULL=1; }
  MAP_DIRTY=1
}

trade_send() {  # my offer changed
  local i items="" mats="" k
  TR_MYSEQ=$(( TR_MYSEQ + 1 )) TR_MYOK=0 TR_THOK=0
  for i in "${TR_MYI[@]}"; do items+="${INV[i]%!},"; done
  for k in "${!TR_MYM[@]}"; do mats+="$k:${TR_MYM[$k]},"; done
  send TOFF "$MY_ID" "$MY_NAME" "$TR_WITH" "$TR_MYSEQ" "$TR_MYG" "${items%,}" "${mats%,}"
  MAP_DIRTY=1
}

trade_toggle() {  # inventory index
  local i=$1 j new=() had=0
  (( i < ${#INV[@]} )) || return
  for j in "${TR_MYI[@]}"; do if (( j == i )); then had=1; else new+=("$j"); fi; done
  if (( ! had )); then
    (( ${#new[@]} < 10 )) || { logm "You can offer at most 10 items per trade." "$K_HURT"; return; }
    new+=("$i")
  fi
  TR_MYI=("${new[@]}")
  trade_send
}

trade_input() {  # finished text of the gold / material prompt
  local t=${TR_BUF,,} n name k best=""
  if [[ $TR_INPUT == gold ]]; then
    isnum "$t" || { logm "Type a number."; return; }
    (( t > GOLD )) && t=$GOLD
    TR_MYG=$t; trade_send; return
  fi
  t=${t#"${t%%[![:space:]]*}"}
  if [[ $t =~ ^([0-9]+)\ +(.+)$ ]]; then n=${BASH_REMATCH[1]} name=${BASH_REMATCH[2]}
  elif [[ $t =~ ^(.+[^0-9\ ])\ +([0-9]+)$ ]]; then name=${BASH_REMATCH[1]} n=${BASH_REMATCH[2]}
  else logm "Type an amount and a material, e.g.  5 iron"; return; fi
  for (( k = 0; k < NMAT; k++ )); do [[ ${MAT_NAME[k],,} == *"$name"* ]] && { best=$k; break; }; done
  [[ -n $best ]] || { logm "No material called '$name'."; return; }
  n=$(( 10#$n )); (( n > MATS[best] )) && n=${MATS[best]}
  if (( n > 0 )); then TR_MYM[$best]=$n; else unset "TR_MYM[$best]"; fi
  trade_send
}

trade_key() {
  local k=$1 i
  if [[ -n $TR_INPUT ]]; then
    case $k in
      ''|$'\r') trade_input; TR_INPUT="" ;;
      ESC) TR_INPUT="" ;;
      $'\x7f'|$'\b') TR_BUF=${TR_BUF%?} ;;
      *) [[ ${#k} == 1 && $k == [[:print:]] ]] && (( ${#TR_BUF} < 30 )) && TR_BUF+=$k ;;
    esac
    return
  fi
  case $k in
    ESC|x|X) send TCAN "$MY_ID" "$MY_NAME" "$TR_WITH"; trade_close "You cancel the trade." ;;
    [1-9]) trade_toggle $(( TR_PG * 10 + k - 1 )) ;;
    0) trade_toggle $(( TR_PG * 10 + 9 )) ;;
    '<'|,|LEFT)  (( TR_PG > 0 )) && TR_PG=$(( TR_PG - 1 )) ;;
    '>'|.|RIGHT) (( (TR_PG + 1) * 10 < ${#INV[@]} )) && TR_PG=$(( TR_PG + 1 )) ;;
    g|G) TR_INPUT=gold TR_BUF="" ;;
    m|M) TR_INPUT=mat TR_BUF="" ;;
    y|Y)
      local mine=${#TR_MYI[@]} theirs=${#TR_THI[@]}
      if (( ${#INV[@]} - mine + theirs > BAGS )); then logm "Not enough room in your bags for their items." "$K_HURT"; return; fi
      TR_MYOK=1
      send TOK "$MY_ID" "$MY_NAME" "$TR_WITH" "$TR_MYSEQ" "$TR_THSEQ"
      trade_check ;;
  esac
}

trade_check() { (( TR_MYOK && TR_THOK )) && trade_exec; }

trade_exec() {
  local i j k c ok=1 idx=() got="" gave="" nm=${OP_NAME[$TR_WITH]:-?}
  for i in "${TR_MYI[@]}"; do [[ -n ${INV[i]} ]] || ok=0; done
  (( TR_MYG <= GOLD )) || ok=0
  for k in "${!TR_MYM[@]}"; do (( MATS[k] >= TR_MYM[$k] )) || ok=0; done
  if (( ! ok )); then send TCAN "$MY_ID" "$MY_NAME" "$TR_WITH"; trade_close "Trade failed - your offer changed."; return; fi
  idx=($(printf '%s\n' "${TR_MYI[@]}" | sort -rn))
  for i in "${idx[@]}"; do item_name "${INV[i]}" "$CLS"; gave+="$INAME, "; unset "INV[i]"; done
  INV=("${INV[@]}")
  GOLD=$(( GOLD - TR_MYG + TR_THG ))
  (( TR_MYG )) && gave+="${TR_MYG} gold, "; (( TR_THG )) && got+="${TR_THG} gold, "
  for k in "${!TR_MYM[@]}"; do MATS[k]=$(( MATS[k] - TR_MYM[$k] )); gave+="${TR_MYM[$k]} ${MAT_NAME[k]}, "; done
  for k in "${!TR_THM[@]}"; do MATS[k]=$(( MATS[k] + TR_THM[$k] )); MAT_NEW[k]=$(( ${MAT_NEW[k]:-0} + TR_THM[$k] )); got+="${TR_THM[$k]} ${MAT_NAME[k]}, "; done
  for c in "${TR_THI[@]}"; do item_name "$c" "$CLS"; got+="$INAME, "; INV+=("$c"); NEWG[$c]=1; done
  INV=("${INV[@]:0:BAGS}")
  gave=${gave%, } got=${got%, }
  logm "Trade with $nm complete. You gave: ${gave:-nothing}. You got: ${got:-nothing}." "$K_LOOT"
  save_char
  trade_close
}

trade_tick() {  # once a second: partner gone or walked off?
  [[ -n $TR_WITH ]] || return
  if [[ -z ${OP_NAME[$TR_WITH]} || ${OP_MAP[$TR_WITH]} != "$CUR_MAP" ]]; then trade_close "The trade was cancelled."; return; fi
  cheb $(( ${OP_X[$TR_WITH]} - PX )) $(( ${OP_Y[$TR_WITH]} - PY ))
  (( D <= 10 )) || { send TCAN "$MY_ID" "$MY_NAME" "$TR_WITH"; trade_close "You are too far apart - trade cancelled."; }
}

trade_msg() {  # typ from name target fields...
  local typ=$1 from=$2 nm=$3 i e list=() n
  [[ $4 == "$MY_ID" ]] || return
  case $typ in
    TREQ)
      if [[ $TR_OUT == "$from" && -z $TR_WITH ]]; then send TACC "$MY_ID" "$MY_NAME" "$from"; trade_open "$from"; return; fi
      TR_IN[$from]=$NOW
      logm "$nm wants to trade with you - type /trade $nm to accept." "$K_LOOT"; printf '\a' ;;
    TACC)
      [[ $TR_OUT == "$from" && -z $TR_WITH ]] && (( NOW - TR_OUT_T < 60000 )) && trade_open "$from" ;;
    TCAN)
      [[ $TR_WITH == "$from" ]] && trade_close "$nm cancelled the trade." ;;
    TOFF)  # seq gold items mats
      [[ $TR_WITH == "$from" ]] && isnum "$5" && isnum "$6" && (( $6 <= 10000000 )) || return
      TR_THI=() TR_THM=()
      IFS=, read -r -a list <<< "$7"
      for e in "${list[@]}"; do valid_item "$e" && TR_THI+=("$e"); done
      TR_THI=("${TR_THI[@]:0:10}")
      IFS=, read -r -a list <<< "$8"
      for e in "${list[@]}"; do
        [[ $e =~ ^(0|[1-9][0-9]?):([1-9][0-9]{0,4})$ ]] || continue
        n=${BASH_REMATCH[1]}; (( n < NMAT )) && TR_THM[$n]=${BASH_REMATCH[2]}
      done
      TR_THSEQ=$5 TR_THG=$6 TR_MYOK=0 TR_THOK=0 MAP_DIRTY=1 ;;
    TOK)   # their seq, my seq as they saw it
      [[ $TR_WITH == "$from" ]] || return
      if [[ $5 == "$TR_THSEQ" && $6 == "$TR_MYSEQ" ]]; then TR_THOK=1 MAP_DIRTY=1; trade_check; fi ;;
  esac
}

ui_trade() {
  local nm=${OP_NAME[$TR_WITH]:-?} w=$(( (VW - 6) / 2 )) L=() Rr=() i k n c line key mk
  ui "  TRADE WITH ${nm^^}" "$K_LOOT$B"
  ui ""
  local mg
  matg() { mg=""; (( TW2 )) && mg=${MAT_I[$1]}; }
  for i in "${TR_MYI[@]}"; do item_name "${INV[i]}" "$CLS"; item_icon "${INV[i]}" "$CLS"; ivl; L+=("$II${II:+ }$INAME ($IVL)"); done
  for k in "${!TR_MYM[@]}"; do matg "$k"; L+=("${TR_MYM[$k]} $mg${MAT_NAME[k]}"); done
  (( TR_MYG )) && L+=("${EMJ[gold]}$TR_MYG gold")
  for c in "${TR_THI[@]}"; do item_name "$c" "$CLS"; item_icon "$c" "$CLS"; ivl; Rr+=("$II${II:+ }$INAME ($IVL)"); done
  for k in "${!TR_THM[@]}"; do matg "$k"; Rr+=("${TR_THM[$k]} $mg${MAT_NAME[k]}"); done
  (( TR_THG )) && Rr+=("${EMJ[gold]}$TR_THG gold")
  (( ${#L[@]} )) || L=("(nothing)"); (( ${#Rr[@]} )) || Rr=("(nothing)")
  printf -v line "  %-*s  %s" "$w" "YOU OFFER" "${nm^^} OFFERS"; ui "$line" "$B"
  n=${#L[@]}; (( ${#Rr[@]} > n )) && n=${#Rr[@]}
  for (( i = 0; i < n; i++ )); do padr "${L[i]}" "$w"; ui "  $PADS  ${Rr[i]}" "$K_CHAT"; done
  local s1="waiting" s2="waiting"
  (( TR_MYOK )) && s1="ACCEPTED"; (( TR_THOK )) && s2="ACCEPTED"
  printf -v line "  %-*s  %s" "$w" "[$s1]" "[$s2]"; ui "$line" "$K_GOOD"
  ui ""
  local pages=$(( (${#INV[@]} + 9) / 10 )) p0
  (( TR_PG >= pages && pages > 0 )) && TR_PG=$(( pages - 1 ))
  p0=$(( TR_PG * 10 ))
  if (( pages > 1 )); then ui "  Your bags (page $(( TR_PG + 1 ))/$pages, [<] [>] turn) - toggle with [1-0]:" "$B"
  else ui "  Your bags - toggle with [1-0]:" "$B"; fi
  for i in "${!INV[@]}"; do
    (( i < p0 )) && continue
    (( i >= p0 + 10 )) && break
    key=$(( (i - p0 + 1) % 10 )) mk=" "
    for k in "${TR_MYI[@]}"; do (( k == i )) && mk="*"; done
    item_name "${INV[i]}" "$CLS"; item_icon "${INV[i]}" "$CLS"
    ivl; ui "   [$key]$mk $II${II:+ }$INAME ($IVL)" $'\e['"${ICOL}m"
  done
  (( ${#INV[@]} )) || ui "   (empty)" "$K_SYS"
  ui ""
  case $TR_INPUT in
    gold) ui "  Gold to offer (you have $GOLD): ${TR_BUF}_" "$K_LOOT" ;;
    mat)  ui "  Material and amount, e.g. '5 iron':  ${TR_BUF}_" "$K_LOOT" ;;
    *)    ui "  [g] gold  [m] materials  [y] accept  [esc] cancel" "$K_SYS"
          ui "  Any change to an offer resets both acceptances." "$K_SYS" ;;
  esac
}

# ---------------------------------------------------------------------------
#  Module 04c - graphics (since v1.4): HD mode (every tile is 2 columns: emoji
#  sprites, colored ground) and the classic 1-column ASCII mode ([v] switches),
#  text width helpers, and the tile-row cache that makes map frames cheap.
# ---------------------------------------------------------------------------
GFX_FILE="$DATA_DIR/config" GFX_NEW=0 TW=1 TW2=0 MW=81 PLX=x
if [[ -z $GFX ]]; then
  [[ -f $GFX_FILE ]] && GFX=$(sed -n 's/^GFX=//p' "$GFX_FILE" 2>/dev/null | head -n1)
  [[ $GFX == @(hd|ascii) ]] || { GFX=hd GFX_NEW=1; }
fi
declare -A GLYH=() GLYP=() TBG=() HITF=()
FT_X=() FT_Y=() FT_T=() FT_C=() FT_S=() FT_M=()

# sprites: one emoji per creature (all of them are 2 columns wide everywhere)
MEMO=(🐀 🦠 🐺 👺 🐜 🧟 🤠 🦍 🐲 💀 👻 🧛 🐗 👹 👺 🧙 🦎 🐉 🦏
      💂 👩 🧔 👵 👴 🧑 🧓 👨 🧚
      🦀 🦂 🐪 🐍 🧟 🗿 👑 🐺 🐻 ⛄ 👹 🐉 😈 👾 🐕 👿 👿 🧜
      👳 🧕 👸 🤴 👱 🧔 💂
      🥉 🔩 🥈 🥇 💎 🔮 🌼 🌿 🍀 🌹 🌷 🍁
      🌳 🐊 🦈 🗽 🥶 🦖
      🤵 🤵 🤵 🤵 🤵
      🦞 🦜 🐙 🐢  🐏 🦗 🤖 🦎  🐸 🐆 🦟 🐅  🦅 🐃 👹 🦂  👽 🦇 💀 🧿
      💀 👺 🦎 🐕 🧙 😈  🧜 🐋 🤖 🗿 🐒  🐍 🐉 😈 🧔 👑  👾 👽 🤴
      🧰
      🐙 🐲 🐘 🦅 🐋
      👮  💁 🚣 💃 🤵  🧐 👷 🧗 🤵 🧖  🧘 🙆 🧒 🤵  🤠 🙋 🧔 🤵 👧  👼 👴 💂 🤵 👨)
for _t in "${!MEMO_X[@]}"; do MEMO[_t]=${MEMO_X[_t]}; done                 # v4.0 creatures
for _t in "${!RARE_BASE[@]}"; do MEMO[_t]=${MEMO[RARE_BASE[$_t]]}; done   # rare elites look like their kind
unset _t
CEMO=(🤺 🧙 🧝 😇 🦹 🦸 🧛 🕺 🦌 🧘)    # Warrior Mage Ranger Cleric Rogue Paladin Necromancer Bard, v4.0: Druid Monk
declare -A FXH=([fire]=🔥 [frost]=🧊 [holy]=✨ [slash]=💥 [poison]=🦠 [bone]=🦴 [sound]=🎵
                [warn]=$'\e[0;5;48;5;52m❗' [bolt]=⚡)
# item "textures": what it is + what it is made of + how rare it is
MAT_E=("" 🍂 🔩 🔗 💎 🔯 🐉 🌠 🔆 🌀 🌋 🌑 🌞)   # Worn ... Voidforged, v4.0: Titanforged Eclipsed Godforged
RAR_E=("  " 🔹 💜 🌟 🔶)                       # Common Rare Epic Legendary Unique
SKILL_E=(💥 🏃 📣  🔥 🧊 ✨  🏹 🎯 💨  ⚡ 💚 🌟  🔪 🧪 👤  🔨 🔰 🌞  🦴 🩸 🦠  🎸 💤 🎺  🌿 🌱 🌸  👊 🦶 🙏)
declare -A CON_E=([h]=🍷 [m]=🧪 [gh]=🍾 [gm]=🍶 [str]=💪 [iron]=🐢 [swift]=🐇 [recall]=🌀 [brew]=🍵
                  [meal1]=🍢 [meal2]=🍲 [tfrost]=🧊 [tfire]=🧯 [tveil]=🥽 [rfw]=🔧 [rfa]=🔧 [hp2]=🍷 [mp2]=🧪)
D_WE=(⬛ 🟫 🟥 🟨 🟦 🟪 🟦 🟪 🟩 🟧 ⬛)            # dungeon walls: crypt warrens lair tomb ice infernal + v2.0
D_WE+=("${D_WE_X[@]}")                            # v4.0
declare -A EMJ=() WEA_E=([rain]=☔ [storm]=⚡ [fog]=🌁 [sand]=💨 [snow]=⛄ [ash]=🌋)
declare -A VROW=() VBUILT=()

# HD ground: colored backgrounds, emoji for things that stand on it
E0=$'\e[0;'
Z2_DOT="${E0}48;5;22m  " Z2_COM="${E0}48;5;22m  " Z2_TG="${E0}48;5;22m🌾" Z2_FLW="${E0}48;5;22m🌸"
Z2_TREE="${E0}48;5;22m🌳" Z2_MTN="${E0}48;5;239m🗻" Z2_ROAD="${E0}48;5;137m  "
Z2_BRG="${E0}48;5;25m🟫" Z2_SWP="${E0}48;5;58m  " Z2_ENT="${E0}48;5;52m🚪" Z2_EXT="${E0}48;5;53m🌀"
Z2_QST="${E0}48;5;102m📜" Z2_FTN="${E0}48;5;102m⛲" Z2_FIRE="${E0}48;5;94m🔥"
Z2_SAND="${E0}48;5;180m  " Z2_DUNE="${E0}48;5;180m🟨" Z2_CACT="${E0}48;5;180m🌵" Z2_SNOW="${E0}48;5;253m  "
Z2_DRIFT="${E0}48;5;253m⬜" Z2_PINE="${E0}48;5;253m🌲" Z2_ICE="${E0}48;5;117m🧊" Z2_ASH="${E0}48;5;236m  "
Z2_ROCK="${E0}48;5;234m🌋" Z2_WAY="${E0}48;5;236m💠" Z2_VOID=$'\e[0m  '
Z2_CRYF="${E0}48;5;60m  " Z2_CRYS="${E0}48;5;60m🔷" Z2_JUNG="${E0}48;5;28m  " Z2_JTREE="${E0}48;5;28m🌴"
Z2_BAD="${E0}48;5;130m  " Z2_MESA="${E0}48;5;94m🟫" Z2_VOIDF="${E0}48;5;53m  " Z2_CHASM="${E0}48;5;17m🌌"
Z2_a="${E0}48;5;28m🌿" Z2_d="${E0}48;5;28m🍃" Z2_e="${E0}48;5;60m✨" Z2_k="${E0}48;5;130m🐾" Z2_p="${E0}48;5;53m💫"
Z2_AUT="${E0}48;5;136m  " Z2_ATREE="${E0}48;5;136m🍁" Z2_MYC="${E0}48;5;96m  " Z2_SHROOM="${E0}48;5;96m🍄"     # v4.0 lands
Z2_HGT="${E0}48;5;66m  " Z2_CRAG="${E0}48;5;66m🗻" Z2_BONE="${E0}48;5;144m  "
# decorations (only in the render copy of the map, see build_vrows) and animated tiles
Z2_b="${E0}48;5;22m🌱" Z2_c="${E0}48;5;22m🍄" Z2_f="${E0}48;5;22m🌺" Z2_g="${E0}48;5;22m🌻" Z2_h="${E0}48;5;22m🌲"
Z2_l="${E0}48;5;180m🐚" Z2_o="${E0}48;5;180m🦴" Z2_r="${E0}48;5;253m🎄" Z2_t="${E0}48;5;236m⬛" Z2_u="${E0}48;5;236m🦴"
Z2_w="${E0}48;5;137m👣" Z2_x="${E0}48;5;58m🍄" Z2_z="${E0}48;5;236m🦴"
WAVE="${E0}48;5;25m🌊" CALM="${E0}38;5;39;48;5;25m~ " LAVA_A="${E0}48;5;202m🟧" LAVA_B="${E0}48;5;202m🟥"
Z2_WAT="${E0}38;5;39;48;5;25m  " Z2_i=$WAVE Z2_j=$CALM Z2_LAVA=$LAVA_A Z2_v=$LAVA_B Z_DARKBG=$'\e[0;48;5;233m'
T2C=(' ' . , '"' '*' T '~' '^' '#' _ : = % '>' '<' Q O F S s Y N n P I A L R Z b c f g h i j l o r t u v w x z K C J W D V E G a d e k p q y M U H X B '+')
T2V=(Z2_VOID Z2_DOT Z2_COM Z2_TG Z2_FLW Z2_TREE Z2_WAT Z2_MTN Z2_WALL Z2_FLR Z2_ROAD Z2_BRG Z2_SWP Z2_ENT Z2_EXT
     Z2_QST Z2_FTN Z2_FIRE Z2_SAND Z2_DUNE Z2_CACT Z2_SNOW Z2_DRIFT Z2_PINE Z2_ICE Z2_ASH Z2_LAVA Z2_ROCK Z2_WAY
     Z2_b Z2_c Z2_f Z2_g Z2_h Z2_i Z2_j Z2_l Z2_o Z2_r Z2_t Z2_u Z2_v Z2_w Z2_x Z2_z
     Z2_CRYF Z2_CRYS Z2_JUNG Z2_JTREE Z2_BAD Z2_MESA Z2_VOIDF Z2_CHASM Z2_a Z2_d Z2_e Z2_k Z2_p
     Z2_AUT Z2_ATREE Z2_MYC Z2_SHROOM Z2_HGT Z2_CRAG Z2_BONE Z2_FURN)

tbg_build() {  # background of every tile, so sprites blend into the ground
  local i z
  for i in "${!T2C[@]}"; do
    z=${!T2V[i]}
    if [[ $z =~ 48\;5\;([0-9]+) ]]; then TBG[${T2C[i]}]=$'\e[0;48;5;'"${BASH_REMATCH[1]}m"; else TBG[${T2C[i]}]=$'\e[0m'; fi
  done
}

colorize2() {  # CZ in place; order matters: chars that appear in a replacement are done before it
  CZ=${CZ//' '/$Z2_VOID}
  CZ=${CZ//'.'/$Z2_DOT};  CZ=${CZ//','/$Z2_COM};  CZ=${CZ//'~'/$Z2_WAT};  CZ=${CZ//'"'/$Z2_TG}
  CZ=${CZ//'*'/$Z2_FLW};  CZ=${CZ//'T'/$Z2_TREE}; CZ=${CZ//'^'/$Z2_MTN};  CZ=${CZ//'#'/$Z2_WALL}
  CZ=${CZ//'_'/$Z2_FLR};  CZ=${CZ//':'/$Z2_ROAD}; CZ=${CZ//'='/$Z2_BRG};  CZ=${CZ//'%'/$Z2_SWP}
  CZ=${CZ//'>'/$Z2_ENT};  CZ=${CZ//'<'/$Z2_EXT};  CZ=${CZ//'Q'/$Z2_QST};  CZ=${CZ//'O'/$Z2_FTN}
  CZ=${CZ//'F'/$Z2_FIRE}; CZ=${CZ//'S'/$Z2_SAND}; CZ=${CZ//'s'/$Z2_DUNE}; CZ=${CZ//'Y'/$Z2_CACT}
  CZ=${CZ//'N'/$Z2_SNOW}; CZ=${CZ//'n'/$Z2_DRIFT}; CZ=${CZ//'P'/$Z2_PINE}; CZ=${CZ//'I'/$Z2_ICE}
  CZ=${CZ//'A'/$Z2_ASH};  CZ=${CZ//'L'/$Z2_LAVA}; CZ=${CZ//'R'/$Z2_ROCK}; CZ=${CZ//'Z'/$Z2_WAY}
  CZ=${CZ//K/$Z2_CRYF}; CZ=${CZ//C/$Z2_CRYS}; CZ=${CZ//J/$Z2_JUNG}; CZ=${CZ//W/$Z2_JTREE}
  CZ=${CZ//D/$Z2_BAD};  CZ=${CZ//V/$Z2_MESA}; CZ=${CZ//E/$Z2_VOIDF}; CZ=${CZ//G/$Z2_CHASM}
  CZ=${CZ//b/$Z2_b}; CZ=${CZ//c/$Z2_c}; CZ=${CZ//f/$Z2_f}; CZ=${CZ//g/$Z2_g}; CZ=${CZ//h/$Z2_h}; CZ=${CZ//i/$Z2_i}
  CZ=${CZ//j/$Z2_j}; CZ=${CZ//l/$Z2_l}; CZ=${CZ//o/$Z2_o}; CZ=${CZ//r/$Z2_r}; CZ=${CZ//t/$Z2_t}; CZ=${CZ//u/$Z2_u}
  CZ=${CZ//v/$Z2_v}; CZ=${CZ//w/$Z2_w}; CZ=${CZ//x/$Z2_x}; CZ=${CZ//z/$Z2_z}
  CZ=${CZ//a/$Z2_a}; CZ=${CZ//d/$Z2_d}; CZ=${CZ//e/$Z2_e}; CZ=${CZ//k/$Z2_k}; CZ=${CZ//p/$Z2_p}
  CZ=${CZ//q/$Z2_AUT}; CZ=${CZ//y/$Z2_ATREE}; CZ=${CZ//M/$Z2_MYC}; CZ=${CZ//U/$Z2_SHROOM}
  CZ=${CZ//H/$Z2_HGT}; CZ=${CZ//X/$Z2_CRAG}; CZ=${CZ//B/$Z2_BONE}; CZ=${CZ//'+'/$Z2_FURN}
}

build_vrow() {  # map y: decorated render copy of one row (sprouts, mushrooms, shells, waves...), deterministic
  local map=$1 y=$2 x row out c h k w=${MAPW[$1]}
  row=${MAPROW[$map:$y]} out="" h=$(( y * 7919 + 104729 ))
  for (( x = 0; x < w; x++ )); do
    c=${row:x:1}
    case $c in
      [.,*T~SPA:%L_NJKDE])
        h=$(( (h * 1103515245 + 12345) & 2147483647 )); k=$(( h / 65536 % 100 ))
        case $c in
          .)   (( k < 4 )) && c=b; (( k == 4 )) && c=c ;;
          ,)   (( k < 30 )) && c=b ;;
          '*') (( k < 33 )) && c=f; (( k >= 33 && k < 66 )) && c=g ;;
          T)   (( k < 22 )) && c=h ;;
          '~') (( k < 20 )) && c=i; (( k >= 20 && k < 40 )) && c=j ;;
          S)   (( k == 0 )) && c=l; (( k == 1 )) && c=o ;;
          P)   (( k < 10 )) && c=r ;;
          A)   (( k < 7 )) && c=t; (( k >= 7 && k < 10 )) && c=u ;;
          :)   (( k < 3 )) && c=w ;;
          %)   (( k < 14 )) && c=x ;;
          L)   (( k < 50 )) && c=v ;;
          _)   [[ $map == D* ]] && (( k < 3 )) && c=z ;;
          J)   (( k < 9 )) && c=a; (( k >= 9 && k < 13 )) && c=d ;;
          K)   (( k < 5 )) && c=e ;;
          D)   (( k < 2 )) && c=k ;;
          E)   (( k < 3 )) && c=p ;;
        esac ;;
    esac
    out+=$c
  done
  VROW["$map:$y"]=$out
}

build_vrows() {  # map: every row (v2.0: rows are normally built lazily, when they first scroll into view)
  local y
  [[ -n ${VBUILT[$1]} ]] && return
  for (( y = 0; y < ${MAPH[$1]:-0}; y++ )); do [[ -n ${VROW[$1:$y]} ]] || build_vrow "$1" "$y"; done
  VBUILT[$1]=1
}

drop_vrows() { local y; for (( y = 0; y < ${MAPH[$1]:-0}; y++ )); do unset "VROW[$1:$y]"; done; unset "VBUILT[$1]"; tiles_drop "$1"; }

dispw() {  # text -> DW: terminal columns (every emoji counts 2)
  local t=${1//[ -~]/}
  t=${t//[←↑→↓↖↗↘↙─│═╭╮╯╰█▉▊▋▌▍▎▏░▒▓▙▟▲▼▶•◆☀☾♣·🗡🛡✖✔★]/}
  DW=$(( ${#1} + ${#t} ))
}

item_icon() {  # code cls -> II: [type][material][rarity] (HD) or "" (ASCII)
  II=""
  (( TW2 )) || return
  item_stats "$1"
  II="$IKE${MAT_E[IT]}${RAR_E[IRR]}"
  [[ $IK == B ]] && II="$IKE${BAG_M[IKD]}${RAR_E[IRR]}"
  [[ $IK == C ]] && II="$IKE${CS_E[${CL_SET[IKD]}]}${RAR_E[IRR]}"
}
ci() { CI=""; (( TW2 )) && CI="${CON_E[$1]:-  } "; }     # consumable icon + space
plain() {  # colored text -> PL (escape sequences removed)
  local r=$1 p=""
  while [[ $r == *$'\e'* ]]; do p+=${r%%$'\e'*}; r=${r#*$'\e'}; r=${r#*[A-Za-z]}; done
  PL=$p$r
}
clipl() {  # colored text width -> CL: cut to <= width terminal columns, colors kept
  plain "$1"; dispw "$PL"
  if (( DW <= $2 )); then CL=$1; return; fi
  local r=$1 o="" w=0 c e
  while [[ -n $r ]]; do
    if [[ $r == $'\e'* ]]; then e=${r%%[A-Za-z]*}; e=${r:0:${#e}+1}; o+=$e; r=${r:${#e}}; continue; fi
    c=${r%%$'\e'*}; dispw "$c"
    if (( w + DW <= $2 )); then o+=$c; w=$(( w + DW )); r=${r:${#c}}; continue; fi
    if [[ $c != *[^\ -~]* ]]; then o+=${c:0:$2-w}; break; fi        # plain ASCII: cut in one go
    while [[ -n $c ]]; do dispw "${c:0:1}"; (( w + DW > $2 )) && break; o+=${c:0:1}; w=$(( w + DW )); c=${c:1}; done
    break
  done
  CL=$o$'\e[0m'
}
declare -A CLIPC=()
clipc() {  # clipl with a cache: the side panel and the log mostly repeat themselves
  local k="$2|$1"
  if [[ -n ${CLIPC[$k]+x} ]]; then CL=${CLIPC[$k]}; return; fi
  clipl "$1" "$2"; (( ${#CLIPC[@]} > 600 )) && CLIPC=()
  CLIPC[$k]=$CL
}
padr() { dispw "$1"; PADS=$1; (( DW < $2 )) && PADS+=${BLANK:0:$2-DW}; }   # pad to terminal columns
padt() {  # cut to <= width columns, then pad
  local t=$1
  dispw "$t"; while (( DW > $2 )); do t=${t:0:${#t}-1}; dispw "$t"; done
  PADS=$t${BLANK:0:$2-DW}
}

declare -A COLC=()
colorize() {  # CZ in place, cached (the world map and menus repeat the same strips)
  local k="$TW$CZ"
  if [[ -n ${COLC[$k]+x} ]]; then CZ=${COLC[$k]}; return; fi
  if (( TW == 2 )); then colorize2; else colorize1; fi
  (( ${#COLC[@]} > 3000 )) && COLC=()
  COLC[$k]=$CZ
}

# --- tile rows: each map row is colored once and a frame only cuts pieces out of it --------
# TRS[map:y] = the colored row (repeated color codes dropped), TRO[map:y] = 5-digit offset of
# every tile in it, so a piece is one substring. ZE[c] = the color code a piece starts with.
# Rows with animated water/lava (HD) exist once per animation phase (key map:y:phase).
declare -A ZT=() ZE=() TRS=() TRO=() TR_AN=()
TR_ON=0 TR_X0=0 TR_W=0 TR_PH=0 TR_K="" TR_RAW=""
tiles_init() {  # per-tile colors for the current graphics mode and palette; forgets all built rows
  local c
  TRS=() TRO=() TR_AN=() ZT=() ZE=() COLC=() DRS=()
  for c in "${T2C[@]}"; do                    # every tile there is (see the TBG table)
    CZ=$c
    if (( TW == 2 )); then colorize2; else colorize1; fi
    ZT[$c]=$CZ; ZE[$c]=""; [[ $CZ == $'\e['* ]] && ZE[$c]=${CZ%%m*}m
  done
}
tiles_row() {  # map y -> TR_K TR_RAW: the colored row is built on first use
  local k="$1:$2" ph="" x r w c t e pe="" o=0 s="" offs="" n
  if (( TW == 2 )); then [[ -n ${VROW[$k]} ]] || build_vrow "$1" "$2"; TR_RAW=${VROW[$k]}; else TR_RAW=${MAPROW[$k]}; fi
  if [[ -z ${TR_AN[$k]} ]]; then
    TR_AN[$k]=0; (( TW == 2 )) && [[ $TR_RAW == *[ijLv]* ]] && TR_AN[$k]=1
  fi
  [[ ${TR_AN[$k]} == 1 ]] && ph=:$TR_PH
  TR_K=$k$ph
  [[ -n ${TRO[$TR_K]} ]] && return
  r=$TR_RAW w=${#r}
  for (( x = 0; x < w; x++ )); do
    c=${r:x:1}
    if [[ -n $ph ]]; then
      case $c in i) t=$Z2_i ;; j) t=$Z2_j ;; L) t=$Z2_LAVA ;; v) t=$Z2_v ;; *) t=${ZT[$c]} ;; esac
    else t=${ZT[$c]}; fi
    printf -v n '%05d' "$o"; offs+=$n
    if [[ $t == $'\e['* ]]; then
      e=${t%%m*}
      if [[ $e == "$pe" ]]; then t=${t#*m}; else pe=$e; fi   # same color as the tile before: glyph only
    fi
    s+=$t; o=$(( o + ${#t} ))
  done
  printf -v n '%05d' "$o"
  TRS[$TR_K]=$s TRO[$TR_K]=$offs$n
}
tiles_drop() {  # map: forget its tile rows (a dungeon that closed)
  local v
  for v in "${!TRO[@]}"; do [[ $v == "$1:"* ]] && unset "TRO[$v]" "TRS[$v]"; done
  for v in "${!TR_AN[@]}"; do [[ $v == "$1:"* ]] && unset "TR_AN[$v]" "DRS[$v]"; done
}
tiles_at() {  # view-x count -> CZ: colored tiles of the current row (tiles_row), view starts at TR_X0
  local a=$(( TR_X0 + $1 )) n=$2 k pre="" post="" o1 o2 c e
  if (( a < 0 )); then k=$(( -a < n ? -a : n )); printf -v pre '%*s' "$k" ''; pre=${pre// /${ZT[' ']}}; a=0 n=$(( n - k )); fi
  if (( a + n > TR_W )); then k=$(( a + n - TR_W )); (( k > n )) && k=$n; printf -v post '%*s' "$k" ''; post=${post// /${ZT[' ']}}; n=$(( n - k )); fi
  CZ=""
  if (( n > 0 )); then
    o1=$(( 10#${TRO[$TR_K]:a*5:5} )) o2=$(( 10#${TRO[$TR_K]:(a+n)*5:5} ))
    c=${TR_RAW:a:1}
    case $c in i) e=${Z2_i%%m*}m ;; j) e=${Z2_j%%m*}m ;; L) e=${Z2_LAVA%%m*}m ;; v) e=${Z2_v%%m*}m ;; *) e=${ZE[$c]} ;; esac
    [[ $TR_K == *:*:* ]] || case $c in i|j|L|v) e=${ZE[$c]} ;; esac
    CZ=$e${TRS[$TR_K]:o1:o2-o1}
  fi
  CZ=$pre$CZ$post
}
colorize_at() { if (( TR_ON )); then tiles_at "$PZ" "${#CZ}"; else colorize; fi; }   # CZ (+ PZ) in place

dark_paint() { dark_glyphs; CZ="$Z_DARK$CZ"; }   # CZ -> plain moonlit sketch of the terrain
declare -A DRS=()
dark_at() {  # view-x count -> CZ: the moonlit sketch of tiles of the current row (see tiles_at)
  local k=${TR_K%:*} a=$(( TR_X0 + $1 )) n=$2 pre="" post="" d
  [[ $TR_K == *:*:* ]] || k=$TR_K
  if [[ -z ${DRS[$k]+x} ]]; then CZ=$TR_RAW; dark_glyphs; DRS[$k]=$CZ; fi
  if (( a < 0 )); then pre=${BLANK:0:(-a < n ? -a : n) * TW}; n=$(( n - ${#pre} / TW )); a=0; fi
  if (( a + n > TR_W )); then post=${BLANK:0:(a + n - TR_W) * TW}; n=$(( n - ${#post} / TW )); fi
  d=${DRS[$k]}
  CZ=$Z_DARK$pre${d:a*TW:n*TW}$post
}
dark_glyphs() {  # CZ in place: every tile becomes its plain sketch, TW characters wide
  if (( TW == 2 )); then
    CZ=${CZ//[bc]/.}; CZ=${CZ//[fg]/'*'}; CZ=${CZ//h/T}; CZ=${CZ//[ij]/'~'}; CZ=${CZ//[lo]/S}; CZ=${CZ//r/P}
    CZ=${CZ//[tu]/A}; CZ=${CZ//v/L}; CZ=${CZ//w/:}; CZ=${CZ//x/%}; CZ=${CZ//z/_}
    CZ=${CZ//[ad]/J}; CZ=${CZ//e/K}; CZ=${CZ//k/D}; CZ=${CZ//p/E}
    CZ=${CZ//' '/'  '}; CZ=${CZ//[._:SNAIKJDEqMHB]/'  '}; CZ=${CZ//[,sn]/' ,'}; CZ=${CZ//'"'/'""'}; CZ=${CZ//'*'/' *'}
    CZ=${CZ//[TPWyU]/'T '}; CZ=${CZ//Y/'Y '}; CZ=${CZ//[~LG]/'~~'}; CZ=${CZ//[\^RCVX]/'^^'}; CZ=${CZ//'#'/'##'}
    CZ=${CZ//'='/'=='}; CZ=${CZ//'%'/'%%'}; CZ=${CZ//'>'/'> '}; CZ=${CZ//'<'/'< '}; CZ=${CZ//Z/'& '}
    CZ=${CZ//Q/'! '}; CZ=${CZ//O/'o '}; CZ=${CZ//F/'* '}; CZ=${CZ//'+'/'  '}
  else
    CZ=${CZ//'+'/.}; CZ=${CZ//[SNAI_:KJDEqMHB]/.}; CZ=${CZ//[sn]/,}; CZ=${CZ//[PWyU]/T}; CZ=${CZ//[LG]/'~'}; CZ=${CZ//[RCVX]/^}
    CZ=${CZ//Z/'&'}; CZ=${CZ//Q/'!'}; CZ=${CZ//O/o}; CZ=${CZ//F/'*'}
  fi
}

mem_paint() {  # remembered but unlit dungeon cells
  if (( TW == 2 )); then
    CZ=${CZ//' '/$'\e[49m  \e[48;5;233m'}; CZ=${CZ//'#'/'▓▓'}; CZ=${CZ//./'  '}; CZ=${CZ//'<'/'< '}
    CZ=$'\e[0;38;5;238;48;5;233m'"$CZ"
  else
    CZ="$Z_MEM$CZ"
  fi
}

set_gfx() {  # (re)build everything that depends on the tile width
  local t bg dy k
  if [[ $GFX == hd ]]; then TW=2 LRX=7 PLX=xx; else TW=1 LRX=12 PLX=x; fi
  LSPAN=()
  for (( dy = -LRY; dy <= LRY; dy++ )); do isqrt $(( LRX * LRX * (LRY * LRY - dy * dy) / (LRY * LRY) )); LSPAN[dy+LRY]=$R; done
  SPANC=()
  for (( t = 0; t < NM; t++ )); do
    if (( TW == 2 )); then
      bg=""; [[ ${M_COL[t]} =~ 48\;5\;([0-9]+) ]] && bg=$'\e[0;48;5;'"${BASH_REMATCH[1]}m"
      GLYH[m$t]="$bg${MEMO[t]:-${M_GLY[t]} }"
      GLYP[m$t]="$bg${MEMO[t]:-${M_GLY[t]} }$N"
    else
      GLYP[m$t]=${GLY[m$t]}
    fi
  done
  for k in "${!FXH[@]}"; do GLYH[f$k]=${FXH[$k]}; done
  GLYH[zrain]=💧 GLYH[zstorm]=💧 GLYH[zsnow]=⚪ GLYH[zsand]=💨 GLYH[zash]=🔸
  GLYH[wbank]=$'\e[0;48;5;236m🏦'
  GLYH[wdun]=🚪 GLYH[wway]=💠 GLYH[wqg]=$'\e[0;48;5;236m❗' GLYH[wqt]=$'\e[0;5;48;5;236m🎯'
  TW2=0; (( TW == 2 )) && TW2=1
  tiles_init
  if (( TW2 )); then
    FISHG="🐟"
    EMJ=([gold]="💰 " [xp]="✨ " [loot]="🎁 " [lvl]="🎉 " [death]="💀 " [quest]="🏆 " [crown]="👑 " [way]="💠 ")
    :   # decorated rows are built lazily while rendering
  else
    FISHG=$'\e[0;1;38;5;45m~'; EMJ=()
  fi
  for k in "${!OP_NAME[@]}"; do player_glyph "$k" "${OP_SYM[$k]:-@}" "${OP_COL[$k]:-0}" "${OP_DEAD[$k]:-0}"; done
  tbg_build
}

toggle_gfx() {
  if [[ $GFX == hd ]]; then GFX=ascii; else GFX=hd; fi
  set_gfx; save_gfx; layout
  if [[ $GFX == hd ]]; then logm "Graphics: HD (emoji sprites, 2 columns per tile). [v] switches back to ASCII." "$K_GOOD"
  else logm "Graphics: classic ASCII. [v] switches to HD emoji graphics." "$K_GOOD"; fi
}

save_gfx() { mkdir -p "$DATA_DIR" 2>/dev/null; printf 'GFX=%s\n' "$GFX" > "$GFX_FILE" 2>/dev/null; }

# --- juice: floating numbers, hit flashes, nicer bars -------------------------------
ft_add() {  # x y text style
  FT_X+=("$1"); FT_Y+=("$2"); FT_T+=("$3"); FT_C+=("$4"); FT_S+=("$NOW"); FT_M+=("$CUR_MAP")
  MAP_DIRTY=1
}

ft_items() {  # cx0 cy0: rising numbers become tags of their own
  local i a txt w dx dy
  for i in "${!FT_S[@]}"; do
    a=$(( NOW - FT_S[i] ))
    if (( a > 1100 || ${#FT_S[@]} > 30 )) || [[ ${FT_M[i]} != "$CUR_MAP" ]]; then
      unset "FT_X[i]" "FT_Y[i]" "FT_T[i]" "FT_C[i]" "FT_S[i]" "FT_M[i]"; continue
    fi
    txt=${FT_T[i]}
    if (( TW == 2 )); then (( ${#txt} % 2 )) && txt+=" "; w=$(( ${#txt} / 2 )); else w=${#txt}; fi
    dx=$(( FT_X[i] - $1 - w / 2 )) dy=$(( FT_Y[i] - $2 - 1 - a / 380 ))
    (( dx >= 0 && dx + w <= VW && dy >= 0 && dy < VH )) || continue
    TAGS+=("${FT_C[i]}$txt$N"); RI[dy]+="$(( dx * 10 + 4 )):$w:t$(( ${#TAGS[@]} - 1 )) "
  done
}

hp_tag() {  # cx0 cy0: tiny health bar above my target
  local m=$TARGET bw=5 w f8 full part s="" c dx dy
  [[ -n $m && -n ${CM_T[$m]} ]] || return
  (( CM_HP[$m] > 0 && CM_HP[$m] < CM_MAX[$m] )) || return
  (( TW == 2 )) && bw=6
  w=$(( bw / TW )) dx=$(( CM_X[$m] - $1 - (bw / TW) / 2 )) dy=$(( CM_Y[$m] - $2 - 1 ))
  (( dx >= 0 && dx + w <= VW && dy >= 0 && dy < VH )) || return
  free_span "$dy" "$dx" "$w" || return
  f8=$(( CM_HP[$m] * bw * 8 / CM_MAX[$m] )) full=$(( f8 / 8 )) part=$(( f8 % 8 ))
  local rest=$(( bw - full )) e=""
  printf -v s '%*s' "$full" ''; s=${s// /█}
  (( part && full < bw )) && { s+=${PBC[part]}; rest=$(( rest - 1 )); }
  printf -v e '%*s' "$rest" ''; s+=$e
  if (( CM_HP[$m] * 100 / CM_MAX[$m] > 50 )); then c=46; elif (( CM_HP[$m] * 100 / CM_MAX[$m] > 25 )); then c=226; else c=196; fi
  TAGS+=($'\e[0;38;5;'"$c;48;5;236m$s$N"); RI[dy]+="$(( dx * 10 + 6 )):$w:t$(( ${#TAGS[@]} - 1 )) "
}

PBC=(" " ▏ ▎ ▍ ▌ ▋ ▊ ▉)      # eighths of a cell (an array: slicing UTF-8 strings breaks in C locales)
PB_FULLS=("")                 # n full cells, for the same reason an array
for (( i = 1; i <= 60; i++ )); do PB_FULLS[i]=${PB_FULLS[i-1]}█; done
pbar() {  # val max width color -> PB  (smooth: 1/8 cell steps on a dark track)
  local w=$3 f8=0 full part a="" e="" rest
  (( $2 > 0 )) && f8=$(( $1 * w * 8 / $2 )); (( f8 > w * 8 )) && f8=$(( w * 8 )); (( f8 < 0 )) && f8=0
  full=$(( f8 / 8 )) part=$(( f8 % 8 )) rest=$(( w - full ))
  a=${PB_FULLS[full]}
  (( part )) && { a+=${PBC[part]}; rest=$(( rest - 1 )); }
  PB="$4"$'\e[48;5;236m'"$a${BLANK:0:rest}$N"
}

hp_col() { if (( $1 * 100 > $2 * 60 )); then HC=$'\e[38;5;46m'; elif (( $1 * 100 > $2 * 30 )); then HC=$'\e[38;5;226m'; else HC=$'\e[38;5;196m'; fi; }

declare -A HDR_E=([SKILLS]=✨ [TARGET]=🎯 [PARTY]=👥 [QUESTS]=📜 [NEARBY]=👀)
hdr() {  # section header in the side panel
  if (( TW2 )); then HDR=$'\e[1;38;5;231;48;5;238m'" ${HDR_E[$1]} $1 $N"; else HDR=$'\e[1;38;5;231;48;5;238m'" $1 $N"; fi
}

LOGO=("##### #   # ##### #     #         #   # #   # ##### ####  ####  #####"
      "#     #   # #     #     #         ## ## ## ## #   # #   # #   # #    "
      "##### ##### ####  #     #         # # # # # # #   # ####  ####  #  ##"
      "    # #   # #     #     #         #   # #   # #   # #  #  #     #   #"
      "##### #   # ##### ##### #####     #   # #   # ##### #   # #     #####")
LOGO_C=(214 214 208 208 202 202 196 196 197 197 198 198 199 199 200 200 201 201 165 165 129 129 93 93)
print_logo() {  # big gradient title for the start screens (sliced as ASCII, drawn as blocks)
  local l i seg
  printf '\n'
  for l in "${LOGO[@]}"; do
    printf '   '
    for (( i = 0; i < ${#l}; i += 3 )); do seg=${l:i:3}; printf '\e[1;38;5;%sm%s' "${LOGO_C[i / 3 % ${#LOGO_C[@]}]}" "${seg//#/█}"; done
    printf '\e[0m\n'
  done
  printf '   \e[38;5;245ma real-time multiplayer RPG in pure bash  -  v%s\e[0m\n' "$VERSION"
}

# ---------------------------------------------------------------------------
#  Module 04e - allies (since v2.0): companions who follow you everywhere,
#  fight what you fight and patch you up. Everyone sees them next to you.
# ---------------------------------------------------------------------------
ALLIES="" ALLY=-1 AX=0 AY=0 ALY_MAP="" ALY_NEXT=0 ALY_HEALT=0 ALY_LAST=""
declare -A OP_ALY=() OP_AX=() OP_AY=()
ALY_E=(🤺 🧝 👼 🐺 🦉 🧞 🐲 💀 "${ALY_E_X[@]}")
ALY_KEYS="1234567890-="                          # the key that calls ally i
for (( i = 0; i < NALY; i++ )); do
  GLY[a$i]=$'\e[0;1;38;5;16;48;5;35m'"${ALY_G[i]}" GLYH[a$i]=$'\e[0;48;5;28m'"${ALY_E[i]}"
done

aly_fix() { while (( ${#ALLIES} < NALY )); do ALLIES+="0"; done; ALLIES=${ALLIES:0:NALY}; }
aly_has() { [[ ${ALLIES:$1:1} == 1 ]]; }
aly_unlock() {  # index -> calls it to your side unless someone is already there
  aly_fix
  ALLIES="${ALLIES:0:$1}1${ALLIES:$1+1}"
  (( ALLY < 0 )) && aly_summon "$1" quiet
  logm "${ALY_E[$1]} ${ALY_NAME[$1]} joins you! [y] calls or sends home your allies." "$K_ANN"
}

aly_place() {  # put the ally on a free tile next to me (after a teleport, a dungeon, a summon)
  local c x y
  ALY_MAP=$CUR_MAP AX=$PX AY=$PY
  for c in "$(( -FDX )),$(( -FDY ))" -1,0 1,0 0,1 0,-1 -1,1 1,1 -1,-1 1,-1; do
    x=$(( PX + ${c%,*} )) y=$(( PY + ${c#*,} ))
    (( x == PX && y == PY )) && continue
    p_walk "$CUR_MAP" "$x" "$y" || continue
    mon_at "$x" "$y" && continue
    AX=$x AY=$y; break
  done
  POS_DIRTY=1 MAP_DIRTY=1
}

aly_summon() {  # index [quiet]
  local i=$1
  aly_has "$i" || return
  ALLY=$i ALY_NEXT=$(( NOW + 600 )); aly_place
  [[ $2 == quiet ]] || logm "${ALY_E[i]} ${ALY_SHORT[i]} is at your side." "$K_GOOD"
}

aly_dismiss() {
  (( ALLY >= 0 )) || return
  logm "${ALY_SHORT[ALLY]} heads home for a rest." "$K_SYS"
  ALLY=-1 POS_DIRTY=1 MAP_DIRTY=1
}

aly_follow() {  # old-x old-y: called after every step I take
  (( ALLY >= 0 )) || return
  if [[ $ALY_MAP != "$CUR_MAP" ]]; then aly_place; return; fi
  cheb $(( AX - PX )) $(( AY - PY ))
  if (( D > 4 )); then aly_place
  elif (( D > 1 )); then AX=$1 AY=$2; fi
}

aly_target() {  # -> AT: what my ally should hit (my target, whoever hits me, foes right next to me)
  local m best=99
  AT=""
  for m in "$TARGET" "$ALY_LAST"; do
    [[ -n $m && -n ${CM_T[$m]} ]] && (( ${CM_HP[$m]:-1} > 0 )) && hostile "$m" || continue
    cheb $(( CM_X[m] - PX )) $(( CM_Y[m] - PY )); (( D <= 8 )) && { AT=$m; return 0; }
  done
  mons_rect $(( PX - 2 )) $(( PY - 2 )) $(( PX + 2 )) $(( PY + 2 ))
  for m in "${MR[@]}"; do                          # anything already fighting me at close range
    (( M_KIND[${CM_T[m]}] == 0 && M_AGGRO[${CM_T[m]}] > 0 )) || continue
    cheb $(( CM_X[m] - PX )) $(( CM_Y[m] - PY )); (( D <= 2 && D < best )) && { best=$D; AT=$m; }
  done
  [[ -n $AT ]]
}

aly_step_to() {  # x y: one step towards it, never too far from me
  local dx=$(( $1 - AX )) dy=$(( $2 - AY )) sx sy c nx ny
  sx=$(( dx > 0 ? 1 : (dx < 0 ? -1 : 0) )) sy=$(( dy > 0 ? 1 : (dy < 0 ? -1 : 0) ))
  for c in "$sx,$sy" "$sx,0" "0,$sy" "$sx,1" "$sx,-1" "1,$sy" "-1,$sy" 0,1 0,-1 1,0 -1,0; do
    nx=$(( AX + ${c%,*} )) ny=$(( AY + ${c#*,} ))
    (( nx == AX && ny == AY )) && continue
    (( nx == PX && ny == PY )) && continue
    p_walk "$CUR_MAP" "$nx" "$ny" || continue
    mon_at "$nx" "$ny" && continue
    cheb $(( nx - PX )) $(( ny - PY )); (( D <= 5 )) || continue
    AX=$nx AY=$ny POS_DIRTY=1 MAP_DIRTY=1; return 0
  done
  return 1
}

aly_hit() {  # mid pct
  local m=$1 d
  [[ -n ${CM_T[$m]} ]] || return
  d=$(( ATK * $2 / 100 * (100 + ${TB_ALY:-0}) / 100 * (85 + RANDOM % 31) / 100 )); (( d < 1 )) && d=1
  (( RANDOM % 100 < 8 )) && d=$(( d * 2 ))
  send HIT "$MY_ID" "$CUR_MAP" "$m" "$d" 0
  CM_HP[$m]=$(( CM_HP[$m] - d )); (( CM_HP[$m] < 0 )) && CM_HP[$m]=0
  HITF[$m]=$NOW
  ft_add "${CM_X[$m]}" "${CM_Y[$m]}" "$d" $'\e[0;1;38;5;16;48;5;78m'
}

aly_tick() {
  (( ALLY >= 0 && ! DEAD && NOW >= ALY_NEXT )) || return
  [[ $ALY_MAP == "$CUR_MAP" ]] || { aly_place; return; }
  cheb $(( AX - PX )) $(( AY - PY )); (( D > 6 )) && { aly_place; return; }     # after a respawn, recall or waystone
  local i=$ALLY role=${ALY_ROLE[$ALLY]} m n h
  ALY_NEXT=$(( NOW + 250 ))
  if [[ $role == heal ]] && (( HP < MAXHP * 85 / 100 && NOW >= ALY_HEALT )); then
    heal_amount; h=$(( HEALV * 55 / 100 + MAXHP / 12 ))
    HP=$(( HP + h )); (( HP > MAXHP )) && HP=$MAXHP
    ft_add "$PX" "$PY" "+$h" $'\e[0;1;38;5;16;48;5;120m'
    add_fx holy "$PX,$PY" 1
    ALY_HEALT=$(( NOW + 4000 )) ALY_NEXT=$(( NOW + ALY_CD[i] )) POS_DIRTY=1 MAP_DIRTY=1
    return
  fi
  aly_target || return
  m=$AT
  cheb $(( CM_X[m] - AX )) $(( CM_Y[m] - AY ))
  if (( D > ALY_RNG[i] )); then                     # walk over (melee) or close in (ranged)
    aly_step_to "${CM_X[m]}" "${CM_Y[m]}"; ALY_NEXT=$(( NOW + 220 )); return
  fi
  aly_hit "$m" "${ALY_PCT[i]}"
  case $role in
    magic)                                           # splash: everything next to the target
      mons_rect $(( CM_X[m] - 1 )) $(( CM_Y[m] - 1 )) $(( CM_X[m] + 1 )) $(( CM_Y[m] + 1 ))
      for n in "${MR[@]}"; do
        [[ $n == "$m" ]] && continue
        cheb $(( CM_X[n] - CM_X[m] )) $(( CM_Y[n] - CM_Y[m] )); (( D <= 1 )) || continue
        hostile "$n" && aly_hit "$n" $(( ALY_PCT[i] * 60 / 100 ))
      done
      if (( i == 6 )); then add_fx fire "${CM_X[m]},${CM_Y[m]}" 1; else add_fx sound "${CM_X[m]},${CM_Y[m]}" 1; fi ;;
    ranged) add_fx bone "${CM_X[m]},${CM_Y[m]}" ;;
    *)      add_fx slash "${CM_X[m]},${CM_Y[m]}" 1 ;;
  esac
  ALY_NEXT=$(( NOW + ALY_CD[i] ))
  MAP_DIRTY=1
}

aly_key() {  # [y] panel: 1-8 call an ally, x sends it home
  case $1 in
    [0-9]|-|=) local k=${ALY_KEYS%%"$1"*} i
           i=${#k}
           if (( i >= NALY )); then return
           elif ! aly_has "$i"; then logm "You have not hired ${ALY_NAME[i]} yet." "$K_HURT"
           elif (( ALLY == i )); then aly_dismiss
           else aly_summon "$i"; fi ;;
    x|X) aly_dismiss ;;
  esac
}

ally_shop_key() {  # a mercenary's list: buy the companion with the number
  local i n=0 k
  for (( i = 0; i < NALY; i++ )); do
    (( ALY_SELL[i] == TALK_T )) || continue
    n=$(( n + 1 )); [[ $1 == "$n" ]] || continue
    if aly_has "$i"; then logm "${ALY_SHORT[i]} already travels with you - call them with [y]." "$K_SYS"; return; fi
    (( GOLD >= ALY_COST[i] )) || { logm "${ALY_SHORT[i]} costs ${ALY_COST[i]} gold." "$K_HURT"; return; }
    GOLD=$(( GOLD - ALY_COST[i] )); aly_unlock "$i"; save_char; return
  done
}

ui_allies() {
  local i st col n=0
  ui "  ALLIES - companions who fight at your side" "$K_LOOT$B"
  ui "  One ally walks with you at a time. Hire more from mercenaries in town." "$K_SYS"
  ui ""
  aly_fix
  local long=$(( VH >= NALY * 2 + 6 )) kc
  for (( i = 0; i < NALY; i++ )); do
    kc=${ALY_KEYS:i:1}
    if (( ALLY == i )); then st="with you" col=$K_GOOD
    elif aly_has "$i"; then st="ready" col=$K_CHAT
    elif (( ALY_SELL[i] >= 0 )); then st="hire: ${N_FULL[${ALY_SELL[i]}]}, ${ALY_COST[i]}g" col=$K_SYS
    else st="joins you on your story" col=$K_SYS; fi
    if (( TW2 )); then uix "  [$kc] ${GLYH[a$i]}$N ${col}$(printf '%-22s' "${ALY_NAME[i]}") $st$N" "  [$kc] xx $(printf '%-22s' "${ALY_NAME[i]}") $st"
    else uix "  [$kc] ${GLY[a$i]}$N ${col}$(printf '%-22s' "${ALY_NAME[i]}") $st$N" "  [$kc] x $(printf '%-22s' "${ALY_NAME[i]}") $st"; fi
    (( long )) && ui "        ${ALY_DESC[i]}" "$K_SYS"
  done
  ui ""
  ui "  [1-9 0 - =] call / send home   [x] send home   [y] or [esc] close" "$K_SYS"
}

ui_allyshop() {
  local i n=0
  [[ -n ${CM_T[$TALK_MID]} ]] || { UI=""; return; }
  ui "  ${N_FULL[$TALK_T]^^}'S COMPANIONS" "$K_LOOT$B"
  ui "  You have ${EMJ[gold]}$GOLD gold. Hired allies follow you forever - [y] calls them."
  ui ""
  aly_fix
  for (( i = 0; i < NALY; i++ )); do
    (( ALY_SELL[i] == TALK_T )) || continue
    n=$(( n + 1 ))
    local h="" row; aly_has "$i" && h="  - hired"
    printf -v row '%-22s %6sg%s' "${ALY_NAME[i]}" "${ALY_COST[i]}" "$h"
    if (( TW2 )); then uix "  [$n] ${GLYH[a$i]}$N $row" "  [$n] xx $row"
    else ui "  [$n] ${ALY_G[i]} $row"; fi
    ui "        ${ALY_DESC[i]}  (${ALY_ROLE[i]})" "$K_SYS"
  done
  ui ""
  ui "  [1-$n] hire   [esc] leave" "$K_SYS"
}

# ---------------------------------------------------------------------------
#  Module 04f - story (since v2.0): the Shattered Crown, 24 chapters through
#  every town. Chapters are data (ST_* in 01b_content.sh); this is the engine.
# ---------------------------------------------------------------------------
STORY=0 STORY_P=0 STORY_SEEN=0 ST_POP_T="" ST_POP_A="" ST_POP_R="" ST_POP_B="" ST_POP_C=""

st_obj() {  # chapter -> SO_K (T/D/K) SO_A SO_N
  local o=${ST_OBJ[$1]}
  IFS=. read -r SO_K SO_A SO_N <<< "$o"; SO_N=${SO_N:-1}
}

st_info() {  # chapter -> STXT (what to do) SWHERE STX STY
  st_obj "$1"
  STX="" STY="" SWHERE=""
  case $SO_K in
    T) STXT="Talk to ${N_FULL[$SO_A]}" SWHERE=${N_HOME[$SO_A]:-${MW_NAME[$SO_A]}} STX=${MW_X[$SO_A]} STY=${MW_Y[$SO_A]} ;;
    D) STXT="Clear the ${D_NAME[$SO_A]}" SWHERE=${D_WHERE[$SO_A]} STX=${D_ENTX[$SO_A]} STY=${D_ENTY[$SO_A]} ;;
    K) STXT="Slay $SO_N ${M_NAME[$SO_A]}s ($STORY_P/$SO_N)" SWHERE=${MW_NAME[$SO_A]} STX=${MW_X[$SO_A]} STY=${MW_Y[$SO_A]} ;;
  esac
}

story_active() { (( STORY < NST && LVL >= ST_LVL[STORY] )); }
story_npc() { story_active && [[ ${ST_OBJ[STORY]} == "T.$1" ]]; }      # npc type -> 0 if the story wants me there

story_reward() {  # chapter -> grants its reward, sets ST_POP_R
  local r=${ST_REW[$1]} code
  ST_POP_R="+${ST_XP[$1]} XP  +${ST_GOLD[$1]} gold"
  case $r in
    A.*) aly_unlock "${r#A.}"; ST_POP_R+="  -  ally: ${ALY_NAME[${r#A.}]}" ; return ;;
    U.*) code=$r ;;
    G.W.*) code="W.${DEFW[CLS]}.${r#G.W.}.3" ;;
    G.A.*) code="A.${DEFA[CLS]}.${r#G.A.}.3" ;;
    G.J.*) code="J.$(( RANDOM % 4 )).${r#G.J.}.3" ;;
    *) return ;;
  esac
  item_name "$code" "$CLS"
  ST_POP_R+="  -  $INAME"
  if (( ${#INV[@]} < BAGS )); then INV+=("$code"); NEWG[$code]=1
  else BANK+=("$code"); ST_POP_R+=" (bags full - sent to your bank vault)"; fi
}

story_complete() {
  local s=$STORY
  ST_POP_T="★ CHAPTER $(( s + 1 )) COMPLETE: ${ST_TITLE[s]}"
  ST_POP_A=${ST_DONE[s]}
  STORY=$(( s + 1 )) STORY_P=0
  story_reward "$s"
  GOLD=$(( GOLD + ST_GOLD[s] ))
  logm "${EMJ[quest]}STORY: ${ST_TITLE[s]} complete! +${ST_XP[s]} XP +${ST_GOLD[s]} gold" "$K_ANN"
  gain_xp "${ST_XP[s]}"
  if (( STORY < NST )); then
    ST_POP_B="CHAPTER $(( STORY + 1 )): ${ST_TITLE[STORY]}"
    ST_POP_C=${ST_TEXT[STORY]}
    (( LVL < ST_LVL[STORY] )) && ST_POP_C+="  (Reach level ${ST_LVL[STORY]} to begin this chapter.)"
    send EVT "$MY_ID" "$MY_NAME" "finished the chapter '${ST_TITLE[s]}'."
  else
    ST_POP_B="THE SHATTERED CROWN - COMPLETE"
    ST_POP_C="You are the Crownbearer. The world is yours to wander - the bosses still hunt, the uniques still wait."
    send EVT "$MY_ID" "$MY_NAME" "finished the story of the Shattered Crown! All hail the Crownbearer!"
  fi
  UI=story MAP_DIRTY=1
  save_char
}

story_event() {  # T npc | D dungeon | K monster -> 0 if it moved the story on
  story_active || return 1
  st_obj "$STORY"
  [[ $1 == "$SO_K" && $2 == "$SO_A" ]] || return 1
  if [[ $SO_K == K ]]; then
    STORY_P=$(( STORY_P + 1 ))
    if (( STORY_P < SO_N )); then
      (( STORY_P % 3 == 0 )) && logm "★ Story: ${M_NAME[$SO_A]}s $STORY_P/$SO_N" "$K_LOOT"
      return 1
    fi
  fi
  story_complete
}

story_intro() {  # first login: the dream
  (( STORY == 0 && STORY_SEEN == 0 )) || return
  STORY_SEEN=1
  ST_POP_T="★ THE SHATTERED CROWN"
  ST_POP_A=${ST_TEXT[0]} ST_POP_R=""
  ST_POP_B="CHAPTER 1: ${ST_TITLE[0]}"
  ST_POP_C="Old Tom runs the inn in the north-east corner of Hearthmoor. Press [q] any time to see where your story goes next."
  UI=story MAP_DIRTY=1
}

story_levelup() {
  (( STORY < NST && LVL == ST_LVL[STORY] )) || return
  st_info "$STORY"
  logm "★ New story chapter: ${ST_TITLE[STORY]} - $STXT. See [q]." "$K_ANN"
}

story_line() {  # -> SL (one line for the side panel) or empty
  SL=""
  (( STORY < NST )) || return
  if (( LVL < ST_LVL[STORY] )); then SL="★ ${ST_TITLE[STORY]}: level ${ST_LVL[STORY]}"; return; fi
  st_info "$STORY"; QTX=$STX QTY=$STY; track
  SL="★ $STXT ${K_SYS}$TRK"
}

ui_wrap() {  # text color [indent]
  local rest=$1 w=$(( VW - 6 )) cut
  while (( ${#rest} > w )); do
    cut=${rest:0:w}; cut=${cut% *}; (( ${#cut} < 10 )) && cut=${rest:0:w}
    ui "  ${3:-}$cut" "$2"; rest=${rest:${#cut}}; rest=${rest# }
  done
  [[ -n $rest ]] && ui "  ${3:-}$rest" "$2"
}

ui_story() {
  local roomy=$(( VH >= 26 ))
  (( roomy )) && ui ""
  ui "  $ST_POP_T" "$K_LOOT$B"
  ui ""
  ui_wrap "$ST_POP_A" "$K_CHAT"
  [[ -n $ST_POP_R ]] && { (( roomy )) && ui ""; ui_wrap "$ST_POP_R" "$K_GOOD"; }
  if [[ -n $ST_POP_B ]]; then
    ui ""; (( roomy )) && ui ""
    ui "  $ST_POP_B" "$K_ANN"
    (( roomy )) && ui ""
    ui_wrap "$ST_POP_C" "$K_NPC"
  fi
  ui ""; (( roomy )) && ui ""
  ui "  [enter] continue" "$K_SYS"
}

story_qlog() {  # the story block on top of the quest log
  (( STORY < NST )) || { ui "  ★ THE SHATTERED CROWN - complete. All hail the Crownbearer!" "$K_LOOT$B"; ui ""; return; }
  ui "  ★ STORY - Chapter $(( STORY + 1 ))/$NST: ${ST_TITLE[STORY]}" "$K_LOOT$B"
  if (( LVL < ST_LVL[STORY] )); then
    ui "          Reach level ${ST_LVL[STORY]} to continue the story." "$K_SYS"
  else
    st_info "$STORY"; QTX=$STX QTY=$STY; track
    ui "          $STXT" "$K_CHAT"
    ui "          where: $SWHERE${TRK:+   ->  $TRK}" "$K_SYS"
  fi
  ui "          reward: ${ST_XP[STORY]} XP, ${ST_GOLD[STORY]} gold${ST_REW[STORY]:+ and something special}" "$K_SYS"
  ui ""
}

# ---------------------------------------------------------------------------
#  Module 04g - v3.0 client mechanics: talents, elements and resistances,
#  status effects, champions, gems and sockets, reputation, and quests 2.0
#  (collect / deliver / scout / bounty objectives and the town questlines).
# ---------------------------------------------------------------------------

# === talents ==================================================================================
TAL=000000000000 CASTK=-1 DEAL_EL=0
tal_fix() { [[ $TAL =~ ^[0-5]{12}$ ]] || TAL=000000000000; }
TP_K=""
tal_points() {  # -> TSPENT TFREE TTREE[0..2] (cached: the panel asks every frame)
  [[ $TP_K == "$TAL.$LVL" ]] && return
  TP_K="$TAL.$LVL"
  local i r
  TSPENT=0 TTREE=(0 0 0)
  for (( i = 0; i < 12; i++ )); do r=${TAL:i:1}; TSPENT=$(( TSPENT + r )); TTREE[i/4]=$(( TTREE[i/4] + r )); done
  TFREE=$(( LVL - 1 - TSPENT )); (( TFREE < 0 )) && TFREE=0
  (( TFREE > 36 - TSPENT )) && TFREE=$(( 36 - TSPENT ))      # v4.0: level 40 has more points than talents
}
tal_can() {  # i -> 0 if a point can go there; TWHY says why not
  local i=$1 r=${TAL:$1:1}
  tal_points; TWHY=""
  if (( TFREE <= 0 )); then TWHY="no free points - you get one every level"
  elif (( r >= TL_MAX[i % 4] )); then TWHY="already mastered"
  elif (( TTREE[i / 4] - r < TL_REQ[i % 4] )); then TWHY="needs ${TL_REQ[i % 4]} points in ${TL_TREE[CLS * 3 + i / 4]}"
  fi
  [[ -z $TWHY ]]
}
tal_learn() {  # i
  tal_can "$1" || { logm "Can't learn that: $TWHY." "$K_SYS"; return 1; }
  TAL="${TAL:0:$1}$(( ${TAL:$1:1} + 1 ))${TAL:$1+1}"
  calc_stats
  logm "You learn ${TL_NAME[CLS * 12 + $1]} (rank ${TAL:$1:1})." "$K_GOOD"
}
tal_reset_cost() { TRC=$(( 30 * LVL * LVL / 4 + 50 )); }
tal_reset() {
  tal_reset_cost
  (( GOLD >= TRC )) || { TALK_LINE="Unlearning costs $TRC gold. Come back when your purse is heavier."; return; }
  GOLD=$(( GOLD - TRC )); TAL=000000000000 PARA_P="0 0 0 0 0 0"; calc_stats
  TALK_LINE="A good night's sleep and a strong drink: your talents are forgotten. ($TRC gold)"
  logm "Your talents are reset - spend your points again with [x]." "$K_GOOD"
}
tal_desc() {  # i -> TD (what one rank does)
  local fx=${TL_FX[CLS * 12 + $1]} k v
  k=${fx%%:*} v=${fx#*:}
  case $k in
    dmg) TD="+$v% damage" ;; crit) TD="+$v% critical chance" ;; cdmg) TD="+$v% critical damage" ;;
    hp) TD="+$v% max HP" ;; mp) TD="+$v% max MP" ;; arm) TD="+$v armor" ;; res) TD="+$v% all resistances" ;;
    dodge) TD="+$v% dodge" ;; block) TD="+$v% block (with a shield)" ;; regen) TD="+$v% regeneration" ;;
    ls) TD="$v% of your damage heals you" ;; melee) TD="+$v% attack damage" ;;
    sk[0-2]) TD="+$v% ${S_NAME[CLS * 3 + ${k:2}]} damage" ;; cd[0-2]) TD="-$v% ${S_NAME[CLS * 3 + ${k:2}]} cooldown" ;;
    cdall) TD="-$v% all cooldowns" ;; mpc) TD="-$v% mana cost" ;; el[0-6]) TD="+$v% ${EL_NAME[${k:2}]} damage" ;;
    dot) TD="+$v% damage over time" ;; heal) TD="+$v% healing" ;; aly) TD="+$v% ally damage" ;;
    speed) TD="+$v% move speed" ;; pot) TD="+$v% potion strength" ;; thorns) TD="$v% of melee damage reflected" ;;
    cap) TD=${CAP_DESC[$v]} ;; *) TD=$fx ;;
  esac
}
TC_K=""
tal_calc() {  # -> TB_* bonuses and CAPS from the learned talents (cached per class and talents)
  [[ $TC_K == "$CLS.$TAL.$PARA_P" ]] && return
  tal_fix; TC_K="$CLS.$TAL.$PARA_P"
  local i r fx k v
  TB_DMG=0 TB_CRIT=0 TB_CDMG=0 TB_HP=0 TB_MP=0 TB_ARM=0 TB_RES=0 TB_DODGE=0 TB_BLOCK=0 TB_REGEN=0 TB_LS=0
  TB_SK=(0 0 0) TB_CD=(0 0 0) TB_CDALL=0 TB_MPC=0 TB_MELEE=0 TB_EL=(0 0 0 0 0 0 0) TB_DOT=0 TB_HEAL=0 TB_ALY=0
  TB_SPEED=0 TB_POT=0 TB_THORNS=0 CAPS=" "
  tal_fix
  for (( i = 0; i < 12; i++ )); do
    r=${TAL:i:1}; (( r )) || continue
    fx=${TL_FX[CLS * 12 + i]}; k=${fx%%:*} v=${fx#*:}
    case $k in
      cap) CAPS+="$v " ;;
      sk[0-2]) TB_SK[${k:2}]=$(( TB_SK[${k:2}] + v * r )) ;;
      cd[0-2]) TB_CD[${k:2}]=$(( TB_CD[${k:2}] + v * r )) ;;
      el[0-6]) TB_EL[${k:2}]=$(( TB_EL[${k:2}] + v * r )) ;;
      dmg) TB_DMG=$(( TB_DMG + v * r )) ;; crit) TB_CRIT=$(( TB_CRIT + v * r )) ;; cdmg) TB_CDMG=$(( TB_CDMG + v * r )) ;;
      hp) TB_HP=$(( TB_HP + v * r )) ;; mp) TB_MP=$(( TB_MP + v * r )) ;; arm) TB_ARM=$(( TB_ARM + v * r )) ;;
      res) TB_RES=$(( TB_RES + v * r )) ;; dodge) TB_DODGE=$(( TB_DODGE + v * r )) ;; block) TB_BLOCK=$(( TB_BLOCK + v * r )) ;;
      regen) TB_REGEN=$(( TB_REGEN + v * r )) ;; ls) TB_LS=$(( TB_LS + v * r )) ;; cdall) TB_CDALL=$(( TB_CDALL + v * r )) ;;
      mpc) TB_MPC=$(( TB_MPC + v * r )) ;; melee) TB_MELEE=$(( TB_MELEE + v * r )) ;; dot) TB_DOT=$(( TB_DOT + v * r )) ;;
      heal) TB_HEAL=$(( TB_HEAL + v * r )) ;; aly) TB_ALY=$(( TB_ALY + v * r )) ;; speed) TB_SPEED=$(( TB_SPEED + v * r )) ;;
      pot) TB_POT=$(( TB_POT + v * r )) ;; thorns) TB_THORNS=$(( TB_THORNS + v * r )) ;;
    esac
  done
  has_cap pack && TB_ALY=$(( TB_ALY + 50 ))
  has_cap evasion && TB_DODGE=$(( TB_DODGE + 10 ))
  has_cap thorns && TB_THORNS=$(( TB_THORNS + 30 ))
  has_cap lifelink && TB_LS=$(( TB_LS + 8 ))
  para_bonus                                                     # v4.5: paragon points
  TB_DMG=$(( TB_DMG + PB_DMG )) TB_HP=$(( TB_HP + PB_HP )) TB_CRIT=$(( TB_CRIT + PB_CRIT ))
  TB_RES=$(( TB_RES + PB_RES )) TB_MP=$(( TB_MP + PB_MP )) TB_CDALL=$(( TB_CDALL + PB_CD ))
}
has_cap() { [[ $CAPS == *" $1 "* ]]; }

# === gems and sockets ===============================================================================
sock_info() {  # code -> SN sockets, SF filled, SGEMS "r1 s2 __"
  local g=${1%!} i
  g=${g#*.*.*.*.}; [[ $g == "${1%!}" || $1 == U.* || $1 == B.* ]] && g=""
  SN=$(( ${#g} / 2 )) SF=0 SGEMS=""
  for (( i = 0; i < SN; i++ )); do SGEMS+="${g:i*2:2} "; [[ ${g:i*2:1} != _ ]] && SF=$(( SF + 1 )); done
}
gem_of() {  # "r2" -> GK (kind index) GQ (grade) GV (value) GFXK (effect)
  local i
  GK=-1 GQ=${1:1:1} GV=0 GFXK=""
  for (( i = 0; i < 6; i++ )); do [[ ${GEM_L[i]} == "${1:0:1}" ]] && GK=$i; done
  (( GK >= 0 )) || return 1
  local v=(${GEM_V[GK]}); GV=${v[GQ-1]} GFXK=${GEM_FX[GK]}
}
gems_txt() {  # code -> GTX: the sockets as icons (empty: ◇)
  local s
  sock_info "$1"; GTX=""
  for s in $SGEMS; do if [[ $s == __ ]]; then GTX+="◇"; else gem_of "$s"; GTX+=${GEM_E[GK]}; fi; done
}
gems_plain() {  # code -> GPL: "+6% dmg, +4 crit" for item cards
  local s
  sock_info "$1"; GPL=""
  for s in $SGEMS; do
    [[ $s == __ ]] && continue
    gem_of "$s"
    case $GFXK in dmg) GPL+="+$GV% dmg, " ;; mp) GPL+="+$GV% MP, " ;; crit) GPL+="+$GV% crit, " ;;
      arm) GPL+="+$GV armor, " ;; hp) GPL+="+$GV% HP, " ;; res) GPL+="+$GV% resist, " ;; esac
  done
  GPL=${GPL%, }
}
gem_bonus() {  # gear worn -> G_DMG G_MP G_CRIT G_ARM G_HP G_RES
  local c s
  G_DMG=0 G_MP=0 G_CRIT=0 G_ARM=0 G_HP=0 G_RES=0
  for c in "$EQW" "$EQA" "$EQO" "$EQH" "$EQJ"; do
    [[ $c == *.*.*.*.* ]] || continue
    item_stats "$c"; [[ $ICLS == *"$CLS"* ]] || continue
    sock_info "$c"
    for s in $SGEMS; do
      [[ $s == __ ]] && continue
      gem_of "$s" || continue
      case $GFXK in dmg) G_DMG=$(( G_DMG + GV )) ;; mp) G_MP=$(( G_MP + GV )) ;; crit) G_CRIT=$(( G_CRIT + GV )) ;;
        arm) G_ARM=$(( G_ARM + GV )) ;; hp) G_HP=$(( G_HP + GV )) ;; res) G_RES=$(( G_RES + GV )) ;; esac
    done
  done
}
sock_set() {  # code index gem|__ -> CODE2: the code with that socket changed
  local c=${1%!} lock="" g pre
  [[ $1 == *! ]] && lock="!"
  g=${c#*.*.*.*.}; pre=${c%".$g"}
  g="${g:0:$2*2}$3${g:$2*2+2}"
  CODE2="$pre.$g$lock"
}
sock_add() {  # code -> CODE2 with one more empty socket
  local c=${1%!} lock=""
  [[ $1 == *! ]] && lock="!"
  if [[ $c == *.*.*.*.* ]]; then CODE2="$c""__$lock"; else CODE2="$c.__$lock"; fi
}
sock_cost() {  # code -> SKC gold for the next socket (0 = not possible)
  item_stats "$1"; sock_info "$1"; SKC=0
  [[ -n $IUQ || $IK == B ]] && return
  (( SN < SOCK_MAX[IRR] )) || return
  SKC=$(( (IT * IT * 40 + 200) * (SN + 1) ))
}

# === elements, damage and status effects ==========================================================
mname() {  # mid -> MN: "Vampiric Wolf" for champions
  local t=${CM_T[$1]}
  [[ -n $t ]] || { MN="Something"; return; }                     # (a monster this client does not know about yet)
  MN=${N_FULL[$t]:-${M_NAME[t]}}
  (( ${CM_CH[$1]:-0} )) && MN="${CHP_NAME[CM_CH[$1]-1]} $MN"
}
el_mult() {  # monster-type element -> EM (% damage the monster takes)
  EM=100
  (( M_WK[$1] == $2 )) && EM=150
  (( M_RS[$1] == $2 )) && EM=50
}
# PS_UNTIL[i] for poisoned bleeding burning chilled stunned weakened; PS_DMG[i] per tick
PS_UNTIL=(0 0 0 0 0 0) PS_DMG=(0 0 0 0 0 0) PS_IMM=0 LS_READY=0 BARRIER=0 BARRIER_T=0 EVPROC=0 FRENZY=0 FRENZY_T=0 SMH=0
declare -A FROZEN=()
pst_apply() {  # effect source-dmg
  local i r=$(( RES / 2 ))
  case $1 in poison) i=0 ;; bleed) i=1 ;; burn) i=2 ;; chill) i=3 ;; stun) i=4 ;; weaken) i=5 ;; *) return ;; esac
  (( RANDOM % 100 < r )) && { logm "You shrug off being ${PS_NAME[i]}." "$K_GOOD"; return; }
  case $i in
    0) PS_UNTIL[0]=$(( NOW + 5000 )) PS_DMG[0]=$(( $2 * 22 / 100 + 1 )) ;;
    1) PS_UNTIL[1]=$(( NOW + 4000 )) PS_DMG[1]=$(( $2 * 28 / 100 + 1 )) ;;
    2) PS_UNTIL[2]=$(( NOW + 3000 )) PS_DMG[2]=$(( $2 * 35 / 100 + 1 )) ;;
    3) PS_UNTIL[3]=$(( NOW + 3000 )) ;;
    4) (( NOW < PS_IMM )) && return
       PS_UNTIL[4]=$(( NOW + 1200 )) PS_IMM=$(( NOW + 7000 )) ;;
    5) PS_UNTIL[5]=$(( NOW + 6000 )) ;;
  esac
  (( i < 3 )) && PS_DMG[i]=$(( PS_DMG[i] * (100 - RES) / 100 + 1 ))
  logm "You are ${PS_NAME[i]}!" "$K_HURT"
}
pst_tick() {  # once a second: damage over time on me
  local i d=0
  for i in 0 1 2; do (( NOW < PS_UNTIL[i] )) && d=$(( d + PS_DMG[i] )); done
  (( d )) || return
  HP=$(( HP - d )); POS_DIRTY=1 MAP_DIRTY=1
  ft_add "$PX" "$PY" "-$d" $'\e[0;38;5;141;48;5;234m'
  (( HP <= 0 )) && die_now "your wounds"
}
pst_clear() {  # [all|poison] cure
  if [[ $1 == all ]]; then PS_UNTIL=(0 0 0 0 0 0); else PS_UNTIL[0]=0 PS_UNTIL[1]=0; fi
}
stunned() { (( NOW < PS_UNTIL[4] )) && { (( NOW - ${STUN_MSG:-0} > 700 )) && { logm "You are stunned!" "$K_HURT"; STUN_MSG=$NOW; }; return 0; }; return 1; }
die_now() {  # killer: shared by blows and damage over time
  (( DEAD )) && return
  if has_cap laststand && (( NOW >= LS_READY )); then
    HP=1 LS_READY=$(( NOW + 90000 )) immune_until=$(( NOW + 3000 ))
    logm "LAST STAND! You refuse to fall." "$K_GOOD"; return
  fi
  HP=0 DEAD=1 dead_until=$(( NOW + 5000 )); DEATHS=$(( DEATHS + 1 )) UI=""
  PS_UNTIL=(0 0 0 0 0 0)
  local lost=$(( GOLD / 10 )); GOLD=$(( GOLD - lost ))
  logm "${EMJ[death]}You were slain by $1! You lose $lost gold. Respawning in town..." "$K_HURT"
  send EVT "$MY_ID" "$MY_NAME" "was slain by $1."
  MAP_DIRTY=1
}
v3_tick() {  # once a second
  pst_tick
  if has_cap barrier && (( NOW >= BARRIER_T )); then BARRIER=$(( MAXHP * 15 / 100 )) BARRIER_T=$(( NOW + 20000 )); fi
  if has_cap aura || has_cap deathaura; then
    local m el=5; has_cap deathaura && el=4
    mons_within 1
    for m in "${MLIST[@]}"; do DEAL_EL=$el; deal "$m" 15 0 q; done; DEAL_EL=0
  fi
  [[ $CUR_MAP == W ]] && ql_explore
  chain_npcs
}

# === reputation ==================================================================================
REP=(0 0 0 0 0 0 0 0)
rep_fix() { local i; for (( i = 0; i < NFAC; i++ )); do [[ ${REP[i]} =~ ^-?[0-9]+$ ]] || REP[i]=0; done; }   # v4.0: eight factions
rep_rank() {  # faction -> RR (-1 unfriendly, 0 neutral ... 4 exalted)
  local v=${REP[$1]} i
  RR=0; (( v < 0 )) && { RR=-1; return; }
  for i in 1 2 3 4; do (( v >= REP_RANK[i] )) && RR=$i; done
}
rep_add() {  # faction amount
  local f=$1 a=$2 old
  [[ $f =~ ^[0-9]$ ]] && (( f < NFAC )) || return
  rep_rank "$f"; old=$RR
  REP[f]=$(( REP[f] + a )); (( REP[f] < -6000 )) && REP[f]=-6000; (( REP[f] > 21000 )) && REP[f]=21000
  local fe=""; (( TW2 )) && fe="${FAC_E[f]} "
  if (( a >= 0 )); then logm "$fe${FAC_NAME[f]}: +$a reputation" $'\e['"${FAC_COL[f]}m"
  else logm "$fe${FAC_NAME[f]}: $a reputation" "$K_HURT"; fi
  rep_rank "$f"
  if (( RR > old )); then logm "${fe}You are now ${REP_NAME[RR]} with the ${FAC_NAME[f]}!" "$K_ANN"
  elif (( RR < old )); then logm "${fe}The ${FAC_NAME[f]} think less of you." "$K_HURT"; fi
}
fac_at() {  # x y -> FA (faction of that place)
  region_of "$1" "$2"
  FA=${TOWN_FAC[$RNAME]:-${REGION_FAC[$RNAME]:-}}
  [[ -n $FA ]] && return
  case $RNAME in
    "Greenfield Meadows"|Whisperwood|Silverlake) FA=0 ;; "Mirefen Swamp"|"Stormcrag Foothills"|"Stormcrag Peaks"|"Ashen Wastes") FA=1 ;;
    "Saltwind Coast"|"Sunscorch Desert"|"Scorched Badlands") FA=2 ;; "Frostfang Tundra"|"Crystal Highlands") FA=3 ;;
    "Sapphire Isles"|"Emerald Jungle") FA=4 ;; *) FA=5 ;;
  esac
}
fac_of_npc() { [[ -n $1 ]] || { FA=-1; return; }; local h=${N_HOME[$1]:-${MW_NAME[$1]}}; FA=${TOWN_FAC[$h]:--1}; }   # npc type -> FA
rep_disc() {  # npc type -> DISC (% off in its shop)
  DISC=0; fac_of_npc "$1"; (( FA >= 0 )) || return
  rep_rank "$FA"; DISC=$(( RR * 5 ))
}

# === quests 2.0 ===================================================================================
qobj_parse() {  # "K.5.6" -> OT OA ON
  local r=${1#*.}
  OT=${1%%.*} OA=${r%%.*} ON=1; [[ $r == *.* ]] && ON=${r#*.}
}
qitem() { QIN=${QI_NAME[$1]:-${M_NAME[$1]} Trophy}; }       # monster type -> QIN
obj_text() {  # type target need have -> OTX (what to do) OWX OWY (where)
  local t=$1 a=$2 n=$3 h=$4
  OWX="" OWY=""
  case $t in
    K) OTX="Slay $n ${M_NAME[a]}s ($h/$n)" OWX=${MW_X[a]} OWY=${MW_Y[a]} ;;
    C) qitem "$a"; OTX="Collect $n ${QIN}s from ${M_NAME[a]}s ($h/$n)" OWX=${MW_X[a]} OWY=${MW_Y[a]} ;;
    B) OTX="Bounty: slay ${M_NAME[a]}" OWX=${MW_X[a]} OWY=${MW_Y[a]} ;;
    G) OTX="Bring $n ${MAT_NAME[a]} (${MATS[a]}/$n)" ;;
    E) OTX="Scout ${SPT_NAME[a]}" OWX=${SPT_X[a]} OWY=${SPT_Y[a]} ;;
    D) OTX="Clear the ${D_NAME[a]}" OWX=${D_ENTX[a]} OWY=${D_ENTY[a]} ;;
    T) OTX="Talk to ${N_FULL[$a]}" OWX=${MW_X[a]} OWY=${MW_Y[a]} ;;
  esac
}

# --- questlines: QLS one char per line (0 not started, 1-9 the step you are on, x done),
#     QLP progress per line, QLC the choices you made (- none, a, b)
QLS="" QLP=() QLC=""
ql_fix() {
  local i
  [[ $QLS =~ ^[0-9x]{$NQL}$ ]] || QLS=$(printf '%*s' "$NQL" '' | tr ' ' 0)
  [[ $QLC =~ ^[-ab]{$NQL}$ ]] || QLC=$(printf '%*s' "$NQL" '' | tr ' ' -)
  for (( i = 0; i < NQL; i++ )); do [[ ${QLP[i]} =~ ^[0-9]{1,4}$ ]] || QLP[i]=0; done
}
ql_step() {  # line -> QST (step index into QS_*, -1 if none active) QSI (1-based step)
  local c=${QLS:$1:1}
  QST=-1 QSI=0
  [[ $c == [1-9] ]] || return 1
  QSI=$c QST=$(( QL_S0[$1] + c - 1 ))
}
ql_ready() {  # line -> 0 if the active objective is done (talk to the turn-in person)
  ql_step "$1" || return 1
  qobj_parse "${QS_OBJ[QST]}"
  case $OT in
    G) (( MATS[OA] >= ON )) ;;
    T) return 1 ;;
    *) (( QLP[$1] >= ON )) ;;
  esac
}
ql_turnin_npc() {  # line -> QTN: who takes the active step
  ql_step "$1"; qobj_parse "${QS_OBJ[QST]}"
  QTN=${QL_NPC[$1]}; [[ $OT == T ]] && QTN=$OA
}
ql_reward_lvl() { QRL=$(( QL_LVL[$1] + QSI )); QRX=$(( (30 * QRL * QRL + 70 * QRL) * 18 / 100 )) QRG=$(( 20 * QRL + 40 )); }
ql_start() {  # line: begin with step 1
  QLS="${QLS:0:$1}1${QLS:$1+1}"; QLP[$1]=0
  ql_step "$1"; qobj_parse "${QS_OBJ[QST]}"; obj_text "$OT" "$OA" "$ON" 0
  logm "${EMJ[quest]}NEW QUESTLINE: ${QL_NAME[$1]} - $OTX" "$K_ANN"
  TALK_LINE=${QS_TXT[QST]}
}
ql_complete() {  # line: finish the active step (rewards), then a choice or the next step
  local l=$1
  ql_step "$l"; qobj_parse "${QS_OBJ[QST]}"
  [[ $OT == G ]] && MATS[OA]=$(( MATS[OA] - ON ))
  ql_reward_lvl "$l"
  logm "${EMJ[quest]}${QL_NAME[l]} ($QSI/${QL_N[l]}) COMPLETE - +$QRX XP +$QRG gold" "$K_ANN"
  TALK_LINE=${QS_DONE[QST]}
  GOLD=$(( GOLD + QRG )); gain_xp "$QRX"
  rep_add "${QL_FAC[l]}" "${QS_REP[QST]}"
  if [[ -n ${QS_CH[QST]} ]]; then QCH_L=$l UI=qchoice MAP_DIRTY=1; return; fi
  ql_next "$l"
}
ql_choose() {  # a|b
  local l=$QCH_L i=0 opt rew txt r
  [[ $1 == b ]] && i=1
  ql_step "$l"
  IFS='|' read -r -a opt <<< "${QS_CHR[QST]}"; rew=${opt[i]}
  IFS='|' read -r -a opt <<< "${QS_CHT[QST]}"; txt=${opt[i]}
  QLC="${QLC:0:$l}$1${QLC:$l+1}"
  logm "$txt" "$K_CHAT"
  for r in ${rew//,/ }; do grant "$r"; done
  UI=talk TALK_LINE=$txt
  [[ -n ${CM_T[$TALK_MID]} ]] || UI=""
  ql_next "$l"
}
grant() {  # one reward: rep:f:n gold:n gem:n pot:n epic:S uq:n
  local a=(${1//:/ }) i g
  case ${a[0]} in
    rep)  rep_add "${a[1]}" "${a[2]}" ;;
    gold) GOLD=$(( GOLD + a[1] )); logm "+${a[1]} gold" "$K_LOOT" ;;
    pot)  POT_H=$(( POT_H + a[1] )); logm "+${a[1]} health potions" "$K_LOOT" ;;
    gem)  for (( i = 0; i < a[1]; i++ )); do g=1; (( LVL >= 12 )) && g=2; (( LVL >= 22 )) && g=3; gem_mat $(( RANDOM % 6 )) "$g"; gem_get "$GM"; done ;;
    epic) epic_item "${a[1]}" 2 1; add_item "$ITEM" ;;
    uq)   valid_item "U.${a[1]}" && add_item "U.${a[1]}" ;;
  esac
}
epic_item() {  # slot rarity sockets [tier] -> ITEM: gear of your class at your level
  local s=$1 t=$4 k=0 i cls n
  [[ -n $t ]] || { tier_for "$LVL"; t=$TF; }
  case $s in W) n=${#WK_NAME[@]} ;; A) n=${#AK_NAME[@]} ;; O) n=${#OK_NAME[@]} ;; H) n=${#HK_NAME[@]} ;; *) n=${#JK_NAME[@]} ;; esac
  for (( i = 0; i < 40; i++ )); do
    k=$(( RANDOM % n ))
    case $s in W) cls=${WK_CLS[k]} ;; A) cls=${AK_CLS[k]} ;; O) cls=${OK_CLS[k]} ;; H) cls=${HK_CLS[k]} ;; *) cls=${JK_CLS[k]} ;; esac
    [[ $cls == *"$CLS"* ]] && break
  done
  ITEM="$s.$k.$t.$2"
  (( $3 > 0 )) && { ITEM+="."; for (( i = 0; i < $3; i++ )); do ITEM+="__"; done; }
}
gem_get() {  # material index: a gem goes into your materials
  MATS[$1]=$(( MATS[$1] + 1 )); MAT_NEW[$1]=$(( ${MAT_NEW[$1]:-0} + 1 ))
  mat_icon "$1"
  logm "${EMJ[loot]}Gem: $MI${MI:+ }${MAT_NAME[$1]} - set it into a socket at any smith" $'\e[1;38;5;213m'
}
ql_next() {  # line: move on to the next step (or finish the line)
  local l=$1 s
  s=$(( ${QLS:$l:1} + 1 ))
  if (( s > QL_N[l] )); then
    QLS="${QLS:0:$l}x${QLS:$l+1}"
    logm "${EMJ[quest]}QUESTLINE COMPLETE: ${QL_NAME[l]}!" "$K_ANN"
    send EVT "$MY_ID" "$MY_NAME" "completed the questline ${QL_NAME[l]}."
    return
  fi
  QLS="${QLS:0:$l}$s${QLS:$l+1}"; QLP[l]=0
  ql_step "$l"; qobj_parse "${QS_OBJ[QST]}"; obj_text "$OT" "$OA" "$ON" 0
  logm "${EMJ[quest]}${QL_NAME[l]} ($s/${QL_N[l]}): $OTX" "$K_LOOT"
  [[ $UI == qchoice ]] || TALK_LINE="${TALK_LINE} ${QS_TXT[QST]}"
}
ql_for_npc() {  # npc type -> QLN: the line this person gives (-1 none)
  local i
  QLN=-1; for (( i = 0; i < NQL; i++ )); do (( QL_NPC[i] == $1 )) && { QLN=$i; return 0; }; done
  return 1
}
chain_npc() { [[ $CHN == *" $1 "* ]]; }       # npc type -> questline business here (see chain_npcs)
ql_talk() {  # npc type: questline business when you talk to someone (T objectives complete here)
  local i
  for (( i = 0; i < NQL; i++ )); do
    ql_step "$i" || continue
    [[ ${QS_OBJ[QST]} == "T.$1" ]] && { ql_complete "$i"; return 0; }
  done
  return 1
}
ql_key() {  # [5] in a conversation with a questline giver
  local l
  ql_for_npc "$TALK_T" || return
  l=$QLN
  case ${QLS:l:1} in
    x) TALK_LINE="You have done more for us than anyone. Thank you, friend." ;;
    0) if (( LVL >= QL_LVL[l] )); then ql_start "$l"; else TALK_LINE="I may have work for you one day - come back at level ${QL_LVL[l]}."; fi ;;
    *) if ql_ready "$l"; then ql_complete "$l"
       else
         ql_step "$l"; qobj_parse "${QS_OBJ[QST]}"; obj_text "$OT" "$OA" "$ON" "${QLP[l]}"
         TALK_LINE="${QS_TXT[QST]} ($OTX)"
         [[ $OT == T ]] && TALK_LINE="Have you spoken to ${N_FULL[$OA]} yet?"
       fi ;;
  esac
}
ql_explore() {  # scouting objectives: are we there yet?
  local i q f
  for (( i = 0; i < NQL; i++ )); do
    ql_step "$i" || continue
    [[ ${QS_OBJ[QST]} == E.* ]] || continue
    (( QLP[i] )) && continue
    qobj_parse "${QS_OBJ[QST]}"
    cheb $(( SPT_X[OA] - PX )) $(( SPT_Y[OA] - PY )); (( D <= 3 )) || continue
    QLP[i]=1; logm "${EMJ[quest]}You found ${SPT_NAME[OA]}. Return to ${N_FULL[${QL_NPC[i]}]}." "$K_ANN"
  done
  for i in "${!QUESTS[@]}"; do
    q=${QUESTS[i]}; [[ $q == E.* ]] || continue
    IFS=. read -r -a f <<< "$q"
    cheb $(( SPT_X[f[1]] - PX )) $(( SPT_Y[f[1]] - PY )); (( D <= 3 )) || continue
    quest_done "$i"; return
  done
}
qev_kill() {  # monster type: kills, drops and bounties for quests and questlines
  local t=$1 i f q done=() n
  for (( i = 0; i < NQL; i++ )); do
    ql_step "$i" || continue
    qobj_parse "${QS_OBJ[QST]}"
    [[ $OA == "$t" && $OT == [KCB] ]] || continue
    (( QLP[i] >= ON )) && continue
    if [[ $OT == C ]] && (( RANDOM % 100 >= (M_BOSS[t] ? 100 : 50) )); then continue; fi
    QLP[i]=$(( QLP[i] + 1 ))
    if [[ $OT == C ]]; then qitem "$t"; logm "${EMJ[loot]}Quest item: $QIN (${QLP[i]}/$ON)" "$K_LOOT"; fi
    (( QLP[i] >= ON )) && logm "${EMJ[quest]}${QL_NAME[i]}: done - return to ${N_FULL[${QL_NPC[i]}]}." "$K_ANN"
  done
  for i in "${!QUESTS[@]}"; do
    IFS=. read -r -a f <<< "${QUESTS[i]}"
    [[ ${f[1]} == "$t" && ${f[0]} == [CB] ]] || continue
    if [[ ${f[0]} == C ]]; then
      (( RANDOM % 100 < (M_BOSS[t] ? 100 : 45) )) || continue
      qitem "$t"; f[3]=$(( f[3] + 1 )); logm "${EMJ[loot]}Quest item: $QIN (${f[3]}/${f[2]})" "$K_LOOT"
    else f[3]=1; fi
    QUESTS[i]="${f[0]}.${f[1]}.${f[2]}.${f[3]}.${f[4]}.${f[5]}"
    (( f[3] >= f[2] )) && done=("$i" "${done[@]}")
  done
  for i in "${done[@]}"; do quest_done "$i"; done
}
qev_dungeon() {  # dungeon type cleared
  local i
  for (( i = 0; i < NQL; i++ )); do
    ql_step "$i" || continue
    [[ ${QS_OBJ[QST]} == "D.$1" ]] || continue
    QLP[i]=1; logm "${EMJ[quest]}${QL_NAME[i]}: done - return to ${N_FULL[${QL_NPC[i]}]}." "$K_ANN"
  done
}
qev_board() {  # at a quest board: hand in materials for delivery quests
  local i f done=()
  for i in "${!QUESTS[@]}"; do
    [[ ${QUESTS[i]} == G.* ]] || continue
    IFS=. read -r -a f <<< "${QUESTS[i]}"
    (( MATS[f[1]] >= f[2] )) || continue
    MATS[f[1]]=$(( MATS[f[1]] - f[2] )); done=("$i" "${done[@]}")
  done
  for i in "${done[@]}"; do quest_done "$i"; done
}
quest_rep() {  # quest code: the faction of the place it helps gets reputation
  local f x="" y=""
  IFS=. read -r -a f <<< "$1"
  case ${f[0]} in
    K|C|B) x=${MW_X[f[1]]} y=${MW_Y[f[1]]} ;;
    D) x=${D_ENTX[f[1]]} y=${D_ENTY[f[1]]} ;;
    E) x=${SPT_X[f[1]]} y=${SPT_Y[f[1]]} ;;
    T) fac_of_npc "${f[1]}"; (( FA >= 0 )) && rep_add "$FA" $(( 60 + LVL * 8 )); return ;;
    G) x=$PX y=$PY ;;
  esac
  [[ -n $x ]] || return
  fac_at "$x" "$y"; rep_add "$FA" $(( 60 + LVL * 8 ))
}

# === faction quartermasters =========================================================================
wares_build() {  # npc type -> WR_* (what the faction sells), WR_F
  local f t
  fac_of_npc "$1"; WR_F=$FA
  WR_NAME=() WR_RANK=() WR_PRICE=() WR_CODE=()
  (( WR_F >= 0 )) || return
  tier_for "$LVL"; f=$WR_F t=$TF
  WR_NAME+=("Gem pouch (2 gems for your level)") WR_RANK+=(1) WR_PRICE+=($(( 300 + 40 * LVL ))) WR_CODE+=(gems)
  WR_NAME+=("${FAC_NAME[f]} armor (epic, 2 sockets)") WR_RANK+=(2) WR_PRICE+=($(( 2000 + 160 * LVL ))) WR_CODE+=(A)
  WR_NAME+=("${FAC_NAME[f]} weapon (epic, 1 socket)") WR_RANK+=(2) WR_PRICE+=($(( 2400 + 180 * LVL ))) WR_CODE+=(W)
  WR_NAME+=("${U_NAME[FAC_UQ0 + f]} (unique)") WR_RANK+=(3) WR_PRICE+=(12000) WR_CODE+=("U.$(( FAC_UQ0 + f ))")
  WR_NAME+=("Champion's weapon (legendary, 3 sockets)") WR_RANK+=(4) WR_PRICE+=(25000) WR_CODE+=(LW)
}
wares_buy() {  # index
  local i=$1
  wares_build "$TALK_T"
  (( i < ${#WR_NAME[@]} )) || return
  rep_rank "$WR_F"
  (( RR >= WR_RANK[i] )) || { logm "The ${FAC_NAME[WR_F]} only sell that to those they call ${REP_NAME[WR_RANK[i]]}." "$K_HURT"; return; }
  (( GOLD >= WR_PRICE[i] )) || { logm "Not enough gold." "$K_HURT"; return; }
  if [[ ${WR_CODE[i]} != gems ]] && (( ${#INV[@]} >= BAGS )); then logm "Your bags are full." "$K_HURT"; return; fi
  GOLD=$(( GOLD - WR_PRICE[i] ))
  case ${WR_CODE[i]} in
    gems) grant gem:2 ;;
    A) epic_item A 2 2; add_item "$ITEM" ;;
    W) epic_item W 2 1; add_item "$ITEM" ;;
    LW) epic_item W 3 3 9; add_item "$ITEM" ;;
    *) add_item "${WR_CODE[i]}" ;;
  esac
}

# ---------------------------------------------------------------------------
#  Module 05 - screen and input: layout, the map frame, side panel, log,
#  menus drawn inside the frame, key handling and the client / dedicated
#  server main loops. Frames only send the screen lines that changed (emit).
# ---------------------------------------------------------------------------
layout() {
  local s r c
  s=$(stty size 2>/dev/null); r=${s% *}; c=${s#* }
  isnum "$r" && (( r > 0 )) || r=40
  isnum "$c" && (( c > 0 )) || c=120
  ROWS=$r COLS=$c
  SMALL=$(( COLS < 100 || ROWS < 30 ))
  if (( TW == 2 )); then      # HD: tiles are 2 columns wide (and look square)
    VW=$(( (COLS - 44) / 2 )); (( VW > 45 )) && VW=45; (( VW % 2 )) || VW=$(( VW - 1 )); (( VW < 21 )) && VW=21
  else
    VW=$(( COLS - 44 )); (( VW > 81 )) && VW=81; (( VW % 2 )) || VW=$(( VW - 1 )); (( VW < 41 )) && VW=41
  fi
  VH=$(( ROWS - 10 )); (( VH > 31 )) && VH=31; (( VH % 2 )) || VH=$(( VH - 1 )); (( VH < 13 )) && VH=13
  MW=$(( VW * TW ))
  PCOL=$(( MW + 4 )) LOGY=$(( VH + 4 )) INPY=$(( VH + 10 ))
  printf -v BLANK '%*s' 240 ''
  NEED_FULL=1 MAP_DIRTY=1 WM_CZ="" CLIPC=()
  [[ $UI == map ]] && wm_open keep
}

# SCR[key] = what a screen line shows right now: a frame only sends the lines that changed
declare -A SCR=()
emit() { [[ ${SCR[$1]} == "$2" ]] && return; SCR[$1]=$2; out+=$2; }   # key text

draw_frame() {
  local bar r
  SCR=()
  printf -v bar '%*s' "$MW" ''; bar=${bar// /─}
  out+=$'\e[0m\e[2J'"$K_FRAME"$'\e[2;1H'"╭${bar}╮"
  for (( r = 3; r < VH + 3; r++ )); do out+=$'\e['"$r;1H│"$'\e['"$r;$(( MW + 2 ))H│"; done
  out+=$'\e['"$(( VH + 3 ));1H╰${bar}╯$N"
}

update_fog() {
  local map=$CUR_MAP mw=${MAPW[$CUR_MAP]} mh=${MAPH[$CUR_MAP]} dy y half x1 x2 real mem
  for (( dy = -LRY; dy <= LRY; dy++ )); do
    y=$(( PY + dy )); (( y < 0 || y >= mh )) && continue
    half=${LSPAN[dy+LRY]}; x1=$(( PX - half )) x2=$(( PX + half ))
    (( x1 < 0 )) && x1=0; (( x2 > mw - 1 )) && x2=$(( mw - 1 ))
    real=${MAPROW[$map:$y]} mem=${EXPL[$map:$y]}
    EXPL["$map:$y"]="${mem:0:x1}${real:x1:x2-x1+1}${mem:x2+1}"
  done
}

# compose lo hi item... : colorize ${row:lo..hi} and splice in glyphs/tags.
# item = "<x*10+prio>:<width>:<key>" ; key = glyph key in GLY, or t<n> for TAGS[n]
compose() {
  local lo=$1 hi=$2 pos=$1 it s x w k i j t arr=()
  shift 2
  for it in "$@"; do
    s=${it%%:*}; x=$(( s / 10 )); t=${it#*:}; w=${t%%:*}
    (( x >= lo && x + w - 1 <= hi )) && arr+=("$it")
  done
  for (( i = 1; i < ${#arr[@]}; i++ )); do
    t=${arr[i]}; j=$(( i - 1 ))
    while (( j >= 0 && ${arr[j]%%:*} > ${t%%:*} )); do arr[j+1]=${arr[j]}; j=$(( j - 1 )); done
    arr[j+1]=$t
  done
  COMP=""
  for it in "${arr[@]}"; do
    s=${it%%:*}; x=$(( s / 10 )); t=${it#*:}; w=${t%%:*}; k=${t#*:}
    (( x < pos )) && continue
    if (( LITMODE )) && [[ $k == m* ]] && ! is_lit "$x"; then continue; fi    # hidden in the dark
    if (( x > pos )); then CZ=${row:pos:x-pos}; PZ=$pos; paint; COMP+=$CZ; fi
    if [[ $k == t* ]]; then COMP+=${TAGS[${k#t}]}
    elif (( TW == 2 )); then                                   # sprite on the ground it stands on
      if (( LITMODE )) && ! is_lit "$x"; then COMP+="$Z_DARKBG${GLYH[$k]:-${GLY[$k]} }"
      else COMP+="${TBG[${row:x:1}]}${GLYH[$k]:-${GLY[$k]} }"; fi
    else COMP+=${GLY[$k]}; fi
    pos=$(( x + w ))
  done
  if (( pos <= hi )); then CZ=${row:pos:hi-pos+1}; PZ=$pos; paint; COMP+=$CZ; fi
}
paint() {  # colorize; night/storm: only the lit spans (LITR) get color; world map: grey sketch
  if (( COMP_DIM && TW == 2 )); then local Z_DARK=$'\e[0;38;5;240;48;5;234m'; dark_paint; return; fi
  if (( COMP_DIM )); then
    CZ=${CZ//[SNAI_:%KJDEqMHB]/.}; CZ=${CZ//[snF]/,}; CZ=${CZ//[PYWyU]/T}; CZ=${CZ//[LG]/'~'}; CZ=${CZ//[RCVX]/^}; CZ=${CZ//Z/.}; CZ=${CZ//[QO]/.}
    CZ="$Z_FOG$CZ"; return
  fi
  (( LITMODE )) || { colorize_at; return; }
  local s=$CZ p=$PZ e=$(( PZ + ${#CZ} - 1 )) iv a b hi o=""
  for iv in $LITR; do
    a=${iv%:*} b=${iv#*:}
    (( b < p )) && continue
    (( a > e )) && break
    if (( a > p )); then
      if (( TR_ON )); then dark_at "$p" $(( a - p )); else CZ=${s:0:a-p}; dark_paint; fi
      o+=$CZ; s=${s:a-p}; p=$a
    fi
    hi=$(( b < e ? b : e ))
    CZ=${s:0:hi-p+1}; PZ=$p; colorize_at; o+=$CZ; s=${s:hi-p+1}; p=$(( hi + 1 ))
    (( p > e )) && break
  done
  if (( p <= e )); then if (( TR_ON )); then dark_at "$p" "${#s}"; else CZ=$s; dark_paint; fi; o+=$CZ; fi
  CZ=$o
}

free_span() {  # row x len -> 0 if no item of that row overlaps
  local it s x t w
  for it in ${RI[$1]}; do
    s=${it%%:*}; x=$(( s / 10 )); t=${it#*:}; w=${t%%:*}
    (( x + w >= $2 && x <= $2 + $3 )) && return 1    # keep one cell distance to everything
  done
  return 0
}

add_tag() {  # dx dy text style - finds a free spot above/below, sliding sideways if needed
  local txt=" $3 " len tx t0 ty o x
  if (( TW == 2 )); then                      # HD: a tag covers whole tiles (2 columns each)
    dispw "$3"
    if (( ${#3} == 1 )); then if (( DW == 2 )); then txt=$3; else txt=" $3"; fi; fi   # lone emoji: exactly one tile
    dispw "$txt"; (( DW % 2 )) && { txt+=" "; DW=$(( DW + 1 )); }
    len=$(( DW / 2 ))
  else len=${#txt}; fi
  (( len > VW )) && return
  t0=$(( $1 - len / 2 ))
  for ty in $(( $2 - 1 )) $(( $2 + 1 )) $(( $2 - 2 )) $(( $2 + 2 )); do
    (( ty >= 0 && ty < VH )) || continue
    for (( o = 0; o <= len; o++ )); do
      for x in $(( t0 - o )) $(( t0 + o )); do
        tx=$x; (( tx < 0 )) && tx=0; (( tx > VW - len )) && tx=$(( VW - len ))
        (( tx <= $1 && tx + len > $1 )) || continue      # the tag must sit right above/below its owner
        free_span "$ty" "$tx" "$len" || continue
        TAGS+=("$4$txt$N"); RI[ty]+="$(( tx * 10 + 5 )):$len:t$(( ${#TAGS[@]} - 1 )) "
        return
      done
    done
  done
}

render_rows() {  # the terrain of every view row (+ sprites and tags); called by render_map
  # byte-wise string offsets are much faster - every string cut here is ASCII or a tile row cut by byte offsets
  local LC_ALL=C ry y row mem dy lx1 lx2
  TR_ON=1 TR_X0=$cx0 TR_W=$mw
  for (( ry = 0; ry < VH; ry++ )); do
    y=$(( cy0 + ry ))
    if (( y < 0 || y >= mh )); then emit "m$ry" $'\e['"$(( ry + 3 ));2H$N${BLANK:0:MW}"; continue; fi
    if (( TW == 2 )); then [[ -n ${VROW[$map:$y]} ]] || build_vrow "$map" "$y"; row=${VROW[$map:$y]}; else row=${MAPROW[$map:$y]}; fi
    tiles_row "$map" "$y"
    if (( cx0 < 0 )); then row="${BLANK:0:-cx0}$row"; row=${row:0:VW}; else row=${row:cx0:VW}; fi
    (( ${#row} < VW )) && row+=${BLANK:0:VW-${#row}}
    if (( dark )); then
      mem=${EXPL[$map:$y]}
      if (( cx0 < 0 )); then mem="${BLANK:0:-cx0}$mem"; mem=${mem:0:VW}; else mem=${mem:cx0:VW}; fi
      (( ${#mem} < VW )) && mem+=${BLANK:0:VW-${#mem}}
      mem=${mem//_/.}
      dy=$(( y - PY ))
      if (( dy >= -LRY && dy <= LRY )); then
        lx1=$(( PX - LSPAN[dy+LRY] - cx0 )) lx2=$(( PX + LSPAN[dy+LRY] - cx0 ))
        (( lx1 < 0 )) && lx1=0; (( lx2 > VW - 1 )) && lx2=$(( VW - 1 ))
        compose "$lx1" "$lx2" ${RI[ry]}
        CZ=${mem:0:lx1}; mem_paint; row=$CZ$COMP
        CZ=${mem:lx2+1}; mem_paint; row+=$CZ
      else
        CZ=$mem; mem_paint; row=$CZ
      fi
    else
      LITR=${LIT[ry]}
      compose 0 $(( VW - 1 )) ${RI[ry]}
      row=$COMP
    fi
    emit "m$ry" $'\e['"$(( ry + 3 ));2H$row"
  done
}

render_map() {
  local map=$CUR_MAP mw=${MAPW[$CUR_MAP]} mh=${MAPH[$CUR_MAP]} cx0 cy0 ry y row m dx dy p i txt
  local lx1 lx2 mem dark=0
  RI=() TAGS=()
  cx0=$(( PX - VW / 2 )) cy0=$(( PY - VH / 2 ))
  if (( mw > VW )); then (( cx0 < 0 )) && cx0=0; (( cx0 > mw - VW )) && cx0=$(( mw - VW )); else cx0=$(( (mw - VW) / 2 )); fi
  if (( mh > VH )); then (( cy0 < 0 )) && cy0=0; (( cy0 > mh - VH )) && cy0=$(( mh - VH )); else cy0=$(( (mh - VH) / 2 )); fi
  if (( TW == 2 )); then                       # rolling waves & bubbling lava
    if (( NOW / 700 % 2 )); then Z2_i=$WAVE Z2_j=$CALM; else Z2_i=$CALM Z2_j=$WAVE; fi
    if (( NOW / 450 % 2 )); then Z2_LAVA=$LAVA_A Z2_v=$LAVA_B; else Z2_LAVA=$LAVA_B Z2_v=$LAVA_A; fi
    TR_PH=$(( (NOW / 700 % 2) * 2 + NOW / 450 % 2 ))
  fi
  mons_rect "$cx0" "$cy0" $(( cx0 + VW - 1 )) $(( cy0 + VH - 1 )); local vis=("${MR[@]}")
  for m in "${vis[@]}"; do
    dx=$(( CM_X[m] - cx0 )) dy=$(( CM_Y[m] - cy0 ))
    if (( NOW - ${HITF[$m]:-0} < 160 )); then                  # flash red when hit
      i=${CM_T[m]}
      GLY[mx$m]=$'\e[0;1;38;5;231;48;5;196m'"${M_GLY[i]}" GLYH[mx$m]=$'\e[0;48;5;196m'"${MEMO[i]:-${M_GLY[i]} }"
      RI[dy]+="$(( dx * 10 + 3 )):1:mx$m "; MAP_DIRTY=1
    else
      RI[dy]+="$(( dx * 10 + 3 )):1:m${CM_T[m]} "
    fi
  done
  for p in "${!OP_MAP[@]}"; do
    [[ ${OP_MAP[$p]} == "$map" && -n ${GLY[p$p]} ]] || continue
    dx=$(( ${OP_X[$p]} - cx0 )) dy=$(( ${OP_Y[$p]} - cy0 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) && RI[dy]+="$(( dx * 10 + 2 )):1:p$p "
  done
  if (( ALLY >= 0 )) && [[ $ALY_MAP == "$map" ]]; then         # my ally, then everybody else's
    dx=$(( AX - cx0 )) dy=$(( AY - cy0 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) && RI[dy]+="$(( dx * 10 + 4 )):1:a$ALLY "
  fi
  for p in "${!OP_ALY[@]}"; do
    [[ ${OP_MAP[$p]} == "$map" ]] || continue
    dx=$(( ${OP_AX[$p]} - cx0 )) dy=$(( ${OP_AY[$p]} - cy0 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) && RI[dy]+="$(( dx * 10 + 4 )):1:a${OP_ALY[$p]} "
  done
  for i in "${!FX_E[@]}"; do
    if (( FX_E[i] < NOW )); then unset "FX_X[i]" "FX_Y[i]" "FX_K[i]" "FX_E[i]"; continue; fi
    dx=$(( FX_X[i] - cx0 )) dy=$(( FX_Y[i] - cy0 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) && RI[dy]+="$(( dx * 10 + ${FXP[${FX_K[i]}]:-0} )):1:f${FX_K[i]} "
  done
  [[ $map == W && -n $CW ]] && add_particles
  [[ $map == H* ]] && room_overlay "$cx0" "$cy0"               # v5.0: the furniture of a room
  if (( DEAD )); then GLY[self]=$'\e[0;38;5;240m'"$SYM" GLYH[self]=$'\e[0;48;5;238m💀'
  elif (( NOW - last_hurt < 180 )); then
    GLY[self]=$'\e[0;1;38;5;231;48;5;196m'"$SYM" GLYH[self]=$'\e[0;48;5;196m'"${CEMO[CLS]}"; MAP_DIRTY=1
  elif (( RIDING )); then GLY[self]=$'\e[0;1;7;38;5;'"${P_COLC[COLR]}m$SYM" GLYH[self]=$'\e[0;48;5;'"${P_COLC[COLR]}m${MNT_E[MNT_CUR]}"
  else GLY[self]=$'\e[0;1;7;38;5;'"${P_COLC[COLR]}m$SYM" GLYH[self]=$'\e[0;48;5;'"${P_COLC[COLR]}m${CEMO[CLS]}"; fi
  dx=$(( PX - cx0 )) dy=$(( PY - cy0 )); RI[dy]+="$(( dx * 10 + 1 )):1:self "
  ft_items "$cx0" "$cy0"; hp_tag "$cx0" "$cy0"
  # name tags & chat bubbles (only for players that are actually visible)
  for p in "${!OP_MAP[@]}"; do
    [[ ${OP_MAP[$p]} == "$map" ]] || continue
    dx=$(( ${OP_X[$p]} - cx0 )) dy=$(( ${OP_Y[$p]} - cy0 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) || continue
    if [[ $map == D* ]]; then cheb $(( ${OP_X[$p]} - PX )) $(( ${OP_Y[$p]} - PY )); (( D <= LRY )) || continue; fi
    if (( ${OP_SAYT[$p]:-0} > NOW )); then
      add_tag "$dx" "$dy" "${OP_SAY[$p]:0:26}" $'\e[0;38;5;16;48;5;254m'
    elif (( TAGS_ON )); then
      if (( ${OP_WANTED[$p]:-0} > NOW )); then add_tag "$dx" "$dy" "${OP_NAME[$p]} WANTED" $'\e[0;1;38;5;231;48;5;124m'
      elif in_party "$p"; then add_tag "$dx" "$dy" "${OP_NAME[$p]}" $'\e[0;38;5;'"${P_COLC[${OP_COL[$p]:-0}]};48;5;22m"
      else add_tag "$dx" "$dy" "${OP_NAME[$p]}" $'\e[0;38;5;'"${P_COLC[${OP_COL[$p]:-0}]};48;5;235m"; fi
    fi
  done
  (( MY_SAYT > NOW )) && add_tag $(( PX - cx0 )) $(( PY - cy0 )) "${MY_SAY:0:26}" $'\e[0;38;5;16;48;5;254m'
  if [[ $map == W && -n $WB_CID && -n ${CM_T[$WB_CID]} ]]; then   # the world boss wears a big red name
    dx=$(( CM_X[$WB_CID] - cx0 )) dy=$(( CM_Y[$WB_CID] - cy0 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) && add_tag "$dx" "$dy" "${EMJ[crown]}${M_NAME[${CM_T[$WB_CID]}]}" $'\e[0;1;38;5;231;48;5;124m'
  fi
  if [[ $map == W ]]; then                  # quest givers show !, delivery targets show ?
    local t
    for m in "${vis[@]}"; do
      t=${CM_T[m]}
      if (( M_KIND[t] == 0 )); then                                # v3.0: champions and elites stand out
        if (( ${CM_CH[$m]:-0} )); then
          if (( TW2 )); then add_tag $(( CM_X[m] - cx0 )) $(( CM_Y[m] - cy0 )) "${CHP_E[CM_CH[m]-1]}" $'\e[0;48;5;236m'
          else add_tag $(( CM_X[m] - cx0 )) $(( CM_Y[m] - cy0 )) "*" $'\e[0;'"${CHP_COL[CM_CH[m]-1]};48;5;236m"; fi
        elif (( M_BOSS[t] == 2 )); then
          if (( TW2 )); then add_tag $(( CM_X[m] - cx0 )) $(( CM_Y[m] - cy0 )) "💀" $'\e[0;48;5;236m'
          else add_tag $(( CM_X[m] - cx0 )) $(( CM_Y[m] - cy0 )) "E" $'\e[0;1;38;5;231;48;5;124m'; fi
        fi
        continue
      fi
      (( M_KIND[t] == 1 )) || continue
      dx=$(( CM_X[m] - cx0 )) dy=$(( CM_Y[m] - cy0 ))
      if (( TW2 )); then
        if story_npc "$t"; then add_tag "$dx" "$dy" "⭐" $'\e[0;48;5;236m'
        elif chain_npc "$t"; then add_tag "$dx" "$dy" "❕" $'\e[0;48;5;236m'
        elif turnin_for "$t"; then add_tag "$dx" "$dy" "❓" $'\e[0;48;5;236m'
        elif [[ -n ${N_QK[$t]}${N_QD[$t]} ]]; then add_tag "$dx" "$dy" "❗" $'\e[0;48;5;236m'; fi
      elif story_npc "$t"; then add_tag "$dx" "$dy" "*" $'\e[0;1;38;5;16;48;5;214m'
      elif chain_npc "$t"; then add_tag "$dx" "$dy" "!" $'\e[0;1;38;5;16;48;5;208m'
      elif turnin_for "$t"; then add_tag "$dx" "$dy" "?" $'\e[0;1;38;5;16;48;5;46m'
      elif [[ -n ${N_QK[$t]}${N_QD[$t]} ]]; then add_tag "$dx" "$dy" "!" $'\e[0;1;38;5;16;48;5;226m'; fi
    done
  fi
  LITMODE=0 LITR=""
  if [[ $map == D* ]]; then dark=1; update_fog
  elif [[ $map == W ]] && (( NR > 0 || WR > 0 )); then LITMODE=1; build_lit "$cx0" "$cy0"; fi
  render_rows
  unset "SCR[m$(( VH - 2 ))]" "SCR[m$(( VH - 3 ))]" "SCR[m$(( VH / 2 ))]" "SCR[m$(( VH / 2 - 5 ))]"   # under the overlays
  out+=$N
  LITMODE=0 TR_ON=0
  draw_overlay
  if (( DEAD )); then
    local msg="   YOU DIED - respawning in $(( (dead_until - NOW + 999) / 1000 ))s   "
    out+=$'\e['"$(( VH / 2 + 3 ));$(( (MW - ${#msg}) / 2 + 2 ))H"$'\e[1;97;41m'"$msg$N"
  elif (( clear_until )); then
    local msg="   DUNGEON CLEARED - teleporting in $(( (clear_until - NOW + 999) / 1000 ))s   "
    out+=$'\e['"$(( VH / 2 - 2 ));$(( (MW - ${#msg}) / 2 + 2 ))H"$'\e[1;30;43m'"$msg$N"
  fi
}

render_header() {
  local loc st on=$(( ${#OP_NAME[@]} + 1 ))
  if [[ $CUR_MAP == W ]]; then
    region_of "$PX" "$PY"
    if [[ $RLVL == safe ]]; then loc="$RNAME ${K_GOOD}(safe)$N"; else loc="$RNAME ${K_SYS}(lvl $RLVL)$N"; fi
  elif [[ $CUR_MAP == H* ]]; then                                     # v5.0: a room at the inn
    if [[ $RM_OWNER == "$MY_ID" ]]; then loc=$'\e[38;5;180m'"your ${ROOM_NAME[RM_TIER]}$N"
    else loc=$'\e[38;5;180m'"${OP_NAME[$RM_OWNER]:-someone}'s ${ROOM_NAME[RM_TIER]}$N"; fi
  else
    loc=$'\e[38;5;203m'"${D_NAME[CUR_DT]}$N"
  fi
  if (( ! net_up )); then st="${K_HURT}offline - reconnecting$N"
  elif [[ $MODE == host ]]; then st="hosting :$NET_PORT"
  else st="online @ $NET_HOST:$NET_PORT"; fi
  clock_txt
  local wt=""; [[ -n $CW ]] && wt=" "$'\e[38;5;153m'"${TW2:+${WEA_E[$CW]} }${WEA_LABEL[$CW]}$N"
  local h=$'\e[1;38;5;214m shellmmorpg'"$N ${K_SYS}|$N ${B}$loc ${K_SYS}|$N $CLKT$wt ${K_SYS}| $PX,$PY | $on online | $st$N"
  (( WANTED_UNTIL > NOW )) && h+="  "$'\e[1;5;38;5;231;48;5;124m'" WANTED $(( (WANTED_UNTIL - NOW + 999) / 1000 ))s $N"
  clipc "$h" "$COLS"
  emit hdr $'\e[1;1H\e[48;5;235m'"${CL//"$N"/$'\e[0;48;5;235m'}"$'\e[K\e[0m'
}

dir_of() {  # dx dy -> DIR
  local h="" v=""
  (( $2 < -1 )) && v=N; (( $2 > 1 )) && v=S; (( $1 < -1 )) && h=W; (( $1 > 1 )) && h=E
  DIR="$v$h"; [[ -n $DIR ]] || DIR=here
}

psym() {  # id -> PS (colored symbol of a player)
  PS=$'\e[1;38;5;'"${P_COLC[${OP_COL[$1]:-0}]}m${OP_SYM[$1]:-@}$N"
}

PEQ_K="" PEQ_L=() PRAW=()
render_panel() {
  local L=() k s c txt id nm tag i line
  L+=($'\e[1;7;38;5;'"${P_COLC[COLR]}m$SYM$N ${B}$MY_NAME$N  ${K_SYS}Lv$N ${B}$LVL$N ${C_NAME[CLS]}")
  (( PARA )) && L[0]+=" ${K_LOOT}P$PARA$N"
  (( TITLE >= 0 )) && { my_title; L+=("  ${K_SYS}$TTL$N"); }
  hp_col "$HP" "$MAXHP"; pbar "$HP" "$MAXHP" 18 "$HC"; L+=("HP $PB $HP/$MAXHP")
  pbar "$MP" "$MAXMP" 18 $'\e[38;5;33m';  L+=("MP $PB $MP/$MAXMP")
  pbar "$XP" "$XPNEXT" 18 $'\e[38;5;220m'; L+=("XP $PB $(( XP * 100 / XPNEXT ))%")
  if (( IN_MK )) && [[ $CUR_MAP == D* ]]; then                       # v4.5: the mythic clock
    myth_left; local mc=$K_GOOD; (( MLS < 60 )) && mc=$K_HURT; (( MLS < 0 )) && mc=$K_SYS
    printf -v PF '%d:%02d' $(( (MLS < 0 ? -MLS : MLS) / 60 )) $(( (MLS < 0 ? -MLS : MLS) % 60 ))
    local ov=""; (( MLS < 0 )) && ov="over "
    L+=("${K_LOOT}MYTHIC +$IN_MK$N  $mc$ov$PF$N")
  fi
  if (( TW2 )); then L+=("💰 ${K_LOOT}$GOLD$N   ${K_SYS}[e]$N 🍷 $POT_H+$POT_GH   ${K_SYS}[r]$N 🧪 $POT_M+$POT_GM")
  else L+=("${K_LOOT}$GOLD gold$N  ${K_SYS}[e]$N $POT_H+$POT_GH HP  ${K_SYS}[r]$N $POT_M+$POT_GM MP"); fi
  if [[ $PEQ_K != "$TW2|$CLS|$EQW|$EQA|$EQO|$EQH|$EQJ" ]]; then   # gear lines only change with the gear
    PEQ_K="$TW2|$CLS|$EQW|$EQA|$EQO|$EQH|$EQJ" PEQ_L=()
    if (( TW2 )); then
      item_name "$EQW" "$CLS"; item_icon "$EQW" "$CLS"; PEQ_L+=("$II "$'\e['"${ICOL}m$INAME$N +$IVAL")
      item_name "$EQA" "$CLS"; item_icon "$EQA" "$CLS"; PEQ_L+=("$II "$'\e['"${ICOL}m$INAME$N +$IVAL")
      txt=""
      for k in O H J; do
        eq_of "$k"
        if [[ -n $EQC ]]; then item_name "$EQC" "$CLS"; txt+="$IKE "$'\e['"${ICOL}m${IKN}$N  "; else txt+="${K_SYS}no ${SLOT_LABEL[$k],,}$N  "; fi
      done
      PEQ_L+=("$txt")
    else
      item_name "$EQW" "$CLS"; PEQ_L+=("${K_SYS}Wpn$N "$'\e['"${ICOL}m$INAME$N +$IVAL")
      item_name "$EQA" "$CLS"; PEQ_L+=("${K_SYS}Arm$N "$'\e['"${ICOL}m$INAME$N +$IVAL")
      txt=""
      for k in O H J; do
        eq_of "$k"
        if [[ -n $EQC ]]; then item_name "$EQC" "$CLS"; txt+="${K_SYS}${SLOT_LABEL[$k]:0:3}$N "$'\e['"${ICOL}m${IKN}$N  "; fi
      done
      [[ -n $txt ]] && PEQ_L+=("$txt")
    fi
  fi
  L+=("${PEQ_L[@]}")
  txt="${K_SYS}Attack$N $ATK  ${K_SYS}Armor$N $ARMOR  ${K_SYS}Crit$N $CRIT% "
  if (( TW2 )); then          # v1.7: running effects as icons
    active_fx; (( ${#AFX_E[@]} )) && { txt+=" "; for k in "${AFX_E[@]}"; do txt+=$k; done; }
    (( NOW < immune_until )) && txt+="✨"
  else
  (( NOW < buff_until ))   && txt+=" ${K_GOOD}FURY$N"
  (( NOW < anthem_until )) && txt+=" ${K_GOOD}ANTHEM$N"
  (( NOW < str_until ))    && txt+=" ${K_GOOD}STR$N"
  (( NOW < iron_until ))   && txt+=" ${K_GOOD}IRON$N"
  (( NOW < swift_until ))  && txt+=" ${K_GOOD}SWIFT$N"
  (( NOW < immune_until )) && txt+=" ${K_GOOD}IMMUNE$N"
  (( NOW < fed_until ))    && txt+=" ${K_GOOD}FED$N"
  (( NOW < fireward_until )) && txt+=" ${K_GOOD}WARD$N"
  (( NOW < frost_until ))  && txt+=" ${K_GOOD}FROST$N"
  (( NOW < veil_until ))   && txt+=" ${K_GOOD}VEIL$N"
  fi
  ps_line; [[ -n $PSL ]] && L+=("$PSL")
  tal_points; (( TFREE > 0 )) && L+=("${K_GOOD}$TFREE talent point(s) to spend - [x]$N")
  hdr SKILLS; L+=("$txt" "" "$HDR")
  for k in 0 1 2; do
    s=$(( CLS * 3 + k ))
    c=$(( SKCD[k] - NOW ))
    if (( c > 0 )); then txt="${K_SYS}$(( (c + 999) / 1000 ))s$N"
    elif (( MP < S_MP[s] )); then txt="${K_HURT}no mana$N"
    else txt="${K_GOOD}ready$N"; fi
    printf -v line '[%d] %-13s %2dmp ' $(( k + 1 )) "${S_NAME[s]}" "${S_MP[s]}"
    (( TW2 )) && line="${line:0:4}${SKILL_E[s]}${line:3}"
    L+=("$line$txt")
  done
  if [[ -n $TARGET && -n ${CM_T[$TARGET]} ]]; then
    k=${CM_T[$TARGET]}
    pbar "${CM_HP[$TARGET]}" "${CM_MAX[$TARGET]}" 18 $'\e[38;5;160m'
    con_col "${M_LVL[k]}"
    hdr TARGET; L+=("" "$HDR ${GLYP[m$k]}$N ${CC}${N_FULL[$k]:-${M_NAME[k]}}$N ${K_SYS}Lv ${M_LVL[k]}$N" "   $PB ${CM_HP[$TARGET]}")
    target_info "$TARGET"; [[ -n $TIL ]] && L+=("$TIL")
  fi
  if [[ -n $MY_PARTY ]]; then
    hdr PARTY; L+=("" "$HDR")
    for id in "${PARTY_IDS[@]}"; do
      [[ $id == "$MY_ID" ]] && continue
      nm=${OP_NAME[$id]:-?}
      if [[ -z ${OP_MAP[$id]} ]]; then tag="${K_SYS}offline$N"
      elif [[ ${OP_DEAD[$id]} == 1 ]]; then tag="${K_HURT}dead$N"
      elif [[ ${OP_MAP[$id]} != "$CUR_MAP" ]]; then tag="${K_SYS}away$N"
      else cheb $(( ${OP_X[$id]} - PX )) $(( ${OP_Y[$id]} - PY )); tag="${K_SYS}${D}m$N"; fi
      pbar "${OP_HP[$id]:-0}" "${OP_MAX[$id]:-1}" 8 $'\e[38;5;46m'
      [[ $id == "$PARTY_LEADER" ]] && nm="$nm*"
      printf -v line '%-11s' "$nm"; psym "$id"
      L+=("$PS ${K_PARTY}$line$N $PB ${C_NAME[${OP_CLS[$id]:-0}]:0:4} ${OP_LVL[$id]:-?} $tag")
    done
  fi
  if [[ -n $WB_CID ]]; then
    k=$WB_CT; con_col "${M_LVL[k]}"; QTX=$WB_CX QTY=$WB_CY; track
    L+=("" $'\e[1;38;5;231;48;5;124m'" WORLD BOSS $N ${GLYP[m$k]}$N ${CC}${M_NAME[k]}$N ${K_SYS}Lv ${M_LVL[k]} $TRK$N")
  fi
  story_line
  if [[ -n $SL ]] || (( ${#QUESTS[@]} + ${#PQ_CODES[@]} )); then
    hdr QUESTS; L+=("" "$HDR")
    [[ -n $SL ]] && L+=(" ${K_LOOT}$SL$N")
    for k in "${PQ_CODES[@]}"; do quest_info "$k"; track; L+=(" ${K_PARTY}P$N $QGLY $QSHORT ${K_SYS}$TRK$N"); done
    for k in "${QUESTS[@]}"; do quest_info "$k"; track; L+=(" ${K_LOOT}!$N $QGLY $QSHORT ${K_SYS}$TRK$N"); done
  fi
  c=0
  for id in "${!OP_MAP[@]}"; do
    [[ ${OP_MAP[$id]} == "$CUR_MAP" ]] && ! in_party "$id" || continue
    cheb $(( ${OP_X[$id]} - PX )) $(( ${OP_Y[$id]} - PY )); (( D <= 30 )) || continue
    (( c == 0 )) && { hdr NEARBY; L+=("" "$HDR"); }
    dir_of $(( ${OP_X[$id]} - PX )) $(( ${OP_Y[$id]} - PY )); psym "$id"
    txt="$PS ${OP_NAME[$id]} ${K_SYS}${C_NAME[${OP_CLS[$id]:-0}]} ${OP_LVL[$id]} - ${D}m $DIR$N"
    (( ${OP_WANTED[$id]:-0} > NOW )) && txt+=" ${K_HURT}WANTED$N"
    L+=("$txt")
    c=$(( c + 1 )); (( c >= 3 )) && break
  done
  local pw=$(( COLS - PCOL + 1 ))
  for (( i = 0; i < VH + 2; i++ )); do
    [[ ${L[i]} == "${PRAW[i]}" && -n ${SCR[p$i]+x} ]] && continue     # same line as last frame and still on screen
    PRAW[i]=${L[i]}; clipc "${L[i]}" "$pw"; emit "p$i" $'\e['"$(( i + 2 ));${PCOL}H$CL"$'\e[K'
  done
}

render_log() {  # events on top, the last chat lines below
  local ne=${#LOG_T[@]} nc=${#CHL_T[@]} rows_c i r=0 w=$(( COLS - 2 )) start
  rows_c=$(( nc < 3 ? nc : 3 ))
  start=$(( ne - (6 - rows_c) )); (( start < 0 )) && start=0
  local l
  for (( i = start; i < start + 6 - rows_c; i++ )); do
    l=$'\e['"$(( LOGY + r ));1H"
    (( i < ne )) && { clipc "${LOG_C[i]}${LOG_T[i]:0:w}" "$w"; l+=" $CL"; }
    emit "l$r" "$l"$'\e[K'; r=$(( r + 1 ))
  done
  for (( i = nc - rows_c; i < nc; i++ )); do
    clipc "${CHL_C[i]}${CHL_T[i]:0:w}" "$w"
    emit "l$r" $'\e['"$(( LOGY + r ));1H"$'\e[48;5;234m'" ${CL%$'\e[0m'}"$'\e[K'"$N"; r=$(( r + 1 ))
  done
}

render_input() {
  local t=$CHAT_BUF w=$(( COLS - 12 )) l=$'\e['"$INPY;1H"
  if (( CHATTING )); then
    (( ${#t} > w )) && t=${t: -w}
    l+=$' \e[1;38;5;51msay>'"$N $t"$'\e[5m_\e[0m'
  else
    t=" [wasd] move [1-3] skills [e/r] potions [u] eat [g] fish/gather [i]nv [x] talents [y] allies [p]rof [m]ap [q]uests [b]easts [c]hat log [H] collection [v] graphics [enter] chat [?] help"
    l+="${K_SYS}${t:0:COLS-1}$N"
  fi
  emit inp "$l"$'\e[K'
}

# --- full-screen panels drawn inside the map frame ------------------------
ui() { UIT+=("$1"); UIC+=("${2:-$K_CHAT}"); UIL+=(-1); }
uix() {  # pre-colored line [its plain twin, for the width - measured if left out]
  UIT+=("$1"); UIC+=("")
  if (( $# > 1 )); then dispw "$2"; else plain "$1"; dispw "$PL"; fi
  UIL+=("$DW")
}

ui_talk() {
  local t=$TALK_T role=${N_ROLE[$TALK_T]}
  if (( TW2 )); then ui "  ${MEMO[t]} ${N_FULL[$t]}" "$B"$'\e[38;5;117m'; else ui "  ${N_FULL[$t]}" "$B"$'\e[38;5;117m'; fi
  ui ""
  local rest="\"$TALK_LINE\"" w=$(( VW - 6 )) cut
  while (( ${#rest} > w )); do
    cut=${rest:0:w}; cut=${cut% *}; (( ${#cut} < 10 )) && cut=${rest:0:w}
    ui "  $cut" "$K_CHAT"; rest=${rest:${#cut}}; rest=${rest# }
  done
  ui "  $rest" "$K_CHAT"
  ui ""
  case $role in
    inn|medic) ui "  [1] Rest and recover (free)" ;;
    guard|villager) ;;
    bank) ui "  [1] Open my vault and the shared chest" "$K_LOOT" ;;
    merc) ui "  [1] Show me your companions" "$K_LOOT" ;;
    stable) ui "  [1] Show me your horses" "$K_LOOT" ;;
    valor) ui "  [1] What does valor buy? ($VALOR valor)" "$K_LOOT" ;;
    *) ui "  [1] Let me see your wares" ;;
  esac
  ui "  [2] Heard any rumors?"
  [[ -n ${N_QK[$t]}${N_QD[$t]} ]] && ui "  [3] Do you have any work for me?" "$K_LOOT"
  case $role in
    smith) ui "  [4] Forge gear from my ore" "$K_GOOD" ;;
    alchemist|hermit) ui "  [4] Brew potions from my herbs" "$K_GOOD" ;;
    inn) ui "  [4] May I use your kitchen? (cook fish)" "$K_GOOD" ;;
  esac
  if ql_for_npc "$t"; then                                       # v3.0: questlines and quartermasters
    case ${QLS:QLN:1} in
      0) if (( LVL >= QL_LVL[QLN] )); then ui "  [5] ${QL_NAME[QLN]}  (new questline)" $'\e[1;38;5;214m'
         else ui "  [5] ${QL_NAME[QLN]}  (from level ${QL_LVL[QLN]})" "$K_SYS"; fi ;;
      x) ui "  [5] ${QL_NAME[QLN]}  (completed)" "$K_SYS" ;;
      *) if ql_ready "$QLN"; then ui "  [5] ${QL_NAME[QLN]}  - I have done it!" "$K_GOOD"
         else ui "  [5] ${QL_NAME[QLN]}  (step ${QLS:QLN:1}/${QL_N[QLN]})" $'\e[38;5;214m'; fi ;;
    esac
    ui "  [6] Show me the ${FAC_NAME[${QL_FAC[QLN]}]}'s wares" "$K_LOOT"
  fi
  [[ $role == smith ]] && ui "  [7] Set gems into my gear (jewelcrafting)" $'\e[1;38;5;213m'
  if [[ $role == inn ]]; then
    tal_reset_cost; ui "  [8] Help me forget my talents ($TRC gold)" "$K_SYS"
    if (( ROOM_T )); then ui "  [9] Rooms upstairs - your ${ROOM_NAME[ROOM_T]}, visits" $'\e[1;38;5;180m'
    else ui "  [9] Rooms upstairs - rent one, or visit a friend" $'\e[1;38;5;180m'; fi
  fi
  ui ""
  if (( TALK_CONFIRM )); then ui "  Really attack ${N_FULL[$t]}? You will be WANTED. Press [x] again." "$K_HURT"
  else ui "  [x] Attack ${N_FULL[$t]}" "$K_SYS"; fi
  ui "  [esc] Goodbye" "$K_SYS"
}

ui_shop() {
  local i code total=0 title
  [[ -n ${CM_T[$TALK_MID]} ]] || { UI=""; return; }
  shop_build "$SHOP"
  case $SHOP in
    general) title="MARA'S GENERAL STORE" ;; smith) title="BROM'S FORGE" ;; alchemist) title="YSOLDE'S ALCHEMY" ;;
    trader) title="GARRICK'S TRADING POST" ;; hermit) title="ORWIN'S HUT" ;; spice) title="NADIA'S SPICE STALL" ;;
    *) title="${N_FULL[$TALK_T]^^}'S SUPPLIES" ;;
  esac
  (( TALK_T >= NPC1 )) && title="${N_FULL[$TALK_T]^^}"
  ui "  $title" "$K_LOOT$B"
  ui "  You have ${EMJ[gold]}$GOLD gold."
  ui ""
  local pc=$(( TW2 ? 61 : 60 )) c ok col
  (( pc > MW - 8 )) && pc=$(( MW - 8 ))
  for i in "${!SH_ID[@]}"; do
    c=${SH_ID[i]}; rb; rt "  [$(( i + 1 ))] " "38;5;245"
    if [[ $c == [WAOHJ].* ]]; then        # gear: icon, name, stats, power change, price
      item_name "$c" "$CLS"; item_icon "$c" "$CLS"; bonus_txt
      ok=0; [[ $ICLS == *"$CLS"* ]] && ok=1
      [[ -n $II ]] && rt "$II "
      padt "$INAME" $(( TW2 ? 24 : 30 )); rt "$PADS " "$ICOL"
      local st=""; (( IVAL )) && { st="+$IVAL dmg "; [[ $IK != W ]] && st="+$IVAL arm "; }
      padt "$st$BTX" 17; rt "$PADS" "38;5;250"
      if (( ok )); then pv_slot "$IK" "$c"; pv_delta; padr " $DLP" 6; rt "$PADS" "$DLC"; else rt " ✖    " "38;5;203"; fi
    elif [[ $c == B.* ]]; then            # bags: size and what it does to your capacity
      item_name "$c" "$CLS"; item_icon "$c" "$CLS"
      [[ -n $II ]] && rt "$II "
      padt "$INAME" $(( TW2 ? 24 : 30 )); rt "$PADS " "$ICOL"
      padt "bag, $IVAL slots" 17; rt "$PADS" "38;5;250"
      bag_gain "${c#B.}"; if (( BG > 0 )); then padr " ▲$BG" 6; rt "$PADS" "1;38;5;84"; else rt " =    " "38;5;242"; fi
    else
      ci "$c"; [[ -n $CI ]] && rt "$CI"
      padt "${SH_LABEL[i]}" $(( pc - 6 - (TW2 ? 3 : 0) )); rt "$PADS" "38;5;252"
    fi
    rpad "$pc"; col="1;38;5;220"; (( GOLD >= SH_PRICE[i] )) || col="38;5;203"
    printf -v PF '%6sg' "${SH_PRICE[i]}"; rt "$PF" "$col"
    uxs
  done
  ui ""
  junk_value
  for code in "${INV[@]}"; do [[ $code == *! || $code == C.* ]] && continue; item_stats "$code"; total=$(( total + ISELL )); done
  ui "  [j] Sell junk (gear worse than yours: $JUNK items)   +${JVAL}g"
  local lk=0; for code in "${INV[@]}"; do [[ $code == *! || $code == C.* ]] && lk=$(( lk + 1 )); done   # (collectables are never sold)
  if (( lk )); then ui "  [s] Sell everything but locked items and collectables ($(( ${#INV[@]} - lk )) items)   +${total}g"
  else ui "  [s] Sell everything in your bags (${#INV[@]} items)   +${total}g"; fi
  if [[ $SHOP == @(general|trader|spice) ]]; then
    fish_value; ui "  [f] Sell all your fish ($FISHN)   +${FISHV}g"
    col_dupes; (( ${#DUP[@]} )) && ui "  [c] Sell duplicate collectables (${#DUP[@]})   +${DUPV}g"
  fi
  ui ""
  [[ $SHOP == smith ]] && ui "  Reforging upgrades the rarity of what you WEAR. It can fail." "$K_SYS"
  ui "  [esc] leave" "$K_SYS"
}

ui_quest() {
  local i f leader=1 title
  [[ -n $MY_PARTY && $PARTY_LEADER != "$MY_ID" ]] && leader=0
  if [[ $QSRC == board ]]; then title="QUEST BOARD OF HEARTHMOOR"; else title="${N_FULL[$QSRC]^^} HAS WORK FOR YOU"; fi
  ui "  $title" "$K_LOOT$B"
  if [[ -n $MY_PARTY ]]; then
    ui "  Party quests (${#PQ_CODES[@]}/3) - shared progress, +25% rewards:" "$B$K_PARTY"
    for f in "${PQ_CODES[@]}"; do quest_info "$f"; uix "    $QGLY ${K_PARTY}$QTXT$N" "    $PLX $QTXT"; done
  fi
  ui "  Your quests (${#QUESTS[@]}/3):" "$B"
  (( ${#QUESTS[@]} )) || ui "    none" "$K_SYS"
  for f in "${QUESTS[@]}"; do quest_info "$f"; uix "    $QGLY $QTXT" "    $PLX $QTXT"; done
  ui ""
  ui "  Offers:" "$B"
  for i in "${!OFFERS[@]}"; do
    quest_info "${OFFERS[i]}"; IFS=. read -r -a f <<< "${OFFERS[i]}"
    uix "  [$(( i + 1 ))] $QGLY ${K_CHAT}${QTXT%% (*}$N" "  [x] $PLX ${QTXT%% (*}"
    ui "        $QWHERE  -  ${f[4]} XP, ${f[5]} gold" "$K_SYS"
  done
  ui ""
  if (( ! leader )); then ui "  Only your party leader (${OP_NAME[$PARTY_LEADER]:-?}) can accept quests for the party." "$K_HURT"
  elif [[ -n $MY_PARTY ]]; then ui "  [1-${#OFFERS[@]}] accept for the WHOLE party   [esc] close" "$K_SYS"
  else ui "  [1-${#OFFERS[@]}] accept a quest   [esc] close" "$K_SYS"; fi
}

bcell() {  # monster type width -> BC (colored) BP (plain), both exactly <width> wide
  local t=$1 w=$2 nm lv
  printf -v lv 'L%-2d' "${M_LVL[t]}"
  if [[ ${SEEN:t:1} == 1 ]]; then
    printf -v nm '%-*s' $(( w - 5 - ${#PLX} )) "${M_NAME[t]:0:w-5-${#PLX}}"
    con_col "${M_LVL[t]}"; BC="${GLYP[m$t]}$N $nm ${CC}$lv$N" BP="$PLX $nm $lv"
  else
    printf -v nm '%-*s' $(( w - 5 - ${#PLX} )) "???"
    BC="${K_SYS}${PLX//x/?} $nm $lv$N" BP="$PLX $nm $lv"
  fi
}

BEAST_PG=0
ui_bestiary() {  # all hostile creatures sorted by level, in pages that fit the frame
  local list=() t i j tmp seen=0 cols rows w r c idx line plain per pages p0
  for (( t = 0; t < NM; t++ )); do (( M_KIND[t] == 0 )) && list+=("$t"); done
  for (( i = 1; i < ${#list[@]}; i++ )); do
    tmp=${list[i]}; j=$(( i - 1 ))
    while (( j >= 0 && M_LVL[list[j]] > M_LVL[tmp] )); do list[j+1]=${list[j]}; j=$(( j - 1 )); done
    list[j+1]=$tmp
  done
  for t in "${list[@]}"; do [[ ${SEEN:t:1} == 1 ]] && seen=$(( seen + 1 )); done
  rows=$(( VH - 5 )); (( rows < 1 )) && rows=1
  cols=$(( (VW - 2) / 18 )); (( cols < 1 )) && cols=1           # cells are at least 16 columns wide
  per=$(( rows * cols ))
  (( per > ${#list[@]} )) && { cols=$(( (${#list[@]} + rows - 1) / rows )); per=$(( rows * cols )); }
  w=$(( (VW - 2) / cols - 2 )); (( w > 26 )) && w=26
  pages=$(( (${#list[@]} + per - 1) / per ))
  (( BEAST_PG >= pages )) && BEAST_PG=$(( pages - 1 )); (( BEAST_PG < 0 )) && BEAST_PG=0
  p0=$(( BEAST_PG * per ))
  ui "  BESTIARY - $seen of ${#list[@]} creatures discovered" "$K_LOOT$B"
  ui "  colors: grey trivial, green easy, yellow even, orange hard, red deadly" "$K_SYS"
  ui ""
  for (( r = 0; r < rows; r++ )); do
    line="  " plain="  "
    for (( c = 0; c < cols; c++ )); do
      idx=$(( p0 + c * rows + r )); (( idx < ${#list[@]} && idx < p0 + per )) || continue
      bcell "${list[idx]}" "$w"; line+="$BC  "; plain+="$BP  "
    done
    uix "$line" "$plain"
  done
  ui ""
  if (( pages > 1 )); then ui "  page $(( BEAST_PG + 1 ))/$pages - [<] [>] turn the page - [esc] close" "$K_SYS"
  else ui "  Quests tell you where each creature lives. [esc] close" "$K_SYS"; fi
}

ui_chatlog() {
  local half i ne=${#LOG_T[@]} nc=${#CHL_T[@]}
  half=$(( (VH - 4) / 2 ))
  ui "  EVENTS" "$B"
  for (( i = ne - half; i < ne; i++ )); do (( i >= 0 )) && ui "  ${LOG_T[i]}" "${LOG_C[i]}"; done
  ui "  CHAT" "$B"
  (( nc )) || ui "  nobody said anything yet - press [enter] to chat" "$K_SYS"
  for (( i = nc - half; i < nc; i++ )); do (( i >= 0 )) && ui "  ${CHL_T[i]}" "${CHL_C[i]}"; done
}

ui_way() {
  local i a cost=$(( 10 + LVL * 3 ))
  ui "  WAYSTONE NETWORK" "$K_LOOT$B"
  ui "  Travel to any attuned waystone for $cost gold. You have $GOLD gold."
  ui ""
  for i in "${!WAYSTONES[@]}"; do
    a=(${WAYSTONES[i]})
    if [[ ${WAYS:i:1} == 1 ]]; then
      cheb $(( a[1] - PX )) $(( a[2] - PY ))
      if (( D <= 3 )) && [[ $CUR_MAP == W ]]; then ui "  [$(( (i + 1) % 10 ))] ${EMJ[way]}${a[0]//_/ }   (you are here)" "$K_SYS"
      else ui "  [$(( (i + 1) % 10 ))] ${EMJ[way]}${a[0]//_/ }"; fi
    else
      ui "  [ ] ??? - not attuned yet" "$K_SYS"
    fi
  done
  ui ""
  ui "  Walk past a waystone (&) once to attune it.   [esc] close" "$K_SYS"
}

HELP_PG=0
ui_help() {  # two pages: [<] [>] turn
  if (( HELP_PG == 0 )); then
  ui "  CONTROLS                                          page 1/4  [>] more" "$B"
  ui "  w a s d / arrows / h j k l   walk - walk into foes to hit"
  ui "  walk into an NPC to talk  -  f / space attack next to you"
  ui "  1 2 3 skills   e / r potions   u eat   i inventory   y allies"
  ui "  x talents  g fish / gather  p professions  m map  z ride  o achievements"
  ui "  q quests, questlines, reputation  b bestiary  c chat log  H collection"
  ui "  v graphics   Q quit   enter chat - /p party  /w name msg"
  ui "  /invite /accept /leave /trade name /give name gold|#item /who"
  ui "  THE WORLD" "$B"
  ui "  Hearthmoor is the heart. South: desert (Oasis of Kadar), the Isles,"
  ui "  the Badlands. East: tundra, Ashen Wastes, Crystal Highlands, Jungle,"
  ui "  Void Rift. Level 30-40: Duskwood, Sunken Kingdom, Stormreach, Gloomcap,"
  ui "  Dragonspine, Bonefields, Starfall Crater. Waystones (&) link 17 towns."
  ui "  NPCs: yellow ! quests, ❕/orange ! a questline, ? a letter, star"
  ui "  the story (talk to Old Tom first). 23 dungeons (>), level 2 to 40."
  ui "  Night: only torches light the way. Weather: sandstorms blind,"
  ui "  blizzards slow, ash burns (tonics!). Murder makes you WANTED."
  ui "  Bankers (B): your vault + a chest shared by all your heroes."
  ui "  [esc] close" "$K_SYS"
  elif (( HELP_PG == 1 )); then
  ui "  DEEPER                                       page 2/4  [<] [>] more" "$B"
  ui "  Talents [x]: a point every level, three trees per class, a"
  ui "  capstone at 10 points in a tree. Forget them at any inn."
  ui "  Elements: skills deal fire, frost, poison, shadow, holy or arcane"
  ui "  damage. Every creature is weak to one and resists one - the"
  ui "  target panel says which. Resistances protect you from magic."
  ui "  Monsters poison, bleed, burn, chill, stun and weaken you. Potions"
  ui "  cure poison and bleeding; resting and cleansing skills cure all."
  ui "  Champions (marked) are stronger: 3x XP, better loot, gems."
  ui "  Rare elites roam every region - bounty boards want them dead."
  ui "  Gems drop from rares, champions, bosses, chests and ore. Any smith"
  ui "  sets them into socketed gear [7] and combines three into one better."
  ui "  Questlines: every town has its own story - and its own choices."
  ui "  Quests raise your standing with the six factions: discounts and"
  ui "  their quartermaster [6] sells socketed gear and a unique."
  ui "  Quests now also ask you to collect, deliver, scout and hunt bounties."
  ui "  [esc] close   [>] endgame" "$K_SYS"
  elif (( HELP_PG == 2 )); then
  ui "  ENDGAME                                      page 3/4  [<] [>] more" "$B"
  ui "  Mythic: at level 40 every dungeon gate asks: normal or mythic? Foes are"
  ui "  level 40 and stronger with every key level (+2 to +20); weekly affixes;"
  ui "  beat the clock and your key rises. Pays epic+ gear, perfect gems, valor."
  ui "  The Eclipse Throne (raid, Starfall Crater, east rim): Nyxara grows with"
  ui "  every hero - stay out of marked ground, kill her guards, run from the"
  ui "  total eclipse. Invasions: now and then the Horde attacks a town."
  ui "  Valor: buy Godforged gear, perfect gems and mounts from Hale (Hearthmoor)"
  ui "  or Seren (Dawnspire). Dailies and weeklies: [q], tab 4 (from level 30)."
  ui "  Paragon: after 40, experience gives paragon points - [x], then [p]."
  ui "  Mounts: Hilda sells horses in Hearthmoor. [z] ride, [Z] choose a mount."
  ui "  Achievements and titles: [o]. Professions go to 40; new ore, herbs, fish."
  ui "  Perfect gems: combine three flawless ones at any smith."
  ui "  [esc] close   [>] your home" "$K_SYS"
  else
  ui "  A HOME OF YOUR OWN                                page 4/4  [<] back" "$B"
  ui "  Every innkeeper rents rooms upstairs [9]: four sizes, a weekly rent, and"
  ui "  the same room waits for you at every inn. Walk into the furniture:"
  ui "  the bed makes you Well Rested (more XP from fights for 30 minutes),"
  ui "  the chest stores items and materials, displays show off your finds,"
  ui "  the bookshelf opens your collection book, visitors sign the guestbook."
  ui "  Collectables: 80 of them in six sets - boss trophies, world boss"
  ui "  trophies, a curio for every land, odd things from fishing and gathering,"
  ui "  relics of the story. [H] shows what you have found and where the rest is."
  ui "  Visits: [9] then [v] - your friends must be online. Your door decides"
  ui "  who may come in: nobody, your party or everybody."
  ui "  Shops buy collectables you have twice [c]. Lock one [l] to keep it."
  ui "  [esc] close" "$K_SYS"
  fi
}

wm_open() {  # [keep] -> fit zoom, center on me
  local z=1 VW=$MW
  while (( MAPW[W] / z > VW || MAPH[W] / z > VH - 1 )); do z=$(( z * 2 )); done
  WM_FIT=$z
  if [[ $1 != keep ]]; then
    WM_Z=$z
    if [[ $CUR_MAP == W ]]; then WM_X=$PX WM_Y=$PY; else WM_X=$WX WM_Y=$WY; fi
  fi
  (( WM_Z > WM_FIT )) && WM_Z=$WM_FIT
  WM_CZ=""
}

wm_build() {  # rows sampled at the current zoom, cached
  (( WM_Z >= 1 )) || { WM_Z=1; wm_open keep; }                 # (zoom 0 would sample forever)
  [[ $WM_CZ == "$WM_Z:$TW" ]] && return
  local z=$WM_Z y x row line
  WMR=()
  for (( y = 0; y * z < MAPH[W]; y++ )); do
    if (( TW == 2 )); then row=${VROW[W:$(( y * z ))]:-${MAPROW[W:$(( y * z ))]}}; else row=${MAPROW[W:$(( y * z ))]}; fi
    if (( z == 1 )); then WMR[y]=$row; continue; fi
    line=""
    for (( x = 0; x * z < MAPW[W]; x++ )); do line+=${row:x*z:1}; done
    WMR[y]=$line
  done
  WM_CZ="$z:$TW"
}

wm_seen() { local k=$(( ($2 / 8) * NCHX + $1 / 8 )); [[ ${EXPW:k:1} == 1 ]]; }

wm_key() {
  local vh=$(( VH - 1 )) VW=$MW
  case $1 in
    m) UI="" ;;
    w|k|UP)    WM_Y=$(( WM_Y - vh / 3 * WM_Z )) ;;
    s|j|DOWN)  WM_Y=$(( WM_Y + vh / 3 * WM_Z )) ;;
    a|h|LEFT)  WM_X=$(( WM_X - VW / 3 * WM_Z )) ;;
    d|l|RIGHT) WM_X=$(( WM_X + VW / 3 * WM_Z )) ;;
    +|=) (( WM_Z > 1 )) && WM_Z=$(( WM_Z / 2 )) ;;
    -|_) (( WM_Z < WM_FIT )) && WM_Z=$(( WM_Z * 2 )) ;;
    c) if [[ $CUR_MAP == W ]]; then WM_X=$PX WM_Y=$PY; else WM_X=$WX WM_Y=$WY; fi ;;
  esac
  (( WM_X < 0 )) && WM_X=0; (( WM_X >= MAPW[W] )) && WM_X=$(( MAPW[W] - 1 ))
  (( WM_Y < 0 )) && WM_Y=0; (( WM_Y >= MAPH[W] )) && WM_Y=$(( MAPH[W] - 1 ))
}

ui_map() {
  local z vh=$(( VH - 1 )) ry sy sx0 sy0 row RI=() RF=() TAGS=() x y i id d a mw mh q cx v1 v2 cy k qw
  (( TW2 && WM_Z <= 2 )) && { TW=2; VW=$(( MW / 2 )); }      # zoomed in far enough: emoji world map
  wm_build; z=$WM_Z
  mw=${#WMR[0]} mh=${#WMR[@]}
  sx0=$(( WM_X / z - VW / 2 )) sy0=$(( WM_Y / z - vh / 2 ))
  if (( mw <= VW )); then sx0=$(( (mw - VW) / 2 )); else (( sx0 < 0 )) && sx0=0; (( sx0 > mw - VW )) && sx0=$(( mw - VW )); fi
  if (( mh <= vh )); then sy0=$(( (mh - vh) / 2 )); else (( sy0 < 0 )) && sy0=0; (( sy0 > mh - vh )) && sy0=$(( mh - vh )); fi
  GLY[wdun]=$Z_ENT GLY[wway]=$Z_WAY GLY[wqg]=$'\e[0;1;38;5;16;48;5;226m!' GLY[wbank]=$'\e[0;1;38;5;16;48;5;220mB' GLY[wqt]=$'\e[0;1;5;38;5;226mx'
  poi() {  # world x y prio key [force]
    local vx=$(( $1 / z - sx0 )) vy=$(( $2 / z - sy0 ))
    (( vx >= 0 && vx < VW && vy >= 0 && vy < vh )) || return
    [[ $5 == 1 ]] && RF[vy]+="$(( vx * 10 + $3 )):1:$4 "
    [[ $5 == 1 ]] || wm_seen "$1" "$2" || return
    RI[vy]+="$(( vx * 10 + $3 )):1:$4 "
  }
  if [[ $CUR_MAP == W ]]; then x=$PX y=$PY; else x=$WX y=$WY; fi
  GLY[self]=$'\e[0;1;7;38;5;'"${P_COLC[COLR]}m$SYM"
  poi "$x" "$y" 1 self 1
  for id in "${!OP_MAP[@]}"; do [[ ${OP_MAP[$id]} == W && -n ${GLY[p$id]} ]] && poi "${OP_X[$id]}" "${OP_Y[$id]}" 2 "p$id" 1; done
  for q in "${PQ_CODES[@]}" "${QUESTS[@]}"; do [[ -n $q ]] && { quest_info "$q"; [[ -n $QTX ]] && poi "$QTX" "$QTY" 3 wqt 1; }; done
  if [[ -n $WB_CID ]]; then
    GLY[wwb]=$'\e[0;5;'"${M_COL[WB_CT]}m${M_GLY[WB_CT]}" GLYH[wwb]=$'\e[0;5;48;5;124m'"${MEMO[WB_CT]}"
    poi "$WB_CX" "$WB_CY" 0 wwb 1
  fi
  for (( d = 0; d < NDT; d++ )); do poi "${D_ENTX[d]}" "${D_ENTY[d]}" 4 wdun; done
  for i in "${!WAYSTONES[@]}"; do a=(${WAYSTONES[i]}); poi "${a[1]}" "${a[2]}" 4 wway; done
  for i in "${NPC_SPAWNS[@]}"; do a=($i); [[ -n ${N_QK[${a[0]}]}${N_QD[${a[0]}]} ]] && poi "${a[1]}" "${a[2]}" 4 wqg; done
  for i in "${NPC_SPAWNS[@]}"; do a=($i); [[ ${N_ROLE[${a[0]}]} == bank ]] && poi "${a[1]}" "${a[2]}" 4 wbank; done
  for i in "${REGIONS[@]}"; do                       # region names
    a=($i); [[ ${a[5]} == safe ]] && continue
    x=$(( (a[0] + a[2]) / 2 )) y=$(( (a[1] + a[3]) / 2 ))
    wm_seen "$x" "$y" || continue
    v1=$(( x / z - sx0 )) v2=$(( y / z - sy0 )); q=" ${a[4]//_/ } "
    (( TW == 2 && ${#q} % 2 )) && q+=" "
    qw=$(( ${#q} / TW ))
    (( v2 >= 0 && v2 < vh )) || continue
    v1=$(( v1 - qw / 2 )); (( v1 < 0 || v1 + qw > VW )) && continue
    free_span "$v2" "$v1" "$qw" || continue
    TAGS+=($'\e[0;1;38;5;231;48;5;236m'"$q$N"); RI[v2]+="$(( v1 * 10 + 5 )):$qw:t$(( ${#TAGS[@]} - 1 )) "
  done
  for (( ry = 0; ry < vh; ry++ )); do
    sy=$(( sy0 + ry ))
    out+=$'\e['"$(( ry + 3 ));2H$N"
    if (( sy < 0 || sy >= mh )); then out+=${BLANK:0:VW*TW}; continue; fi
    row=${WMR[sy]}
    if (( sx0 < 0 )); then row="${BLANK:0:-sx0}$row"; row=${row:0:VW}; else row=${row:sx0:VW}; fi
    (( ${#row} < VW )) && row+=${BLANK:0:VW-${#row}}
    cy=$(( sy * z / 8 ))                               # explored 8x8 chunks in color, the rest grey
    local spans="" pv=-1 st=0 vx e
    for (( vx = 0; vx < VW; vx++ )); do
      x=$(( (sx0 + vx) * z ))
      if (( sx0 + vx < 0 || x >= MAPW[W] )); then e=1
      else k=$(( cy * NCHX + x / 8 )); e=${EXPW:k:1}; fi
      if [[ $e != "$pv" ]]; then (( vx > 0 )) && spans+="$st:$(( vx - 1 )):$pv "; st=$vx pv=$e; fi
      (( x >= 0 && z < 8 && x / 8 == (x + z) / 8 )) && { vx=$(( vx + (8 - x % 8) / z - 1 )); (( vx > VW - 1 )) && vx=$(( VW - 1 )); }
    done
    spans+="$st:$(( VW - 1 )):$pv"
    for e in $spans; do
      v1=${e%%:*}; v2=${e#*:}; v2=${v2%:*}
      if [[ ${e##*:} == 1 ]]; then COMP_DIM=0; compose "$v1" "$v2" ${RI[ry]}
      else COMP_DIM=1; compose "$v1" "$v2" ${RF[ry]}; fi
      out+=$COMP
    done
    COMP_DIM=0
  done
  local lg=" 1:$z +/-  @ you  ! quests  x target  > dungeon  & waystone  B bank"
  [[ -n $WB_CID ]] && lg+="  ${M_GLY[WB_CT]} world boss"
  (( ${#lg} > MW )) && lg=${lg:0:MW}
  lg=${lg//"@ you"/$'\e[1;7;38;5;'"${P_COLC[COLR]}m$SYM$N${K_SYS} you"}
  lg=${lg//"! quests"/$'\e[1;38;5;16;48;5;226m!'"$N${K_SYS} quests"}
  lg=${lg//"x target"/$'\e[1;38;5;226mx'"$N${K_SYS} target"}
  lg=${lg//"> dungeon"/"${Z_ENT}$N${K_SYS} dungeon"}
  lg=${lg//"& waystone"/"${Z_WAY}$N${K_SYS} waystone"}
  lg=${lg//"B bank"/"${GLY[wbank]}$N${K_SYS} bank"}
  [[ -n $WB_CID ]] && lg=${lg//"  ${M_GLY[WB_CT]} world boss"/"  "$'\e[0;5;'"${M_COL[WB_CT]}m${M_GLY[WB_CT]}$N${K_SYS} world boss"}
  out+=$'\e['"$(( VH + 2 ));2H$N${BLANK:0:MW}"$'\e['"$(( VH + 2 ));2H${K_SYS}$lg$N"
}

render_ui() {   # panels use every column of the frame, the world map is drawn in ASCII
  local r t VW=$MW TW=1
  UIT=() UIC=() UIL=()
  for (( r = 0; r < VH; r++ )); do unset "SCR[m$r]"; done          # the map rows are covered now
  if [[ $UI == map ]]; then ui_map; return; fi
  case $UI in
    shop) ui_shop ;; inv) ui_inv ;; quest) ui_quest ;; help) ui_help ;; talk) ui_talk ;;
    qlog) ui_qlog ;; beasts) ui_bestiary ;; chatlog) ui_chatlog ;; way) ui_way ;;
    prof) ui_prof ;; craft) ui_craft ;; trade) [[ -n $TR_WITH ]] && ui_trade || UI="" ;; bank) ui_bank ;;
    allies) ui_allies ;; allyshop) ui_allyshop ;; story) ui_story ;;
    talents) if (( TL_PAGE )); then ui_paragon; else ui_talents; fi ;; jewel) ui_jewel ;; wares) ui_wares ;; qchoice) ui_qchoice ;;
    dgate) ui_dgate ;; stable) ui_stable ;; valor) ui_valor ;; ach) ui_ach ;;
    inn) ui_inn ;; visit) ui_visit ;; dsp) ui_dsp ;; book) ui_book ;; guest) ui_guest ;;
  esac
  [[ -n $UI ]] || { MAP_DIRTY=1; return; }
  for (( r = 0; r < VH; r++ )); do
    if (( ${UIL[r]:--1} > VW )); then             # too wide for the frame: cut, keep the colors
      clipl "${UIT[r]}" "$VW"; out+=$'\e['"$(( r + 3 ));2H$N$CL"
    elif (( ${UIL[r]:--1} >= 0 )); then
      out+=$'\e['"$(( r + 3 ));2H$N${UIT[r]}$N${BLANK:0:VW-UIL[r]}"
    else
      t=${UIT[r]}; dispw "$t"
      while (( DW > VW )); do t=${t:0:${#t}-1}; dispw "$t"; done
      out+=$'\e['"$(( r + 3 ));2H$N${UIC[r]}$t${BLANK:0:VW-DW}$N"
    fi
  done
}

render() {
  local out="" t0=${EPOCHREALTIME/[.,]/}
  if (( SMALL )); then
    printf '\e[H\e[2J\e[0m  shellmmorpg needs at least 100x30 characters (now %sx%s).\n  Enlarge the window, or press Q to quit.' "$COLS" "$ROWS"
    NEED_FULL=1; return
  fi
  (( NEED_FULL )) && { draw_frame; NEED_FULL=0; MAP_DIRTY=1; }
  (( NOW - ${SCR_T:-0} > 5000 )) && { SCR=(); SCR_T=$NOW; }    # now and then resend everything
  clock_now; weather_now
  render_header
  if [[ -n $UI ]]; then          # the world map is slow to draw: background changes refresh it twice a second
    if (( MAP_DIRTY )) && { (( KEYD )) || [[ $UI != map ]] || (( NOW - UI_T >= 500 )); }; then
      MAP_DIRTY=0 KEYD=0 UI_T=$NOW; render_ui
    fi
  elif (( MAP_DIRTY || NOW >= next_mapdraw )); then
    render_map; MAP_DIRTY=0; next_mapdraw=$(( NOW + 250 ))
    [[ -n $CW ]] && next_mapdraw=$(( NOW + 120 ))
  fi
  render_panel; render_log; render_input
  if [[ -n $SHELLMMO_DEBUG ]]; then
    local t1=${EPOCHREALTIME/[.,]/}; RT_SUM=$(( RT_SUM + t1 - t0 )) RT_N=$(( RT_N + 1 ))
    (( RT_N >= 20 )) && { RT_AVG=$(( RT_SUM / RT_N / 1000 )); RT_SUM=0 RT_N=0; }
    out+=$'\e[1;'"$(( COLS - 14 ))H${K_SYS}frame ${RT_AVG:-?}ms$N"
  fi
  [[ -n $out ]] && printf '%s' "$out"
}

# ---------------------------------------------------------------------------
#  Input & main loop
# ---------------------------------------------------------------------------
handle_key() {
  local k=$1 rest
  KEYD=1
  if (( CHATTING )); then
    chat_key "$k"
    while (( CHATTING )) && read -t 0; do IFS= read -rsn1 k; chat_key "$k"; done
    return
  fi
  if [[ $k == $'\e' ]]; then
    rest=""; read -rsn2 -t 0.01 rest
    case $rest in
      '[A'|OA) k=UP ;; '[B'|OB) k=DOWN ;; '[C'|OC) k=RIGHT ;; '[D'|OD) k=LEFT ;;
      '') k=ESC ;;
      *) read -rsn6 -t 0.01 rest; return ;;
    esac
  fi
  if [[ -n $UI ]]; then
    MAP_DIRTY=1
    if [[ $UI == trade ]]; then trade_key "$k"; return; fi
    if [[ $UI == bank ]]; then bank_key "$k"; [[ -z $UI ]] && NEED_FULL=1; return; fi
    if [[ $UI == story ]]; then [[ $k == @(|$'\r'|' '|ESC|q) ]] && { UI="" NEED_FULL=1; }; return; fi
    case $k in ESC|q) [[ $UI == inv ]] && inv_leave_tab; UI="" NEED_FULL=1; return ;; esac
    case $UI in
      shop)  shop_key "$k" ;;
      talk)  talk_key "$k" ;;
      inv)   if [[ $k == i ]]; then inv_leave_tab; UI=""; else inv_key "$k"; fi ;;
      quest) quest_key "$k" ;;
      map)   wm_key "$k"; [[ -z $UI ]] && NEED_FULL=1 ;;
      way)   [[ $k == [1-9] ]] && way_travel $(( k - 1 )); [[ $k == 0 ]] && way_travel 9 ;;
      help)  case $k in '?') UI="" ;; RIGHT|'>'|.|d|l|' ') (( HELP_PG < 3 )) && HELP_PG=$(( HELP_PG + 1 )) ;; LEFT|'<'|,|a|h) (( HELP_PG > 0 )) && HELP_PG=$(( HELP_PG - 1 )) ;; esac ;;
      beasts)  case $k in
                 b) UI="" ;;
                 RIGHT|'>'|.|d|l|' ') BEAST_PG=$(( BEAST_PG + 1 )) ;;
                 LEFT|'<'|,|a|h)      (( BEAST_PG > 0 )) && BEAST_PG=$(( BEAST_PG - 1 )) ;;
               esac ;;
      chatlog) [[ $k == c ]] && UI="" ;;
      prof)    [[ $k == p ]] && UI="" ;;
      craft)   craft_key "$k" ;;
      allies)  if [[ $k == y ]]; then UI=""; else aly_key "$k"; fi ;;
      allyshop) ally_shop_key "$k" ;;
      talents) if [[ $k == x ]]; then UI=""
               elif [[ $k == [pt] ]]; then TL_PAGE=$(( ! TL_PAGE ))
               elif (( TL_PAGE )); then [[ $k == [1-6] ]] && para_learn $(( k - 1 ))
               else tal_key "$k"; fi ;;
      dgate)   dgate_key "$k" ;;
      stable)  stable_key "$k" ;;
      valor)   valor_key "$k" ;;
      ach)     if [[ $k == o ]]; then UI=""; else ach_key "$k"; fi ;;
      inn)     inn_key "$k" ;;
      visit)   visit_key "$k" ;;
      dsp)     dsp_key "$k" ;;
      book)    if [[ $k == H ]]; then UI=""; else book_key "$k"; fi ;;
      jewel)   jewel_key "$k" ;;
      wares)   wares_key "$k" ;;
      qchoice) case $k in 1|a) ql_choose a ;; 2|b) ql_choose b ;; esac ;;
      qlog)    case $k in 1|2|3|4) QLOG_TAB=$(( k - 1 )) ;; LEFT) QLOG_TAB=$(( (QLOG_TAB + 3) % 4 )) ;; RIGHT|' '|$'\t') QLOG_TAB=$(( (QLOG_TAB + 1) % 4 )) ;; esac ;;
    esac
    [[ -z $UI ]] && NEED_FULL=1
    return
  fi
  if (( FISH_ST )) && [[ $k == [\ gf] ]]; then fish_strike; return; fi
  case $k in
    w|k|UP)    try_move 0 -1 ;;
    s|j|DOWN)  try_move 0 1 ;;
    a|h|LEFT)  try_move -1 0 ;;
    d|l|RIGHT) try_move 1 0 ;;
    1|2|3)     cast $(( k - 1 )) ;;
    f|' ')     melee_any ;;
    e)         use_item h ;;
    r)         use_item m ;;
    i)         UI=inv MAP_DIRTY=1 ;;
    m)         wm_open; UI=map MAP_DIRTY=1 ;;
    q)         UI=qlog MAP_DIRTY=1 ;;
    b)         UI=beasts MAP_DIRTY=1 ;;
    c)         UI=chatlog MAP_DIRTY=1 ;;
    n)         TAGS_ON=$(( ! TAGS_ON )) MAP_DIRTY=1 ;;
    v)         toggle_gfx ;;
    g)         gather_key ;;
    p)         UI=prof MAP_DIRTY=1 ;;
    u)         eat ;;
    y)         UI=allies MAP_DIRTY=1 ;;
    x)         UI=talents MAP_DIRTY=1 ;;
    z)         mount_toggle ;;
    Z)         STABLE_SRC=keys UI=stable MAP_DIRTY=1 ;;
    o)         UI=ach MAP_DIRTY=1 ;;
    H)         BOOK_PG=0 UI=book MAP_DIRTY=1 ;;
    '?')       UI=help MAP_DIRTY=1 ;;
    ''|$'\r'|t) CHATTING=1 CHAT_BUF="" ;;
    /)         CHATTING=1 CHAT_BUF="/" ;;
    Q)         exit 0 ;;
  esac
}

regen() {
  local rh rm id
  for id in "${!OP_SEEN[@]}"; do (( NOW - OP_SEEN[$id] > 10000 )) && op_del "$id"; done
  trade_tick
  (( DEAD )) && return
  weather_hazard
  v3_tick; v45_tick; v50_tick; (( DEAD )) && return
  rh=$(( MAXHP / 100 + 1 )) rm=$(( MAXMP * 3 / 100 + 1 ))
  (( NOW - last_hurt > 6000 )) && rh=$(( MAXHP * 4 / 100 + 1 ))
  if [[ $CUR_MAP == H* ]] || { [[ $CUR_MAP == W ]] && in_safe_xy "$PX" "$PY"; }; then rh=$(( rh * 3 )) rm=$(( rm * 2 )); fi   # towns and rooms
  (( NOW < fed_until )) && { rh=$(( rh * 2 )) rm=$(( rm * 2 )); }
  (( TB_REGEN )) && { rh=$(( rh * (100 + TB_REGEN) / 100 )) rm=$(( rm * (100 + TB_REGEN) / 100 )); }
  if (( HP < MAXHP || MP < MAXMP )); then
    HP=$(( HP + rh )) MP=$(( MP + rm )); (( HP > MAXHP )) && HP=$MAXHP; (( MP > MAXMP )) && MP=$MAXMP
    POS_DIRTY=1
  fi
}

choose_class() {
  local k i
  printf '\e[0m\e[2J\e[H'
  print_logo
  printf '\n   A new hero awakens. Welcome, \e[1m%s\e[0m. Choose your class:\n\n' "$MY_NAME"
  local rows=40 keys=1234567890; rows=$(stty size 2>/dev/null); rows=${rows%% *}; [[ $rows =~ ^[0-9]+$ ]] || rows=40
  for (( i = 0; i < NCLS; i++ )); do
    printf '   \e[1;38;5;226m[%s]\e[0m %s \e[1m%-11s\e[0m %s\n' "${keys:i:1}" "${CEMO[i]}" "${C_NAME[i]}" "${C_DESC[i]}"
    (( rows >= 12 + NCLS * 2 )) && printf '                   \e[38;5;245mHP %d+%d/lvl  MP %d+%d/lvl  %s / %s / %s\e[0m\n' \
      "${C_HP0[i]}" "${C_HPL[i]}" "${C_MP0[i]}" "${C_MPL[i]}" "${S_NAME[i*3]}" "${S_NAME[i*3+1]}" "${S_NAME[i*3+2]}"
  done
  printf '\n   \e[38;5;245mYour hero is saved on the server, as %s\e[0m\n' "$MY_NAME"
  while :; do
    IFS= read -rsn1 k
    [[ -n $k && $keys == *"$k"* ]] && { k=${keys%%"$k"*}; (( ${#k} < NCLS )) && { new_char "${#k}"; return; }; }
    [[ $k == [Qq] ]] && exit 0
  done
}

choose_look() {
  local k i keys="123456789abc"
  SYM="@"; name_color "$MY_NAME"; COLR=$NCI
  printf '\e[0m\e[2J\e[H'; print_logo
  printf '\n   How should the world see you?\n\n'
  printf '   Press the key of the \e[1msymbol\e[0m you want on the map (any letter, digit or sign).\n'
  printf '   Enter keeps the classic @\n\n   '
  while :; do
    IFS= read -rsn1 k
    if [[ -z $k ]]; then break; fi
    valid_sym "$k" && { SYM=$k; break; }
  done
  printf 'Symbol: \e[1m%s\e[0m\n\n   Now pick your \e[1mcolor\e[0m:\n\n' "$SYM"
  for i in "${!P_COLC[@]}"; do
    printf '   \e[1;38;5;226m[%s]\e[0m \e[1;38;5;%sm%s %-8s\e[0m' "${keys:i:1}" "${P_COLC[i]}" "$SYM" "${P_COLN[i]}"
    (( i % 4 == 3 )) && printf '\n'
  done
  printf '\n   Enter keeps \e[1;38;5;%sm%s\e[0m\n' "${P_COLC[COLR]}" "${P_COLN[COLR]}"
  while :; do
    IFS= read -rsn1 k
    [[ -z $k ]] && break
    i=${keys%%"$k"*}; [[ ${#i} -lt ${#keys} && -n $k ]] && { COLR=${#i}; break; }
  done
  save_char
}

lan_ip() {
  local ip
  ip=$(hostname -I 2>/dev/null); ip=${ip%% *}
  [[ -n $ip ]] || ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i+1)}')
  LANIP=${ip:-<your-ip>}
}

cleanup() {
  save_char
  acct_flush
  (( net_up )) && send BYE "$MY_ID" "$MY_NAME"
  [[ $MODE == host ]] && sleep 0.2
  exec 7>&- 2>/dev/null
  [[ $MODE == host ]] && stop_all
  [[ -n $old_stty ]] && stty "$old_stty" 2>/dev/null
  printf '\e[0m\e[?7h\e[?25h\e[?1049l'
  [[ -n $CLS ]] && echo "shellmmorpg: $MY_NAME (level $LVL ${C_NAME[CLS]}) saved. See you in Hearthmoor!"
  [[ -n $KICKED ]] && echo "shellmmorpg: $KICKED This session ended without saving."
}

srv_watch() {  # v6.3: the world server says something at least every 10 s (CLOCK) - silence means it is gone
  if [[ $MODE == host ]] && [[ -n $WS_PID ]] && ! alive "$WS_PID"; then
    logm "The world server stopped - restarting it (see $DATA_DIR/server.log)." "$K_HURT"
    { echo "--- restarted $(date)"; } >> "$DATA_DIR/server.log" 2>/dev/null
    alive "$HUB_PID" || start_hub
    start_world_server; LAST_SRV=$NOW
    return
  fi
  if (( net_up && NOW - ${LAST_SRV:-$NOW} > 35000 )); then
    LAST_SRV=$NOW
    logm "The world server is not answering - reconnecting..." "$K_HURT"
    net_lost
  fi
}

client_main() {
  local key tries=0 next_frame=0 next_sec=0 next_save next_reconnect=0
  trap '' PIPE
  mkdir -p "$DATA_DIR" || die "cannot create $DATA_DIR"
  load_world
  if [[ $MODE == host ]]; then
    pick_hub_tool || die "hosting needs ncat, python3 or socat (joining works with plain bash)"
    echo "Starting the world on port $NET_PORT (hub: $HUB_TOOL)..."
    start_hub || { stop_all; die "could not open port $NET_PORT - already in use? Try --port"; }
    : > "$DATA_DIR/server.log" 2>/dev/null
    start_world_server
  fi
  echo "Connecting to $NET_HOST:$NET_PORT..."
  until net_connect; do
    tries=$(( tries + 1 ))
    if (( tries > 10 )) || [[ $MODE == join ]]; then
      stop_all; die "could not connect to $NET_HOST:$NET_PORT - is the world running? Firewall?"
    fi
    sleep 0.3
  done
  [[ $MODE == host ]] && trap 'stop_all' EXIT
  acct_login                                   # v6.2: your hero lives on the server
  CHAR_REMOTE=1
  on_line() { cli_line "$1"; }
  net_lost() {
    (( net_up )) || return
    net_up=0; exec 7>&- 2>/dev/null
    local id; for id in "${!OP_NAME[@]}"; do op_del "$id"; done
    logm "Lost connection to the world server - retrying..." "$K_HURT"
  }
  old_stty=$(stty -g)
  stty -echo -icanon
  set_gfx
  printf '\e[?1049h\e[?25l\e[?7l'
  trap cleanup EXIT
  trap 'exit 0' INT TERM HUP
  trap 'RESIZED=1' WINCH
  if load_char; then
    logm "Welcome back, $MY_NAME the ${C_NAME[CLS]}!" "$K_ANN"
  else
    choose_class; choose_look
    logm "Welcome to Hearthmoor, $MY_NAME the ${C_NAME[CLS]}! Press [?] for help." "$K_ANN"
    logm "Walk into people to talk. The quest board (!) is on the plaza." "$K_SYS"
  fi
  p_walk W "$WX" "$WY" || { WX=$SPAWN_X WY=$SPAWN_Y; }
  CUR_MAP=W PX=$WX PY=$WY
  if (( GFX_NEW )); then
    save_gfx
    logm "NEW: HD graphics with emoji sprites are on. Tiles look broken or shifted? Press [v] for classic ASCII." "$K_ANN"
  fi
  init_where; init_explore; explore_here; init_lights
  now_ms
  (( ALLY >= 0 )) && aly_place
  story_intro
  send HELLO "$MY_ID" "$MY_NAME" "$CLS" "$LVL"; send_pos
  if [[ $MODE == host ]]; then
    lan_ip
    logm "Your world is online. Friends join with: ./shellmmorpg.sh --join $LANIP:$NET_PORT" "$K_PARTY"
  fi
  next_save=$(( NOW + 30000 ))
  layout
  while :; do
    now_ms
    if (( net_up )); then
      net_poll 300
    elif (( NOW >= next_reconnect )); then
      next_reconnect=$(( NOW + 5000 ))
      if net_connect && acct_resume; then
        [[ $CUR_MAP != W ]] && leave_instance quiet
        [[ -n $MY_PARTY ]] && { MY_PARTY="" PARTY_LEADER="" PARTY_IDS=(); pq_to_personal; }
        WANTED_UNTIL=0
        send HELLO "$MY_ID" "$MY_NAME" "$CLS" "$LVL"; send_pos; send SYNC "$MY_ID" W
        (( SAVE_LOST )) && save_char
        LAST_SRV=$NOW
        logm "Reconnected to the world." "$K_GOOD"
      fi
    fi
    (( ${#DOT_M[@]} )) && dot_tick
    [[ -n $GATH_MID ]] && gather_tick
    (( FISH_ST )) && fish_tick
    (( ALLY >= 0 )) && aly_tick
    if (( NOW >= next_sec )); then next_sec=$(( NOW + 1000 )); regen; srv_watch; fi
    (( DEAD && NOW >= dead_until )) && respawn
    (( clear_until && NOW >= clear_until )) && { clear_until=0; leave_instance; }
    if (( net_up )) && { (( POS_DIRTY && NOW - last_pos >= 60 )) || (( NOW - last_pos >= 2000 )); }; then send_pos; fi
    (( NOW >= next_save )) && { save_char; next_save=$(( NOW + 30000 )); }
    (( RESIZED )) && { RESIZED=0; layout; }
    if (( NOW >= next_frame )); then render; next_frame=$(( NOW + 80 )); fi
    if IFS= read -rsn1 -t 0.03 key; then now_ms; handle_key "$key"; fi
  done
}

dedicated_main() {
  trap '' PIPE
  pick_hub_tool || die "the server needs ncat, python3 or socat"
  echo "shellmmorpg dedicated server - starting hub ($HUB_TOOL) on port $NET_PORT..."
  start_hub || { stop_all; die "could not open port $NET_PORT"; }
  trap 'kill_tree "$HUB_PID"; [[ -n $HUB_DIR ]] && rm -rf "$HUB_DIR"' EXIT
  lan_ip
  if [[ -n $NET_BIND ]]; then echo "Listening on $NET_BIND only. Players: ssh -t user@host shellmmorpg-play   (docs/SERVER.md)"
  else echo "Players join with: ./shellmmorpg.sh --join $LANIP:$NET_PORT   (Ctrl+C stops the server)"; fi
  server_main
}

# ---------------------------------------------------------------------------
#  Module 05b - inventory (since v1.7): four tabs (gear, items, materials,
#  hero), a cursor, item cards that show what changes if you wear something,
#  a power score, locks, sorting and a best-gear button
# ---------------------------------------------------------------------------
INV_TAB=0 INV_CUR=(1 1 1 0) INV_TOP=(0 0 0 0) INV_CONF=-1 SORT_M=0 LR_FAST=0
MAT_NEW=(); declare -A NEWG=()
INV_TABN=(Gear Items Materials Hero) INV_TABE=(🎒 🧪 💎 👤)
SORT_NAME=(type rarity value)
MAT_I=(🥉 🔩 🥈 🥇 💎 🔮 🌼 🌿 🍀 🌹 🌷 🍁 🐟 🐠 🐡 🦑 🦐 🐬 🦈 🎏 🐋 🐍)
for (( _i = GEM0; _i < NMAT; _i++ )); do gem_kq "$_i" && MAT_I[_i]=${GEM_E[GKI]}; done; unset _i   # v3.0 gems (and v4.5's perfect ones)
MAT_I[M45]=💠 MAT_I[M45+1]=⭐ MAT_I[M45+2]=🌺 MAT_I[M45+3]=🌻 MAT_I[M45+4]=🐍 MAT_I[M45+5]=🐟 MAT_I[M45+6]=🐠 MAT_I[M45+7]=🌟
MAT_RN=(common uncommon rare) MAT_RC=("38;5;252" "1;38;5;120" "1;38;5;171")
TIER_FL=("" "It has seen better days." "Plain, solid and dependable." "Fine work from a good smithy."
         "Light as a feather, hard as stone." "Runes hum quietly along it." "Still warm from dragonfire."
         "Forged from a fallen star." "Sings softly when the stars come out." "Made from the dark between worlds."
         "Hammered on the anvils of the old titans." "Cold and dark as the sun's own shadow." "Nobody remembers who made it. Probably nobody did.")
CON_L=(h m gh gm - str iron swift brew recall - meal1 meal2 - tfrost tfire tveil)   # "-" starts the next section
CON_SEC=(POTIONS "ELIXIRS & SCROLLS" FOOD TONICS)
declare -A CON_VAR=([h]=POT_H [m]=POT_M [gh]=POT_GH [gm]=POT_GM [str]=EL_STR [iron]=EL_IRON [swift]=EL_SWIFT
                    [recall]=SCROLL [brew]=BREW [meal1]=MEAL1 [meal2]=MEAL2 [tfrost]=TON_FROST [tfire]=TON_FIRE [tveil]=TON_VEIL)
declare -A CON_KEY=([h]=e [m]=r [gh]=a [gm]=b [str]=c [iron]=d [swift]=f [recall]=g [brew]=h
                    [meal1]=j [meal2]=k [tfrost]=l [tfire]=m [tveil]=n)
declare -A CON_NM=([h]="Health potion" [m]="Mana potion" [gh]="Greater health potion" [gm]="Greater mana potion"
                   [str]="Elixir of Strength" [iron]="Elixir of Iron Skin" [swift]="Elixir of Swiftness"
                   [recall]="Scroll of Recall" [brew]="Hermit's Brew" [meal1]="Grilled Fish" [meal2]="Fisherman's Feast"
                   [tfrost]="Frost Tonic" [tfire]="Fire Ward Tonic" [tveil]="Sand Veil")
declare -A CON_FX=([h]="Restores 40% of your HP. [e] on the map drinks one."
                   [m]="Restores 50% of your MP. [r] on the map drinks one."
                   [gh]="Restores 80% of your HP. [e] picks it when you are out of small ones."
                   [gm]="Restores 80% of your MP. [r] picks it when you are out of small ones."
                   [str]="+30% damage for 90 seconds." [iron]="+50% armor for 90 seconds."
                   [swift]="You move much faster for 60 seconds." [recall]="Teleports you home to Hearthmoor."
                   [brew]="Full HP and MP at once and +30% damage for 2 minutes."
                   [meal1]="Heals 35% HP. Well Fed: double regeneration for 5 minutes. [u] eats."
                   [meal2]="Heals 70% HP and 40% MP. Well Fed+: double regeneration and +10% damage for 10 minutes."
                   [tfrost]="Blizzards can't slow you down for 5 minutes."
                   [tfire]="Burning ash can't hurt you for 5 minutes."
                   [tveil]="Your eyes pierce storms and darkness for 5 minutes.")
declare -A CON_GET=([h]="Mara (Hearthmoor), most shops. Alchemy: 2 Peacebloom." [m]="Mara (Hearthmoor), most shops. Alchemy: 2 Silverleaf."
                    [gh]="Ysolde, Garrick, Nadia. Alchemy: 2 Bog Myrtle + 1 Peacebloom." [gm]="Ysolde, Orwin. Alchemy: 2 Bog Myrtle + 1 Silverleaf."
                    [str]="Ysolde. Alchemy: 3 Desert Rose." [iron]="Ysolde. Alchemy: 2 Frost Lotus + 1 Bog Myrtle."
                    [swift]="Ysolde, Orwin, Nadia. Alchemy: Emberroot, Silverleaf, Peacebloom."
                    [recall]="Mara, Garrick." [brew]="Orwin the hermit, deep in the wilds."
                    [meal1]="Cook common fish at a campfire (*) or an inn." [meal2]="Cook a rare fish at a campfire (*) or an inn."
                    [tfrost]="Nadia and the north. Alchemy: 2 Frost Lotus." [tfire]="Nadia and the ash lands. Alchemy: 2 Emberroot."
                    [tveil]="Nadia and the desert. Alchemy: 2 Desert Rose + 1 Silverleaf.")
CON_E[bag]=🎒

# --- small helpers ---------------------------------------------------------------------
mat_icon() { MI=""; (( TW2 )) && MI=${MAT_I[$1]}; }
ico() { IC=""; (( TW2 )) && IC="$1 "; }                       # emoji + space (HD only)
mat_prof() { if (( $1 < 6 )); then MP_K=1; elif (( $1 < 12 )); then MP_K=2; elif (( $1 < NFISHE )); then MP_K=0; else MP_K=3; fi; }
# rows and card lines: RC is colored ("§" marks where a row background goes), RP its plain twin
rb() { RC="" RP=""; }
rt() { RC+=$'\e[0§'"${2:+;$2}m$1"; RP+=$1; }
rpad() { dispw "$RP"; (( DW < $1 )) && { RC+=$'\e[0§m'"${BLANK:0:$1-DW}"; RP+=${BLANK:0:$1-DW}; }; }
lr() { LR_C+=("$RC"); LR_P+=("$RP"); LR_S+=("$1"); LR_ID+=("${2:-}"); }
lh() { rb; rt "$1" "${2:-1;38;5;220}"; [[ -n $3 ]] && rt "$3" "38;5;245"; lr 0; }
cc() { CD_C+=("$RC"); CD_P+=("$RP"); }
uxs() { dispw "$RP"; if (( DW > MW )); then padt "$RP" "$MW"; uix "$K_SYS$PADS$N" "$PADS"; else uix "${RC//§/}$N" "$RP"; fi; }   # emit, never wider than the frame
cblank() { RC="" RP=""; cc; }
wrapt() {  # plain text width -> WRL (lines)
  local t=$1 w=$2 cut
  WRL=()
  while (( ${#t} > w )); do
    cut=${t:0:w+1}; cut=${cut% *}; (( ${#cut} < w / 2 )) && cut=${t:0:w}
    WRL+=("$cut"); t=${t:${#cut}}; t=${t# }
  done
  [[ -n $t ]] && WRL+=("$t")
}
ctext() { local l; wrapt "$1" "$CDW"; for l in "${WRL[@]}"; do rb; rt "$l" "${2:-38;5;250}"; cc; done; }   # wrapped card text
secs() { local s=$(( $1 / 1000 )); if (( s >= 60 )); then TS="$(( s / 60 ))m$(( s % 60 ))s"; else TS="${s}s"; fi; }

set_eq() { case $1 in W) EQW=$2 ;; A) EQA=$2 ;; O) EQO=$2 ;; H) EQH=$2 ;; *) EQJ=$2 ;; esac; }
power() { POW=$(( ATK * 3 + ARMOR * 2 + (CRIT - 10) * 4 + MAXHP / 4 + MAXMP / 8 + B_LIGHT * 5 )); }
declare -A PVC=()
pv_slot() {  # slot code -> PV_ATK PV_ARM PV_CRIT PV_HP PV_MP PV_POW: my stats if <code> was worn there ("" = nothing)
  local hp=$HP mp=$MP o key="$1|$2|$EQW|$EQA|$EQO|$EQH|$EQJ|$LVL|$CLS"
  if [[ -n ${PVC[$key]} ]]; then
    set -- ${PVC[$key]}; PV_ATK=$1 PV_ARM=$2 PV_CRIT=$3 PV_HP=$4 PV_MP=$5 PV_POW=$6; power; return
  fi
  (( ${#PVC[@]} > 600 )) && PVC=()
  eq_of "$1"; o=$EQC
  set_eq "$1" "$2"; calc_stats; power
  PV_ATK=$ATK PV_ARM=$ARMOR PV_CRIT=$CRIT PV_HP=$MAXHP PV_MP=$MAXMP PV_POW=$POW
  set_eq "$1" "$o"; calc_stats; power; HP=$hp MP=$mp
  PVC[$key]="$PV_ATK $PV_ARM $PV_CRIT $PV_HP $PV_MP $PV_POW"
}
pv_delta() {  # -> DLC DLP: colored / plain power change of the last pv_slot
  local d=$(( PV_POW - POW ))
  if (( d > 0 )); then DLC="1;38;5;84" DLP="▲$d"; elif (( d < 0 )); then DLC="38;5;203" DLP="▼${d#-}"; else DLC="38;5;242" DLP="="; fi
}

active_fx() {  # -> AFX_E AFX_N AFX_T: buffs running right now
  AFX_E=() AFX_N=() AFX_T=()
  afx() { (( NOW < $1 )) || return; secs $(( $1 - NOW )); AFX_E+=("$2"); AFX_N+=("$3"); AFX_T+=("$TS"); }
  afx "$str_until" 💪 "Strength +30% dmg"; afx "$iron_until" 🐢 "Iron Skin +50% armor"
  afx "$swift_until" 🐇 "Swiftness"; afx "$buff_until" 📣 "Battle Cry +40% dmg"; afx "$anthem_until" 🎺 "Anthem"
  if (( fed_lvl == 2 )); then afx "$fed_until" 🍲 "Well Fed+ +10% dmg"; else afx "$fed_until" 🍢 "Well Fed"; fi
  afx "$frost_until" 🧊 "Frost Tonic"; afx "$fireward_until" 🧯 "Fire Ward"; afx "$veil_until" 🥽 "Sand Veil"
  afx "$REST_UNTIL" 😴 "Well Rested +$REST_PCT% XP"                                              # v5.0
}

# --- tab contents: list rows (LR_*) ------------------------------------------------------------
inv_rows_gear() {  # width
  local W=$1 s i j c key nm nw lk nn d ok P0
  power; P0=$POW
  lh "EQUIPPED" "1;38;5;220" "   power $P0"
  for s in W A O H J; do
    eq_of "$s"; rb
    printf -v PF '%-8s' "${SLOT_LABEL[$s]}"; rt "$PF" "38;5;245"
    if [[ -n $EQC ]]; then
      item_name "$EQC" "$CLS"; item_icon "$EQC" "$CLS"
      nm=$INAME; (( TW2 )) && nm=$INSHORT
      lk="  "; [[ $EQC == *! ]] && { lk="* "; (( TW2 )) && lk=🔒; }
      nw=$(( W - 8 - (TW2 ? 7 : 0) - 2 - 6 ))
      rt "$lk" "38;5;220"; [[ -n $II ]] && rt "$II "
      padt "$nm" "$nw"; rt "$PADS" "$ICOL"
      if (( IVAL )); then printf -v PF '%5s' "+$IVAL"; rt "$PF" "1;38;5;231"; fi
    else
      rt "·  empty" "38;5;240"
    fi
    lr 1 "e:$s"
  done
  lh "BAG SLOTS" "1;38;5;220" "   your bags hold $BAGS"
  rb; printf -v PF '%-8s' Starter; rt "$PF" "38;5;245"; (( TW2 )) && rt "🎒🧵   "
  padt "Backpack" $(( W - 8 - (TW2 ? 7 : 0) - 6 )); rt "$PADS" "38;5;242"; rt "  +10" "38;5;242"; lr 0
  for j in 0 1 2; do
    rb; printf -v PF '%-8s' "Bag $(( j + 1 ))"; rt "$PF" "38;5;245"
    if [[ ${BAGEQ[j]} == [0-5] ]]; then
      item_name "B.${BAGEQ[j]}" "$CLS"; item_icon "B.${BAGEQ[j]}" "$CLS"
      [[ -n $II ]] && rt "$II "
      padt "$INAME" $(( W - 8 - (TW2 ? 7 : 0) - 6 )); rt "$PADS" "$ICOL"
      printf -v PF '%5s' "+$IVAL"; rt "$PF" "1;38;5;231"
    else
      rt "·  empty" "38;5;240"
    fi
    lr 1 "q:$j"
  done
  lh "BAGS ${#INV[@]}/$BAGS" "1;38;5;220" "   sorted by ${SORT_NAME[SORT_M]}"
  (( ${#INV[@]} )) || { rb; rt "  empty - slay monsters for loot" "38;5;242"; lr 0; }
  for i in "${!INV[@]}"; do
    c=${INV[i]}; rb
    key=" "; (( i < 10 )) && key=$(( (i + 1) % 10 ))
    rt "$key " "38;5;245"
    item_name "$c" "$CLS"; item_icon "$c" "$CLS"
    ok=0; [[ $ICLS == *"$CLS"* ]] && ok=1
    nm=$INAME; (( TW2 )) && nm=$INSHORT
    lk="  "; [[ $c == *! ]] && { lk="* "; (( TW2 )) && lk=🔒; }
    nn="  "; [[ -n ${NEWG[${c%!}]} ]] && { nn="+ "; (( TW2 )) && nn=✨; }
    nw=$(( W - 2 - 2 - (TW2 ? 7 : 0) - 6 - 2 ))
    rt "$lk" "38;5;220"
    [[ -n $II ]] && rt "$II "
    padt "$nm" "$nw"
    if [[ $IK == B ]]; then
      rt "$PADS" "$ICOL"
      bag_gain "$IKD"; if (( BG > 0 )); then padr " ▲$BG" 6; rt "$PADS" "1;38;5;84"; else rt " =    " "38;5;242"; fi
    elif [[ $IK == C ]]; then                   # v5.0: a collectable - for a display, not for wearing
      rt "$PADS" "$ICOL"; rt " show " "38;5;180"
    elif (( ok )); then
      rt "$PADS" "$ICOL"
      if (( LR_FAST )); then rt "      "
      else pv_slot "$IK" "$c"; pv_delta; padr " $DLP" 6; rt "$PADS" "$DLC"; fi
    else
      rt "$PADS" "38;5;242"; rt " ✖    " "38;5;203"
    fi
    rt "$nn" "1;38;5;226"
    lr 1 "b:$i"
  done
  (( ${#INV[@]} < BAGS )) && { rb; rt "  $(( BAGS - ${#INV[@]} )) free slots" "38;5;240"; lr 0; }
}

inv_rows_items() {  # width
  local W=$1 e sec=0 n v col nw
  lh "${CON_SEC[0]}"
  for e in "${CON_L[@]}"; do
    if [[ $e == - ]]; then sec=$(( sec + 1 )); lh "${CON_SEC[sec]}"; continue; fi
    v=${CON_VAR[$e]}; n=${!v}; rb
    rt "[${CON_KEY[$e]}] " "38;5;245"
    ci "$e"; [[ -n $CI ]] && rt "$CI"
    col="38;5;252"; (( n > 0 )) || col="38;5;242"
    nw=$(( W - 4 - (TW2 ? 3 : 0) - 6 ))
    padt "${CON_NM[$e]}" "$nw"; rt "$PADS" "$col"
    if (( n > 0 )); then printf -v PF '%6s' "x$n"; rt "$PF" "1;38;5;231"; else rt "    x0" "38;5;240"; fi
    lr 1 "c:$e"
  done
  lh "ACTIVE EFFECTS"
  active_fx
  (( ${#AFX_N[@]} )) || { rb; rt "  none - drink something!" "38;5;242"; lr 0; }
  for n in "${!AFX_N[@]}"; do
    rb; ico "${AFX_E[n]}"; [[ -n $IC ]] && rt "$IC"
    padt "${AFX_N[n]}" $(( W - (TW2 ? 3 : 0) - 7 )); rt "$PADS" "38;5;120"; printf -v PF '%7s' "${AFX_T[n]}"; rt "$PF" "1;38;5;231"
    lr 0
  done
}

inv_rows_mats() {  # width
  local W=$1 p k a b nw col tot=0 g
  for p in 1 2 0 3; do
    case $p in 1) g=🔨 ;; 2) g=🌿 ;; 0) g=🎣 ;; 3) g=💎 ;; esac
    rb; ico "$g"; [[ -n $IC ]] && rt "$IC" "1"
    if (( p == 3 )); then rt "GEMS" "1;38;5;213"; rt "  set them in at any smith" "38;5;245"
    else
    prof_next "${PROF_LV[p]}"
    printf -v PF '%-10s' "${PROF_NAME[p]^^}"; rt "$PF" "1;38;5;220"; printf -v PF '%-3d' "${PROF_LV[p]}"; rt "Lv $PF" "1;38;5;231"
    if (( PROF_LV[p] >= PROF_MAX )); then rt "MASTER" "1;38;5;84"
    else pbar "${PROF_XP[p]}" "$PN" 10 $'\e[38;5;220m'; RC+="$PB"; RP+=${BLANK:0:10}; fi
    fi
    lr 0
    for k in ${MAT_GRP[p]}; do
      rb; mat_icon "$k"; [[ -n $MI ]] && rt "$MI "
      col=${MAT_RC[${MAT_RARE[k]}]}; (( MATS[k] > 0 )) || col="38;5;242"
      nw=$(( W - (TW2 ? 3 : 0) - 6 - 5 - 1 ))
      padt "${MAT_NAME[k]}" "$nw"; rt "$PADS" "$col"
      if (( MATS[k] > 0 )); then printf -v PF '%6s' "${MATS[k]}"; rt "$PF" "1;38;5;231"; else rt "     0" "38;5;240"; fi
      if (( ${MAT_NEW[k]:-0} > 0 )); then printf -v PF ' %-4s' "+${MAT_NEW[k]}"; rt "$PF" "1;38;5;84"; else rt "     "; fi
      tot=$(( tot + MATS[k] * MAT_VAL[k] ))
      lr 1 "m:$k"
    done
  done
  rb; rt "worth about ${tot}g in total" "38;5;245"; lr 0
}

inv_rows_hero() {  # width
  local W=$1 s i pad=$(( ($1 - 2) / 2 - 9 )) e c t
  (( pad < 0 )) && pad=0
  dollc() { eq_of "$1"; if [[ -n $EQC ]]; then item_stats "$EQC"; DC=$IKE; else DC="··"; fi; }
  if (( TW2 )); then
    rb; lr 0
    dollc H; rb; rt "${BLANK:0:pad+8}"; rt "$DC"; lr 0
    dollc W; local dw=$DC; dollc O; rb; rt "${BLANK:0:pad}"; rt "$dw" ; rt "      "; rt "${CEMO[CLS]}"; rt "      "; rt "$DC"; lr 0
    dollc A; rb; rt "${BLANK:0:pad+8}"; rt "$DC"; lr 0
    dollc J; rb; rt "${BLANK:0:pad+8}"; rt "$DC"; lr 0
    rb; lr 0
  fi
  rb; rt "$MY_NAME" "1;38;5;${P_COLC[COLR]}"; rt "  Level $LVL ${C_NAME[CLS]}" "1;38;5;231"; lr 0
  rb; rt "XP " "38;5;245"; pbar "$XP" "$XPNEXT" 16 $'\e[38;5;220m'; RC+="$PB"; RP+=${BLANK:0:16}
  rt " $XP/$XPNEXT" "38;5;245"; lr 0
  rb; rt "HP " "38;5;245"; hp_col "$HP" "$MAXHP"; pbar "$HP" "$MAXHP" 16 "$HC"; RC+="$PB"; RP+=${BLANK:0:16}; rt " $HP/$MAXHP" "38;5;245"; lr 0
  rb; rt "MP " "38;5;245"; pbar "$MP" "$MAXMP" 16 $'\e[38;5;33m'; RC+="$PB"; RP+=${BLANK:0:16}; rt " $MP/$MAXMP" "38;5;245"; lr 0
  rb; lr 0
  rb; ico 💰; rt "$IC" ; rt "$GOLD gold" "1;38;5;220"; rt "   "; ico 🎒; rt "$IC"; rt "bags ${#INV[@]}/$BAGS" "38;5;252"; lr 0
  rb; ico 💀; rt "$IC"; rt "$KILLS kills" "38;5;252"; rt "   "; ico 👻; rt "$IC"; rt "$DEATHS deaths" "38;5;252"; lr 0
  rb; ico 📜; rt "$IC"; rt "${#QUESTS[@]}/3 quests" "38;5;252"; lr 0
  rb; lr 0
  lh "PROFESSIONS"
  for i in 0 1 2; do
    prof_next "${PROF_LV[i]}"; rb
    case $i in 0) e=🎣 ;; 1) e=🔨 ;; 2) e=🌿 ;; esac
    ico "$e"; rt "$IC"; printf -v PF '%-10s Lv %-3d' "${PROF_NAME[i]}" "${PROF_LV[i]}"; rt "$PF" "38;5;252"
    if (( PROF_LV[i] >= PROF_MAX )); then rt "MASTER" "1;38;5;84"
    else pbar "${PROF_XP[i]}" "$PN" 10 $'\e[38;5;220m'; RC+="$PB"; RP+=${BLANK:0:10}; fi
    lr 0
  done
}

inv_build() {  # width -> LR_* for the current tab
  LR_C=() LR_P=() LR_S=() LR_ID=()
  case $INV_TAB in 0) inv_rows_gear "$1" ;; 1) inv_rows_items "$1" ;; 2) inv_rows_mats "$1" ;; 3) inv_rows_hero "$1" ;; esac
}

inv_fixcur() {  # keep the cursor on a row that can be selected
  local n=${#LR_S[@]} c=${INV_CUR[INV_TAB]} j
  (( c >= n )) && c=$(( n - 1 )); (( c < 0 )) && c=0
  if (( ! ${LR_S[c]:-0} )); then
    for (( j = c; j < n; j++ )); do (( LR_S[j] )) && break; done
    if (( j >= n )); then for (( j = c; j >= 0; j-- )); do (( LR_S[j] )) && break; done; fi
    c=$j
  fi
  INV_CUR[INV_TAB]=$c
}

# --- the card on the right ----------------------------------------------------------------
cmp_row() {  # label old new [suffix]
  local d=$(( $3 - $2 )) col="38;5;242" t="" sx=${4:-}
  (( d > 0 )) && { col="1;38;5;84" t="▲$d"; }; (( d < 0 )) && { col="38;5;203" t="▼${d#-}"; }
  (( d )) || return
  rb; printf -v PF '%-8s%5s →%5s ' "$1" "$2$sx" "$3$sx"; rt "$PF" "38;5;250"; rt "$t" "$col"; cc
}

inv_card_bag() {  # code worn-slot ("" = in your bags)
  local c=$1 j=$2 k nb
  item_name "$c" "$CLS"; item_icon "$c" "$CLS"; k=$IKD
  rb; [[ -n $II ]] && rt "$II "; rt "$INAME" "$ICOL"; cc
  rb; rt "${RAR_NAME[IRR]} bag · $IVAL slots" "38;5;245"; cc
  ctext "${BAG_FL[k]}" "3;38;5;244"
  cblank
  rb; ico 🎒; rt "$IC"; rt "+$IVAL bag slots" "1;38;5;231"; cc
  rb; ico 💰; rt "$IC"; rt "sells for ${ISELL}g" "38;5;220"; cc
  [[ $c == *! ]] && { rb; ico 🔒; rt "$IC"; rt "locked - shops won't buy it" "38;5;220"; cc; }
  cblank
  if [[ -n $j ]]; then
    nb=$(( BAGS - IVAL ))
    rb; rt "Take it off: " "38;5;250"; rt "$BAGS → $nb slots" "1;38;5;203"; cc
    (( ${#INV[@]} + 1 > nb )) && ctext "Make room first: you carry ${#INV[@]} items." "38;5;203"
  else
    bag_gain "$k"
    if (( BG > 0 )); then
      rb; rt "Put it on: " "38;5;250"; rt "$BAGS → $(( BAGS + BG )) slots" "1;38;5;84"; cc
      [[ ${BAGEQ[BGJ]} == [0-5] ]] && ctext "It replaces your ${BAG_NAME[${BAGEQ[BGJ]}]}." "38;5;245"
    else
      ctext "All 3 bag slots already hold bags at least this big. Sell it, store it at a banker or trade it." "38;5;245"
    fi
  fi
}

inv_card_col() {  # code: a collectable (v5.0)
  local c=$1 k s l
  item_name "$c" "$CLS"; item_icon "$c" "$CLS"; k=$IKD s=${CL_SET[IKD]}
  wrapt "$INAME" $(( CDW - (TW2 ? 7 : 0) ))
  rb; [[ -n $II ]] && rt "$II "; rt "${WRL[0]}" "$ICOL"; cc
  for l in "${WRL[@]:1}"; do rb; rt "$l" "$ICOL"; cc; done
  ctext "${RAR_NAME[IRR]} collectable · ${CS_NAME[s]}" "38;5;245"
  ctext "${CL_FL[k]}" "3;38;5;244"
  cblank
  rb; rt "FROM" "1;38;5;220"; cc
  ctext "${CL_SRC[k]}" "38;5;250"
  cblank
  col_count
  rb; ico "${CS_E[s]}"; rt "$IC"; rt "${CLSD[s]}/${CLST[s]} ${CS_NAME[s]} found" "1;38;5;231"; cc
  rb; ico 💰; rt "$IC"; rt "sells for ${ISELL}g" "38;5;220"; cc
  [[ $c == *! ]] && { rb; ico 🔒; rt "$IC"; rt "locked - always kept" "38;5;220"; cc; }
  cblank
  if (( ROOM_T )); then ctext "Put it on a display in your room: walk into a display there." "38;5;180"
  else ctext "Rent a room at any inn [9] and put it on a display for all to see." "38;5;180"; fi
  ctext "Shops buy the ones you have twice [c]." "38;5;245"
}

inv_card_gear() {  # id
  local id=$1 c worn=0 s nm col k kn t r v bt cl sell ok l uq fl
  case $id in
    q:*) s=${id#q:}
         if [[ ${BAGEQ[s]} == [0-5] ]]; then inv_card_bag "B.${BAGEQ[s]}" "$s"
         else
           rb; rt "Empty bag slot" "1;38;5;231"; cc; cblank
           ctext "Put a bag on with [enter] in your bags. Mara, Garrick, Nadia, Jarl Hrolf and Ser Kael sell them; bosses drop the big ones." "38;5;250"
         fi
         return ;;
    b:*) c=${INV[${id#b:}]}; [[ $c == B.* ]] && { inv_card_bag "$c" ""; return; }
         [[ $c == C.* ]] && { inv_card_col "$c"; return; } ;;
    e:*) s=${id#e:}; eq_of "$s"; c=$EQC; worn=1 ;;
    *) return ;;
  esac
  if [[ -z $c ]]; then
    rb; rt "Empty ${SLOT_LABEL[$s],,} slot" "1;38;5;231"; cc; cblank
    ctext "Monsters drop gear for every slot. Smiths and traders sell some, and other players trade it."
    return
  fi
  item_name "$c" "$CLS"; item_icon "$c" "$CLS"; bonus_txt
  nm=$INAME col=$ICOL k=$IK kn=$IKN t=$IT r=$IRR v=$IVAL bt=$BTX cl=$ICLS sell=$ISELL uq=$IUQ fl=${TIER_FL[IT]}
  if [[ -n $uq ]]; then                       # uniques: say what kind of thing it is, tell its own story
    case $k in W) kn=${WK_NAME[IKD]} ;; A) kn=${AK_NAME[IKD]} ;; O) kn=${OK_NAME[IKD]} ;; H) kn=${HK_NAME[IKD]} ;; *) kn=${JK_NAME[IKD]} ;; esac
    fl=${U_FL[uq]}
  fi
  ok=0; [[ $cl == *"$CLS"* ]] && ok=1
  wrapt "$nm" $(( CDW - (TW2 ? 7 : 0) ))
  rb; [[ -n $II ]] && rt "$II "; rt "${WRL[0]}" "$col"; cc
  for l in "${WRL[@]:1}"; do rb; rt "$l" "$col"; cc; done
  rb; rt "${RAR_NAME[r]} ${SLOT_LABEL[$k],,} · $kn" "38;5;245"; cc
  ctext "$fl" "3;38;5;244"
  [[ -n $uq ]] && ctext "${TIER_Q[t]} tier - the only one of its kind." "38;5;208"
  cblank
  if (( v )); then
    rb; if [[ $k == W ]]; then ico 💥; rt "$IC"; rt "+$v damage" "1;38;5;231"; else ico 🔰; rt "$IC"; rt "+$v armor" "1;38;5;231"; fi; cc
  fi
  [[ -n $bt ]] && { rb; ico ✨; rt "$IC"; rt "$bt" "1;38;5;117"; cc; }
  sock_info "$c"
  if (( SN )); then                           # v3.0: sockets and gems
    gems_txt "$c"; gems_plain "$c"
    rb; ico 💎; rt "$IC"; (( TW2 )) && rt "$GTX " "1"; rt "$SF/$SN sockets${GPL:+: $GPL}" "1;38;5;213"; cc
  fi
  cls_list "$cl"
  if (( ok )); then rb; ico 👥; rt "$IC"; rt "✔ " "1;38;5;84"; rt "$CLT" "38;5;250"; cc
  else rb; ico 👥; rt "$IC"; rt "✖ " "1;38;5;203"; rt "only $CLT" "38;5;203"; cc; fi
  rb; ico 💰; rt "$IC"; rt "sells for ${sell}g" "38;5;220"; cc
  [[ $c == *! ]] && { rb; ico 🔒; rt "$IC"; rt "locked - shops won't buy it" "38;5;220"; cc; }
  cblank
  if (( worn )); then
    if [[ $k == [WA] ]]; then ctext "You are wearing it. Equip another ${SLOT_LABEL[$k],,} from your bags to swap." "38;5;245"
    else
      pv_slot "$k" ""; rb; rt "If you take it off:" "1;38;5;231"; cc
      cmp_row Power "$POW" "$PV_POW"; cmp_row Attack "$ATK" "$PV_ATK"; cmp_row Armor "$ARMOR" "$PV_ARM"
      cmp_row Crit "$CRIT" "$PV_CRIT" %; cmp_row "Max HP" "$MAXHP" "$PV_HP"; cmp_row "Max MP" "$MAXMP" "$PV_MP"
    fi
  elif (( ok )); then
    pv_slot "$k" "$c"
    eq_of "$k"
    if [[ -n $EQC ]]; then item_name "$EQC" "$CLS"; rb; rt "Instead of your " "1;38;5;231"; padt "$IKN:" $(( CDW - 16 )); rt "$PADS" "1;$ICOL"; cc
    else ctext "Fills your empty ${SLOT_LABEL[$k],,} slot:" "1;38;5;231"; fi
    local n0=${#CD_C[@]}
    cmp_row Power "$POW" "$PV_POW"; cmp_row Attack "$ATK" "$PV_ATK"; cmp_row Armor "$ARMOR" "$PV_ARM"
    cmp_row Crit "$CRIT" "$PV_CRIT" %; cmp_row "Max HP" "$MAXHP" "$PV_HP"; cmp_row "Max MP" "$MAXMP" "$PV_MP"
    (( ${#CD_C[@]} > n0 )) || { rb; rt "no change at all" "38;5;242"; cc; }
  else
    ctext "A ${C_NAME[CLS]} can't use this. Sell it, or /trade it to someone who can." "38;5;203"
  fi
}

inv_card_items() {  # id
  local e=${1#c:} v n
  [[ $1 == c:* ]] || return
  v=${CON_VAR[$e]}; n=${!v}
  rb; ci "$e"; [[ -n $CI ]] && rt "$CI"; rt "${CON_NM[$e]}" "1;38;5;231"; cc
  if (( n > 0 )); then rb; rt "You have $n" "1;38;5;84"; cc; else rb; rt "You have none" "38;5;203"; cc; fi
  cblank
  ctext "${CON_FX[$e]}" "38;5;252"
  cblank
  rb; rt "WHERE TO GET IT" "1;38;5;220"; cc
  ctext "${CON_GET[$e]}" "38;5;245"
  cblank
  if (( n > 0 )); then rb; rt "[enter]" "1;38;5;226"; rt " or " "38;5;245"; rt "[${CON_KEY[$e]}]" "1;38;5;226"; rt " use it now" "38;5;245"; cc; fi
}

mat_found() {  # material -> MF (where it comes from)
  local k=$1 t kind e f rq rr cond z zones="" req=1 night=""
  if mat_node "$k"; then
    t=$MNT_T; node_prof "$t"
    MF="${M_NAME[t]}, ${PROF_NAME[NPK]} ${M_LVL[t]}+. ${MW_NAME[t]}."
    return
  fi
  for kind in "${!FISHW[@]}"; do
    for e in ${FISHW[$kind]}; do
      IFS=: read -r f rq rr cond <<< "$e"
      (( f == k )) || continue
      req=$rq; [[ $cond == night ]] && night=" Only bites at night."
      for z in "${!WATER_OF[@]}"; do [[ ${WATER_OF[$z]} == "$kind" ]] && zones+="${z//_/ }, "; done
      [[ $kind == fresh ]] && zones+="rivers and ponds, "
    done
  done
  MF="Fishing $req+. ${zones%, }.$night"
}

mat_uses() {  # material -> MU (lines)
  local k=$1 i t TW2=0 sv=$CRAFT
  MU=()
  if gem_kq "$k"; then
    local g=$GKI q=$(( GQI - 1 )) v=(${GEM_V[GKI]})
    MU+=("In a socket: +${v[q]}${GEM_TXT[g]}." "Jewelcrafting at any smith sets it into gear with sockets.")
    (( q < 2 )) && MU+=("Three of them make one ${GEM_GRADE[q+1]} ${GEM_NAME[g]}.")
    return
  fi
  if (( k < 6 )); then
    t=$(( k + 2 )); MU+=("Forge (Brom): ${TIER_Q[t]} weapons and armor - 6 ore + $(( 15 * t * t ))g, often Rare or better.")
  elif (( k < 12 )); then
    CRAFT=alch; craft_build
    for i in "${!RC_ID[@]}"; do
      [[ " ${RC_NEED[i]} " == *" $k:"* ]] || continue
      t=" ${RC_NEED[i]}"; t=${t#* $k:}; t=${t%% *}
      MU+=("Alchemy: ${RC_LAB[i]%% (*} ($t)")
    done
    CRAFT=$sv
  else
    if (( MAT_RARE[k] == 2 )); then MU+=("Cooking: Fisherman's Feast"); else MU+=("Cooking: Grilled Fish"); fi
    MU+=("Mara, Garrick and Nadia buy fish.")
  fi
}

inv_card_mats() {  # id
  local k=${1#m:} l
  [[ $1 == m:* ]] || return
  mat_prof "$k"; mat_icon "$k"
  rb; [[ -n $MI ]] && rt "$MI "; rt "${MAT_NAME[k]}" "${MAT_RC[${MAT_RARE[k]}]}"; cc
  rb; rt "${PROF_NAME[MP_K]:-Jewelcrafting} · ${MAT_RN[${MAT_RARE[k]}]}" "38;5;245"; cc
  cblank
  rb; rt "You have " "38;5;250"; rt "${MATS[k]}" "1;38;5;231"
  (( ${MAT_NEW[k]:-0} > 0 )) && rt "  (+${MAT_NEW[k]} new)" "1;38;5;84"
  cc
  rb; ico 💰; rt "$IC"; rt "${MAT_VAL[k]}g each, $(( MATS[k] * MAT_VAL[k] ))g for all" "38;5;220"; cc
  cblank
  rb; rt "FOUND" "1;38;5;220"; cc
  mat_found "$k"; ctext "$MF" "38;5;250"
  cblank
  rb; rt "USED FOR" "1;38;5;220"; cc
  mat_uses "$k"; for l in "${MU[@]}"; do ctext "$l" "38;5;250"; done
}

inv_card_hero() {
  local s n
  power
  rb; rt "COMBAT" "1;38;5;220"; cc
  rb; ico ⚡; rt "$IC"; rt "Power  " "38;5;245"; rt "$POW" "1;38;5;226"; cc
  rb; ico 💥; rt "$IC"; rt "Attack " "38;5;245"; rt "$ATK" "1;38;5;231"; cc
  rb; ico 🔰; rt "$IC"; rt "Armor  " "38;5;245"; rt "$ARMOR" "1;38;5;231"; cc
  rb; ico 🎯; rt "$IC"; rt "Crit   " "38;5;245"; rt "$CRIT%" "1;38;5;231"; cc
  cblank
  rb; rt "FROM YOUR GEAR" "1;38;5;220"; cc
  rb; rt "+$B_HP% HP  +$B_MP% MP  +$B_DMG% dmg" "38;5;117"; cc
  rb; rt "+$B_ARM armor  +$B_LIGHT light" "38;5;117"; cc
  cblank
  rb; rt "ACTIVE EFFECTS" "1;38;5;220"; cc
  active_fx
  (( ${#AFX_N[@]} )) || { rb; rt "none" "38;5;242"; cc; }
  for n in "${!AFX_N[@]}"; do rb; ico "${AFX_E[n]}"; rt "$IC"; rt "${AFX_N[n]} " "38;5;120"; rt "${AFX_T[n]}" "1;38;5;231"; cc; done
  (( NOW < WANTED_UNTIL )) && { cblank; rb; rt "WANTED by the guards!" "1;38;5;203"; cc; }
}

inv_card() {  # id
  CD_C=() CD_P=()
  case $INV_TAB in 0) inv_card_gear "$1" ;; 1) inv_card_items "$1" ;; 2) inv_card_mats "$1" ;; 3) inv_card_hero ;; esac
}

# --- drawing ---------------------------------------------------------------------------
ui_inv() {
  local lw rw H r li top cur n bg mk lc lp line plain i id narrow=0 nl nc foot1 foot2 badge t
  lw=$(( MW * 54 / 100 )); (( lw > 46 )) && lw=46; (( lw < 36 )) && lw=36
  rw=$(( MW - lw - 3 ))
  (( rw < 26 )) && { narrow=1 lw=$(( MW - 2 )) rw=$(( MW - 2 )); }
  CDW=$(( rw - 4 ))
  # tab bar
  rb; rt " "
  for i in 0 1 2 3; do
    badge=""; (( i == 0 && ${#NEWG[@]} )) && badge=" •${#NEWG[@]}"
    if (( i == 2 )); then n=0; for t in "${MAT_NEW[@]}"; do n=$(( n + t )); done; (( n )) && badge=" •$n"; fi
    ico "${INV_TABE[i]}"
    if (( i == INV_TAB )); then rt " $IC${INV_TABN[i]}$badge " "1;38;5;16;48;5;220"
    else rt " $IC${INV_TABN[i]}" "38;5;250"; [[ -n $badge ]] && rt "$badge" "1;38;5;84"; rt " "; fi
    rt " "
  done
  ico 💰; t="$IC$GOLD"; dispw "$RP$t"; (( DW < MW - 2 )) && rt "${BLANK:0:MW-2-DW}"; rt "$t" "1;38;5;220"
  uxs
  # stats
  power; rb
  rt " Power " "38;5;245"; rt "$POW" "1;38;5;226"; rt "   Attack " "38;5;245"; rt "$ATK" "1;38;5;231"
  rt "  Armor " "38;5;245"; rt "$ARMOR" "1;38;5;231"; rt "  Crit " "38;5;245"; rt "$CRIT%" "1;38;5;231"
  rt "  HP " "38;5;245"; rt "$MAXHP" "1;38;5;231"; rt "  MP " "38;5;245"; rt "$MAXMP" "1;38;5;231"
  dispw "$RP"; (( DW <= MW )) || { rb; rt " Power $POW  Atk $ATK  Arm $ARMOR  Crit $CRIT%" "38;5;250"; }
  uxs
  t=${BLANK:0:MW}; uix "$K_FRAME${t// /─}$N" "$t"
  # list + card
  LR_FAST=0; inv_build $(( lw - 2 )); inv_fixcur
  cur=${INV_CUR[INV_TAB]}; id=${LR_ID[cur]:-}
  inv_card "$id"
  nc=${#CD_C[@]} n=${#LR_C[@]}
  H=$(( VH - 5 ))
  if (( narrow )); then (( nc > H / 2 )) && nc=$(( H / 2 )); else (( nc > H - 2 )) && nc=$(( H - 2 )); fi
  nl=$H; (( narrow && nc )) && { nl=$(( H - nc - 2 )); (( nl < 6 )) && nl=6; }
  top=${INV_TOP[INV_TAB]}
  (( cur >= 0 && cur < top )) && top=$cur
  (( cur >= top + nl )) && top=$(( cur - nl + 1 ))
  (( top > n - nl )) && top=$(( n - nl )); (( top < 0 )) && top=0
  INV_TOP[INV_TAB]=$top
  for (( r = 0; r < H; r++ )); do
    lc="" lp=""
    if (( r < nl )); then
      li=$(( top + r ))
      if (( li < n )); then
        bg="" mk="  "
        if (( li == cur )); then bg=";48;5;237"; mk=$'\e[0;1;38;5;226;48;5;237m▶ '
        elif (( r == 0 && top > 0 )); then mk=$'\e[0;38;5;245m▲ '
        elif (( r == nl - 1 && li < n - 1 )); then mk=$'\e[0;38;5;245m▼ '; fi
        lc="$mk${LR_C[li]//§/$bg}" lp="  ${LR_P[li]}"
        dispw "$lp"; (( DW < lw )) && { lc+=$'\e[0'"${bg}m${BLANK:0:lw-DW}"; lp+=${BLANK:0:lw-DW}; }
        lc+=$N
      else
        lc=${BLANK:0:lw} lp=$lc
      fi
    fi
    if (( narrow )); then
      (( r < nl )) || { i=$(( r - nl - 1 )); inv_cardline "$i" "$nc"; lc=$CLC lp=$CLP; }
      uix " $lc" " $lp"
    else
      inv_cardline $(( r - 1 )) "$nc"
      uix " $lc $CLC" " $lp $CLP"
    fi
  done
  # footer
  case $INV_TAB in
    0) foot1="[↑↓] select  [enter] equip/put on  [l] lock  [x] destroy  [o] sort: ${SORT_NAME[SORT_M]}"
       foot2="[1-0] quick equip  [b] best gear  [←→/tab] tabs  [esc] close" ;;
    1) foot1="[↑↓] select  [enter] use  [a-n] quick use  [e/r] potions"
       foot2="[←→/tab] tabs  [esc] close   - [u] eats on the map" ;;
    2) foot1="Gather: [g] at veins, herbs and water. Forge/brew/cook at NPCs."
       foot2="[↑↓] select  [←→/tab] tabs  [esc] close" ;;
    3) foot1="Power: what your gear and level are worth in a fight."
       foot2="[←→/tab] tabs  [esc] close" ;;
  esac
  if (( INV_CONF >= 0 )) && [[ -n ${INV[INV_CONF]} ]]; then item_name "${INV[INV_CONF]}" "$CLS"; ui "  Press [x] again to destroy $INAME - it will be gone for good." "$K_HURT"
  else ui "  $foot1" "$K_SYS"; fi
  ui "  $foot2" "$K_SYS"
}

inv_cardline() {  # row count -> CLC CLP: one line of the bordered card (row -1 = top border)
  local r=$1 n=$2 t
  CLC="" CLP=""
  (( n )) || return
  if (( r == -1 )); then t=${BLANK:0:rw-2}; CLC="$K_FRAME╭${t// /─}╮$N" CLP="╭${t}╮"
  elif (( r == n )); then t=${BLANK:0:rw-2}; CLC="$K_FRAME╰${t// /─}╯$N" CLP="╰${t}╯"
  elif (( r >= 0 && r < n )); then
    t=${CD_P[r]}; dispw "$t"
    if (( DW > CDW )); then padt "$t" "$CDW"; CLC="$K_FRAME│$N $PADS $K_FRAME│$N" CLP="│ $PADS │"
    else CLC="$K_FRAME│$N ${CD_C[r]//§/}$N${BLANK:0:CDW-DW} $K_FRAME│$N" CLP="│ $t${BLANK:0:CDW-DW} │"; fi
  fi
}

# --- keys ------------------------------------------------------------------------------
inv_leave_tab() { case $INV_TAB in 0) NEWG=() ;; 2) MAT_NEW=() ;; esac; INV_CONF=-1; }

inv_tab() { inv_leave_tab; INV_TAB=$(( (INV_TAB + $1 + 4) % 4 )); }

inv_move() {  # -1 | 1 | -10 | 10
  local c n j step=1
  LR_FAST=1; inv_build 40; LR_FAST=0; inv_fixcur
  c=${INV_CUR[INV_TAB]} n=${#LR_S[@]}
  (( $1 < 0 )) && step=-1
  for (( j = c + step; j >= 0 && j < n; j += step )); do (( LR_S[j] )) && { c=$j; (( ${1#-} == 1 )) && break; }; done
  INV_CUR[INV_TAB]=$c
}

inv_key() {
  local k=$1 id conf=$INV_CONF
  INV_CONF=-1
  case $k in
    LEFT|'[') inv_tab -1; return ;;
    RIGHT|']'|$'\t') inv_tab 1; return ;;
    UP|w) inv_move -1; return ;;
    DOWN|s) inv_move 1; return ;;
  esac
  LR_FAST=1; inv_build 40; LR_FAST=0; inv_fixcur
  id=${LR_ID[${INV_CUR[INV_TAB]}]:-}
  case $INV_TAB in
    0) case $k in
         ''|$'\r'|' '|e) case $id in b:*) inv_equip "${id#b:}" ;; e:*) inv_unequip "${id#e:}" ;; q:*) bag_unequip "${id#q:}" ;; esac ;;
         [1-9]) inv_equip $(( k - 1 )) ;;
         0) inv_equip 9 ;;
         l|L) inv_lock "$id" ;;
         x|X) inv_destroy "$id" "$conf" ;;
         o|O) SORT_M=$(( (SORT_M + 1) % 3 )); inv_sort ;;
         b|B) inv_best ;;
       esac ;;
    1) case $k in
         ''|$'\r'|' ') [[ $id == c:* ]] && use_item "${id#c:}" ;;
         e) use_item h ;; r) use_item m ;;
         a) use_item gh ;; b) use_item gm ;; c) use_item str ;; d) use_item iron ;;
         f) use_item swift ;; g) use_item recall ;; h) use_item brew ;;
         j) use_item meal1 ;; k) use_item meal2 ;; l) use_item tfrost ;;
         m) use_item tfire ;; n) use_item tveil ;;
       esac ;;
  esac
}

inv_equip() {  # bag index [quiet]
  local i=$1 old c pl
  (( i < ${#INV[@]} )) || return 1
  c=${INV[i]}; item_name "$c" "$CLS"
  if [[ $IK == B ]]; then [[ $2 == quiet ]] && return 1; bag_equip "$i"; return; fi
  if [[ $IK == C ]]; then                                      # v5.0
    [[ $2 == quiet ]] || logm "You can't wear the $INAME - put it on a display in your room (any innkeeper, [9])." "$K_SYS"
    return 1
  fi
  if [[ $ICLS != *"$CLS"* ]]; then
    pl=${IKN}s; [[ $IKN == *s ]] && pl=$IKN
    cls_list "$ICLS"; logm "A ${C_NAME[CLS]} can't use $pl - only $CLT. Sell or trade it." "$K_HURT"; return 1
  fi
  eq_of "$IK"; old=$EQC
  set_eq "$IK" "$c"
  if [[ -n $old ]]; then INV[i]=$old; else unset "INV[i]"; INV=("${INV[@]}"); fi
  unset "NEWG[${c%!}]"
  calc_stats
  [[ $2 == quiet ]] || logm "Equipped $INAME. Attack $ATK, armor $ARMOR, crit $CRIT%." "$K_GOOD"
  POS_DIRTY=1
}

inv_unequip() {  # slot
  local s=$1
  if [[ $s == [WA] ]]; then logm "You always keep a weapon and armor on - equip another one to swap." "$K_SYS"; return; fi
  eq_of "$s"; [[ -n $EQC ]] || return
  (( ${#INV[@]} < BAGS )) || { logm "Your bags are full." "$K_HURT"; return; }
  item_name "$EQC" "$CLS"
  INV+=("$EQC"); set_eq "$s" ""; calc_stats
  logm "You take off $INAME." "$K_SYS"
}

inv_lock() {  # id
  local id=$1 i c s
  case $id in
    b:*) i=${id#b:}; c=${INV[i]}; [[ -n $c ]] || return
         if [[ $c == *! ]]; then INV[i]=${c%!}; else INV[i]="$c!"; fi; c=${INV[i]} ;;
    e:*) s=${id#e:}; eq_of "$s"; c=$EQC; [[ -n $c ]] || return
         if [[ $c == *! ]]; then c=${c%!}; else c="$c!"; fi; set_eq "$s" "$c" ;;
    *) return ;;
  esac
  item_name "$c" "$CLS"
  if [[ $c == *! ]]; then logm "Locked $INAME - shops won't buy it and it can't be destroyed." "$K_LOOT"
  else logm "Unlocked $INAME." "$K_SYS"; fi
}

inv_destroy() {  # id confirmed-index
  local i
  [[ $1 == b:* ]] || { [[ $1 == e:* ]] && logm "Take it off first." "$K_SYS"; return; }
  i=${1#b:}; [[ -n ${INV[i]} ]] || return
  if [[ ${INV[i]} == *! ]]; then logm "That one is locked - unlock it with [l] first." "$K_HURT"; return; fi
  if (( $2 == i )); then
    item_name "${INV[i]}" "$CLS"; unset "INV[i]"; INV=("${INV[@]}")
    logm "You smash the $INAME to pieces." "$K_HURT"
  else
    INV_CONF=$i
  fi
}

inv_sort() { sort_items INV; logm "Bags sorted by ${SORT_NAME[SORT_M]}." "$K_SYS"; }

sort_items() {  # array name: by SORT_M (type, rarity or value) - things you can use first
  local -n sarr=$1
  local c k u si ord=WAOHJBC lines=() l
  for c in "${sarr[@]}"; do
    item_stats "$c"; u=1; [[ $ICLS == *"$CLS"* ]] && u=0
    si=${ord%%"$IK"*}; si=${#si}
    case $SORT_M in
      0) k=$(( u * 10000000 + si * 1000000 + 999999 - IVAL * 100 - IBV )) ;;
      1) k=$(( u * 10000000 + (4 - IRR) * 1000000 + (9 - IT) * 100000 + si * 10000 + 9999 - IVAL )) ;;
      *) l=$ISELL; (( l > 999999 )) && l=999999; k=$(( u * 10000000 + 999999 - l )) ;;
    esac
    printf -v l '%08d %s' "$k" "$c"; lines+=("$l")
  done
  (( ${#lines[@]} )) && mapfile -t "$1" < <(printf '%s\n' "${lines[@]}" | sort | cut -d' ' -f2)
}

inv_best() {  # wear the strongest thing you have for every slot
  local s i c bi bp n=0 names=""
  for s in W A O H J; do
    power; bp=$POW bi=-1
    for i in "${!INV[@]}"; do
      c=${INV[i]}; item_stats "$c"
      [[ $IK == "$s" && $ICLS == *"$CLS"* ]] || continue
      pv_slot "$s" "$c"; (( PV_POW > bp )) && { bp=$PV_POW bi=$i; }
    done
    if (( bi >= 0 )); then item_name "${INV[bi]}" "$CLS"; names+="$IKN, "; inv_equip "$bi" quiet; n=$(( n + 1 )); fi
  done
  power
  if (( n )); then logm "Equipped ${names%, }. Power is now $POW." "$K_GOOD"
  else logm "You already wear your best gear (power $POW)." "$K_SYS"; fi
}

# ---------------------------------------------------------------------------
#  Module 05c - bags and banks (since v1.8): bags in six sizes; bankers in
#  every town open the same personal vault; the shared chest is one for all
#  heroes on this computer.
# ---------------------------------------------------------------------------
SC_FILE="$DATA_DIR/shared.chest" SC_CAP=24 SC_ITEMS=() SC_G=0 SC_M=()
BK_TAB=0 BK_SIDE=0 BK_CUR=(0 0) BK_TOP=(0 0) BK_INPUT="" BK_BUF="" BK_NPC=""
VAULT_UP=(30 40 50 60) VAULT_COST=(1500 4000 9000)
BAGEQ=(- - -) BAGS=10 BANK=() BANKG=0 BANKCAP=30 BANKM=()

ivl() { if [[ $IK == B ]]; then IVL="$IVAL slots"; else IVL="+$IVAL"; fi; }       # after item_stats
bag_cap() { local b; BAGS=10; for b in "${BAGEQ[@]}"; do [[ $b == [0-5] ]] && BAGS=$(( BAGS + BAG_SZ[b] )); done; }

bag_gain() {  # kind -> BG (slots won by wearing it) BGJ (bag slot it goes to, -1 = no use)
  local j s min=99 mj=-1
  BG=0 BGJ=-1
  for j in 0 1 2; do
    if [[ ${BAGEQ[j]} != [0-5] ]]; then BG=${BAG_SZ[$1]} BGJ=$j; return; fi
    s=${BAG_SZ[${BAGEQ[j]}]}; (( s < min )) && { min=$s mj=$j; }
  done
  (( BAG_SZ[$1] > min )) && { BG=$(( BAG_SZ[$1] - min )) BGJ=$mj; }
}

bag_equip() {  # bag index in INV
  local i=$1 c k old
  c=${INV[i]%!}; k=${c#B.}
  bag_gain "$k"
  if (( BGJ < 0 )); then logm "All 3 bag slots already hold bags at least this big." "$K_SYS"; return 1; fi
  old=${BAGEQ[BGJ]}
  BAGEQ[BGJ]=$k
  if [[ $old == [0-5] ]]; then INV[i]="B.$old"; else unset "INV[i]"; INV=("${INV[@]}"); fi
  unset "NEWG[$c]"
  bag_cap
  if [[ $old == [0-5] ]]; then logm "${BAG_E[k]} You swap your ${BAG_NAME[old]} for the ${BAG_NAME[k]}. Your bags now hold $BAGS items." "$K_GOOD"
  else logm "${BAG_E[k]} You put on the ${BAG_NAME[k]}. Your bags now hold $BAGS items." "$K_GOOD"; fi
}

bag_unequip() {  # bag slot 0-2
  local j=$1 k=${BAGEQ[$1]}
  [[ $k == [0-5] ]] || return
  if (( ${#INV[@]} + 1 > BAGS - BAG_SZ[k] )); then
    logm "Make room first - without the ${BAG_NAME[k]} your bags would only hold $(( BAGS - BAG_SZ[k] )) items." "$K_HURT"; return
  fi
  BAGEQ[j]=-; bag_cap; INV+=("B.$k")
  logm "You take off the ${BAG_NAME[k]}. Your bags now hold $BAGS items." "$K_SYS"
}

bag_buy() {  # B.k -> 1 if there is no room for it
  local k=${1#B.}
  bag_gain "$k"
  if (( BGJ >= 0 )) && [[ ${BAGEQ[BGJ]} != [0-5] ]]; then
    BAGEQ[BGJ]=$k; bag_cap
    logm "${BAG_E[k]} You buy a ${BAG_NAME[k]} and strap it on. Your bags now hold $BAGS items!" "$K_ANN"; return 0
  fi
  (( ${#INV[@]} < BAGS )) || { logm "Your bags are full - sell something first." "$K_HURT"; return 1; }
  INV+=("$1"); NEWG[$1]=1
  logm "${BAG_E[k]} Bought a ${BAG_NAME[k]}. Swap it for a smaller bag in your inventory [i]." "$K_LOOT"
}

# --- the shared chest (a file every hero on this computer can reach) ------------------
sc_load() {
  (( CHAR_REMOTE )) && return 0                      # v6.2: the shared chest is part of your hero, on the server
  local k v x i
  SC_ITEMS=() SC_G=0 SC_M=()
  for (( i = 0; i < NMAT; i++ )); do SC_M[i]=0; done
  [[ -r $SC_FILE ]] || return 0
  while IFS='=' read -r k v; do
    case $k in
      ITEMS) for x in $v; do valid_item "${x%!}" && SC_ITEMS+=("$x"); done ;;
      GOLD)  [[ $v =~ ^[0-9]{1,12}$ ]] && SC_G=$(( 10#$v )) ;;
      MATS)  i=0; for x in $v; do [[ $x =~ ^[0-9]{1,6}$ ]] && (( i < NMAT )) && SC_M[i]=$(( 10#$x )); i=$(( i + 1 )); done ;;
    esac
  done < "$SC_FILE"
  SC_ITEMS=("${SC_ITEMS[@]:0:SC_CAP}")
}

sc_save() {
  (( CHAR_REMOTE )) && return 0                      # (bk_commit saves the hero, chest included)
  local IFS=$' \t\n' tmp="$SC_FILE.tmp.$$"
  mkdir -p "$DATA_DIR" 2>/dev/null
  { echo "ITEMS=${SC_ITEMS[*]}"; echo "GOLD=$SC_G"; echo "MATS=${SC_M[*]}"; } > "$tmp" 2>/dev/null && mv -f "$tmp" "$SC_FILE"
}

bk_store() {  # BK_TAB -> ST SG SM (variable names) SCAP SNAME   (tab 2: the chest in your room, v5.0 - no gold)
  if (( BK_TAB == 0 )); then ST=BANK SG=BANKG SM=BANKM SCAP=$BANKCAP SNAME=vault
  elif (( BK_TAB == 2 )); then ST=ROOMC SG="" SM=ROOMM SCAP=${ROOM_CAP[ROOM_T]:-0} SNAME="room chest"
  else ST=SC_ITEMS SG=SC_G SM=SC_M SCAP=$SC_CAP SNAME="shared chest"; fi
}
bk_fresh() { (( BK_TAB == 1 )) && sc_load; bk_store; }            # always work on the newest chest
bk_commit() { save_char; (( BK_TAB == 1 )) && sc_save; MAP_DIRTY=1; }

bank_open() {
  BK_NPC=$TALK_T BK_INPUT="" BK_SIDE=0 BK_CUR=(0 0) BK_TOP=(0 0)
  (( BK_TAB == 2 )) && BK_TAB=0                                  # (the room chest is only upstairs)
  (( ${#BANKM[@]} )) || { local i; for (( i = 0; i < NMAT; i++ )); do BANKM[i]=0; done; }
  sc_load; UI=bank MAP_DIRTY=1
}

# --- moving things -----------------------------------------------------------------
bk_transfer() {
  local i c new=() j
  bk_fresh; local -n st=$ST
  i=${BK_CUR[BK_SIDE]}
  if (( BK_SIDE == 0 )); then
    c=${INV[i]}; [[ -n $c ]] || return
    (( ${#st[@]} < SCAP )) || { logm "The $SNAME is full ($SCAP)." "$K_HURT"; return; }
    unset "INV[i]"; INV=("${INV[@]}"); st+=("$c")
    item_name "$c" "$CLS"; logm "Stored $INAME in the $SNAME." "$K_LOOT"
  else
    c=${st[i]}; [[ -n $c ]] || return
    (( ${#INV[@]} < BAGS )) || { logm "Your bags are full ($BAGS)." "$K_HURT"; return; }
    for j in "${!st[@]}"; do (( j == i )) || new+=("${st[j]}"); done
    st=("${new[@]}"); INV+=("$c")
    item_name "$c" "$CLS"; logm "Took $INAME from the $SNAME." "$K_LOOT"
  fi
  bk_commit
}

bk_gold() {  # dep|wd amount ("" = all of it)
  local a=${2:-} have
  bk_fresh; [[ -n $SG ]] || { logm "Gold belongs in the vault - any banker keeps it safe."; return; }
  have=${!SG}
  [[ -n $a ]] && a=$(( 10#$a ))
  if [[ $1 == dep ]]; then
    [[ -z $a ]] && a=$GOLD; (( a > GOLD )) && a=$GOLD; (( a > 0 )) || { logm "You have no gold to put in."; return; }
    GOLD=$(( GOLD - a )); printf -v "$SG" '%d' $(( have + a ))
    logm "${EMJ[gold]}Deposited $a gold. In the $SNAME: ${!SG}." "$K_LOOT"
  else
    [[ -z $a ]] && a=$have; (( a > have )) && a=$have; (( a > 0 )) || { logm "There is no gold in the $SNAME."; return; }
    GOLD=$(( GOLD + a )); printf -v "$SG" '%d' $(( have - a ))
    logm "${EMJ[gold]}Took $a gold. In the $SNAME: ${!SG}." "$K_LOOT"
  fi
  bk_commit
}

bk_mats() {  # in|out: all materials into the store or back into your bags
  local k n=0 kinds=0
  bk_fresh; local -n sm=$SM
  for (( k = 0; k < NMAT; k++ )); do
    if [[ $1 == in ]]; then
      (( MATS[k] > 0 )) || continue
      n=$(( n + MATS[k] )) kinds=$(( kinds + 1 )); sm[k]=$(( ${sm[k]:-0} + MATS[k] )); MATS[k]=0
    else
      (( ${sm[k]:-0} > 0 )) || continue
      n=$(( n + sm[k] )) kinds=$(( kinds + 1 )); MATS[k]=$(( MATS[k] + sm[k] )); sm[k]=0
    fi
  done
  (( n )) || { if [[ $1 == in ]]; then logm "You carry no materials."; else logm "No materials in the $SNAME."; fi; return; }
  if [[ $1 == in ]]; then logm "Stored $n materials ($kinds kinds) in the $SNAME." "$K_LOOT"
  else logm "Took $n materials ($kinds kinds) from the $SNAME." "$K_LOOT"; fi
  bk_commit
}

bk_lock() {
  local i=${BK_CUR[BK_SIDE]} c
  if (( BK_SIDE == 0 )); then inv_lock "b:$i"; save_char; return; fi
  bk_fresh; local -n st=$ST
  c=${st[i]}; [[ -n $c ]] || return
  if [[ $c == *! ]]; then st[i]=${c%!}; else st[i]="$c!"; fi
  item_name "$c" "$CLS"; logm "$([[ $c == *! ]] && echo Unlocked || echo Locked) $INAME." "$K_SYS"
  bk_commit
}

bk_sort() {
  if (( BK_SIDE == 0 )); then inv_sort; save_char; return; fi
  bk_fresh; sort_items "$ST"; logm "Sorted the $SNAME by ${SORT_NAME[SORT_M]}." "$K_SYS"; bk_commit
}

bk_upgrade() {
  local i cost
  (( BK_TAB == 2 )) && { logm "A bigger room has a bigger chest - ask any innkeeper [9]."; return; }
  (( BK_TAB == 0 )) || { logm "The shared chest always holds $SC_CAP items."; return; }
  for (( i = 0; i < 3; i++ )); do (( BANKCAP == VAULT_UP[i] )) && break; done
  (( i < 3 )) || { logm "Your vault is as big as it gets ($BANKCAP)."; return; }
  cost=${VAULT_COST[i]}
  (( GOLD >= cost )) || { logm "More vault space costs $cost gold." "$K_HURT"; return; }
  GOLD=$(( GOLD - cost )) BANKCAP=${VAULT_UP[i+1]}
  logm "${EMJ[gold]}You rent more vault space: it now holds $BANKCAP items." "$K_ANN"
  save_char
}

bk_move() {  # -1|1
  local n c
  bk_store; local -n st=$ST
  if (( BK_SIDE == 0 )); then n=${#INV[@]}; else n=${#st[@]}; fi
  c=$(( BK_CUR[BK_SIDE] + $1 )); (( c >= n )) && c=$(( n - 1 )); (( c < 0 )) && c=0
  BK_CUR[BK_SIDE]=$c
}

bank_key() {
  local k=$1
  MAP_DIRTY=1
  if [[ -n $BK_INPUT ]]; then
    case $k in
      ''|$'\r') bk_gold "$BK_INPUT" "$BK_BUF"; BK_INPUT="" ;;
      ESC) BK_INPUT="" ;;
      $'\x7f'|$'\b') BK_BUF=${BK_BUF%?} ;;
      [0-9]) (( ${#BK_BUF} < 9 )) && BK_BUF+=$k ;;
    esac
    return
  fi
  case $k in
    ESC|q) UI="" ;;
    LEFT|RIGHT|$'\t'|a|d) BK_SIDE=$(( 1 - BK_SIDE )) ;;
    UP|w) bk_move -1 ;;
    DOWN|s) bk_move 1 ;;
    1) (( BK_TAB == 2 )) || BK_TAB=0 BK_CUR[1]=0 ;;
    2) (( BK_TAB == 2 )) || { BK_TAB=1 BK_CUR[1]=0; sc_load; } ;;
    ''|$'\r'|' '|e) bk_transfer ;;
    g) (( BK_TAB == 2 )) || BK_INPUT=dep BK_BUF="" ;;
    t) (( BK_TAB == 2 )) || BK_INPUT=wd BK_BUF="" ;;
    m) bk_mats in ;;
    n) bk_mats out ;;
    l) bk_lock ;;
    o) SORT_M=$(( (SORT_M + 1) % 3 )); bk_sort ;;
    u) bk_upgrade ;;
  esac
}

# --- drawing -----------------------------------------------------------------------
bk_row() {  # code width -> RC RP (one cell of a column; narrow columns drop the icons)
  local c=$1 w=$2 nm lk ok col TW2=$TW2
  (( w < 30 )) && TW2=0
  rb
  item_name "$c" "$CLS"; item_icon "$c" "$CLS"
  ok=0; [[ $ICLS == *"$CLS"* ]] && ok=1
  lk="  "; [[ $c == *! ]] && { lk="* "; (( TW2 )) && lk=🔒; }
  nm=$INAME; (( TW2 || w < 30 )) && nm=$INSHORT
  rt "$lk" "38;5;220"; [[ -n $II ]] && rt "$II "
  col=$ICOL; (( ok )) || col="38;5;242"
  padt "$nm" $(( w - 2 - (TW2 ? 7 : 0) - 5 )); rt "$PADS" "$col"
  ivl; [[ $IK == B ]] && IVL="+$IVAL"
  (( IVAL )) || IVL=""
  printf -v PF '%5s' "$IVL"; if (( ok )); then rt "$PF" "38;5;250"; else rt "    ✖" "38;5;203"; fi
}

ui_bank() {
  local cw H n0 n1 r i li c top lc lp rc rp bg mk side t g=0 nm k carried=0 stored=0 ck=0 sk=0
  if (( BK_TAB == 2 )); then room_mine || { UI=""; return; }
  else [[ -n ${CM_T[$TALK_MID]} ]] || { UI=""; return; }; fi
  (( BK_TAB == 1 )) && sc_load
  bk_store; local -n st=$ST sm=$SM
  [[ -n $SG ]] && g=${!SG}
  cw=$(( (MW - 5) / 2 ))
  # title + tabs
  if (( BK_TAB == 2 )); then
    rb; ico 📦; rt " $IC" "1"; rt "YOUR ROOM CHEST" "1;38;5;220"; rt " · ${ROOM_NAME[ROOM_T]}" "38;5;245"; uxs
    rb; ico 💰; rt " $IC"; rt "carried " "38;5;245"; rt "$GOLD" "1;38;5;220"; rt "   - only for you, in every inn" "38;5;242"; uxs
  else
  rb; ico 🏦; rt " $IC" "1"; rt "${N_FULL[$BK_NPC]^^}" "1;38;5;220"
  rt " · ${N_HOME[$BK_NPC]:-}" "38;5;245"; rt "   "
  for i in 0 1; do
    if (( i == 0 )); then ico 🔐; t="[1] ${IC}Vault"; else ico 👥; t="[2] ${IC}Shared chest"; fi
    if (( i == BK_TAB )); then rt " $t " "1;38;5;16;48;5;220"; else rt " $t " "38;5;250"; fi
    rt " "
  done
  dispw "$RP"; (( DW > MW )) && { rb; rt " ${N_FULL[$BK_NPC]^^}   [1] Vault  [2] Shared chest" "1;38;5;220"; }
  uix "${RC//§/}$N" "$RP"
  rb; ico 💰; rt " $IC" ; rt "carried " "38;5;245"; rt "$GOLD" "1;38;5;220"
  rt "   in the $SNAME " "38;5;245"; rt "$g" "1;38;5;220"
  if (( BK_TAB == 0 )); then rt "   - safe when you die" "38;5;242"; else rt "   - every hero on this computer" "38;5;242"; fi
  uxs
  fi
  t=${BLANK:0:MW}; uix "$K_FRAME${t// /─}$N" "$t"
  # column heads
  rb; rt " YOUR BAGS ${#INV[@]}/$BAGS" "1;38;5;220"; rpad $(( cw + 4 )); rt " ${SNAME^^} ${#st[@]}/$SCAP" "1;38;5;220"
  uix "${RC//§/}$N" "$RP"
  H=$(( VH - 10 )); (( H < 4 )) && H=4
  n0=${#INV[@]} n1=${#st[@]}
  for side in 0 1; do
    if (( side == 0 )); then n=$n0; else n=$n1; fi
    (( BK_CUR[side] >= n )) && BK_CUR[side]=$(( n - 1 )); (( BK_CUR[side] < 0 )) && BK_CUR[side]=0
    top=${BK_TOP[side]}
    (( BK_CUR[side] < top )) && top=${BK_CUR[side]}
    (( BK_CUR[side] >= top + H )) && top=$(( BK_CUR[side] - H + 1 ))
    (( top > n - H )) && top=$(( n - H )); (( top < 0 )) && top=0
    BK_TOP[side]=$top
  done
  for (( r = 0; r < H; r++ )); do
    lc="" lp="" rc="" rp=""
    for side in 0 1; do
      li=$(( BK_TOP[side] + r ))
      if (( side == 0 )); then c=${INV[li]:-}; n=$n0; else c=${st[li]:-}; n=$n1; fi
      if [[ -n $c ]]; then
        bk_row "$c" $(( cw - 2 ))
        bg="" mk="  "
        if (( li == BK_CUR[side] )); then
          if (( side == BK_SIDE )); then bg=";48;5;237"; mk=$'\e[0;1;38;5;226;48;5;237m▶ '; else mk=$'\e[0;38;5;242m› '; fi
        elif (( r == 0 && BK_TOP[side] > 0 )); then mk=$'\e[0;38;5;245m▲ '
        elif (( r == H - 1 && li < n - 1 )); then mk=$'\e[0;38;5;245m▼ '; fi
        t="$mk${RC//§/$bg}" k="  $RP"
        dispw "$k"; (( DW < cw )) && { t+=$'\e[0'"${bg}m${BLANK:0:cw-DW}"; k+=${BLANK:0:cw-DW}; }
        t+=$N
      elif (( r == 0 && li == 0 )); then
        if (( side == 0 )); then k="  (nothing in your bags)"; else k="  (empty)"; fi
        padr "$k" "$cw"; k=$PADS t="$K_SYS$k$N"
      else
        t=${BLANK:0:cw} k=$t
      fi
      if (( side == 0 )); then lc=$t lp=$k; else rc=$t rp=$k; fi
    done
    uix " $lc $K_FRAME│$N $rc" " $lp │ $rp"
  done
  t=${BLANK:0:MW}; uix "$K_FRAME${t// /─}$N" "$t"
  # what is selected
  if (( BK_SIDE == 0 )); then c=${INV[BK_CUR[0]]:-}; else c=${st[BK_CUR[1]]:-}; fi
  if [[ -n $c ]]; then
    item_name "$c" "$CLS"; item_icon "$c" "$CLS"; bonus_txt
    rb; rt " "; [[ -n $II ]] && rt "$II "; rt "$INAME" "$ICOL"
    if [[ $IK == B ]]; then rt "  bag, $IVAL slots" "38;5;250"
    elif [[ $IK == C ]]; then rt "  ${CS_NAME[${CL_SET[IKD]}]}" "38;5;180"
    else
      (( IVAL )) && { if [[ $IK == W ]]; then rt "  +$IVAL dmg" "38;5;250"; else rt "  +$IVAL armor" "38;5;250"; fi; }
      [[ -n $BTX ]] && rt "  $BTX" "38;5;117"
      cls_list "$ICLS"
      if [[ $ICLS == *"$CLS"* ]]; then rt "  ✔ ${CLT}" "38;5;120"; else rt "  ✖ only $CLT" "38;5;203"; fi
    fi
    rt "  ${ISELL}g" "38;5;220"
    uxs
  else
    ui ""
  fi
  # materials
  for (( k = 0; k < NMAT; k++ )); do
    (( MATS[k] > 0 )) && { carried=$(( carried + MATS[k] )) ck=$(( ck + 1 )); }
    (( ${sm[k]:-0} > 0 )) && { stored=$(( stored + sm[k] )) sk=$(( sk + 1 )); }
  done
  rb; ico 🧺; rt " $IC"; rt "Materials " "38;5;245"; rt "carried $carried ($ck kinds)" "38;5;252"
  rt "   in the $SNAME $stored ($sk kinds)" "38;5;252"
  uxs
  # keys
  ui "  [↑↓] select  [←→] side  [enter] move it across  [l] lock  [o] sort: ${SORT_NAME[SORT_M]}" "$K_SYS"
  if [[ -n $BK_INPUT ]]; then
    if [[ $BK_INPUT == dep ]]; then t="Deposit how much gold?"; else t="Take how much gold?"; fi
    ui "  $t > ${BK_BUF}_     (enter = all, esc = cancel)" "$K_LOOT$B"
  else
    t=""
    if (( BK_TAB == 0 )); then
      for (( i = 0; i < 3; i++ )); do (( BANKCAP == VAULT_UP[i] )) && { t="  [u] +10: ${VAULT_COST[i]}g"; break; }; done
    fi
    if (( BK_TAB == 2 )); then ui "  [m/n] materials in/out  [esc] leave" "$K_SYS"
    else ui "  [g/t] gold in/out  [m/n] materials in/out$t  [esc] leave" "$K_SYS"; fi
  fi
}

# ---------------------------------------------------------------------------
#  Module 05d - v3.0 screens: talents [x], the jeweler (any smith), faction
#  quartermasters, questline choices, the quest log with questlines and
#  reputation, and the side-panel / map details for champions and effects.
# ---------------------------------------------------------------------------

# === talents ===================================================================================
TL_CUR=0
ui_talents() {
  local k i n r mx mark col req
  tal_points; tal_reset_cost
  ui "  TALENTS - ${C_NAME[CLS]}   $TSPENT spent, $TFREE free (one point every level)" "$K_LOOT$B"
  ui "  [w/s] choose  [enter] learn  [x] close  - forget them all at any inn ($TRC gold)" "$K_SYS"
  for (( k = 0; k < 3; k++ )); do
    ui "  ${TL_TREE[CLS * 3 + k]^^}  (${TTREE[k]})" "$B"$'\e[38;5;117m'
    for (( n = 0; n < 4; n++ )); do
      i=$(( k * 4 + n )) r=${TAL:i:1} mx=${TL_MAX[n]} req=""
      mark="   "; (( i == TL_CUR )) && mark="  >"
      col=$K_SYS
      if (( r >= mx )); then col=$K_LOOT
      elif (( r > 0 )); then col=$K_GOOD
      elif tal_can "$i"; then col=$K_CHAT
      else (( TTREE[k] < TL_REQ[n] )) && req="  (${TL_REQ[n]} in tree)"; fi
      tal_desc "$i"
      (( n == 3 )) && TD="capstone"
      printf -v PF '%s %-22s %s/%s  %s%s' "$mark" "${TL_NAME[CLS * 12 + i]}" "$r" "$mx" "$TD" "$req"
      ui "$PF" "$col"
    done
  done
  tal_desc "$TL_CUR"; tal_can "$TL_CUR"
  ui ""
  ui "  ${TL_NAME[CLS * 12 + TL_CUR]}: $TD${TWHY:+  - $TWHY}" "$K_CHAT"
}
tal_key() {
  case $1 in
    w|k|UP)    TL_CUR=$(( (TL_CUR + 11) % 12 )) ;;
    s|j|DOWN)  TL_CUR=$(( (TL_CUR + 1) % 12 )) ;;
    $'\r'|''|+|' '|l|RIGHT) tal_learn "$TL_CUR" ;;
  esac
}

# === the jeweler ==================================================================================
JW_TAB=0 JW_CUR=0 JW_STEP=0 JW_SOCK=0 ABC=abcdefghijklmnopqrstuvwxyz
jw_list() {  # -> JWL: gear that has or can get sockets ("E:W" worn, "I:3" bag slot)
  local s c i
  JWL=()
  for s in W A O H J; do
    eq_of "$s"; c=$EQC; [[ -n $c && $c != U.* ]] || continue
    JWL+=("E:$s")
  done
  for i in "${!INV[@]}"; do [[ ${INV[i]} == [WAOHJ].* ]] && JWL+=("I:$i"); done
}
jw_code() {  # "E:W" | "I:3" -> JC (the item code)
  if [[ $1 == E:* ]]; then eq_of "${1#E:}"; JC=$EQC; else JC=${INV[${1#I:}]}; fi
}
jw_store() {  # "E:W" | "I:3" new-code
  if [[ $1 == E:* ]]; then printf -v "EQ${1#E:}" '%s' "$2"; calc_stats; else INV[${1#I:}]=$2; fi
}
jw_gems() {  # -> JGL: the gem materials you own
  local i
  JGL=(); for i in ${MAT_GRP[3]}; do (( MATS[i] > 0 )) && JGL+=("$i"); done
}
jewel_open() { JW_TAB=0 JW_CUR=0 JW_STEP=0 UI=jewel MAP_DIRTY=1; }
ui_jewel() {
  local i e c n s g line sel
  [[ -n ${CM_T[$TALK_MID]} ]] || { UI=""; return; }
  ui "  JEWELCRAFTING - ${N_FULL[$TALK_T]}   ${EMJ[gold]}$GOLD gold" "$K_LOOT$B"
  if (( JW_TAB == 0 )); then ui "  [1] SOCKETS   2  combine gems     [tab] switch  [esc] leave" "$K_SYS"
  else ui "   1  sockets  [2] COMBINE GEMS     [tab] switch  [esc] leave" "$K_SYS"; fi
  ui ""
  if (( JW_TAB == 1 )); then
    ui "  Three gems of a grade make one of the next. Pick with [a]-[r]." "$K_SYS"
    n=0
    for (( g = 0; g < 6; g++ )); do
      for e in 1 2 3; do
        gem_mat "$g" "$e"; i=$GM; c=$(( 60 * e * e ))
        mat_icon "$i"
        line="  [${ABC:n:1}] $MI${MI:+ }${MAT_NAME[i]} x${MATS[i]}  ->  ${GEM_GRADE[e]} ${GEM_NAME[g]}  (${c}g)"
        if (( MATS[i] >= 3 )); then ui "$line" "$K_CHAT"; else ui "$line" "$K_SYS"; fi
        n=$(( n + 1 ))
      done
    done
    return
  fi
  jw_list
  (( ${#JWL[@]} )) || { ui "  You carry no gear that could hold a gem."; return; }
  (( JW_CUR >= ${#JWL[@]} )) && JW_CUR=$(( ${#JWL[@]} - 1 ))
  for i in "${!JWL[@]}"; do
    (( i >= VH - 9 )) && break
    jw_code "${JWL[i]}"; item_name "$JC" "$CLS"; gems_txt "$JC"; sock_cost "$JC"
    sel="  "; (( i == JW_CUR )) && sel="> "
    e="bag "; [[ ${JWL[i]} == E:* ]] && e="worn"
    line="  $sel$e  ${INAME}"; [[ -n $GTX ]] && line+="  $GTX"
    if (( i == JW_CUR )); then ui "$line" $'\e[1;'"${ICOL}m"; else ui "$line" $'\e['"${ICOL}m"; fi
  done
  ui ""
  jw_code "${JWL[JW_CUR]}"; item_name "$JC" "$CLS"; sock_info "$JC"; sock_cost "$JC"; gems_plain "$JC"
  case $JW_STEP in
    0) ui "  $INAME: $SN socket(s)${GPL:+ - $GPL}" "$K_CHAT"
       if (( SKC )); then ui "  [enter] set a gem   [n] add a socket ($SKC gold)" "$K_GOOD"
       elif (( SN )); then ui "  [enter] set a gem   (no more sockets fit this item)" "$K_GOOD"
       else ui "  This item can't take a socket." "$K_SYS"; fi ;;
    1) line="  Which socket? "; s=1
       for g in $SGEMS; do if [[ $g == __ ]]; then line+=" [$s] empty"; else gem_of "$g"; line+=" [$s] ${GEM_GRADE[GQ-1]} ${GEM_NAME[GK]}"; fi; s=$(( s + 1 )); done
       ui "$line" "$K_CHAT"; ui "  A gem already in the socket is destroyed." "$K_SYS" ;;
    2) jw_gems
       if (( ! ${#JGL[@]} )); then ui "  You have no gems. Rare monsters, champions, bosses, chests and ore veins drop them." "$K_SYS"
       else
         line="  Which gem?"; n=0
         for i in "${JGL[@]}"; do
           mat_icon "$i"; gem_kq "$i"; g=$GKI e=$GQI
           line+=" [${ABC:n:1}] ${MI:-${GEM_L[g]^^}$e}x${MATS[i]}"; n=$(( n + 1 ))
         done
         ui "$line" "$K_CHAT"
         n=0; line=""
         for i in "${JGL[@]}"; do
           gem_kq "$i"; g=$GKI e=$(( GQI - 1 )); local v=(${GEM_V[g]})
           line+="${GEM_L[g]^^}${e}=+${v[e]} ${GEM_FX[g]}  "; n=$(( n + 1 ))
         done
         ui "  $line" "$K_SYS"
       fi ;;
  esac
}
jewel_key() {
  local k=$1 i g n c
  case $k in
    $'\t') JW_TAB=$(( 1 - JW_TAB )) JW_STEP=0; return ;;
    1) (( JW_STEP == 0 && JW_TAB == 1 )) && { JW_TAB=0; return; } ;;
    2) (( JW_STEP == 0 )) && { JW_TAB=1; return; } ;;
  esac
  if (( JW_TAB == 1 )); then
    [[ $k == [a-r] ]] || return
    printf -v n '%d' "'$k"; n=$(( n - 97 ))
    g=$(( n / 3 )) i=$(( n % 3 + 1 ))
    gem_mat "$g" "$i"; c=$(( 60 * i * i ))
    (( MATS[GM] >= 3 )) || { logm "You need three of them." "$K_HURT"; return; }
    (( GOLD >= c )) || { logm "Not enough gold." "$K_HURT"; return; }
    MATS[GM]=$(( MATS[GM] - 3 )); GOLD=$(( GOLD - c ))
    gem_mat "$g" $(( i + 1 )); gem_get "$GM"; (( i == 3 )) && { GEMP=1; ach_check; }
    return
  fi
  jw_list; (( ${#JWL[@]} )) || return
  case $JW_STEP in
    0) case $k in
         w|k|UP)   (( JW_CUR > 0 )) && JW_CUR=$(( JW_CUR - 1 )) ;;
         s|j|DOWN) (( JW_CUR < ${#JWL[@]} - 1 )) && JW_CUR=$(( JW_CUR + 1 )) ;;
         $'\r'|''|' ') jw_code "${JWL[JW_CUR]}"; sock_info "$JC"; (( SN )) && JW_STEP=1 ;;
         n) jw_code "${JWL[JW_CUR]}"; sock_cost "$JC"
            (( SKC )) || return
            (( GOLD >= SKC )) || { logm "A socket costs $SKC gold." "$K_HURT"; return; }
            GOLD=$(( GOLD - SKC )); sock_add "$JC"; jw_store "${JWL[JW_CUR]}" "$CODE2"
            logm "${N_FULL[$TALK_T]} drills a new socket. ($SKC gold)" "$K_GOOD" ;;
       esac ;;
    1) jw_code "${JWL[JW_CUR]}"; sock_info "$JC"
       [[ $k == [1-3] ]] && (( k <= SN )) && { JW_SOCK=$(( k - 1 )) JW_STEP=2; } ;;
    2) jw_gems
       [[ $k == [a-r] ]] || return
       printf -v n '%d' "'$k"; n=$(( n - 97 ))
       (( n < ${#JGL[@]} )) || return
       i=${JGL[n]}; gem_kq "$i"; g=$GKI
       jw_code "${JWL[JW_CUR]}"
       sock_set "$JC" "$JW_SOCK" "${GEM_L[g]}$GQI"
       MATS[i]=$(( MATS[i] - 1 ))
       jw_store "${JWL[JW_CUR]}" "$CODE2"; item_name "$CODE2" "$CLS"
       logm "The ${MAT_NAME[i]} clicks into your $INAME." "$K_GOOD"
       JW_STEP=0 ;;
  esac
}

# === faction quartermasters =========================================================================
ui_wares() {
  local i col line
  [[ -n ${CM_T[$TALK_MID]} ]] || { UI=""; return; }
  wares_build "$TALK_T"
  (( WR_F >= 0 )) || { UI=talk; return; }
  rep_rank "$WR_F"
  ui "  QUARTERMASTER OF THE ${FAC_NAME[WR_F]^^}" "$K_LOOT$B"
  ui "  You are ${REP_NAME[RR < 0 ? 0 : RR]} (${REP[WR_F]} reputation).  ${EMJ[gold]}$GOLD gold" $'\e['"${FAC_COL[WR_F]}m"
  ui ""
  for i in "${!WR_NAME[@]}"; do
    printf -v line '  [%d] %-44s %6sg  %s' $(( i + 1 )) "${WR_NAME[i]}" "${WR_PRICE[i]}" "${REP_NAME[WR_RANK[i]]}"
    if (( RR >= WR_RANK[i] )); then col=$K_CHAT; (( GOLD >= WR_PRICE[i] )) || col=$K_HURT; else col=$K_SYS; fi
    ui "$line" "$col"
  done
  ui ""
  ui "  Quests for this faction's towns and lands raise your standing; so do the" "$K_SYS"
  ui "  questlines. Friendly 1500, Honored 4500, Revered 9000, Exalted 15000." "$K_SYS"
  ui "  Better standing also means up to 20% off in their shops.   [esc] back" "$K_SYS"
}
wares_key() { [[ $1 == [1-5] ]] && wares_buy $(( $1 - 1 )); }

# === a questline asks you to decide ==================================================================
ui_qchoice() {
  local l=$QCH_L opt w=$(( VW - 6 )) rest cut
  ql_step "$l"
  IFS='|' read -r -a opt <<< "${QS_CHA[QST]}"
  ui "  ${QL_NAME[l]^^} - A CHOICE" "$K_LOOT$B"
  ui ""
  rest="\"${QS_DONE[QST]}\" ${QS_CH[QST]}"
  while (( ${#rest} > w )); do
    cut=${rest:0:w}; cut=${cut% *}; ui "  $cut" "$K_CHAT"; rest=${rest:${#cut}}; rest=${rest# }
  done
  ui "  $rest" "$K_CHAT"
  ui ""
  ui "  [1] ${opt[0]}" "$K_GOOD"
  ui "  [2] ${opt[1]}" "$K_GOOD"
  ui ""
  ui "  Choices change who thinks well of you - and what you get." "$K_SYS"
}

# === the quest log =====================================================================================
QLOG_TAB=0
ui_qlog() {
  local q f tag plain n=0 i c st
  case $QLOG_TAB in 0) tag="[1] QUESTS  2 lines  3 reputation  4 daily" ;; 1) tag=" 1 quests [2] LINES  3 reputation  4 daily" ;;
    2) tag=" 1 quests  2 lines [3] REPUTATION  4 daily" ;; *) tag=" 1 quests  2 lines  3 reputation [4] DAILY" ;; esac
  ui "  QUEST LOG   $tag" "$K_LOOT$B"
  ui ""
  (( QLOG_TAB == 3 )) && { ui_dailies; return; }
  if (( QLOG_TAB == 2 )); then
    for (( i = 0; i < NFAC; i++ )); do
      rep_rank "$i"
      local nx=${REP_RANK[RR < 4 ? (RR < 0 ? 0 : RR + 1) : 4]} have=${REP[i]} bar
      (( RR >= 4 )) && nx=21000
      pbar "$(( have < 0 ? 0 : have ))" "$nx" 16 $'\e['"${REP_COL[RR < 0 ? 0 : RR]}m"; bar=$PB
      st=${REP_NAME[RR < 0 ? 0 : RR]}; (( RR < 0 )) && st=Unfriendly
      local fe=""; (( TW2 )) && fe="${FAC_E[i]} "
      printf -v PF '%-20s' "${FAC_NAME[i]}"
      uix "  $fe"$'\e['"${FAC_COL[i]}m$PF$N $bar $st ($have)"
    done
    ui ""
    ui "  Quests in a faction's towns and lands raise your standing with it." "$K_SYS"
    ui "  Their shops give 5% off per rank; their quartermaster (the questline" "$K_SYS"
    ui "  giver of each town, [6] in a conversation) sells gems, socketed gear" "$K_SYS"
    ui "  and, to the Revered, a unique." "$K_SYS"
    return
  fi
  if (( QLOG_TAB == 1 )); then
    for (( i = 0; i < NQL; i++ )); do
      c=${QLS:i:1}
      case $c in
        x) st="${K_LOOT}done$N"; [[ ${QLC:i:1} != - ]] && st+=" ${K_SYS}(you chose ${QLC:i:1^^})$N" ;;
        0) if (( LVL >= QL_LVL[i] )); then st="${K_GOOD}ask ${N_FULL[${QL_NPC[i]}]}$N"; else st="${K_SYS}from level ${QL_LVL[i]}$N"; fi ;;
        *) st="${K_CHAT}step $c/${QL_N[i]}$N" ;;
      esac
      local fe=""; (( TW2 )) && fe="${FAC_E[${QL_FAC[i]}]} "
      uix "  $fe${QL_NAME[i]}  - $st"
    done
    ui ""
    ui "  Every town has a questline. Its giver wears a ❕ (ASCII: orange !)." "$K_SYS"
    return
  fi
  story_qlog
  for (( i = 0; i < NQL; i++ )); do
    ql_step "$i" || continue
    qobj_parse "${QS_OBJ[QST]}"; obj_text "$OT" "$OA" "$ON" "${QLP[i]}"
    QTX=$OWX QTY=$OWY; track
    if ql_ready "$i"; then st="${K_GOOD}ready - return to ${N_FULL[${QL_NPC[i]}]}$N"; else st=""; fi
    uix "  ${K_LOOT}[line]$N ${QL_NAME[i]} ($QSI/${QL_N[i]}): $OTX" "  [line] ${QL_NAME[i]} ($QSI/${QL_N[i]}): $OTX"
    [[ -n $st ]] && uix "          $st" "          ready - return to ${N_FULL[${QL_NPC[i]}]}"
    [[ -z $st && -n $TRK ]] && ui "          ->  $TRK" "$K_SYS"
  done
  for q in "${PQ_CODES[@]}" "${QUESTS[@]}"; do
    [[ -n $q ]] || continue
    n=$(( n + 1 )); IFS=. read -r -a f <<< "$q"
    if (( n <= ${#PQ_CODES[@]} )); then tag="${K_PARTY}[party]$N"; plain="[party]"; else tag="${K_LOOT}[own]$N  "; plain="[own]  "; fi
    quest_info "$q"; track
    uix "  $tag $QGLY $QTXT" "  $plain $PLX $QTXT"
    ui "          $QWHERE${TRK:+   ->  $TRK}   - ${f[4]} XP, ${f[5]} gold" "$K_SYS"
  done
  (( n )) || { ui "  No quests yet. The quest board (!) in every town and NPCs with a"; ui "  yellow ! over their head have work for you."; }
  ui ""
  ui "  [1-3] tabs   [m] shows targets on the world map   [esc] close" "$K_SYS"
}

# === side panel and map details ==========================================================================
ps_line() {  # -> PSL: my status effects (empty if none)
  local i s=""
  for i in 0 1 2 3 4 5; do
    (( NOW < PS_UNTIL[i] )) || continue
    secs $(( PS_UNTIL[i] - NOW ))
    if (( TW2 )); then s+="${PS_E[i]}$TS "; else s+=$'\e['"${PS_COL[i]}m${PS_NAME[i]}$N $TS "; fi
  done
  (( BARRIER > 0 )) && s+="${K_GOOD}shield $BARRIER$N "
  PSL=$s
}
target_info() {  # mid -> TIL: champion / rare / weakness details for the side panel
  local t=${CM_T[$1]} s=""
  TIL=""
  (( M_KIND[t] == 0 )) || return
  (( ${CM_CH[$1]:-0} )) && s+=$'\e['"${CHP_COL[CM_CH[$1]-1]}m${CHP_NAME[CM_CH[$1]-1]}$N "
  (( M_BOSS[t] == 2 )) && s+=$'\e[1;38;5;220m'"elite$N "
  (( M_WK[t] >= 0 )) && s+="${K_GOOD}weak:${EL_NAME[M_WK[t]]}$N "
  (( M_RS[t] >= 0 )) && s+="${K_HURT}resists:${EL_NAME[M_RS[t]]}$N"
  TIL="   $s"
}
CHN=" "
chain_npcs() {  # -> CHN: everyone with questline business for me (refreshed once a second)
  local i
  CHN=" "
  for (( i = 0; i < NQL; i++ )); do
    if [[ ${QLS:i:1} == 0 ]]; then (( LVL >= QL_LVL[i] )) && CHN+="${QL_NPC[i]} "; continue; fi
    ql_step "$i" || continue
    if [[ ${QS_OBJ[QST]} == T.* ]]; then CHN+="${QS_OBJ[QST]#T.} "; elif ql_ready "$i"; then CHN+="${QL_NPC[i]} "; fi
  done
}

# ---------------------------------------------------------------------------
#  Module 04h - v4.5 client: professions and gems to level 40, paragon, mythic
#  keys, valor, mounts, dailies and weeklies, achievements and titles.
#  (Loaded after the UI modules: it overrides a few of their helpers.)
# ---------------------------------------------------------------------------
PARA=0 PARA_P="0 0 0 0 0 0" KEYLV=2 MYBEST=0 VALOR=0 MOUNTS="" MNT_CUR=0 RIDING=0 ACHS="" TITLE=-1
DAILY="" WEEKLY="" DCLR=0 RAIDK=0 RAREK=0 INVK=0 DLYK=0 MYDONE=0 GEMP=0
IN_MK=0 IN_LIM=0 IN_T0=0 IN_AFX=""
V45_VARS=(PARA KEYLV MYBEST VALOR MNT_CUR TITLE DCLR RAIDK RAREK INVK DLYK MYDONE GEMP)

v45_reset() {  # a new hero
  PARA=0 PARA_P="0 0 0 0 0 0" KEYLV=2 MYBEST=0 VALOR=0 MOUNTS="" MNT_CUR=0 RIDING=0 ACHS="" TITLE=-1
  DAILY="" WEEKLY="" DCLR=0 RAIDK=0 RAREK=0 INVK=0 DLYK=0 MYDONE=0 GEMP=0
  v50_reset; v45_fix
}
v45_fix() {
  local i
  [[ $PARA_P =~ ^(0|[1-9][0-9]?)( (0|[1-9][0-9]?)){5}$ ]] || PARA_P="0 0 0 0 0 0"     # (no "08": octal)
  while (( ${#MOUNTS} < NMNT )); do MOUNTS+="0"; done; MOUNTS=${MOUNTS:0:NMNT}
  [[ -z $ACHS ]] && ACH_QUIET=1                                # (an old hero: no fanfare for what is already done)
  while (( ${#ACHS} < NACH )); do ACHS+="0"; done; ACHS=${ACHS:0:NACH}
  (( MNT_CUR >= 0 && MNT_CUR < NMNT )) || MNT_CUR=0
  (( KEYLV >= 2 && KEYLV <= MYTH_MAX )) || KEYLV=2
  (( TITLE >= -1 && TITLE < NACH )) || TITLE=-1
  (( TITLE >= 0 )) && [[ ${ACHS:TITLE:1} != 1 ]] && TITLE=-1
  for i in "${!PROF_LV[@]}"; do (( PROF_LV[i] <= PROF_MAX )) || PROF_LV[i]=$PROF_MAX; done
  dly_fix; v50_fix
}
v45_load_kv() {  # key value: the lines load_char does not know
  case $1 in
    PARA_P) [[ $2 =~ ^(0|[1-9][0-9]?)( (0|[1-9][0-9]?)){5}$ ]] && PARA_P=$2 ;;
    MOUNTS|ACHS) [[ $2 =~ ^[01]{1,64}$ ]] && printf -v "$1" '%s' "$2" ;;
    DAILY|WEEKLY) [[ $2 =~ ^(0|[1-9][0-9]{0,6})(\ (0|[1-9][0-9]?):(0|[1-9][0-9]{0,5}):[01]){1,3}$ ]] && printf -v "$1" '%s' "$2" ;;
    PARA|KEYLV|MYBEST|VALOR|MNT_CUR|DCLR|RAIDK|RAREK|INVK|DLYK|MYDONE|GEMP) [[ $2 =~ ^[0-9]{1,9}$ ]] && printf -v "$1" '%d' "$(( 10#$2 ))" ;;
    TITLE) [[ $2 =~ ^-?[0-9]{1,3}$ ]] && TITLE=$2 ;;
    *) v50_load_kv "$1" "$2" ;;                                 # v5.0: housing and collectables
  esac
}
v45_save() {  # the lines save_char adds
  local k
  for k in "${V45_VARS[@]}"; do echo "$k=${!k}"; done
  echo "PARA_P=$PARA_P"; echo "MOUNTS=$MOUNTS"; echo "ACHS=$ACHS"; echo "DAILY=$DAILY"; echo "WEEKLY=$WEEKLY"
  v50_save
}

# --- professions: tables instead of index ranges ---------------------------------------------------------
node_prof() { NPK=${NODE_PK[$1]:-1}; }                         # node type -> NPK (1 mining, 2 herbalism)
mat_prof() { MP_K=${MAT_PK[$1]:-0}; }                           # material -> MP_K
mat_node() {  # material -> MNT_T: the node it grows on ("" for fish and gems)
  local t; MNT_T=""
  for t in "${NODE_T[@]}"; do (( NODE_MAT[$t] == $1 )) && { MNT_T=$t; return 0; }; done
  return 1
}

# --- paragon ----------------------------------------------------------------------------------------------
para_points() {  # -> PPT (earned) PSP (spent) PFREE
  local v; PSP=0
  for v in $PARA_P; do PSP=$(( PSP + v )); done
  PPT=$(( PARA + (LVL - 1 > 36 ? LVL - 37 : 0) )); PFREE=$(( PPT - PSP )); (( PFREE < 0 )) && PFREE=0
}
para_learn() {  # stat index
  local p=($PARA_P) i=$1
  (( i >= 0 && i < 6 )) || return 1
  para_points
  (( PFREE > 0 )) || { logm "No paragon points to spend - they come with experience after level $MAXLVL." "$K_SYS"; return 1; }
  (( p[i] < PARA_MAX[i] )) || { logm "${PARA_NAME[i]} is at its maximum." "$K_SYS"; return 1; }
  p[i]=$(( p[i] + 1 )); PARA_P="${p[*]}"; calc_stats
  logm "${PARA_NAME[i]} ${p[i]}/${PARA_MAX[i]} (${PARA_DESC[i]})." "$K_GOOD"
}
para_bonus() {  # -> PB_DMG PB_HP PB_CRIT PB_RES PB_MP PB_CD
  local p=($PARA_P)
  PB_DMG=${p[0]:-0} PB_HP=${p[1]:-0} PB_CRIT=$(( ${p[2]:-0} / 2 )) PB_RES=${p[3]:-0} PB_MP=${p[4]:-0} PB_CD=${p[5]:-0}
}
para_xp() {  # after level 40: experience turns into paragon levels
  (( LVL >= MAXLVL )) || return
  para_next "$PARA"
  while (( XP >= PNX )); do
    XP=$(( XP - PNX )) PARA=$(( PARA + 1 ))
    logm "${EMJ[lvl]}*** PARAGON $PARA! A point to spend - [x], then [p]. ***" "$K_ANN"
    send EVT "$MY_ID" "$MY_NAME" "reached paragon level $PARA!"
    para_next "$PARA"
  done
  XPNEXT=$PNX
}

# --- valor ---------------------------------------------------------------------------------------------------
valor_add() {  # amount why
  (( $1 > 0 )) || return
  VALOR=$(( VALOR + $1 ))
  logm "+$1 valor${2:+ ($2)}  -  $VALOR in all. Spend it at a Valor Quartermaster." "$K_LOOT"
}
valor_buy() {  # index
  local i=$1 w c s
  (( i >= 0 && i < ${#VW_NAME[@]} )) || return
  c=${VW_COST[i]} w=${VW_WHAT[i]}
  (( VALOR >= c )) || { logm "You need ${c} valor (you have $VALOR)." "$K_HURT"; return; }
  case $w in
    gem) gem_mat $(( RANDOM % 6 )) 4; VALOR=$(( VALOR - c )); MATS[GM]=$(( MATS[GM] + 1 )); MAT_NEW[GM]=$(( ${MAT_NEW[GM]:-0} + 1 ))
         logm "A ${MAT_NAME[GM]} is yours." "$K_LOOT"; GEMP=1 ;;
    m*)  s=${w#m}; [[ ${MOUNTS:s:1} == 1 ]] && { logm "You already own the ${MNT_NAME[s]}." "$K_SYS"; return; }
         VALOR=$(( VALOR - c )); mount_give "$s" ;;
    LW|W|A|H|O|J)
         (( ${#INV[@]} < BAGS )) || { logm "Your bags are full." "$K_HURT"; return; }
         if [[ $w == LW ]]; then epic_item W 3 3 12; else epic_item "$w" 2 2 12; fi
         VALOR=$(( VALOR - c )); INV+=("$ITEM"); NEWG[$ITEM]=1; item_name "$ITEM" "$CLS"
         logm "The quartermaster hands you $INAME." $'\e['"${ICOL}m" ;;
  esac
  ach_check
}

# --- mounts --------------------------------------------------------------------------------------------------
mount_give() {  # index
  [[ ${MOUNTS:$1:1} == 1 ]] && return
  MOUNTS="${MOUNTS:0:$1}1${MOUNTS:$1+1}"; MNT_CUR=$1
  logm "${MNT_E[$1]} The ${MNT_NAME[$1]} is yours! Ride with [z], choose your mount with [Z]." "$K_ANN"
  send EVT "$MY_ID" "$MY_NAME" "rides a ${MNT_NAME[$1]} now!"
  ach_check
}
mount_has() { [[ ${MOUNTS:$1:1} == 1 ]]; }
mount_toggle() {
  if (( RIDING )); then mount_off; return; fi
  mount_has "$MNT_CUR" || { logm "You have no mount yet - Hilda the Stablemaster in Hearthmoor sells horses." "$K_SYS"; return; }
  [[ $CUR_MAP == W ]] || { logm "No mounts in dungeons." "$K_SYS"; return; }
  (( NOW - last_hurt > 3000 && NOW - ${last_att:-0} > 2000 )) || { logm "You can't mount up in the middle of a fight." "$K_HURT"; return; }
  RIDING=1 POS_DIRTY=1 MAP_DIRTY=1
  logm "${MNT_E[MNT_CUR]} You mount your ${MNT_NAME[MNT_CUR]} (+${MNT_SPD[MNT_CUR]}% speed)." "$K_GOOD"
}
mount_off() { (( RIDING )) || return; RIDING=0 POS_DIRTY=1 MAP_DIRTY=1; [[ $1 == quiet ]] || logm "You dismount." "$K_SYS"; }
mount_buy() {  # index (at Hilda's)
  local i=$1 r
  (( i >= 0 && i < NMNT && MNT_GOLD[i] > 0 )) || return
  mount_has "$i" && { logm "You already own the ${MNT_NAME[i]}." "$K_SYS"; return; }
  r=${MNT_REQ[i]}
  case $r in
    lvl:*) (( LVL >= ${r#lvl:} )) || { logm "Hilda: 'Come back at level ${r#lvl:}, this one bites.'" "$K_HURT"; return; } ;;
    rep:*) r=${r#rep:}; (( REP[${r%%:*}] >= ${r#*:} )) || { logm "Hilda: 'Only for the Honored of the ${FAC_NAME[${r%%:*}]}.'" "$K_HURT"; return; } ;;
  esac
  (( GOLD >= MNT_GOLD[i] )) || { logm "You need ${MNT_GOLD[i]} gold." "$K_HURT"; return; }
  GOLD=$(( GOLD - MNT_GOLD[i] )); mount_give "$i"
}
mount_delay() {  # next_move after a step: faster on horseback
  (( RIDING )) || return
  next_move=$(( NOW + (next_move - NOW) * 100 / (100 + MNT_SPD[MNT_CUR]) ))
}

# --- mythic keys ------------------------------------------------------------------------------------------------
myth_txt() {  # level -> MYT: "+7  Tyrannical, Molten, Raging"
  myth_afx; MYT="+$1"
  (( $1 >= 2 )) && MYT+="  ${MYTH_A[MA]}"
  (( $1 >= 4 )) && MYT+=", ${CHP_NAME[MB]}"
  (( $1 >= 7 )) && MYT+=", ${MYTH_C[MC]}"
}
myth_done() {  # level upgrade seconds valor (from the server)
  local k=$1 up=$2 s=$3
  MYDONE=$(( MYDONE + 1 ))
  if (( up > 0 )); then
    (( k > MYBEST )) && MYBEST=$k
    (( k + up > KEYLV )) && KEYLV=$(( k + up )); (( KEYLV > MYTH_MAX )) && KEYLV=$MYTH_MAX
    logm "MYTHIC +$k IN TIME ($(( s / 60 )):$(printf '%02d' $(( s % 60 )))) - your key rises to +$KEYLV!" "$K_ANN"
    send EVT "$MY_ID" "$MY_NAME" "completed a Mythic +$k in time!"
    dly_ev myth; (( k >= 15 )) && mount_give 6
  else
    logm "Mythic +$k completed - but too slow. Your key stays at +$KEYLV." "$K_SYS"
  fi
  dly_ev mythn
  valor_add "$4" "Mythic +$k"
  ach_check
}
myth_left() {  # -> MLS seconds left on the clock (negative: over time)
  MLS=$(( (IN_LIM - (NOW - IN_T0)) / 1000 ))
}

# --- dailies and weeklies -----------------------------------------------------------------------------------------
dly_pick() {  # seed count templates... -> DP: "kind:need:text" picks
  local seed=$1 n=$2 i j t; shift 2
  local pool=("$@") out=()
  for (( i = 0; i < n && ${#pool[@]}; i++ )); do
    j=$(( (seed * 7919 + i * 104729) % ${#pool[@]} )); t=${pool[j]}
    out+=("$t"); pool=("${pool[@]:0:j}" "${pool[@]:j+1}")
  done
  DP=("${out[@]}")
}
dly_fix() {  # new day / new week: new tasks
  local p pool=() t i r
  week_now
  if [[ ${DAILY%% *} != "$DAYN" ]]; then
    for t in "${DLY_T[@]}"; do [[ $t == myth* ]] && (( LVL < MAXLVL )) && continue; pool+=("$t"); done
    dly_pick "$DAYN" 3 "${pool[@]}"
    DAILY=$DAYN
    for (( i = 0; i < 3; i++ )); do DAILY+=" $(( ( (DAYN + i) * 31 ) % 100 )):0:0"; done
    DLY_CUR=("${DP[@]}")
  fi
  if [[ ${WEEKLY%% *} != "$WEEK" ]]; then
    WEEKLY=$WEEK; for (( i = 0; i < 2; i++ )); do WEEKLY+=" 0:0:0"; done
  fi
  dly_tasks
}
dly_tasks() {  # -> DLY_CUR (3 dailies) WKY_CUR (2 weeklies), DREG (the region of the kill daily)
  local pool=() t
  for t in "${DLY_T[@]}"; do [[ $t == myth* ]] && (( LVL < MAXLVL )) && continue; pool+=("$t"); done
  dly_pick "${DAILY%% *}" 3 "${pool[@]}"; DLY_CUR=("${DP[@]}")
  dly_pick "$(( ${WEEKLY%% *} + 5 ))" 2 "${WKY_T[@]}"; WKY_CUR=("${DP[@]}")
  DREG=${DLY_REG[$(( ${DAILY%% *} % ${#DLY_REG[@]} ))]}
}
dly_text() {  # "kind:need:text" -> DTX
  DTX=${1#*:}; DTX=${DTX#*:}; DTX=${DTX//%R/$DREG}
}
dly_ev() {  # kind [amount]: progress on today's and this week's tasks
  (( LVL >= 30 )) || return
  local k=$1 n=${2:-1} i a f need set
  [[ -n $DAILY ]] || dly_fix
  for set in d w; do
    if [[ $set == d ]]; then a=($DAILY) f=("${DLY_CUR[@]}"); else a=($WEEKLY) f=("${WKY_CUR[@]}"); fi
    for (( i = 0; i < ${#f[@]}; i++ )); do
      [[ ${f[i]%%:*} == "$k" ]] || continue
      local e=(${a[i+1]//:/ }); (( e[2] )) && continue
      need=${f[i]#*:}; need=${need%%:*}
      e[1]=$(( e[1] + n )); (( e[1] >= need )) && { e[1]=$need e[2]=1; dly_reward "$set" "${f[i]}"; }
      a[i+1]="${e[0]}:${e[1]}:${e[2]}"
    done
    if [[ $set == d ]]; then DAILY="${a[*]}"; else WEEKLY="${a[*]}"; fi
  done
}
dly_reward() {  # d|w task
  dly_text "$2"
  if [[ $1 == d ]]; then
    DLYK=$(( DLYK + 1 )); GOLD=$(( GOLD + 20 * LVL + 200 ))
    logm "DAILY DONE: $DTX!  +$(( 20 * LVL + 200 )) gold" "$K_ANN"; valor_add 30 daily; gain_xp $(( 300 * LVL ))
  else
    gem_mat $(( RANDOM % 6 )) 4; MATS[GM]=$(( MATS[GM] + 1 ))
    logm "WEEKLY DONE: $DTX!  +1 ${MAT_NAME[GM]}" "$K_ANN"; valor_add 150 weekly; gain_xp $(( 1000 * LVL ))
  fi
  ach_check
}
dly_kill() {  # monster type: kills count for the dailies
  (( LVL >= 30 )) || return
  local t=$1
  if [[ $CUR_MAP == W ]]; then region_of "$PX" "$PY" nosafe; [[ $RNAME == "$DREG" ]] && dly_ev kill; fi
  (( ${CM_CH[$KILL_MID]:-0} )) && dly_ev champ
  (( M_BOSS[t] == 2 )) && { dly_ev rare; RAREK=$(( RAREK + 1 )); }
  (( M_BOSS[t] == 1 )) && [[ $CUR_MAP == W ]] && [[ " ${WB_LIST[*]} " == *" $t "* ]] && dly_ev wboss
  if (( t == RD_NYX )); then
    RAIDK=$(( RAIDK + 1 )); dly_ev raid; valor_add 80 "the Eclipse Throne"
    (( RANDOM % 100 < 10 )) && mount_give 7
  fi
  (( t == W_RIDER && RANDOM % 100 < 8 )) && mount_give 5
}

# --- achievements and titles -------------------------------------------------------------------------------------------
ach_ok() {  # index -> 0 if earned
  local i=$1 n f
  case $i in
    0) (( LVL >= 20 )) ;; 1) (( LVL >= 30 )) ;; 2) (( LVL >= 40 )) ;; 3) (( PARA >= 10 )) ;; 4) (( PARA >= 50 )) ;;
    5) (( KILLS >= 2000 )) ;; 6) (( KILLS >= 10000 )) ;; 7) (( STORY >= 24 )) ;; 8) (( STORY >= NST )) ;;
    9|10) n=${QLS//[^x]/}; if (( i == 9 )); then (( ${#n} >= 10 )); else (( ${#n} >= NQL )); fi ;;
    11) (( DCLR >= 25 )) ;; 12) (( DCLR >= 100 )) ;;
    13) (( MYBEST >= 5 )) ;; 14) (( MYBEST >= 10 )) ;; 15) (( MYBEST >= 15 )) ;; 16) (( MYBEST >= 20 )) ;;
    17) (( RAIDK >= 1 )) ;; 18) (( RAIDK >= 10 )) ;;
    19|20) n=0; for f in "${REP[@]}"; do (( f >= REP_RANK[4] )) && n=$(( n + 1 )); done
           if (( i == 19 )); then (( n >= 1 )); else (( n >= NFAC )); fi ;;
    21) (( PROF_LV[0] >= PROF_MAX || PROF_LV[1] >= PROF_MAX || PROF_LV[2] >= PROF_MAX )) ;;
    22) (( PROF_LV[0] >= PROF_MAX && PROF_LV[1] >= PROF_MAX && PROF_LV[2] >= PROF_MAX )) ;;
    23) [[ $MOUNTS == *1* ]] ;; 24) [[ ${MOUNTS//1/} == "" ]] ;;
    25) (( RAREK >= 15 )) ;; 26) (( INVK >= 5 )) ;; 27) (( DLYK >= 50 )) ;;
    28) n=${EXPW//0/}; (( ${#n} * 100 >= ${#EXPW} * 80 )) ;;
    29) n=${SEEN//0/}; (( ${#n} >= 200 )) ;;
    30) (( GOLD >= 250000 )) ;; 31) (( GEMP )) ;;
    *) ach_ok50 "$i" ;;                                         # v5.0
  esac
}
ach_check() {  # unlock what is earned (cheap: a few tests per achievement)
  local i nm w
  [[ -n $ACHS ]] || v45_fix
  for (( i = 0; i < NACH; i++ )); do
    [[ ${ACHS:i:1} == 1 ]] && continue
    ach_ok "$i" || continue
    ACHS="${ACHS:0:i}1${ACHS:i+1}"; nm=${ACH[i]%%:*} w=${ACH[i]#*:}; w=${w%%:*}
    logm "🏆 ACHIEVEMENT: $nm - $w" "$K_ANN"
    (( ACH_QUIET )) || send EVT "$MY_ID" "$MY_NAME" "earned the achievement '$nm'!"
  done
  ACH_QUIET=0
}
ach_title() { local a=${ACH[$1]##*:}; ATT=$a; }                    # index -> ATT ("" none)
title_next() {  # cycle through the titles you have earned
  local i j
  for (( j = 1; j <= NACH + 1; j++ )); do
    i=$(( (TITLE + j + 1) % (NACH + 1) - 1 ))
    (( i < 0 )) && { TITLE=-1; logm "No title." "$K_SYS"; return; }
    [[ ${ACHS:i:1} == 1 ]] || continue
    ach_title "$i"; [[ -n $ATT ]] || continue
    TITLE=$i; logm "You are now known as $MY_NAME $ATT." "$K_GOOD"; return
  done
}
my_title() { TTL=""; (( TITLE >= 0 )) && { ach_title "$TITLE"; TTL=$ATT; }; }

v45_tick() {  # once a second
  (( NOW - ${ACH_T:-0} >= 5000 )) && { ACH_T=$NOW; ach_check; }
  if [[ ${DAILY%% *} != "${DAYN:-x}" ]] || (( NOW - ${DLY_T0:-0} > 60000 )); then DLY_T0=$NOW; week_now; [[ ${DAILY%% *} == "$DAYN" ]] || dly_fix; fi
}

# ---------------------------------------------------------------------------
#  Module 05e - v4.5 screens: paragon (on the talent screen), the mythic gate,
#  Hilda's stable and the mount list, the valor quartermaster, achievements and
#  titles, dailies and weeklies (the quest log's fourth tab).
# ---------------------------------------------------------------------------
TL_PAGE=0 DG_D=-1 DG_K=2 ACH_PG=0

ui_paragon() {
  local p=($PARA_P) i col bar
  para_points; para_next "$PARA"
  ui "  PARAGON $PARA   $PFREE point(s) to spend   [t] talents  [1-6] spend  [x] close" "$K_LOOT$B"
  if (( LVL >= MAXLVL )); then pbar "$XP" "$PNX" 20 $'\e[38;5;220m'; uix "  next paragon level: $PB $XP/$PNX" "  next paragon level: #################### $XP/$PNX"
  else ui "  From level $MAXLVL on, experience turns into paragon levels - a point each." "$K_SYS"; fi
  ui "  Points over 36 talents (level 38-40) count as paragon points too." "$K_SYS"
  ui ""
  for (( i = 0; i < 6; i++ )); do
    col=$K_SYS; (( p[i] > 0 )) && col=$K_GOOD; (( p[i] >= PARA_MAX[i] )) && col=$K_LOOT
    pbar "${p[i]}" "${PARA_MAX[i]}" 12 $'\e[38;5;117m'; bar=$PB
    printf -v PF '  [%d] %-10s %2d/%-2d ' $(( i + 1 )) "${PARA_NAME[i]}" "${p[i]}" "${PARA_MAX[i]}"
    uix "$col$PF$N$bar  ${K_SYS}${PARA_DESC[i]}$N" "$PF############  ${PARA_DESC[i]}"
  done
  ui ""
  ui "  Forget them (with your talents) at any inn." "$K_SYS"
}

# --- the mythic gate: at a dungeon entrance from level 40 ---------------------------------------------------
dgate_open() { DG_D=$1 DG_K=$KEYLV UI=dgate MAP_DIRTY=1; }      # your best key first
ui_dgate() {
  local d=$DG_D
  myth_afx; myth_txt "$DG_K"; myth_limit "$d"
  ui "  ${D_NAME[d]^^}" "$K_LOOT$B"
  ui ""
  ui "  [1] Enter as always (level ${D_REQ[d]})"
  if (( d == RAID_DT )); then
    ui "  The Eclipse Throne is a raid - bring friends. Nyxara grows with every"  "$K_SYS"
    ui "  hero who enters. Stand out of the marked ground, kill her guards when she"  "$K_SYS"
    ui "  hides behind her shield, run when the eclipse is total." "$K_SYS"
  else
    uix "  [2] ${K_LOOT}MYTHIC $MYT$N" "  [2] MYTHIC $MYT"
    ui "      [<] [>] key level ($DG_K of +$KEYLV)   time: $(( MYL / 60000 )) min   best: +$MYBEST" "$K_SYS"
    ui ""
    ui "  Mythic: every foe is level $MYTH_LVL and stronger with every key level." "$K_SYS"
    ui "  In time, your key rises (+2 if very fast). Deaths cost 5 seconds." "$K_SYS"
    ui "  The boss pays epic or better gear, perfect gems and valor." "$K_SYS"
    (( DG_K >= 2 )) && ui "  ${MYTH_A[MA]}: ${MYTH_AD[MA]}" "$K_SYS"
    (( DG_K >= 4 )) && ui "  ${CHP_NAME[MB]}: a third of all foes are ${CHP_DESC[MB]}" "$K_SYS"
    (( DG_K >= 7 )) && ui "  ${MYTH_C[MC]}: ${MYTH_CD[MC]}" "$K_SYS"
  fi
  ui ""
  ui "  [esc] step back" "$K_SYS"
}
dgate_key() {
  case $1 in
    1) dgate_go 0 ;;
    2) (( DG_D != RAID_DT )) && dgate_go "$DG_K" ;;
    LEFT|'<'|,|a|h) (( DG_K > 2 )) && DG_K=$(( DG_K - 1 )) ;;
    RIGHT|'>'|.|d|l) (( DG_K < KEYLV )) && DG_K=$(( DG_K + 1 )) ;;
  esac
}
dgate_go() {  # mythic level (0 = normal)
  UI="" NEED_FULL=1
  (( NOW < dreq_until )) && return
  dreq_until=$(( NOW + 4000 ))
  send DREQ "$MY_ID" "$DG_D" "$1"
  if (( $1 )); then myth_txt "$1"; logm "You turn your key: Mythic $MYT..." "$K_LOOT"
  else logm "You open the gate to the ${D_NAME[DG_D]}..." "$K_SYS"; fi
}

# --- mounts: Hilda's stable, and [Z] to choose yours ------------------------------------------------------------------
ui_stable() {
  local i st col hilda=0
  [[ $STABLE_SRC == talk && ${N_ROLE[${TALK_T:-0}]:-} == stable ]] && hilda=1
  if (( hilda )); then ui "  HILDA'S STABLE   [1-4] buy   [enter] ride the chosen one   [esc] close" "$K_LOOT$B"
  else ui "  YOUR MOUNTS   [1-8] choose   [z] mount / dismount   [esc] close" "$K_LOOT$B"; fi
  ui ""
  for (( i = 0; i < NMNT; i++ )); do
    if mount_has "$i"; then st="owned"; col=$K_GOOD; (( i == MNT_CUR )) && st="owned - riding this one" col=$K_LOOT
    else st=${MNT_SRC[i]}; col=$K_SYS; fi
    printf -v PF '%-15s +%3d%%  ' "${MNT_NAME[i]}" "${MNT_SPD[i]}"
    if (( TW2 )); then uix "  [$(( i + 1 ))] ${MNT_E[i]} $col$PF$N${K_SYS}$st$N" "  [$(( i + 1 ))] xx $PF$st"
    else uix "  [$(( i + 1 ))] $col$PF$N${K_SYS}$st$N" "  [$(( i + 1 ))] $PF$st"; fi
  done
  ui ""
  ui "  On horseback you travel faster. Fighting or getting hit throws you off," "$K_SYS"
  ui "  and mounts stay outside dungeons." "$K_SYS"
}
stable_key() {
  local i
  case $1 in
    [1-8]) i=$(( $1 - 1 ))
           if [[ $STABLE_SRC == talk ]] && (( MNT_GOLD[i] > 0 )) && ! mount_has "$i"; then mount_buy "$i"
           elif mount_has "$i"; then MNT_CUR=$i; logm "You will ride the ${MNT_NAME[i]}." "$K_GOOD"
           else logm "${MNT_NAME[i]}: ${MNT_SRC[i]}." "$K_SYS"; fi ;;
    z|$'\r'|'') UI="" NEED_FULL=1; mount_toggle ;;
  esac
}

# --- the valor quartermaster ------------------------------------------------------------------------------------------
ui_valor() {
  local i col
  ui "  VALOR QUARTERMASTER   you have $VALOR valor   [1-9] buy   [esc] close" "$K_LOOT$B"
  ui ""
  for (( i = 0; i < ${#VW_NAME[@]}; i++ )); do
    col=$K_SYS; (( VALOR >= VW_COST[i] )) && col=$K_GOOD
    printf -v PF '  [%d] %-42s %5d valor' $(( i + 1 )) "${VW_NAME[i]}" "${VW_COST[i]}"
    ui "$PF" "$col"
  done
  ui ""
  ui "  Valor: Mythic dungeons (more for higher keys), the Eclipse Throne," "$K_SYS"
  ui "  invasions, dailies (30) and weeklies (150)." "$K_SYS"
}
valor_key() { [[ $1 == [1-9] ]] && valor_buy $(( $1 - 1 )); }

# --- achievements -------------------------------------------------------------------------------------------------------
ui_ach() {
  local i n=0 a nm what tt col per first last mark
  for (( i = 0; i < NACH; i++ )); do [[ ${ACHS:i:1} == 1 ]] && n=$(( n + 1 )); done
  my_title
  ui "  ACHIEVEMENTS  $n/$NACH   title: ${TTL:-none}   [t] change title  [<][>] page  [o] close" "$K_LOOT$B"
  ui ""
  per=$(( VH - 4 )); (( per < 8 )) && per=8
  first=$(( ACH_PG * per )); (( first >= NACH )) && { ACH_PG=0; first=0; }
  last=$(( first + per )); (( last > NACH )) && last=$NACH
  for (( i = first; i < last; i++ )); do
    a=${ACH[i]}; nm=${a%%:*} a=${a#*:} what=${a%%:*} tt=${a#*:}
    if [[ ${ACHS:i:1} == 1 ]]; then col=$K_LOOT mark="*"; (( TW2 )) && mark="🏆"; else col=$K_SYS mark="."; (( TW2 )) && mark="  "; fi
    printf -v PF '%-16s %s' "$nm" "$what"
    [[ -n $tt ]] && PF+="  (title: $tt)"
    if (( TW2 )); then uix "  $mark $col$PF$N" "  xx $PF"; else uix "  $mark $col$PF$N" "  x $PF"; fi
  done
}
ach_key() {
  case $1 in
    t) title_next ;;
    RIGHT|'>'|.|d|l|' ') ACH_PG=$(( ACH_PG + 1 )) ;;
    LEFT|'<'|,|a|h) (( ACH_PG > 0 )) && ACH_PG=$(( ACH_PG - 1 )) ;;
  esac
}

# --- dailies and weeklies (quest log, tab 4) ---------------------------------------------------------------------------
ui_dailies() {
  local i a e need col mk
  dly_fix
  if (( LVL < 30 )); then ui "  Dailies and weeklies open at level 30." "$K_SYS"; return; fi
  ui "  TODAY" "$B"
  a=($DAILY)
  for (( i = 0; i < ${#DLY_CUR[@]}; i++ )); do
    e=(${a[i+1]//:/ }); need=${DLY_CUR[i]#*:}; need=${need%%:*}; dly_text "${DLY_CUR[i]}"
    col=$K_CHAT; (( e[2] )) && col=$K_GOOD
    mk="."; (( e[2] )) && mk="+"
    printf -v PF '  %s %-46s %s/%s' "$mk" "$DTX" "${e[1]}" "$need"
    ui "$PF" "$col"
  done
  ui "  each: 30 valor, gold and experience - new tasks every day" "$K_SYS"
  ui ""
  ui "  THIS WEEK" "$B"
  a=($WEEKLY)
  for (( i = 0; i < ${#WKY_CUR[@]}; i++ )); do
    e=(${a[i+1]//:/ }); need=${WKY_CUR[i]#*:}; need=${need%%:*}; dly_text "${WKY_CUR[i]}"
    col=$K_CHAT; (( e[2] )) && col=$K_GOOD
    mk="."; (( e[2] )) && mk="+"
    printf -v PF '  %s %-46s %s/%s' "$mk" "$DTX" "${e[1]}" "$need"
    ui "$PF" "$col"
  done
  ui "  each: 150 valor, a perfect gem and lots of experience" "$K_SYS"
  ui ""
  myth_afx
  ui "  MYTHIC   your key: +$KEYLV   best in time: +$MYBEST   valor: $VALOR" "$B"
  ui "  this week: ${MYTH_A[MA]} (+2), ${CHP_NAME[MB]} (+4), ${MYTH_C[MC]} (+7)" "$K_SYS"
}

# ---------------------------------------------------------------------------
#  Module 04i - v5.0 client: housing and collectables. A room upstairs at any
#  inn (rent, four sizes), walked like a little map of its own (H<owner>):
#  a bed (Well Rested), a chest, displays, a collection book, a guestbook.
#  Friends visit while the owner is online - the owner's client answers.
#  Collectables (C.<n>) are found on bosses, in every land, while fishing
#  and gathering, and along the story.
# ---------------------------------------------------------------------------
ROOM_T=0 ROOM_PAID=-1 ROOM_DOOR=1 REST_UNTIL=0 REST_PCT=0 GUESTS="" CLOG=""
ROOMD=() ROOMC=() ROOMM=()
V50_VARS=(ROOM_T ROOM_PAID ROOM_DOOR REST_UNTIL REST_PCT)
declare -A RM_AT=() VIS_INFO=() RM_ANS=()
RM_F=() RM_DSP=() RM_OWNER="" RM_TIER=0 RM_NCOL=0 RM_SIGNED=0 RM_SX=0 RM_SY=0 RM_NS=0
VIS_OWNER="" VIS_WANT="" VIS_T=0 DSP_I=0 DSP_CUR=0 BOOK_PG=0
DOOR_NAME=("locked - nobody comes in" "party - your party may visit" "open - everybody may visit")

v50_reset() {  # a new hero
  ROOM_T=0 ROOM_PAID=-1 ROOM_DOOR=1 REST_UNTIL=0 REST_PCT=0 GUESTS="" CLOG="" ROOMD=() ROOMC=() ROOMM=()
  v50_fix
}
v50_fix() {
  local i n
  (( ROOM_T >= 0 && ROOM_T <= NROOM )) || ROOM_T=0
  (( ROOM_DOOR >= 0 && ROOM_DOOR <= 2 )) || ROOM_DOOR=1
  (( REST_PCT <= 40 )) || REST_PCT=0
  while (( ${#CLOG} < NCOL )); do CLOG+=0; done; CLOG=${CLOG:0:NCOL}
  n=${ROOM_NDSP[ROOM_T]:-0}
  ROOMD=("${ROOMD[@]:0:n}"); for (( i = ${#ROOMD[@]}; i < n; i++ )); do ROOMD[i]=-; done
  ROOMC=("${ROOMC[@]:0:${ROOM_CAP[ROOM_T]:-0}}")
  for (( i = 0; i < NMAT; i++ )); do ROOMM[i]=${ROOMM[i]:-0}; done
}
v50_load_kv() {  # key value: the lines load_char and v45_load_kv do not know
  local x i=0
  case $1 in
    ROOM_T|ROOM_DOOR|REST_PCT) [[ $2 =~ ^[0-9]{1,2}$ ]] && printf -v "$1" '%d' "$(( 10#$2 ))" ;;
    REST_UNTIL) [[ $2 =~ ^[0-9]{1,14}$ ]] && REST_UNTIL=$(( 10#$2 )) ;;
    ROOM_PAID) [[ $2 =~ ^(-1|[0-9]{1,7})$ ]] && { if [[ $2 == -1 ]]; then ROOM_PAID=-1; else ROOM_PAID=$(( 10#$2 )); fi; } ;;
    CLOG)   [[ $2 =~ ^[01]{1,256}$ ]] && CLOG=$2 ;;
    ROOMD)  ROOMD=(); for x in $2; do if [[ $x == - ]] || valid_item "$x"; then ROOMD+=("$x"); else ROOMD+=(-); fi; done ;;
    ROOMC)  ROOMC=(); for x in $2; do valid_item "${x%!}" && ROOMC+=("$x"); done ;;
    ROOMM)  for x in $2; do [[ $x =~ ^[0-9]{1,6}$ ]] && (( i < NMAT )) && ROOMM[i]=$(( 10#$x )); i=$(( i + 1 )); done ;;
    GUESTS) [[ $2 =~ ^([A-Za-z0-9_-]{1,12}:[0-9]{1,6}( |$)){0,12}$ ]] && GUESTS=$2 ;;
  esac
}
v50_save() {  # the lines save_char adds
  local k
  for k in "${V50_VARS[@]}"; do echo "$k=${!k}"; done
  echo "CLOG=$CLOG"; echo "ROOMD=${ROOMD[*]}"; echo "ROOMC=${ROOMC[*]}"; echo "ROOMM=${ROOMM[*]}"; echo "GUESTS=$GUESTS"
}

# --- collectables -------------------------------------------------------------------------------------------
col_has() { [[ ${CLOG:$1:1} == 1 ]]; }                         # index -> 0 if ever found
col_mark() { col_has "$1" || CLOG="${CLOG:0:$1}1${CLOG:$1+1}"; }
col_count() {  # -> CLN (found) CLSD[set] (found per set) CLST[set] (all per set) - it only depends on CLOG
  local i s
  [[ $CLN_K == "$CLOG" && -n $CLN_K ]] && return
  CLN_K=$CLOG CLN=0 CLSD=() CLST=()
  for (( s = 0; s < NCS; s++ )); do CLSD[s]=0 CLST[s]=0; done
  for (( i = 0; i < NCOL; i++ )); do
    s=${CL_SET[i]}; CLST[s]=$(( CLST[s] + 1 ))
    [[ ${CLOG:i:1} == 1 ]] && { CLN=$(( CLN + 1 )) CLSD[s]=$(( CLSD[s] + 1 )); }
  done
}
col_where() {  # index -> CW_AT: where you keep it now ("" = nowhere)
  local c="C.$1" x
  CW_AT=""
  for x in "${ROOMD[@]}"; do [[ $x == "$c" ]] && { CW_AT="on display"; return; }; done
  for x in "${INV[@]}"; do [[ ${x%!} == "$c" ]] && { CW_AT="in your bags"; return; }; done
  for x in "${ROOMC[@]}"; do [[ ${x%!} == "$c" ]] && { CW_AT="in your room chest"; return; }; done
  for x in "${BANK[@]}"; do [[ ${x%!} == "$c" ]] && { CW_AT="in your vault"; return; }; done
}
col_scan() {  # everything you hold counts as found (trades, gifts, the vault)
  local x
  for x in "${INV[@]}" "${ROOMD[@]}" "${ROOMC[@]}" "${BANK[@]}"; do
    [[ $x == C.* ]] && { x=${x%!}; x=${x#C.}; [[ $x =~ ^(0|[1-9][0-9]{0,2})$ ]] && (( x < NCOL )) && col_mark "$x"; }
  done
}
col_pick() {  # set -> CP: a random member, rare ones are rarer; something new is a bit more likely
  local l=(${COL_SETL[$1]}) i tot r try
  CP=${l[0]}
  for try in 1 2; do
    tot=0; for i in "${l[@]}"; do tot=$(( tot + COL_W[CL_RR[i]] )); done
    r=$(( RANDOM % tot ))
    for i in "${l[@]}"; do r=$(( r - COL_W[CL_RR[i]] )); (( r < 0 )) && { CP=$i; break; }; done
    col_has "$CP" || break
    (( RANDOM % 2 )) && break
  done
}
col_give() {  # index: a collectable for you
  local i=$1 c="C.$1" first=1 to="" s=${CL_SET[$1]}
  col_has "$i" && first=0
  col_mark "$i"
  if (( ${#INV[@]} < BAGS )); then INV+=("$c"); NEWG[$c]=1
  elif (( ROOM_T > 0 && ${#ROOMC[@]} < ROOM_CAP[ROOM_T] )); then ROOMC+=("$c"); to=" Your bags are full - the innkeepers carried it to your room chest."
  else INV+=("$c"); NEWG[$c]=1; fi                      # too precious to sell: it squeezes in, like a unique
  item_name "$c" "$CLS"; item_icon "$c" "$CLS"
  logm "${EMJ[loot]}COLLECTABLE: $II${II:+ }$INAME (${CS_NAME[s]})$to" $'\e['"${ICOL}m"
  if (( first )); then
    col_count
    logm "New for your collection: ${CLSD[s]}/${CLST[s]} ${CS_NAME[s]}, $CLN/$NCOL in all. Show it off in your room!" "$K_ANN"
    (( CL_RR[i] >= 2 )) && send EVT "$MY_ID" "$MY_NAME" "found the $INAME for their collection!"
    ach_check
  fi
}
col_kill() {  # monster type champion: trophies from bosses, curios from the creatures of every land
  local t=$1 ch=${2:-0} i chance
  i=${COL_BOSS[$t]}
  if [[ -n $i ]]; then
    if col_has "$i"; then chance=12; else chance=40; fi
    (( RANDOM % 100 < chance )) && col_give "$i"
    return
  fi
  if (( M_KIND[t] == 4 )); then                         # treasure chests hide odd things
    (( RANDOM % 100 < 6 )) && { col_pick $(( 3 + RANDOM % 2 )); col_give "$CP"; }
    return
  fi
  (( M_KIND[t] == 0 )) && [[ $CUR_MAP == W ]] || return
  in_safe_xy "$PX" "$PY" && return
  RNAME=""; region_of "$PX" "$PY" nosafe; i=${COL_CUR[$RNAME]}
  [[ -n $i ]] || return
  if col_has "$i"; then chance=4; else chance=15; fi    # per thousand
  (( ch )) && chance=$(( chance * 3 ))
  (( M_BOSS[t] == 2 )) && chance=$(( chance * 15 ))
  (( RANDOM % 1000 < chance )) && col_give "$i"
}
col_find() { (( RANDOM % 1000 < 30 )) && { col_pick "$1"; col_give "$CP"; }; }   # set: a find while fishing (3) or gathering (4)
col_story() {  # the story pays a relic every sixth chapter (old heroes get theirs at once)
  local i
  for i in ${COL_SETL[5]}; do
    (( STORY >= CL_REF[i] )) && ! col_has "$i" && col_give "$i"
  done
}
col_dupes() {  # -> DUP (indexes in INV) DUPV (what they sell for): unlocked collectables you already own once
  local i c held=" "
  DUP=() DUPV=0
  for c in "${ROOMD[@]}" "${ROOMC[@]}" "${BANK[@]}"; do [[ $c == C.* ]] && held+="${c%!} "; done   # displayed and stored ones are keepers
  for c in "${INV[@]}"; do [[ $c == C.*! ]] && held+="${c%!} "; done                               # and so are locked ones
  for i in "${!INV[@]}"; do
    c=${INV[i]}; [[ $c == C.* && $c != *! ]] || continue
    if [[ $held == *" $c "* ]]; then DUP+=("$i"); item_stats "$c"; DUPV=$(( DUPV + ISELL ))
    else held+="$c "; fi                                                  # the first copy in your bags stays
  done
}

# --- the room: building it, walking in and out ----------------------------------------------------------------
room_map() { RMAP="H$(( 16#$1 ))"; }                           # owner id -> RMAP (the map name everybody uses)
room_build() {  # map tier -> MAPROW, RM_F ("kind x y slot"), RM_AT, RM_SX RM_SY (just inside the door), RM_NS
  local rows r y x c row n=0 s=0 IFS=/
  rows=(${ROOM_LAY[$2]})
  IFS=$' \t\n'
  RM_F=() RM_AT=()
  for (( y = 0; y < ${#rows[@]}; y++ )); do
    r=${rows[y]} row=""
    for (( x = 0; x < ${#r}; x++ )); do
      c=${r:x:1}
      case $c in
        '#') row+='#' ;;
        '<') row+='<'; RM_SX=$x RM_SY=$(( y - 1 )) ;;
        .)   row+=_ ;;
        *)   row+=+; RM_AT["$x,$y"]=$n
             if [[ $c == D ]]; then RM_F[n]="D $x $y $s"; s=$(( s + 1 )); else RM_F[n]="$c $x $y -"; fi
             n=$(( n + 1 )) ;;
      esac
    done
    MAPROW["$1:$y"]=$row
  done
  MAPW[$1]=${#rows[0]} MAPH[$1]=${#rows[@]} RM_NS=$s
}
dsp_look() {  # code -> DLE (HD sprite) DLG (ASCII glyph) DLC (color)
  item_stats "$1"; item_name "$1" "$CLS"
  DLC=$ICOL DLE=$IKE
  if [[ $IK == C ]]; then DLG=${CL_G[IKD]}
  elif [[ -n $IUQ ]]; then DLG='*'
  else case $IK in W) DLG=/ ;; A) DLG=']' ;; O) DLG=')' ;; H) DLG='^' ;; J) DLG='"' ;; *) DLG=b ;; esac; fi
  [[ $DLE == ?' ' ]] && DLE="${DLE:0:1} "                       # narrow sprites keep their padding
}
room_glyphs() {  # the sprites of all furniture, from what stands on the displays
  local i a k c e g col
  for i in "${!RM_F[@]}"; do
    a=(${RM_F[i]}); k=${a[0]}
    if [[ $k == D ]]; then
      c=${RM_DSP[a[3]]:--}
      if [[ $c == - ]]; then e=${FURN_E[D]} g=${FURN_G[D]} col=${FURN_C[D]}
      else dsp_look "$c"; e=$DLE g=$DLG col=$DLC; fi
      GLYH[h$i]=$'\e[0;48;5;'"${RM_PED}m$e"
    else
      e=${FURN_E[$k]} g=${FURN_G[$k]} col=${FURN_C[$k]}; GLYH[h$i]=$e
    fi
    GLY[h$i]=$'\e[0;'"${col}m$g"
  done
  MAP_DIRTY=1
}
room_overlay() {  # cx0 cy0: furniture into the frame (called by render_map)
  local i a dx dy
  for i in "${!RM_F[@]}"; do
    a=(${RM_F[i]}); dx=$(( a[1] - $1 )) dy=$(( a[2] - $2 ))
    (( dx >= 0 && dx < VW && dy >= 0 && dy < VH )) && RI[dy]+="$(( dx * 10 + 3 )):1:h$i "
  done
}
room_go() {  # owner-id tier "displays": walk up into a room (from the open world only)
  [[ $CUR_MAP == W ]] || return
  (( DEAD )) && return
  room_map "$1"
  WX=$PX WY=$PY                                            # where the stairs bring you back down
  mount_off quiet; FISH_ST=0 GATH_MID=""
  room_build "$RMAP" "$2"; drop_vrows "$RMAP"
  RM_OWNER=$1 RM_TIER=$2 RM_DSP=($3) RM_SIGNED=0
  CUR_MAP=$RMAP CUR_DT=-1 PX=$RM_SX PY=$RM_SY UI="" clear_until=0
  cm_clear; set_palette -2; room_glyphs
  POS_DIRTY=1 MAP_DIRTY=1 NEED_FULL=1
  (( ALLY >= 0 )) && aly_place
}
room_leave() {  # [text]: back down to the taproom
  [[ $CUR_MAP == H* ]] || return
  leave_instance quiet
  logm "${1:-You go back down to the taproom.}" "$K_SYS"
}
room_left() { RM_F=() RM_AT=() RM_DSP=() RM_OWNER="" VIS_OWNER="" VIS_WANT=""; }   # (leave_instance calls it)
room_mine() { [[ $CUR_MAP == H* && $RM_OWNER == "$MY_ID" ]]; }
room_shown() { local x; RSH=0; for x in "${ROOMD[@]}"; do [[ $x != - ]] && RSH=$(( RSH + 1 )); done; }   # -> RSH

# --- renting -----------------------------------------------------------------------------------------------------
rent_week() { RWK=$(( (NOW / 86400000 + 3) / 7 )); }            # weeks start on Monday, like the mythic affixes
room_pay() {  # -> 0 if this week's rent is paid (pays it now if it can)
  local r=${ROOM_RENT[ROOM_T]}
  rent_week
  (( ROOM_PAID >= RWK )) && return 0
  if (( GOLD >= r )); then GOLD=$(( GOLD - r )); logm "${EMJ[gold]}You pay this week's rent: ${r}g." "$K_LOOT"
  elif (( BANKG >= r )); then BANKG=$(( BANKG - r )); logm "${EMJ[gold]}This week's rent (${r}g) comes out of your vault." "$K_LOOT"
  else logm "This week's rent is ${r}g and you can't pay it. Your things are safe - come back with the gold." "$K_HURT"; return 1; fi
  ROOM_PAID=$RWK; save_char
}
room_rent() {  # tier: move in, or move up to a bigger room (everything moves along)
  local t=$1 cost first=0
  (( t >= 1 && t <= NROOM )) || return 1
  if (( t == ROOM_T )); then logm "That is your room already." "$K_SYS"; return 1; fi
  if (( t < ROOM_T )); then logm "Your ${ROOM_NAME[ROOM_T]} is bigger - the guild does not move anybody down." "$K_SYS"; return 1; fi
  (( LVL >= ROOM_LVL[t] )) || { logm "The ${ROOM_NAME[t]} is kept for heroes of level ${ROOM_LVL[t]} and up." "$K_HURT"; return 1; }
  cost=$(( ROOM_COST[t] - ROOM_COST[ROOM_T] ))
  (( GOLD >= cost )) || { logm "The ${ROOM_NAME[t]} costs ${cost}g to move in (you have $GOLD)." "$K_HURT"; return 1; }
  (( ROOM_T == 0 )) && first=1
  GOLD=$(( GOLD - cost )) ROOM_T=$t
  rent_week; ROOM_PAID=$RWK
  v50_fix
  if (( first )); then logm "🔑 The key to your ${ROOM_NAME[t]} is yours! Any innkeeper takes you up - [9] when you talk to them." "$K_ANN"
  else logm "🔑 You move up into the ${ROOM_NAME[t]}. Your things are already there." "$K_ANN"; fi
  send EVT "$MY_ID" "$MY_NAME" "rents the ${ROOM_NAME[t]} at the inn!"
  ach_check; save_char
}
room_home() {  # go up to my own room
  (( ROOM_T )) || { logm "You have no room yet - rent one here first." "$K_SYS"; return; }
  room_pay || return
  room_go "$MY_ID" "$ROOM_T" "${ROOMD[*]}"
  logm "You climb the stairs to your ${ROOM_NAME[ROOM_T]}. Walk into things to use them." "$K_GOOD"
  room_bcast
}
door_next() { ROOM_DOOR=$(( (ROOM_DOOR + 1) % 3 )); logm "Your door: ${DOOR_NAME[ROOM_DOOR]}." "$K_SYS"; save_char; room_bcast; }

# --- inside: the furniture ---------------------------------------------------------------------------------------
room_use() {  # furniture index
  local a=(${RM_F[$1]}) k who=${OP_NAME[$RM_OWNER]:-someone}
  k=${a[0]}
  case $k in
    B) if room_mine; then room_sleep; else logm "That is $who's bed. Better not."; fi ;;
    C) if room_mine; then room_chest; else logm "$who's chest is locked. Of course it is."; fi ;;
    D) if room_mine; then DSP_I=${a[3]} DSP_CUR=0 UI=dsp
       else dsp_examine "${a[3]}"; fi ;;
    K) if room_mine; then BOOK_PG=0 UI=book; else logm "$who's collection book: $RM_NCOL of $NCOL collectables found."; fi ;;
    G) if room_mine; then UI=guest; else room_sign; fi ;;
    *) logm "${FURN_SAY[$k]}" ;;
  esac
  MAP_DIRTY=1
}
room_sleep() {
  room_shown
  local p=$(( ROOM_REST[ROOM_T] + (RSH / 4 > 10 ? 10 : RSH / 4) ))
  REST_PCT=$p REST_UNTIL=$(( NOW + REST_MS ))
  rest "You sleep in your own bed and wake up Well Rested: +$p% experience from fights for 30 minutes."
  save_char
}
room_chest() {
  BK_TAB=2 BK_INPUT="" BK_SIDE=0 BK_CUR=(0 0) BK_TOP=(0 0)
  UI=bank MAP_DIRTY=1
}
dsp_examine() {  # slot (a visitor looks at a display)
  local c=${RM_DSP[$1]:--}
  if [[ $c == - ]]; then logm "An empty display."; return; fi
  item_name "$c" "$CLS"; item_icon "$c" "$CLS"
  if [[ $IK == C ]]; then logm "On display: $II${II:+ }$INAME - ${CS_NAME[${CL_SET[IKD]}]}. \"${CL_FL[IKD]}\"" $'\e['"${ICOL}m"
  else bonus_txt; logm "On display: $II${II:+ }$INAME${IVAL:+ (+$IVAL)}${BTX:+, $BTX}" $'\e['"${ICOL}m"; fi
}
dsp_put() {  # slot bag-index: put something on a display (what stood there goes back into your bags)
  local s=$1 i=$2 c old
  c=${INV[i]}; [[ -n $c ]] || return 1
  old=${ROOMD[s]:--}
  unset "INV[i]"; INV=("${INV[@]}"); unset "NEWG[${c%!}]"
  ROOMD[s]=${c%!}
  [[ $old != - ]] && INV+=("$old")
  item_name "$c" "$CLS"; logm "You put the $INAME on display." "$K_GOOD"
  room_refresh
}
dsp_take() {  # slot
  local s=$1 c=${ROOMD[$1]:--}
  [[ $c != - ]] || return 1
  (( ${#INV[@]} < BAGS )) || { logm "Your bags are full." "$K_HURT"; return 1; }
  INV+=("$c"); ROOMD[s]=-
  item_name "$c" "$CLS"; logm "You take the $INAME back." "$K_SYS"
  room_refresh
}
room_refresh() {  # my displays changed: redraw, tell visitors, save
  room_mine && { RM_DSP=("${ROOMD[@]}"); room_glyphs; }
  room_bcast; ach_check; save_char
}

# --- the guestbook ------------------------------------------------------------------------------------------------
guest_add() {  # name: newest first, everybody once, twelve at most
  local n=$1 e out="$1:$(( NOW / 86400000 ))" k=1
  for e in $GUESTS; do
    [[ ${e%%:*} == "$n" ]] && continue
    (( k >= 12 )) && break
    out+=" $e"; k=$(( k + 1 ))
  done
  GUESTS=$out
}
room_sign() {
  (( RM_SIGNED )) && { logm "You already signed it."; return; }
  RM_SIGNED=1
  send RSIGN "$MY_ID" "$MY_NAME" "$RM_OWNER"
  logm "You sign ${OP_NAME[$RM_OWNER]:-the owner}'s guestbook." "$K_GOOD"
}

# --- visiting (player to player, through the hub) ---------------------------------------------------------------
room_list() { local IFS=,; RLIST="${ROOMD[*]}"; }              # -> RLIST "C.5,-,U.3"
door_lets() {  # id -> 0 if my door lets that player in
  (( ROOM_T )) || return 1
  case $ROOM_DOOR in 2) return 0 ;; 1) in_party "$1" ;; *) return 1 ;; esac
}
room_bcast() {  # tell everybody in my room what it looks like now (tier 0: the door closed)
  local id here=0 t=$ROOM_T
  (( ROOM_T )) || return
  room_map "$MY_ID"
  for id in "${!OP_MAP[@]}"; do [[ ${OP_MAP[$id]} == "$RMAP" ]] && here=1; done
  (( here )) || return
  (( ROOM_DOOR == 0 )) && t=0
  col_count; room_list
  send ROOM "$MY_ID" "$MY_NAME" '*' "$t" "$CLN" "$RLIST"
}
visit_ask() { VIS_INFO=() VIS_T=$NOW UI=visit MAP_DIRTY=1; send RASK "$MY_ID" "$MY_NAME"; }
visit_go() {  # owner id
  [[ -n ${OP_NAME[$1]} ]] || return
  VIS_WANT=$1
  send RREQ "$MY_ID" "$MY_NAME" "$1"
  logm "You ask the innkeeper to take you up to ${OP_NAME[$1]}'s room..." "$K_SYS"
}
room_msg() {  # typ from name b c d e  (cli_line hands over RASK RHAS RREQ ROOM RNO RSIGN)
  local typ=$1 from=$2 nm=$3 b=$4 c=$5 d=$6 e=$7 x l=() ok=() n
  if [[ $typ == @(RASK|RREQ|RSIGN) ]]; then                       # what makes me answer: once a second per player
    (( NOW - ${RM_ANS[$from:$typ]:-0} >= 1000 )) || return
    RM_ANS[$from:$typ]=$NOW; (( ${#RM_ANS[@]} > 200 )) && RM_ANS=()
  fi
  case $typ in
    RASK) door_lets "$from" || return
          room_shown; col_count
          send RHAS "$MY_ID" "$MY_NAME" "$from" "$ROOM_T" "$RSH" "$CLN" ;;
    RHAS) [[ $b == "$MY_ID" ]] && [[ $c =~ ^[1-4]$ ]] && isnum "$d" && isnum "$e" || return
          (( d <= 99 && e <= NCOL )) || return
          VIS_INFO[$from]="$c $d $e"; MAP_DIRTY=1 ;;
    RREQ) [[ $b == "$MY_ID" ]] || return
          if (( ! ROOM_T )); then send RNO "$MY_ID" "$MY_NAME" "$from" none
          elif ! door_lets "$from"; then x=locked; (( ROOM_DOOR )) && x=party; send RNO "$MY_ID" "$MY_NAME" "$from" "$x"
          else
            col_count; room_list
            send ROOM "$MY_ID" "$MY_NAME" "$from" "$ROOM_T" "$CLN" "$RLIST"
            logm "$nm comes up to visit your ${ROOM_NAME[ROOM_T]}." "$K_PARTY"
          fi ;;
    RNO)  [[ $b == "$MY_ID" && $VIS_WANT == "$from" ]] || return
          VIS_WANT=""
          case $c in
            none)  logm "$nm has no room at the inn." "$K_SYS" ;;
            party) logm "$nm's door only opens for their party." "$K_SYS" ;;
            *)     logm "$nm's door is locked." "$K_SYS" ;;
          esac ;;
    ROOM) [[ $c =~ ^[0-4]$ ]] && isnum "$d" || return
          (( d <= NCOL )) || d=0
          n=${ROOM_NDSP[c]:-0}
          IFS=, read -r -a l <<< "$e"
          for x in "${l[@]:0:n}"; do if [[ $x == - ]] || valid_item "$x"; then ok+=("$x"); else ok+=(-); fi; done
          while (( ${#ok[@]} < n )); do ok+=(-); done
          if [[ $b == "$MY_ID" && $VIS_WANT == "$from" ]]; then          # the door opens for me
            VIS_WANT=""
            (( c )) || return
            [[ $CUR_MAP == W ]] || return
            room_go "$from" "$c" "${ok[*]}"; VIS_OWNER=$from RM_NCOL=$d
            logm "You step into $nm's ${ROOM_NAME[c]}. Walk into the displays to look at them - and sign the guestbook!" "$K_GOOD"
          elif [[ $b == '*' && $VIS_OWNER == "$from" ]]; then           # the owner changed something
            room_map "$from"; [[ $CUR_MAP == "$RMAP" ]] || return
            if (( c == 0 )); then room_leave "$nm closed the door - the innkeeper shows you out."; return; fi
            if (( c != RM_TIER )); then
              local ox=$PX oy=$PY
              room_build "$RMAP" "$c"; drop_vrows "$RMAP"; RM_TIER=$c
              p_walk "$RMAP" "$ox" "$oy" && [[ -z ${RM_AT[$ox,$oy]} ]] && PX=$ox PY=$oy || { PX=$RM_SX PY=$RM_SY; }
              NEED_FULL=1
            fi
            RM_DSP=("${ok[@]}") RM_NCOL=$d; room_glyphs
          fi ;;
    RSIGN) [[ $b == "$MY_ID" ]] && (( ROOM_T )) || return
           room_map "$MY_ID"; [[ ${OP_MAP[$from]} == "$RMAP" ]] || return     # only people who stand in my room
           guest_add "$nm"; logm "📒 $nm signed your guestbook!" "$K_PARTY"; save_char; ach_check ;;
  esac
}

# --- achievements (index ACH50 and up) -------------------------------------------------------------------------------
ach_ok50() {
  local j=$(( $1 - ACH50 )) s
  case $j in
    0) (( ROOM_T >= 1 )) ;; 1) (( ROOM_T >= 4 )) ;;
    2|3|4) col_count; case $j in 2) (( CLN >= 20 )) ;; 3) (( CLN >= 50 )) ;; *) (( CLN >= NCOL )) ;; esac ;;
    5|6|7|8|9|10) s=$(( j - 5 )); col_count; (( CLSD[s] >= CLST[s] )) ;;
    11) room_shown; (( RSH >= 20 )) ;;
    12) set -- $GUESTS; (( $# >= 5 )) ;;
    *) ach_ok60 "$1" ;;                                        # v6.0
  esac
}

v50_tick() {  # once a second
  if (( NOW - ${COL_T:-0} >= 5000 )); then COL_T=$NOW; col_scan; col_story; fi
  if [[ -n $VIS_OWNER && -z ${OP_NAME[$VIS_OWNER]} ]]; then room_leave "Your host has left the world - the innkeeper shows you out."; fi
  [[ -n $VIS_WANT ]] && [[ -z ${OP_NAME[$VIS_WANT]} ]] && VIS_WANT=""
}

# ---------------------------------------------------------------------------
#  Module 05f - v5.0 screens: the rooms at the inn (renting, the door,
#  visiting), a display in your room, the collection book, the guestbook.
# ---------------------------------------------------------------------------

# --- the innkeeper: rooms upstairs -------------------------------------------------------------------------------
ui_inn() {
  local i cost col st wide=0
  (( MW >= 70 && VH >= 23 )) && wide=1
  rent_week
  ui "  ROOMS AT THE INN" "$K_LOOT$B"
  ui "  Every inn of the realm keeps your room ready for you." "$K_SYS"
  ui ""
  if (( ROOM_T )); then
    room_shown
    ui "  Your ${ROOM_NAME[ROOM_T]}: $RSH/${ROOM_NDSP[ROOM_T]} on display, chest ${#ROOMC[@]}/${ROOM_CAP[ROOM_T]}" "$B"
    if (( ROOM_PAID >= RWK )); then ui "  Rent ${ROOM_RENT[ROOM_T]}g a week - paid for this week." "$K_GOOD"
    else ui "  Rent ${ROOM_RENT[ROOM_T]}g a week - due when you go up." "$K_LOOT"; fi
    ui "  [1] Go up to my room" "$K_GOOD$B"
  else
    ui "  Rent a room: a bed to wake up Well Rested, a chest" "$K_CHAT"
    ui "  and displays to show off your treasures." "$K_CHAT"
  fi
  ui ""
  for (( i = 1; i <= NROOM; i++ )); do
    cost=$(( ROOM_COST[i] - ROOM_COST[ROOM_T] ))
    if (( i == ROOM_T )); then st="your room" col=$K_GOOD
    elif (( i < ROOM_T )); then st="smaller than yours" col=$K_SYS
    elif (( LVL < ROOM_LVL[i] )); then st="from level ${ROOM_LVL[i]}" col=$K_SYS
    else
      st="${cost}g + ${ROOM_RENT[i]}g/week"; (( ROOM_T )) && st="move up: ${cost}g"
      col=$K_CHAT; (( GOLD >= cost )) || col=$K_HURT
    fi
    printf -v PF '  [%d] %-12s %s' $(( i + 1 )) "${ROOM_NAME[i]}" "$st"
    ui "$PF" "$col"
    printf -v PF '      %d displays, chest %d, rested +%d%%' "${ROOM_NDSP[i]}" "${ROOM_CAP[i]}" "${ROOM_REST[i]}"
    ui "$PF" "$K_SYS"
    (( wide )) && ui "      ${ROOM_DESC[i]}" "$K_SYS"
  done
  ui ""
  (( ROOM_T )) && ui "  [d] door: ${DOOR_NAME[ROOM_DOOR]}"
  ui "  [v] visit a friend's room   [esc] back" "$K_SYS"
}
inn_key() {
  case $1 in
    1) room_home ;;
    [2-5]) room_rent $(( $1 - 1 )) ;;
    d) (( ROOM_T )) && door_next ;;
    v) visit_ask ;;
  esac
}

# --- visiting: who has a room for me? -----------------------------------------------------------------------------------
visit_list() {  # -> VIS_L: the owners who answered, sorted by name
  local id l=() s
  for id in "${!VIS_INFO[@]}"; do [[ -n ${OP_NAME[$id]} ]] && l+=("${OP_NAME[$id],,} $id"); done
  VIS_L=()
  (( ${#l[@]} )) || return
  while read -r s id; do VIS_L+=("$id"); done < <(printf '%s\n' "${l[@]}" | sort)
}
ui_visit() {
  local i id a
  visit_list
  ui "  VISIT A ROOM" "$K_LOOT$B"
  ui "  Whose door is open to you? (they must be online)" "$K_SYS"
  ui ""
  for (( i = 0; i < ${#VIS_L[@]} && i < 9; i++ )); do
    id=${VIS_L[i]} a=(${VIS_INFO[$id]})
    ui "  [$(( i + 1 ))] ${OP_NAME[$id]}'s ${ROOM_NAME[a[0]]}" "$K_CHAT$B"
    ui "      ${a[1]} on display, ${a[2]}/$NCOL collectables found" "$K_SYS"
  done
  if (( ! ${#VIS_L[@]} )); then
    if (( NOW - VIS_T < 3000 )); then ui "  The innkeeper asks around the taproom..." "$K_SYS"
    else ui "  Nobody's door is open to you right now." "$K_SYS"; fi
  fi
  ui ""
  ui "  [1-9] knock   [r] ask again   [esc] back" "$K_SYS"
}
visit_key() {
  case $1 in
    [1-9]) visit_list; local id=${VIS_L[$(( $1 - 1 ))]}; [[ -n $id ]] && { visit_go "$id"; UI=""; } ;;
    r) visit_ask ;;
  esac
}

# --- a display in my room -------------------------------------------------------------------------------------------------
dsp_row() {  # code -> RC RP: icon, name, what it is
  local c=$1
  rb; item_name "$c" "$CLS"; item_icon "$c" "$CLS"
  [[ -n $II ]] && rt "$II "
  rt "$INAME" "$ICOL"
  if [[ $IK == C ]]; then rt "  ${CS_NAME[${CL_SET[IKD]}]}" "38;5;245"
  elif [[ $IK == B ]]; then rt "  bag" "38;5;245"
  else rt "  ${RAR_NAME[IRR],,} ${SLOT_LABEL[$IK],,}" "38;5;245"; fi
}
ui_dsp() {
  local i n=${#INV[@]} H top c mk
  room_mine || { UI=""; return; }
  ui "  DISPLAY $(( DSP_I + 1 )) OF ${ROOM_NDSP[ROOM_T]}" "$K_LOOT$B"
  c=${ROOMD[DSP_I]:--}
  if [[ $c == - ]]; then ui "  It is empty." "$K_SYS"
  else dsp_row "$c"; RC=$'\e[0§m'"  on it: $RC" RP="  on it: $RP"; uxs; ui "  [t] take it back into your bags" "$K_SYS"; fi
  ui ""
  ui "  PUT SOMETHING ON IT - from your bags" "$B"
  H=$(( VH - 8 )); (( H < 3 )) && H=3
  (( DSP_CUR >= n )) && DSP_CUR=$(( n - 1 )); (( DSP_CUR < 0 )) && DSP_CUR=0
  top=$(( DSP_CUR - H / 2 )); (( top > n - H )) && top=$(( n - H )); (( top < 0 )) && top=0
  (( n )) || ui "  (your bags are empty)" "$K_SYS"
  for (( i = top; i < n && i < top + H; i++ )); do
    dsp_row "${INV[i]}"
    if (( i == DSP_CUR )); then mk=$'\e[0;1;38;5;226m▶ '; else mk="  "; fi
    RC="$mk$RC" RP="  $RP"; uxs
  done
  ui ""
  ui "  [↑↓] choose  [enter] put it on display  [esc] done" "$K_SYS"
}
dsp_key() {
  case $1 in
    UP|w) (( DSP_CUR > 0 )) && DSP_CUR=$(( DSP_CUR - 1 )) ;;
    DOWN|s) (( DSP_CUR < ${#INV[@]} - 1 )) && DSP_CUR=$(( DSP_CUR + 1 )) ;;
    ''|$'\r'|' '|e) dsp_put "$DSP_I" "$DSP_CUR" ;;
    t) dsp_take "$DSP_I" ;;
  esac
}

# --- the collection book -----------------------------------------------------------------------------------------------------
ui_book() {
  local s i L=() P=() per pages first last e nm st col
  col_count
  for (( s = 0; s < NCS; s++ )); do
    if (( TW2 )); then e="${CS_E[s]} "; else e=""; fi
    L+=("  $K_LOOT$B$e${CS_NAME[s]^^}$N $K_SYS${CLSD[s]}/${CLST[s]} - ${CS_HOW[s]}$N")
    P+=("  $e${CS_NAME[s]^^} ${CLSD[s]}/${CLST[s]} - ${CS_HOW[s]}")
    for i in ${COL_SETL[s]}; do
      if col_has "$i"; then
        col_where "$i"; st=${CW_AT:-found, not kept}
        col=${RAR_COL[${CL_RR[i]}]}; [[ -z $CW_AT ]] && col="38;5;245"
        if (( TW2 )); then e="${CL_E[i]} "; else e="${CL_G[i]} "; fi
        printf -v nm '%-30s' "${CL_NAME[i]}"
        L+=("    $e"$'\e['"${col}m$nm$N $K_SYS$st$N"); P+=("    $e$nm $st")
      else
        if (( TW2 )); then e="❔ "; else e="? "; fi
        L+=("    $e$K_SYS??? - ${CL_SRC[i]}$N"); P+=("    $e??? - ${CL_SRC[i]}")
      fi
    done
  done
  per=$(( VH - 3 )); (( per < 5 )) && per=5
  pages=$(( (${#L[@]} + per - 1) / per ))
  (( BOOK_PG >= pages )) && BOOK_PG=$(( pages - 1 )); (( BOOK_PG < 0 )) && BOOK_PG=0
  first=$(( BOOK_PG * per )) last=$(( first + per ))
  ui "  COLLECTION BOOK  $CLN/$NCOL found   page $(( BOOK_PG + 1 ))/$pages  [<][>] turn  [esc]" "$K_LOOT$B"
  ui ""
  for (( i = first; i < last && i < ${#L[@]}; i++ )); do uix "${L[i]}" "${P[i]}"; done
}
book_key() {
  case $1 in
    RIGHT|'>'|.|d|l|' ') BOOK_PG=$(( BOOK_PG + 1 )) ;;
    LEFT|'<'|,|a|h) (( BOOK_PG > 0 )) && BOOK_PG=$(( BOOK_PG - 1 )) ;;
  esac
}

# --- the guestbook --------------------------------------------------------------------------------------------------------------
ui_guest() {
  local e n d today=$(( NOW / 86400000 )) k=0
  set -- $GUESTS
  ui "  YOUR GUESTBOOK   $# signature(s)   [esc] close" "$K_LOOT$B"
  ui ""
  (( $# )) || ui "  Nobody has signed it yet. Invite your friends up!" "$K_SYS"
  for e in "$@"; do
    n=${e%%:*} d=$(( today - ${e#*:} ))
    if (( d <= 0 )); then d="today"; elif (( d == 1 )); then d="yesterday"; else d="$d days ago"; fi
    printf -v PF '  %-14s %s' "$n" "$d"; ui "$PF" "$K_CHAT"
    k=$(( k + 1 )); (( k >= VH - 5 )) && break
  done
  ui ""
  ui "  Visitors sign it when they walk into it." "$K_SYS"
}

# ---------------------------------------------------------------------------
#  Module 04j - v6.0 client: what the new content needs once the sprites and
#  screens exist - icons of the new materials, the sprites of the hunter's
#  trophies, the achievements of 6.0, and the "what is it for" of a material
#  (it follows the tables now, for every material there is).
# ---------------------------------------------------------------------------
MAT_I[M60]=🔵 MAT_I[M60+1]=🟣 MAT_I[M60+2]=🌾 MAT_I[M60+3]=🍇 MAT_I[M60+4]=🐠 MAT_I[M60+5]=🐟
for i in ${COL_SETL[6]}; do CL_E[i]=${MEMO[CL_REF[i]]:-🎯}; done; unset i

ach_ok60() {  # achievements of 6.0 (index ACH60 and up)
  local n
  case $(( $1 - ACH60 )) in
    0) (( RAREK >= 50 )) ;;
    1) col_count; (( CLSD[6] >= CLST[6] )) ;;
    2) col_count; (( CLN >= 100 )) ;;
    3) n=${QLS//[^x]/}; (( ${#n} >= 25 )) ;;
    4) (( DCLR >= 250 )) ;;
    *) return 1 ;;
  esac
}

mat_uses() {  # material -> MU (lines): what the crafting tables do with it (v6.0: from the recipes, not from index ranges)
  local k=$1 i t TW2=0 sv=$CRAFT sf=$FWK sa=$FAK seen=" "
  MU=()
  if gem_kq "$k"; then
    local g=$GKI q=$(( GQI - 1 )) v=(${GEM_V[GKI]})
    MU+=("In a socket: +${v[q]}${GEM_TXT[g]}." "Jewelcrafting at any smith sets it into gear with sockets.")
    (( q < GEM_MAXQ - 1 )) && MU+=("Three of them make one ${GEM_GRADE[q+1]} ${GEM_NAME[g]}.")
    return
  fi
  mat_prof "$k"
  case $MP_K in
    1) CRAFT=forge; craft_build
       for i in "${!RC_ID[@]}"; do
         [[ " ${RC_NEED[i]} " == *" $k:"* && ${RC_ID[i]} == W.* ]] || continue
         t=${RC_ID[i]##*.}; [[ $seen == *" $t "* ]] && continue; seen+="$t "
         MU+=("Forge (any smith): ${TIER_Q[t]} weapons and armor - $(( 15 * t * t ))g, often Rare or better.")
       done ;;
    2) CRAFT=alch; craft_build
       for i in "${!RC_ID[@]}"; do
         [[ " ${RC_NEED[i]} " == *" $k:"* ]] || continue
         t=" ${RC_NEED[i]}"; t=${t#* $k:}; t=${t%% *}
         MU+=("Alchemy: ${RC_LAB[i]%% (*} ($t)")
       done ;;
    *) if (( MAT_RARE[k] == 2 )); then MU+=("Cooking: Fisherman's Feast"); else MU+=("Cooking: Grilled Fish"); fi
       MU+=("General stores, traders and spice stalls buy fish.") ;;
  esac
  (( ${#MU[@]} )) || MU+=("Shops pay ${MAT_VAL[k]}g for it.")
  CRAFT=$sv FWK=$sf FAK=$sa
}

# ---------------------------------------------------------------------------
#  Module 04k - your hero lives on the server (v6.2): log in, load, save.
#  Nothing is stored on the player's computer. See 03c_accounts.sh and
#  docs/PROTOCOL.md for the messages.
# ---------------------------------------------------------------------------
CHAR_REMOTE=0 CHAR_TEXT="" ACC_PASS="" ACK_PEND=0 SAVE_LOST=0 MIGRATE_FILE="" AR_K="" AR_A="" AR_B="" AR_C="" ar_buf=""
US=$'\x1f'

acct_wait() {  # ms -> waits for one private answer (AR<my id>) into AR_K AR_A AR_B AR_C; 1 = silence, 2 = connection lost
  local end line rc tag typ from
  now_ms; end=$(( NOW + $1 ))
  while now_ms; (( NOW < end )); do
    IFS= read -r -t 0.2 -u 7 line 2>/dev/null; rc=$?
    if (( rc == 0 )); then
      line=$ar_buf$line; ar_buf=""
      [[ $line == "SM1|AR$MY_ID|srv|"* ]] || continue
      IFS='|' read -r tag typ from AR_K AR_A AR_B AR_C <<< "$line"
      return 0
    elif (( rc > 128 )); then ar_buf+=$line
    else return 2; fi
  done
  return 1
}

acct_pass_ok() { valid_pass "$1"; }

acct_ask() {  # prompt -> ACC_IN (not echoed)
  local old=""
  printf '%s' "$1" >&2
  [[ -t 0 ]] || die "no terminal to ask for the password - set SHELLMMO_PASS"
  IFS= read -rs ACC_IN; printf '\n' >&2
}

acct_login() {  # talks to the world server: loads the hero into CHAR_TEXT ("" = a new hero)
  local tries=0 n total txt="" again
  CHAR_TEXT="" ar_buf=""
  while :; do
    if [[ -z $ACC_PASS ]]; then
      if [[ -n $SHELLMMO_PASS ]]; then ACC_PASS=$SHELLMMO_PASS
      else acct_ask "Password for $MY_NAME: "; ACC_PASS=$ACC_IN; fi
    fi
    if ! acct_pass_ok "$ACC_PASS"; then
      echo "The password needs 4-32 characters (not |)." >&2
      [[ -n $SHELLMMO_PASS ]] && die "bad SHELLMMO_PASS"
      ACC_PASS=""; continue
    fi
    for (( n = 0; n < 5; n++ )); do                 # the world server may still be starting up
      send ALOAD "$MY_ID" "$MY_NAME" "$ACC_PASS" || die "lost the connection"
      acct_wait 3000 && break
      (( n == 0 )) && echo "Waiting for the world server..." >&2
    done
    (( n < 5 )) || die "the world server did not answer - is it running, or older than 6.2?"
    case $AR_K in
      NONE)
        if [[ -z $SHELLMMO_PASS ]]; then
          echo "New hero: $MY_NAME - this name is free." >&2
          acct_ask "Repeat the password: "
          if [[ $ACC_IN != "$ACC_PASS" ]]; then echo "The passwords differ." >&2; ACC_PASS=""; continue; fi
        fi
        if [[ -r $CHAR_FILE ]]; then                  # a hero saved on this computer before 6.2: move it to the server
          CHAR_TEXT=$(<"$CHAR_FILE"); MIGRATE_FILE=$CHAR_FILE
          echo "Found your old local hero - it moves to the server." >&2
        fi
        return 0 ;;
      DATA)
        txt=""; n=$AR_A total=$AR_B txt=$AR_C
        while [[ $n =~ ^[0-9]+$ && $total =~ ^[0-9]+$ ]] && (( n < total )); do
          acct_wait 5000 || die "the server stopped answering while sending your hero"
          [[ $AR_K == DATA ]] || continue
          n=$AR_A total=$AR_B txt+=$AR_C
        done
        CHAR_TEXT=${txt//$US/$'\n'}
        return 0 ;;
      DENY)
        echo "Login refused: $AR_B" >&2
        if [[ $AR_A == PASS && -z $SHELLMMO_PASS ]] && (( ++tries < 3 )); then ACC_PASS=""; continue; fi
        die "could not log in as $MY_NAME" ;;
      *) die "unexpected answer from the server ($AR_K)" ;;
    esac
  done
}

acct_resume() {  # after a lost connection: log in again without loading, then store what happened meanwhile
  send ALOAD "$MY_ID" "$MY_NAME" "$ACC_PASS" keep
  if acct_wait 5000 && [[ $AR_K == OK ]]; then return 0; fi
  [[ $AR_K == DENY ]] && logm "Could not log in again: $AR_B" "$K_HURT"
  net_up=0; exec 7>&- 2>/dev/null
  return 1
}

acct_send_save() {  # text on stdin of $1
  local txt=${1//$'\n'/$US} n total
  total=$(( (${#txt} + 1399) / 1400 ))
  (( total >= 1 && total <= 60 )) || { logm "Your hero is too big to save (${#txt} characters)!" "$K_HURT"; return 1; }
  for (( n = 1; n <= total; n++ )); do
    send ASAVE "$MY_ID" "$n" "$total" "${txt:(n-1)*1400:1400}" || return 1
  done
  ACK_PEND=$(( ACK_PEND + 1 ))
}

acct_acked() {
  (( ACK_PEND > 0 )) && ACK_PEND=$(( ACK_PEND - 1 ))
  if [[ -n $MIGRATE_FILE && -e $MIGRATE_FILE ]]; then
    mv -f "$MIGRATE_FILE" "$MIGRATE_FILE.moved-to-server" 2>/dev/null && logm "Your old local hero file is now $MIGRATE_FILE.moved-to-server (the server has your hero)." "$K_SYS"
    MIGRATE_FILE=""
  fi
}

acct_flush() {  # on quit: wait (at most 4 s) until the server confirmed our last saves
  local end
  (( CHAR_REMOTE && net_up && ACK_PEND > 0 )) || return 0
  now_ms; end=$(( NOW + 4000 ))
  while (( ACK_PEND > 0 && NOW < end )); do
    net_poll 50; (( ACK_PEND > 0 )) && sleep 0.05; now_ms
  done
}

# v6.3: the world server restarted under us (or dropped our session): log in again without blocking -
# AUTH asks for it, OK (the answer to "keep") brings us back into the world
acct_nudged() {
  (( CHAR_REMOTE )) || return
  (( NOW - ${ACC_NUDGED:-0} >= 3000 )) || return
  ACC_NUDGED=$NOW
  send ALOAD "$MY_ID" "$MY_NAME" "$ACC_PASS" keep
}
acct_back() {
  (( CHAR_REMOTE )) || return
  [[ $CUR_MAP != W ]] && leave_instance quiet
  [[ -n $MY_PARTY ]] && { MY_PARTY="" PARTY_LEADER="" PARTY_IDS=(); pq_to_personal; }
  send HELLO "$MY_ID" "$MY_NAME" "$CLS" "$LVL"; send_pos; send SYNC "$MY_ID" W
  ACK_PEND=0; save_char
  logm "The world server is back - you are in the world again." "$K_GOOD"
}
acct_kicked() {  # our hero logged in somewhere else: stop at once, and do not save over the new session
  CLS=""                                   # (save_char does nothing without a class)
  KICKED=$1
  exit 0
}

# ---------------------------------------------------------------------------
#  The open world (480x200), made by tools/worldgen. Legend:
#  . , " * grass/flowers  T trees  P pines  ~ water  = bridge  : road  ^ mountains
#  % swamp  S s sand/dunes  Y cactus  N n snow  I ice  A ash  L lava  R rock
#  K C crystal ground/spires  J W jungle ground/trees  D V badlands/mesas
#  E G void ground/chasms  # walls  _ floor  > dungeon  Q quest board  O fountain
#  F campfire  Z waystone
# ---------------------------------------------------------------------------
world_data() {
  cat <<'WORLD'
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
^^T^T^^^^^^^^TTT^^^^TTTT^^T^T^"^T^T^^..^T^^^^T^^T^^^^^^^T^^TT^^T^^^....^^,^^^^,^,^^^*^^^^^"^^^^...^^..^^..^^^^^^^^^^^^^^^^^^^""^""^^^"^^^^^^^^^^"^^^^^^^^^^^,,,^nnnnN^^NNNPNNNNNNNNNNNNPPPPPnnnnnnnnnnnnnPPPPPNNNNNNNPNnnnnnnnnPPnnnnnnPnnnnnn^^KKKNNNN^^^CCCKKKKKKKKKKKKKKKK^^^^^^^^^^^^^^^^^^^^^^^^^^CCCCCCCCKKKKKKKKKNNNNCCKKKKKKKKCKKKKKKKKKNNKKKCKKKKKKKKKKKKKKKK^^XXX^^^^^HHHHHHHHXXHHHHHHHHHHHHNNHHHNNHHHHHHHHHHHHHHHNNNNHHHHHHHHHHHNNNNHHXXXHHHHHXXXXXXHHHHHHHHHHHXXXXXXXXHHHHXHHHHHHHX^
^^TTTTTTTTTTTTTTTTTTTTTTTTTTTT,T,.T.T..TTTTTTTTTTT~~TTTTTTTTTTTT...T...,,,..,,",,......,,""",,,.......T...,^^^^^^^^^^^^^^^^^^,,,,,^^""",,"T",,,T,,^^^^^^^T,,,,^^nnnnPPNNNNNnnnnnnnnnPPPPPPPNnnnnnnnNnnnnNNNPPPNNNNNNNNNnnnnnnnnnnnnnnnnnnnnnNP^^KNNNNNK^^^CCCKKKKKKKKKKKKKKKK^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^CCCCKKKKKCKKKKNKKCCCKKKKKKKCCCCKKKKKCNNKKCCCKKKKKKNNKKKKKKK^^XXXX^^^HHHHHHHHHHHHHHHHHHHHHHHNHHHHHNNHHHHHHHHHHHHXXNNHHHHHHHHHHHHNNNNNHHHXHHHHHXXXXXXXHHHHHHHHHHHXXXXXXXHHHHHHHHHHHHHH^
^TTTTTTTTTTTTTTTTTTTTTTTTTTTTT,.........TTTTTTTTTTT~~TTTTTTTTTTTT.....,,,,...,",,......,,,,,,,,......T....,^^^^^^^^^^^^^^^^^,,,,.,,^,,,,TT"",,,,,,.^^^^^""",,,,^nnnNPPNNNNnnnnnnnnnPPPPPNNNNNNNnnnnNNnnnNNNPPPNNNNPPNNNnnnnnnnnnnnnnnnnnnnnNPP^^KNNNNNKK^CKKKKKKKKKKKKKKKKKKKK^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^KKKKKKKKKKKKCKKKKKKKKCCKKKK^^^^^^^^^^^KKKKKKNNKKKKKKKK^XXXX^^^HHHHHHHHHHHHHHHHHHHHHHHHHHHHHNNHHHHHHHHHHHXXXNNHHHHHHHHHHHHNNNNNNNHHHHHHXXXHHHHHHHHHHHHHHHXXXHHHHHHHHHHHHHHHHHHH^
^TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT......TTTTTTTTTTTTT~~TTTTTTT...T......,,,,...,,,,,,...,*T,,,,,.......T.....^^^^^^^^^^^^^^^^^^T...,,^,,,,,""*^,..T..^^^^^^",,,,.^nnnnNNNNNNNNnnnnnnnnNNNNNNNNNNNnnnNNNnnnNNNNPNNNNnPPNNnnnnnnnnNNnnnnnnnnnnnNNP^^KKNNNKKK^KKKKCCCKKKKKKKKKKKKKK^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^KKKKCKKKKKKKKCKKKKKKKKKK^^^^^^^^^^^^^^KKKKNKKKKKKKK^^XXXX^^^HXHHHHHHHHHHHHHHHHHHHHHHHHHHXHHHHHHHHHHHHXXXXNNHHHHHHHHHHHHNNNHHHHHHHHHHXXXHHHHHHHHHHXXHHHXXXHHHHHHHHHHHHHHHHHHH^
^^TTTTTTTTTTTTTTTTTTTTTTTTTTTTTTT.....TTTTTTTTTTTTTT~~TTTT....*....T.,,,,,...,,,,,,,,,................,....T^^^^^^^^^^^^^^^^^...,,,,,,,,,T"^^^...T,,^^^^^^^^^,.^nnnnnNNNNNNNNNNnnnnNNNNNNNNNNNNNNNNNNNNNNNNNNNnnnnnPnnnnnnnnnNNNNPnnnnnNnnnNNN^^KKKKKKKK^NNKKCCCCKKKKKKKKKKKKKKC^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^KKKCCKKNNNNKKCCKKKKKKKKK^^^^^^^^^^^^^^^KKKKKKKKKKKKK^^XXX^^^HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHXXXXXHNNNHHHHHHHHHHNNHHHHHHHHHHHXXXHHHHHHNNNHXHHHHHXHHHHHHHHHHHHHHHHHHHH^
^^TTTTTTTTTTTTTTTTTTTTTTTTTTTTTT......TTTTTTTTTTTTTTT~~TTT........T..,,,,T...,,,""",,,...*.......*...TT,...,,^^^^^^^^^^^^^^^^^^^^"",.^^^,,,^^^^^..,""^^^^^^^^,.^nPPPnnNNNNNNNNNNnnNNNNnnnNNNNNNNNNNNNNNNNPNNNnnnnnnnnnnnPnnnnNNNPPPnnnNPPnnNNN^^KKKKKKKKNNNKKKCKKKKKKKKKKKKKKKKK^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^KKKCCKKNNNNNKCCKKKKKKKKK^^^^^^^^^^^^^^^KKKKKKKKKKKKK^XXXX^^HHHHHHHHHHHHHHHHHHHHHNXXHHHHHHHHHHHXHHHHXXXXXXHNNNNHHHHHXHHHNHHHHHHHHHHHHXXXHHHHHHNNNHHHHHHHHHHHHHHHHHHHHHHHHXXXH^
^^TTTTTTTTTTTTTTTTTTTTTTTTT..TTT......TTTTTTTTTTTTTTTT~~T...........,,,,,,...,,,,,,,,,,...............,....^^^^^^^^^^^^^^^^^^..^^T,,.^^^^,#####^^.,"^^^^^^^^^,^^nnnPnNNNNNNNNNNNnnNNNNnnnNNNNNNNNNNNNNNNNNNNNnnnnnPPnnnnPnnnnNNNPP#####NNnnNNN^^KKKKKKKKKKKKKKKKKKKKKKKKKCCKKKKKKK^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^CCCKCCCKKII~~~~~IIKKKKKKKKKK^^^^^^^^^^^KKKKKKKKKKKKKK^^XXXXHHHHHHHXXHHHHHHHHHHHHHXXXXXHHHHHHHHHXXXHHHXXXXXHHNNNXHHHHXXXHHHXXHHHHHHHHHHXXXHHHHHNNNNHHHHHHHHHHHHHHH#####HHHHXXXH^
^^TTTTTTTTTTTTTTTTTTTTTTTT.....T......TTTTT.T,TTTTTTTTT~~........,,,,""""",..,,,,,,,,,"",.............T...^^^^^^^^^^^^^^^^^^...*.,,,^^^^^^#_>_#^^^^^^^^^^^.,,,^^nnnnNNNNPNNnnNNNnPnNNNnnnNNNNNNNNNNNNnnnnNNNNNnn^^^^PPnnnnnnnnnNNP#_>_#NNnnNNN^^KKKKKKKKKKKKKKKKKKKKKKKKKCCKKKKKKKKKK^^^^^^^^^^^^^^^^^^^^^^^CCKCCCCCCCCKKKI~~~~~~~IKKKKKKKKKCKKKKKKKCCKKKKKKKKKKKKKKCK^^XXXXHHHHHHHXHHHHHHHHHHHHHHXXXXXNHHHHHNNNXXXHHHXXXHHHHNNNHHHHHXXXHHHXXHHHHHHHHHHHXHHHNNNNNHHHHHHHHHHHHHHHHH#_>_#HHHHXXHH^
^^TTTTTTTTTTTTTTTTTTTTTTTT.......,,.T.#####...,T"TTTT""~~.......,""""""""",,,.....,,""""",............T..^^^^^^^^^^^..^^^^^,......^^^^^^^^^.:.^^^^^^^^^^^..,,,^^NNNNPPNPPNPPnNNNPPPNNNnnNNPPNNNNNNNNNnnnnnNNNNn^^^^^^PPnnnnnnnnNNNP.:.NNNnPN^^^^KKKKKKKKKKKKKKKKNKKKKKKKKCCKKKKKKKKKKKKNNKKNN^^^^^^^^^^^^^KCCNKKCCCCCKKKKKII~~~~~IIKKKKKKKKKCCKKKKKK#####KKKKKKKKKKKCK^^HXXXHHHHHHXXHHHHHHHHXHHHHXXXXXXNHHXXXXXXXXHHHHHXHHHHNNNNHHHHHHXHHHHXXXXXHHHHHHHHHHHXNNNNHXHHHHHHHHXXXXNHHHHH:HHHHXXHHNN^
^^TTTTTTTTTTTTTTTTTTTTTTTTT.....,,,,TT#_>_#:::::::::::::==:::*..,"""""""""",,....,,"""""",*........,,,,,,^^^^^^^^^^^..^^^^^^....^^^^^^^^^^^.:.^^^^^^^^^...,,,""^nnnNNPNPPPnnnNNNNPNNnnnnNNNPNNNNNNNNnnnnnnNNNNn^^^^^^^nnnnnnnnnnNNN.:nnNnn^^^^^^KKKKKKKKKKKKKKKNNKKNNKKKKKKKKKKKKKKKKKNNNKKKNNNN^^^^^^^^KKKKNNKKKKNKKKKKKKKKKKKKKKKKKKKKKKKCCCKKKKKK#_>_#KKKKKKKKKKKCKK^HHXXNHHHXXXXHHHHHHHXXXHHHXXXXXXXHXXXXXXXXXHHHHHXHHHHHNNHHHHHHHHHHHHXXXXXHHHHHHHHHHHXXHHHXXXHHHHHHHXXXXXHHHHH:HHHXXXHNNN^
^TTTTTTTTTTTTTTTTTTTTTTTTTTT,,,,,,,,,,..:....TT....,,""TT~~T:T,,,,,""""""""",,..,,,""""",,,,......,,,,,,,^^^^^^^^^^^..^^^^^^...^^^^^^^^^^^^^:^^^^^^^^^^..,,^""^^nnnnNNNNnnnnnNNNNNNnnnnNNnnPNNNNNNnnnnPPnnnNNNn^^^^^^^nnnnnPnnnnnnnn:nnnnn^^^^^^CKKKKKKKKKKKKKCNNKKKCKKKKKKKKKKKKKKKKKCNNKKKKNNNNK^^^^^KKKKKKKKKKKKKKKKKKKKKCCKKKKKKKKKKKCCCCCCCKKKKKK:KCCKKKKKKKKKKCKK^HHXNNNHXXXXXHHHHHHHHXHHHNHXXXXXHHHHXXXXXXHHHHHHXHHHHHHHHHHHHHHHHHHHHHHXXXHHHHHHHHHHXXHHHHXHHHHHHHHXXXXHHHHHH:HHHHXHHNNH^
^^TTTTTTTTTTTTTTTTTTT######,,T,,,,""",..*...TTT....,,""TTT~~:T,,,,,,""""""""",.,,,""""",,,,,......,,,,,,^^^^^^^^^^^^..^^^^^^...^^^^^^^^^^^^^:^^^^^"^^^:::::::::::::::::::::::::::::::::::::::::::::::::::::NNnn^^^^^^^nnnnnPnnnnnnnn:nnnnn^^^^^^CKKKKKKKKKKKKKKNNKKKNKKKKKKKKKKKKKKKKKCNNKKKKKKNNKCKKKKKKKKKKKKKKKKKKKKKKKKKKCKKKKKKKKKKKCCCCCKKKKKKKK:KCKKKKKKKKKKKKK^^HHHNNNHXXXXHXXXHHHHHHHHHNHHHHHHHHHHHHXXXHHHHHHHHHHHHHXXXXXXXXHHHHHHHHHXXXHHHHHHHHHHXHHHHHNNHHHHHHHHHHHHHHHHH:HHHHXHHNHH^
^^TTTTTTTTTTTTTTTTTTT#_____::,,,,,,"",...T..TTT...,,,"TTTT~~:T,,,,,,"""",""T,,..,,,""",,,,,,...T...,,,,,,^^^^^^^^^..*.^^^^^^..T^^^^^^^....^^:^^""",,^^:^.,^^T"^^nnnnNNNnnnnnNNNNNNNnnnnnnPPPNNNNNnnnnPPnnn:nnnn^^^^^^^NNNNnnnnnnnnnn:nnnn^^^^^^^CCCKKKKKKKKKKKKNNNKNNKKKKKKKKCCKKKKKKKCNKKKKKKKKKKKKKKKKKKKKKKKKKKKKCKKKK^^^KKKKKKKKKKKKKCCCCCKKKKKKKK:KKKKKKKKKKKKKKKK^HHHNNXXXXXXHXX^^^^^^^^^^^^^^^^HHHHHHHHXHHHHHXHHHHXXXXXXXXXXXXHHHHHHHHHHXXXXHHHHHHHHHHHHHNNNHHHHXXHHHHHHHHHHH:HHHHXHHHHH^
^^TTTTTTTTTTTTTTTTTTT#_*__#TT,,,TTTT",TT...TTT....TTTTTTTT~~:TT,,,,,,,,,,,,,,.....,""",......T........T..,^^^^^^^.....^^^^^^:::::::::::::::::::::::::::^^^^,",^^NnnnNNNnnnnnNNNNNNNNNnnnNNPPNNNNNnnnnnnnnn:nnnn^^^^^^^NNPNNNNnnnnPPn:nn^^^^^^^^^CCCCKKKCCKKKNKKKKCNNNKKKKKKKKCCCCKKKKKCKKKKKKKKKKKKKKCKKKKKKNNNKKKKKCKKK^^^^^KKCCCCKKKKKKCCCCKKKKKKKKK:KKKKKKKKKKCKKKK^^HHHHHHHHHHHHH^^^^^^^^^^^^^^^^^^HNNNHHHXHHHHHHHHHHHXXHHXXXXXXXHHHHHHHHHHXXHHHHHHHHHHHHHHNNNNHHHHHHHHHHHHHHHHH:HHHHXHHHHH^
^TTTTTTTTTTTTTTTTTTTT######T,,,,TTT,,TTTTTTTTTT,,,TTTTTTTT~~:T......,,,,,,,,,...*.,"",....TT.T.......TT...^^^^^^......^^^^^^:^^^^^^^^......^^^,,,,,,^^^^^^,T,,.^NNnnNNNNnnnNNNNNNNNNNNnnPNPPNNNNNnnnnnnnnn:nnnn^^^^^^^NPPPNNNnnnPPnn:^^^^^^^^^^^CCCCKKKKKKKNNNKKKCNNNKKKKKKKKCCKKKKKKKKKKKKKKKKKKKKKKKKKKKKKNNNKKKKKCKKK^^^^^KKCCCKKKKKKCCCCCCKKKKKKKK:KKKKKKKKKKKKKKK^^HHHHHHHHHHHH^^^^^^^^^^^^^^^^^^^^NNNHHHXXHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHNHHHHXXHHHHNNNNNHHHHHHHHHHHHHHHHH:HHHHXHHHHH^
^^TTTTTTTTTTTTTTTTTTTTTTTTT,,T,TTTTTTTTTTTTTTTT.,TTTTTTTTT~~:::::::::::::::::::::.,,",...............,,,..^^^^^^^.....^^^^^^:^^^^^^^^*.........,,,,^^^^^^^.,,,^^NNnNNNNnnnnnNNNNNNNNNnnnnNPNNNNN#########___#########^NNPNNNNnnnPPP^:^^^^^^^^^^^CCKKKKKKKKKCNNKKKNNNKKKKKKKKKKKKKKKKKKKKKK#########___#########KKKKCCCKK^^^^^KKCCKKKKKCCCCCCCCCCCKKKKK:KKKKKKKKKKKKKCK^^HHHHHHHHHHHH^^^^^^^^^^^^^^^^^^^^NNNHHXXXHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHNNHHHXXXXHHHHNNNHXXXHHHHHHHXXXXXHH:XXXXXHHHHH^
^^.TTTTTTTTTTTTTTTTTTTTT,,T,TTTTTTTTTTTTTTTTTTTT.TTTTTTTTT~~TT..................:,,,,,,............,,,,,,.^^^^^^^^^...^^^^^^:""^^^^^^...........,^^^^^^^...,,,,^NNNNNNnnnnnnnnNNNnnNNnnnnNNNNNNP#___________________#^^^^NNNNPP^^^^^:^^^^^^^^^^^CKKKCCKKKKNCNNNKKKKKKKKKKKKKKKKKKKKKKKKKKK#___________________#KKKKCCCKK^^^^^KKCCKKKKCCCCCCCCCCCCCKKKK:KKKKKKKKKKKKCCCC^HHHHNNHHHHHH^^^^^^^^^^^^^^^^^^^^HHHHHHXXHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHNNHHHXXXXHHHHNNHHHXHHHHHHHHXXHHHHH:HHHXXHHHHH^
^^.TTTTTTTTTTTTTTTTTTTT,,,,.TTTTTTTTTTTTTTTTTTTTTTTTTTTTTT~~TT..T,,.............:,,,,,,,...........,T"TT,.^^^^^^^^^..,^^^^^^:""",^^^^,.T.........^^^^^^....,,,,^NNNNPPPPPPnnnnnnnnnnNnnnnNNNNNNP#__Z________________#^^^^^^^^^^^^^^^:^^^^^^^^^^^KKKKKKKKKKNCNNNNKKKKKKKKKKKKKKKKKKKKKKKKKK#__Z________________#KKKKCCCKK^^^^^KKKCKKKKKKCCCCCKKCCCKKKKK:KKKKKKKKKKKKKKK^^HHHNNNNNHHHH^^^^^^^^^^^^^^^^^^^^HHHHHHXHHHHHHHHHHH#########___#########HHHNNHHHXXXHHHHHNHHHHHHHHHHHHXXXHHHHH:HHHXXXHNNN^
^..TTTTTTTTTTTTTTTTTTTT,,,,TTTTTTTTTTTTTTTTTTTTT.TTTTTTTT~~TTT...,,,........T...:,T,,,,,..........*,,,,,,..^^^^^^^^..,^^^^^.:""",..^...TTTT......,,,^^^....,,T.^NNNNNPPPPPnnnnnnnnnnnnnnnNNNNNNN#___________________#^^^^^^^^^^^^^^^:^^^^^^^^^^^KKKKKKKKKKNNNNNKKKKKKKKKKKKKKKKKKKKKKKKKKK#___________________#KKKKCCCKK^^^^^^KKKKKKKKKKKCCKKKKKKKKKKK:KCCKKKKKKKKKKKK^^HHHNNXNNHHHX^^^^^^^^^^^^^^^^^^^XXHHHHHXHHHHHHHHHHH#___________________#HHHXXHHHXXXHHHHHHHXHHHHHHHHXXXXHHHHHH:HHHXXXXHHH^
^^,TTTTTTTTTTTTTTTT,TT,,,,TTTTTTTTTTTTTTTTTTTTT..TTTTTTTT~~TTT..,,,,,,,....,....:....,,,.......T..T,,,TT,T....^^^^^,,,^^^,..:T"",,.....TTTT.*........,,,T,,T,T.^NNNNNNnPPPnnnnn>NNnnnnnnnnNNNNNN#___________________#^^^^^^^^^^^^^^^:^^^^^^^^^^^KKKKKKKKKNNNNNKKKNNNCKKKKKKKKKKKCKKKKKCKKK#___________________#KKKKKCKK^^^^^^^KKKKCCKKKKKCKKKKKKKKKKKK:CCCCCCKKKKKKKKK^^HHHHHXNHHHHH^^^^^^^^^^^^^^^^^^HHXHHHHHXHHHHHHHHHHH#__Z________________#HHHXXHHHXXX^HHHHHHXNHHHHHHHHHHHHHHHHH:HHHHXXXHHH^
^^,,,..TTTTTTTTT..*,,,,..,TTTT.TTTTTTTTTTTTTT,,,..TTTTTT~~TTTT..,,,,,,,....,,...:.....,,..*......,,"",,,,,T.....^^^,,,^^,,..:TT"",......,T,,........TTTTT,TT,T.^NNNNNNNnPPnnnnnnNNNnnnPPPnnNNNNN__________F__________^^^^^^^^^^^^^^^:^^^^^^^^^^^KKKKKKKKKNNNKKKKKNNNKKKKKKKKKKKCCKKKKKKKKK#___________________#KKKKKKKK^^^^^^^^KKKKCKKKKKKKKKKKKKKKKKK:NCCC^^KNNKKKKKKK^HHHHHHHHHHHH^^^^^^^^^^^^^HHHHHHHHHHHHHHHHXHHHNHHHH#___________________#HHHHHHHHHH^^^XHHHHXXHHHHHHHHHHHHHHHHH:HHHHHHHHXX^
^^T,....TTTTTTTT.TTT.T....TTTT..TTTTTTTT,...,,,,,,TTTTT~~TTTTT..,,,,,,..........:T.T...........,T,""^,T,^,.......,""^,,,,.T.:""",,.T.T.,T"""TT.......^T,^T,,,,^^NNPNNNnnPnnnnnnnnnnnnnnnnnNNNNNN#___________________#^^^^^^^^^^^^^^^:^^^^^^^^^^^KKKKKKKKKKKKKKKKKNNKKK::::::::::::::::::::_____________________::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::XXHHHXHHH#___________________#HHHHHHHHHH^^^XHHHHXXHHHHHHHHHHHHHHHHH:NHHHHHHXXX^
^,.*.T..........TT.TTTTTTTTTT....,"""TTTTTTTTT,,,,,TTT~~TTTTTT...............,,,:..............,""""""T^T........,",,,.....T:""T,..TT.,,"TTTTT....*..,,,.^*...^^NNNNNnnPPnnnnnnnnPnnnnnnnnNNNNNN#___________________#^^^^^^^^^^^^^^^:^^^^^^^^^^^KKKKKKKKKKKKKKKKNNNKKK:KKKCCCCCCCCKKKKKKCC#___________________#CCCCKKKK^^^^^^^^^NNNCKKKKKKKKKKKKKKKKKKKKK^^^^^^^^^^^^^^^HHHHHHHHHHHH^^^^^^^^^^^HHHXHHHHHHHHHHHHH:HHHHHHHHH#___________________#HHHHHHHHHH^^^XHHHHHHHHHHHHHHHHHHHHHHN:NHHHHHHHHX^
^,.....*............TTTTTT,T.....,*T"TTTTTTTTT,,T,,"T~~,TTTTTT.....*.........,,,:T......TT...T."""""""",,........,,^,,.....,:""",^....,""""",,.......,^,......^^NNPNNnnPPnnnnnnnnPPnnnnnnNNNNNNN#___________________#^^^^^^^^^^^^^^^:^^^^^^^^^^^KKNNNNNKKKKKKKNNNNNKKK:KKKCCCCCKKKKKKKKKKN#___________________#KCCKKKK^^^^^^^^^^^NNKKKKKKKKKKKKKKKKKKKKKK^^^^^^^^^^^^^^^HHXHHHHHHHHH^^^^^^^^^^HHHHHHHHHHHHHHHXXX::::::::::_____________________::::::::::::::::::::::::::::::::::::::NHHHHHHHHH^
^^..................TT....,,T....,,"""TTT.T,T,,,T,,,~~",TTTTTT.,...T.........,,,:,,,......T...,""""""",,,,......,,,,,,..^..,:"",^.....,""""",,....^..,,,^..^...^NNPPNnnnPnnnnnnnnPnnnnnnnNNNNNNN#___________________#Nn^^^^^^^^^^^^^:^^^^^^^^^^^KKCKKKKKKKKKKKKNKKKKKK:KKKKCCCKKKKKKKKKKKK#_____________F_____#KKCKKKK^^^^^^^^^^^^^KKKKKKKKKKKKKKKKKKKKK^^^^^^^^^^^^^^^^HHXXHHHHHHHXX^^^^^^^^^HHHHHHHHHHHHHHHXXXHHHHHHHHHH#___________________#HHHHHXXXXX^^^^XXHHHHHNNHHHHHNNHHHHHHNNNHHHHHHHHH^
^T,..............,,*.........T....*"""""T,.,,,,....~~""*,TTTT.,,........,...T.,,:"""",T,.....,,""",,^,,,,,,....,:::::::::::::,,T......,,"">,,,,,....,,,,,,,,,,,^NNNNnnnNNNNnNNNNNnnNNnnPnNNNnnPn##########_##########NNNnnNNNnnNNNN^:^^^^^^^^N^^NCCCCC^^^^KKKKKKKKKKCC:CCKKKKKKKKKKKKKKKKK#___________________#KKKKKKK^^^^^^^^^^^^^^^^KKKKKKKKKKKKKKKKKK^^^^^^^^^^^^^^^^HHHHHHHHHHHHH^^^^^^^^^HHHHHHHHHHHHHHHXXXHHHHHHHHHH#___________________#HHHHHXXXXX^^^^XXHHHHNNNNXHHHNNNNNHHNNNNNNHHHHHHH^
^^,,...T.,,......,,,.....T....*....,""""TTTT,,,....~~""",T,,,,,,,......T,.....,,:""""""",...,,"""",..,,,"",,.,,,:*,,,........,,,.....,,"",,,",,^,,,.,,,,,,"T"""^NNNNnnnNNNNPNNNNNNNNNNnnnnNnnPPPPnN^^^^^^^:^^^^^^^^^NNNNnNNNNnnnnNNn:N^^^NNNNN^^KCCCCK^^^^^KKKKKKKKKCC:CKKKKKKKKKKKKKKKKKK#___________________#KKKKKKK^^^^^^^^^^^^^^^^^KKKKKKKKCKKKKKKKK^^^^^^^^^^^^^^^^HHHHHHHHHHHHH^^^^^^^^^HHHHHHHHHHHHHHHX^HHHHHHHHHHH#_____________F_____#HHHHXXXXXX^^^^XXXHHHNNXXXXHNNNNNNHHNNNNNNHHHHXXH^
^",,....T,,,,....,,,..................,,,,TT,,....~~.,,,,,",,,,,,.#############___#############"T,,,,,,,,,,,,,,,:,,,,.............,,,,*""",,,,,,",,,,,,,,,""""^^NNPNnnnNNNPPNNNNNNNNNNnnnNNnnnnnnnn^^^^^^^:^^^^^^^^^NNNNnNNNNNNNNNNN:NNNNNNNNN^^CCCCKK^^^^KKKKKKKKKCCC:CKKKKKKKKKKKCKKKKKK#########___#########KKKKKKK^^^^^^^^^^^^^^^^III~~~IIICKKKKKKKK^^^^^^^^^^^^^^^^HHHHHHHXXHHHH^^^^^^^^^HHHHXXXHHHHHHXXX^HHHHHHHHHHH#___________________#HHHXXXXXXX^^^^XXIII~~~~~IIIHNNNNHHHHHHHHHHHHXXXX^
^^,,,.......,,..,,,,....................,,TT,,....~~,...,""""",,,.#___________________________#,.,,*,,,,*,,,,,,,:T.,,..........^..,,,""""T"",,,"""",,,,,,,*"""^^NPNNnnnPPPPPPNNNNPNNNNNNNNNNnnnnnnnn^^^^^^:^^^^^^^^^PPPnnNNNNNPPNNNN:NNPPPPPNN^^CCCCKKKK^KKKKKKKCCCCCC:CKKKKKKKKKKCCKKKKKKKKCKKKKKKK:KKKKKKKNNKKKKKKKK^^^^^^^^^^^^^^KII~~~~~~~IIKKKKKKKC^^^^^^^^^^^^^^^^HHHHHHHHHHHH^^^^^^^^^^HHHHHHHXHHHHHXXH^HHHHHHHHHHH#___________________#HHHXXXXXXX^^^HXII~~~~~~~~~IIHHHHHHHHHHHHHHHHHXHH^
^^,,,....T..,,,,,,,,......T..............,,,,,....~~,...,""""",,..#__#######_________#######__#...,"",T,,,,,,,^,:...,.............,,,"""""T",,,"T"""",,,,,,"""^^PPNPnnnPPPPPPN^^^^^NnnNNNNNNNnNNNnnP^^^^^^:::===============:::::::::::::::::::::::::::::::::::::::::::CKKKKKKKKKKKKKKKKKKKCCCKKKKKK:KKKKKKNNNKKKKKKKKK^^^^^^^^^^^CCCI~~~~~~~~~IKKKKKKKC^^^^^^^^^^^^^^^^HHHHHHHHHHHH^^^^^^^^^HHHHHHHHXXXXXHHHH^HHHHHHHHHHH#########___#########HHHXXXXXXXHHHHXI~~~~~~~~~~~IHHHHHHHHHHHHHHHHHHHH^
^^,,*.T.....,,,,,,,......................,,,,,...~~,,...,""""",,,.#__#_____#_*_____*_#_____#__#...,"",..,,,,,,,,:,,,.....T.......,,,,,T"^"",,*,,*,"T,,^,..,,"""^PNPNnnnNNPNnN^^^^^^^nnNNNNPNnnnnnnnn^^^^^^:IIIIIIIIIIIIIIIIIIIPPNNNNPPPPPNPPNN^^CCCCKKKKKKKKKCCCKKKKKKKCKKKKKKKKCCKKKKKKKCCCCCKKKKKK:CKKKKKKNNCKKKKKKKKK^^^^^^^^KKKCCII~~~~~~~IIKKKKKKKK^^^^^^^^^^^^^^^^HHHHHHHHHHHH^^^^^^^^^HHHHHHHHXXXXXHHHHHHHHHHXHHHHHHHHHHHHHHH:HHHHHHHHHHHHHXXXHHXXHHHHXII~~~~~~~~~IIHHHHHHHHHHHHHHHHHHHH^
^^,,.*......,,,",,.........*..,,.........""",.....~~,...,",,,,,,,,#__#_____#_______Q_#_____#__#...""",..........:,,,.........T...,,,,,,,,,,,T,...,,,,,,...,,,,,^nnNnnnnNNNnn^^^^^^^^^nNNNnPnnnnnnnnnn^^^^^=IIIIIIIIIIIIIIIIIIIInnnnnPPPPNnnnPP^^CCCCKKKKKKKCCCCCKKKKKKKCKKKKKKKKCCKKKKKKCCCCCCKKKKCC:CCKKKKKKCCKKKKKKKKKKK^^KCKKKKKCCCIII~~~IIIKKKNNKKK^^^^^^^^^^^^^^^^^HHHHHHHHHHHH^^^^^^^^^HHHHHHHHHHXXXHHHHHHHHHHHHHHHHHHHHHHHHHH:HHHHHHHHHHHHHXXHHHNNNNHHHHIII~~~~~IIIHHHHHHHHHHHHHHHHHHHHH^
^",,........*,"",,.....T*....,"T,,.......""T,.....~~,...*,,.....,,___###_###_________###_###___,.*"*T.......,..^:.,,.............,,,.,,,,,,,,,....,,.^....,T,^^^nnnnnnnnNnnn^^^^^^^^^nNNNnnnnNnnnnnnn^^^^I=IIIIIIIIIIIIIIIIIIIIInnnnnnnnnnnnNN^^CCCCKKKKKKKCCCKKKKKKKKKKKKKKKKKKCCKKKKKKKKCCCCKKKKKN:CKKKKKKKCCNKKKKKKKKKKKKKCKKKKKCKKKCCCCCCNKKKKNNNKK^^^^^^^^^^^^^^^^^HHHHHHHHHHH^^^^^^^^^^HHHHHHHHHHHHNHHHHHHHHHHHHHHHHHHHHHHHHHH:HHHHHHHHHHHHHXXHHNNNNNXHHHHHHHXXXXNNNHHHHHHHHHHHHHHHHHHHHH^
^^,.......T,,,,,,,.,,,......,,",,,......,""",..*..~~,,..::::::::::______________O______________::::::::::::::::::::::::::::::::...*...,,,,,,,,,....^......,,""^^nnnnnnnnnnnn^^^^^^^^^PnNNnnnnPnnnnnnn^^^^I=IIIIIIIIIIIIIIIIIIIIInnnnPnnnnnnnnP^^^CCKKKKKKKKCKKKKKCKKKKKKKKKKKKKKCCCCCKKKKKKKKKKKKKKN:KKKCCCCKKKNKKKKCKKKKKKKKCKKKKKKKKKKCCCKKKKKKKNNNK^^^^^^^^^^^^^^^^^^HHHHHHHHH^^^^^^^^^^^^HHHHHHHHHHHHHHHHHHHHHHHHHHHHXXXHHHHHHXX:HHHHHNNXXXXXXXXHHNNNNXXXHHHHHHXXXXXXHHHHHHHHHHHHHHHHHHHHHH^
^T,.....T..,"",.,,,,,,,,..,,,,,,,,......,"""",,,,,,~~,,,:........T___________Z_________________,,,"",...,,,,,,#####__#####....:.......,,"""""",^.........,"""""^nnnnnnnnnnnnn^^^^^^^PPnnnnnnnnnnnnnnnnnn^I=IIIIIIIIIIIIIIIIIIIIIPnPPPnnnnnnnnn^^^^KKKKKKKKKCKKKKKCKKKKKKKK^^^^^^^^^CCCCKKKKKKKKKKKKN:KKKCCCCCKNNKKKKCKKKKKKKCCCKKKKKKKKKKKKKKKKNNNNN^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^HHHHHHHHHHHHHHHHHHHHHHHHHHHHHXHHHHHHHHH:HHHHNNXXXXXXXXHHHHHHHXXXHHHHHH^^^^^XHHHHHNHHHHHHHHHHHHHHHH^
^^T........""",..,"""",,.,,,,,,T,.......T""""",T,,,,~~,,:*..T.....#__###_###_________###_###__#,,,""^...,,,,,,#_______Z__#..^.:.*....,,,"""""^,.....*...,,"""""^nnnnnPnnnnnnnn^^^^^PPPPPnnnnnPnnnnnnnnnNNN=IIIIIIIIIIIIIIIIIIIIPPPPPPnnNnnPnnn^^^^KKKKKKKKKKKKKKKKKKKKKK^^^^^^^^^^^^^KKKKKKKKKKKKKKN:KKKCCCCCNNNKKKKKKKKKKKKKCKKKKKKKKKKKKKKKK^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^HHHHHHHHHHHHHHXXXHHHHH^^^^^^^^^^HHHHHHHH:HHHHNXXXXNNNHHHHHHHHHXXXHHHHH^^^^^^^^HHHNNNHHHHHHHHHHHHXHH^
^^,........T"",..,,,,,,...,,,,..........,"""""",,,,,~~,,:.........#__#_____#_*_____*_#_____#__#,,,"",,..,,,,,^#_____F____#....:.......,,,"""^^,,........,,"""""^nnnnnPnnnnnnnnnnPPPPPPPPnnnNnnnnnnnnnnNNnn:IIIIIIIIIIIIIIIIIIIPnPnnnnnnnnnnnnn^^^^KKKKKKKKKKKKKKKKKKKKK^^^^^^^^^^^^^^^KKKKKKCCCCCKNN:KKKKKCCCKKKKKKKKKKKKKKKKKKKCKKKKKKKKKKKK^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^HHHHHHHHHHHHHXXXXHHHH^^^^^^^^^^^^HHHHHHH:HHHHXXXXXNNNHHHHHHHHHHXXHHNH^^^^^^^^^HHHHHHHHHHHHHHHXXXXHH^
^,.........,,,....,................,,,,,,,,,""",,,,,~~"T:..*.....,#__#_____#________F#_____#__#,,,,,,,,*,,,,,,#__________#....:..*..T.....,,"""",,,......,""""T^nnnnnnnNnnnnnNPPPPPPPPPnPPNNNNNNNNNNNNNNnn:nnIIIIIIIIIIIIIIInnnnnnnnnnnnnPnPnn^^^^KKKKKKKKKKKKCKKIII~~~~~III^^^^^^^^^^^KKKKKCCCCCCCC:CCNNKCCCKKKCCKKKKKKKKKKKKKCCCKKKKKKKKKKK^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^HHII~~~~~IIHHHXXXHHHH^^^^^^^^^^^^HHHHHHH:HHHHXXXXNNNHHHHHXHHHHHHHHHNN^^^^^^^^^^HHHHHHHHHHHHHHHXXXHH^
^T..........T,....*...............*""",,,,,,""",,,,,~~",........,"#__#######_________#######__#....*,,*,,.,,,,############...T:.............,""""",......,,,,,,^nnnnnNNNNNnPPPPPPPPPNPPnPPPNNNNNNPPPPPPNnn:nPnnnnnnnnPPNNNnnnnnnnnnnnnnnnPPnnn^^^^KKKKKKKKKKKKKKII~~~~~~~~~II^^^^^^^^^^KKKKKKNKKKKNN:CNNNKKKKKKKCCCKKKKKKKKKKKKCCCKKKKKKKKKKK^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^HI~~~~~~~~~IHHHXXXHHH^^^^^^^^^^^^HHHHHHH:HHHHNNNNNHHHHHHXXHHHHHHHHHNN^^^^^^^^^^HHHHHHHHHHHHHHHHXXHH^
^^,.........,,....T.......~~~~~~~~~~~~",,,,,,,,,.,,~~,",.T......,"#############___#############.....,,,,,~~~~~~~~~~~.,*....%%%:....~~~~....%%%%%%%%......%%%%%%^nnnnnNNNNNnnPPPNNPNNnnPnnPnnNNNNPPPNPNPNnn:NNnnnnnnnnNNNPNnnnnnnnnnnnnnPPPPnnn^^^^KKKKKKCKKKKKKKI~~~~~~~~~~~I^^^^^^^^^^KKKKKKKKKKKKN::::::::KKKKCCCKKKKKKKKKKKKKCCKKKKKKKKKKK^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^XI~~~~~~~~~IHHHXXX^^^^^^^^^^^^^^^HHHHHHH:HHHHNNNNHHHHHHXXXHHHHHHHHXNN^^^^^^^^^^HHHHHHHHHHHHHHHHHXHH^
^^,,.......,,,...,,,..~~~~~~~~~~~~~~~~~~~~,,,*.,,,,~~,,,...*...,,"""""",,,,,,""":.........,......*...,,,.~~~~~~~~~........,%%%:.T,,,"~~.....%%%%%%%.....%%%%%%%^nnnnNNNNNNNPPNNNNNnnnnnnnn^^^^NNPNNnnNPNNN:NNNnnnnnnnNNNNPNnnnPPPnnnnnnnnnnnnn^^^KKKKKKCCCCCKKKKII~~~~~~~~~II^^^^^^^^^^^^^KKKKKKKKKKKKKKKKK:KKKKCCCCCKKKKKKKKKKKCKKKKKCKKKKKK^^^^^^^^^^CCCCCCCPP^^^^^^^^^^^^^^^^^^^^^^^^^^^^HI~~~~~~~~~IHHHHH^^^^^^^^^^^^^^^^HHHHHHH:HXXHNNNHHHHHHHXXXHHHHHHHHHNH^^^^^^^^^HHHHHHHHHHHHHHHHHHHHH^
^",,.....,,,,,T..,,~~~~~~~~~~~~~~~~~~~~~~~~~~...,,,~~,,........,""""*",,,,,,,""":.....................,..~~~~~...........%%%,.:..%%%",.......%%%%%%%%%%%%%%%%%^^nnnNNNNNNNNPNNNNNnnnnnnnn^^^^^^NPNNnnnPPNN:NNNPPnnnnnNNNPPPPPnPPPnPnnnnnnnnnPP^^^KKKKKKCCCCCKKKKKIII~~~~~III^^^^^^^^^^^^^^^KKKKKKKKKKKKKKKK:KKKKCCCNNNKKKKCKKKKKCKKKKKKNKKKK^^^^^^^^^^CCCCCCCCPPPPCCCC^^^^^^^^^^^^^^^^^^^^^^HHII~~~~~IIHHHHH^^^^^^^^^^^^^^^^^HHHHNHX:XXXXXNNHHHHHXXXXXHHHHHHHHHHH^^^^^^^^^HHHNNNXXHHHHHHHHHHHHH^
^^,,......*,,,,,,,~~~~~~~~~~~~~~~~~~~~~~~~~~~~~...~~*,,........,,"""",,,,,,,,""":.......,,,...........,..TTT~....%%%%...%%%,..:%%%%%",.~~~~.T,,,%%%%%%%%%%%%%%^^nnPnNNNNNNNNNNNNNNnnnnnnn^^^^^^NPNnnnNNNNN:NNnnPnnnnnNNNPPPPnnnnnPnnnnnnnnnnnn^^^KKKKKKCCCCCKKKKKKKKKKKKKNNN^^^^^^^^^^^^^^^^^KKCKKKKKKKKKKK:KKKKKCNNNNNKKCCCKKKKKKCCKKKKKKK^^^^^^^^^^CCCCCCCCCPPPCCCCC^^^XXXXXXXX^^^^^^^^^^^HHHHHHHHHHHHXHHH^^^^^^^^^^^^^^^^^HHHHHHX:XXXXXNNHHHHHXXXXHHHHHHHHHHHH^^^^^^^^^HHHHHHXXXXXHHHHHHHHHX^
^,........,,"",,,~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.~~.....,,.....,,,,,,,,,,,...,,,:....T.,,,,,,*.......,,..TT~...%%%%%%..T.%..~T:%%%%%%,....T..,"T%%%%%%%%%%%%%%%^PnnnnNNNNNNNNNNNNPNnnnnn^^^^^^^^PNnnNNNNNN:nPnnnnnnnnNNPPPNnnNNnNNnnnnnnnnnnnn^^KKCCKKKCCCCKKKKKKKKCCKKKKKNNNNNK^^^^^^^^^^^^^KCCCKKKKKKKKKC:CKKKKCNNNNNCCCCCKKKKKKCCKKKKKK^^^^^^^^^^CCCCCCCCCCCCCCCCCC^^XXXXXXXXXXX^^^^^^^^^HHHHHHHHHHHHXHHH^^^^^^^^^^^^^^^^HHHHHHHX:XXXXXNNNN^^^HHHHHHHHHHHHHHH^^^^^^^^^^HHHHHXXXXXHHHHHHHHHHX^
^^......*.,"""",,~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.~~.....,,,,,,.,..........T.....:.....,,,""",,,,,,,,.....~~~..%%%%%%..*....~~~:%%%%%%%%%%..~.,""%%%%%%%%%%%%%%^^nnnnPPNNNNNNNNNPPPNNnnnn^^^^^^^PNNnn:::::::nnPnnnPnPPNNNNNNnnNNNNNNnnnnnnnnnnn^^KKKKKKKCCCCKKKKKKKKKCKKKKKNNNNNNKKC^^^^^^^^^^^CCKKKKKKKKKKK:KKKKKCKNNNNNNCCKKKKKKKCCKKKKK^^^^^^^^^^^CCCCCCCCCCCCCCCCCC^^XXXXXXXXXXXX^^^^^^^HXXXXHHHHHHHXXXH^^^^^^^^^^^^^^^^^HHHHHHXX:XXXNNNN^^^^^^^HHHHHHHHHHHHH^^^^^^^^^HHHHHXXXXHHHHHHHHHHHHX^
^^........,"""",~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.*.....,,,,,,..................:.,,T,,,,,,,,,,,,,,,.....~~~..%%%%%%....*..~~~:%%%T%%%%%%*.~~,""%%%%%%%%%%%%%%%^^^^P^PN^^^^^^^^^^^^^n^n^P^^^^^^P^^nn:^^NN^^^^^^nn^PnNN^^P^^^^NNNNNN^^nn^^n^n^n^^KKKKKKCCCCCKKKKKKKKKKKKKKNNNNNNNKKC^^^^^^^^^^^^KKKKKKCCKKKK:KKKKKCNNNNNNNNKKKKKKKKK^^^^^^^^^^^^^^^^^CCCCCCCCCCCCCCCCCC^^XXXXXXXXXXXXX^^^^^^HXXXXHHHHHHHXXXH^^^^^^^^^^^^^^^^^HHNHHHXX:XXXNNNN^^^^^^^^HHHHHHHHHHHH^^^^^^^^^HHXXXXXXHHHHHHHHHHHHHX^
^"........,"""",~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~.......,,,,,,..................:,"""",,,..,,,,,,,,,......~~..%%%%%%..T..T.~~~:%%%%%%%%%%%....,,%%%%%%%%%%%%%%^^^P^P^P^^^P^P^P^PP^^^N^n^^^^^^^^^^^^^:^^NN^P^P^^^^^^^N^^^P^^^P^NNN^^^^nn^^n^nnn^^KKKKKKCCCCCKCCCCKKKKKKKKKNNNNCNNNNKC^^^^^^^^^^^^KKKKCCCCCKK:KKKKKKNNKKKNNNKKKKKK^^^^^^^^^^^^^^^^^^^^CCCCCCCCCCPPCCCCCC^^XXXXXXXXXXXXXX^^^^^HHHHHHHHHHHHXXHH^^^^^^^^^^^^^^^^^NNHNNNHX:HHHHHH^^^^^^^^^^HHHHHHHHHH^^^^^^^^^^HXXXXXHHHHHHHHHHHHHHHX^
^^,...T..,,"""",~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~T.......,,,",..................:""""",,....,,,,,,,,..........T%%%%%%.~.....~~:..%%%%%%%%%%....%%%%%%%%%%%%%%%%^^^^^PP^^^^^^^^^^^^P^N^NN^^^^^^^^^^PN:^P^Nn^P^^^^^^^P^^P^^PP^^^N^P^P^^n^^^^^n^^^^KKKKKKKKCCCCCCCCKKKKKKKKKNNNNNNNNNKC^^^^^^^^^^^^^KKKKCCCCKK:KKKKKKKKKKKKKKKKKK^^^^^^^^^^^^^^^^^^^^^^CCCCCCCCCCPPPCCCCCC^XXXXXXXXXXXXXX^^^^^HHHHHHHHHXXXHHHH^^^^^^^^^^^^^^^^NNNHNNNNH:HHHHX^^^^^^^^^^^HHHHHHHHHH^^^^^^^^^^XXXXXHHHHHHHHXHHHHHXXX^
^^....T..,,"""*,.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~........,,,,,..................:,"""",,.....,,..,,,...T%%...T.%%%%%%.~~......:..%%%#####%%%%%%%%%%%%%%%%%%%%%^^^R^^^^^^R^RRR^^^^^^^^^R^^^^^^^^^^^^^:^R^^^^^^^R^RR^^L^^^L^^^^R^R^^^^^^^^^LL^^L^^K^^^^^^K^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^C^^^^^:^^C^^K^^^^^^^^^^K^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^C^^^^^^^^^^^^XX^^X^^X^^^^^^^^^^HH^^H^^^H^^^H^^^^^^^^^^^^^^^^^^^^^^^^^^^^:HH^H^^^^^^^^^^^^^XH^^^H^HH^^^^^^^^^^^^^^^^^^^^H^^^^^^^^^^^^
^^.......,,"""",.~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~**......,,...............T......:,""""",,.........,,....%%%%T..%%%%%..~~......::::::#_>_#%%%%%%%%%%%%%%%%%%%%%^^R^^^R^^R^^^^^^L^^L^^^^^RRRR^R^^^^^^^:^^^^^^^^^^^^^LLL^L^L^L^^RRR^^^^^^^^^^L^L^^^^^^^^^^^^WWWW^^^^^^^^^^^^^^^W^^^W^W^^W^^^^^^^^^^^^^^^^^^^W^:^J^^^W^^^^^^W^W^^^^^W^^^^^W^^^W^^^W^^^^^^^^^^^^^^^^^^^^^^^^^U^^^U^^^U^^^M^^^^%^^^^^M^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^:^^^^^^^^^^M^^^^^^^^^M^M^^^^^^M^^^^^^^^^^^MM^^U^%^^^^^^^^M^^
^........,,,,,"",..~~~~~~~~~~~~~~~~~~~~~~~~~~~~...,T,,,,,T..........T...........:.,"""",,..........,...T%%%%%%%%%%%%...T..,~~~..,%%%%.:::::::::::::::::,%%%%%%^^^^^^^^RR^^RRRR^^^^LLAA^^^^^^^A^^AA^^:^^^^^^^^^^^^L^^L^L^^^^A^^A^^^^^^^^^^^^^^^^^^^^^^^J^^^^^^^^J^^^J^^^%^^^^^^^^^^W^^^^^^^^^J^^^^^^^^^^^^^^:JJ^^^^^^^^^J^^^^^JJ^^^^^^^W^^W^^^^^^^^^^^^^^^^^^^^^W^^^^^^^^UUUUUUUUMMMM%%%%%%%MMMMMMMMMMMUUMMMMMUMMMMMMMUUUUMUUUUMMMMUM:MMMMMMMMMMMMMMMUUUUUMMMM%MMMMMMMMMMUUUUMMMM%%U%%%%%MMMMMMM^
^^T.......,,,,",,*..~~~~~~~~~~~~~~~~~~~~~~~~~......,,,,,,..............,,.......:.,,"",,,...............%%%%%%%%%%%...,..,,~~~T..%%%%...%%%%%%%%,,,~~~:,%%%%%%%^RRRRRRRRRRRRRRLLLLLLAAAAAAAAAAAAAAA^:^RR^^AAAAAAARLLLLLAAAAAAAAAARRA^^RR^^LLLL^^JJJWJJJWWWWWWJJJJJJJ^JJJJJJJJJJWWWWWWJJJJJJJJJWWWJJJJJJJJJJ:WJJJWWWJJJJJJJJJJJJWJJ~~~WWWWWWWWWWWW^^^^^^^^^^^^^^WJJJJJJJ^UUUUUUUUMMMM%%%%U%%MMMMMMMMMMMMUMMMMMMMMMMMMMUUUUMUUUUMMMMUM:MMMMMMUMMMMMMMUUUUUUMU%%%%MMMMMMMMMUUUUMMMU%%%%%%%%MMMMMMM^
^..........,,,,,,...,,~~~~~~~~~~~~~~~~~~~~~.......T,,,",........,.....,,,,......:,,,T,,,,,,..........,,,%%%%%%%%%%%..,,,.,T,~....%%%%%%%%%%%%%%%%*,~~,:,%%%%%%%^RRRRRRRRRLLRRRLLLLLLAAAAAAAAAAAAAAAA:^RR^AAARLLAAALLLLRAAAAAAAAAAAAAAA^^^ALLLL^^JJ*JJWWWWWWWWWWWJJJJ^JJWJJWJJWJJJWWWWWJJJJJJJJWJJJJJJJJJJ*J:JWWWWWWJJJJJJJJJWJJJJ*W~~~WWWWWWWWWWW^^^^^^^^^^^^^JJJJJJJWJ^UUUUUUUMMMMM%%%%%%%UMMMMMMMMMMMMMUUMMMMMMMMMMMUUMMUUUUMMMMUM:MMMMMMMMMMMMMMUUUUUUMM%%%MMMMMMMMMMUUUUMMMU%%%%%%%UMMMMMMM^
^^.*.......,,,*,,..,,,,,.~~~~~~~~~~~~~~~~.....*....,,"",.....*..,,,,..,,,,,.....:,,.T.,,,,,,.......*.,,,%%%%%%%%%%.T.,,,.,T,,.%%%%%%%%%%%%%%%%%%,,,.~,:%%%%%%%^^^^^^^^^RRLLLRRLLLLLLAAAAAAAAAAAAAAAA:RRR^AARLLLLLLLLLLLAAAAAAAAAAAAAAAAAAALLLL^^WJJ*WWWWWWWWWWWWWJJJJJWWWJJJWWWJJJWWJJJJJJJJJJJJ*JJJJWWWWWJ:WWWWWWWWJ*JJJJJJJJJJJWW~~~WWWWWWWWWWWWWWWWWJJJJJJJWJJJJJWWJ^UUUUMMUMMM%%%%U%%%MMMMMMMMMMMMMUMMMMMMMMMMMMMUMMMMMUUUMMUMMM:UMMMMUMMMMMMMMUUUUUMM%%%MMMMMMMMMMUUUUUUMU%%MMMMMMMMMMMMMM^
^^.........,,,,,,,,,,,,,,,..*........,,,,...........,,,,......T.,,,,,,,,,,,.....:,,...,,,,,...........,,%%%%%%%%%%...,%%%%%,,%%%%%%%%%%%%%%%%%%%,,..~,:%%%....^^^^^^^^^^R^LLLLLLLLLLAAAAAAAAAAAAAARR:RRRAAARLLLLLLAAALLAAAAAAAAAAAAAAAAAALLLLL^^JJJJWWWWWWWWWWWWWWWWWWWWWJJJWWJJJJJWJJJJJJJJJJJJJJWJJWWWWWW:WWWWWWWJJJJJJJJWJJJWWWWW~~~WWWWWWWWWWWWWWWWJJJJJJJJJJWJJJJ^^UUUUMMMMMM%%%%%%MMMMMUMMMMMMMMMMMUMMM%MMMMUMMMMMMMMMUUMMMMMU:UUUUUUUMM%MMMMUUUUMUM%%MMMMMMMMMMMMUUUUUMM%MMMMMMMMMMMMMMM^
^^........,,"",,,,,*,,,,,,,.T..............T.........,,,,......,,..,,,,,T*......:..T,,,,,...,T......*...%%%%%%%%%%...T%%%%%%.%%%%%%%%%%%%%%,"",,,,..~,:::::::::::::::::::::===::=====::::::::::::ARR:RR^AAAALLLLLLAAALLLAAAAAAAAAAAAAAAALLLLLL^^JJJWWWWWWWWWWWWWWWWWWWWWWWWWWWJJJJJJJJJJJJJWJJJJJJJJJJJWWWW:WWWWWWWJJJJJJJJJJJJWWWWW~~~WWWWWWWWWWWWWWJJJJJJJJJJJJJWJJJJ^UUUUMMMMMM%%MMMMMUMMMMMMMMMMMMMMMMMMMUMMMMMMMMMMMMMMUUUUUUUU:UUUUUUMMMUMMMMMMMMMMM%%%M%%MMMUUMMMUUUUUMMMMMMMMMMMMMMMMUM^
^^...T..T,,""",,,,,,,....>...............T,........*....,*,...,*,...,,,.*.......:...,T,,,..,,"",,,......%%%%%%%%%%%%%.*%%%%%.%%%%...,...**..,,,,,,.TT,"~~~~~~~~^^^^^^^^^^^^AAAAALLLLLAAAAAAAAAAA:AAAAA^^AAAALLLLLLRAAALAAAAAAAAAAAAAAAAAAAAAAA^^JJWWWWWWWWWWWWWWWWWWWWWWWWWWWWJJJJJJJJWJJJ*JJJWJJJJJJJJJWWW:WWWWWWWJJJJJJWJJJJWWWWWW~~~WWWWWWWWWWWWWJJJJJJJJJJWWJJJJJW^^UUUUMMMUMMMMMMMUMUMMMMMMMMM%%%%MMMMMMMMMMMMMMMMMUUUUUUUUUUUU:UUUUUMMMMUMMMMMMMMMM%%%%%U%%MUUUUMMMMMUUUMMMMMMMMMMMMMMMMM^
^",.....T*,,,""",,,,,.................T...,...T..........,,,,,,,*....,T.........:......,,,.,"""""",.....%%%%%%%%%%%%%.,"%%%%,%%%%.*..~~~~~...,...~..,*~~~~~~~~~^^^^^^^^^^^^AAARALLLLLAAAAA#####___#####^AAAAALLRRRRRAAAAAAAAAAAAARAAAAAAAAAAAA^^JWJWWWWWWWWWWWWWWWWWWWWWWWWWWWJJWJJJJJJWJJJJWWJJJJWJJJJJJWW:WWWWWWWJJJJJJWJJJJJWWWW~~~WWWWWWWWWWWWWWJJJJJJJJJJJJWJJ*JJJ^^^^^^^^^MMMMMMMMM%%~~~%%MMM%%%%%MMMMMMMMMMMMMMMUUUUUUUUUUUUU:UUUUMMMMMMMMMM%%%%%%%%%%%%%%MUUUUMMUMMUUUUUUMMMMMMMMMMUUUU^
^^,..,",T,,T,,"",,,,,,..................,................,,,,,,.................:.........,,"""""",,....%%%%%%%%%%%%%.,"%%%%%%%%%...T.~T............,,~~~~~~~~^^^^^^^^^^^^^AAAAALLLLLLLAAA#___________#^AAAAALLARRRLLAAAAAAAAAAAAAAAAAAAAAAAAA^^JJJJWWWWWWWWWWWWWWWWWWWWWWWWWWWWJJWWJJJJJJJWWWWWW*JJJJJJJJW:WWWWWWWWWJJJJ*JJJJJJJWW~~~WWWWWWWWWWWJJJJJJJWJJJJWJJJJJWWWW^^^^^^^^^^MUMMMMM%~~~~~~~%MM%%%%MMMMMMMMMMMMMMMMMUUUUUUUUUUUU:UUMMMMMMMMMMMMMMMMMM%%%%%%%%MUUUUMMMMMUUUUMMMMMMMMMMMUUUUU^
^^,.,"T*,,,,.,,"",,,,,...............T.,,................,,,,,,......*........,,:,........,,T"""""",.T..%%%%%,,%%%%..T,T"%%%%%%%%%%....T....TT....%%%,"~~TTTTT^^^^^^^^^^^^AAAAAALLLLLLLLLA#_Z_________#^AAAAALAAARRRAAAAAAAAAAAAAAAAAAAAAAAAAA^^JJJJWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWWJJWJJJWWWWWWWJJWJJJJJJW:WWWWWWWWWWJJJJJJ%WJJJW~~~WWWWWJJJWWWWJJJJJJJWJJJJJWJJJJWWW^^^^^^^^^^^MMMMMMM%~~~~~~~%MM%%%MMMUMMMMMMMMMMMMMMMMUUUUUUUUUU:UMMMMMMMMMMMMMMMMMMMMMMMM%%MMUUUUMUUUUUUUUMMMMUMMMUUUUUUUU^
^^,,,"""T,,,,T,",,.,,,.................,,.................,,,,..................:,......,,,*""""""",.....%%%,,.%%%.TTTT,",%%%%%%%%%%....%.......%%%%%%T~TTTTTTT^^^^^^^^^^^AAAAAALLLLAAAALL#___________#^AAAARLAAARRRALLLAAAAAAAAAAAARAAAARRAAA^^JJJJJWWWW^^^WWWWWWWWWWWWWWWWWWWWWWWWJJJJJJWWWWWWWJJJJJJJJWW:WWWWJJJWWJWJJJJJ%JJJWW~~~^^^^JJJJJWWWJJJJJJJJJWJJJJJJ**WWWW^^^^^^^^^^MMM%%%M%~~~~~~~%MMMUMUMMMMMMMMMMMUUMMMMMMUUUUUUUUUU:UMMMMMUUMMMMMMMMMMMMMMMMMMMMUUUUUMUUUUUUUUMMM%%MMMUUUUUUUU^
^^^^,^,^^,^^^T^^^^^^,^^^..^..^..^^..^^^^,^.^..^^...^.^....^^s^ss^s^.^^^..s.^^s.^:^ss^^.^^^s",^s^ss,,.^^s%^^%^^.^^^.^^^ss^^s^ss%s^s%s^s^^^T.s^^^s^^^s^^^^s^TsT^s^^^^^^^^^^AAAAAALLLLLAAAALL________F___#^^AARRLAAARRAALLLLLAAAAAAAAAARAAAAAAAAA^^JJJJJWJW^^^^^^WWWWWWWWWWWWJJJJWWWWWJJJJ*JJJWWWWWJJJJW%%%JJJ:WJWJJJJWWJJWJW%%%JWJW~~~^^^^^^JJJJJWJJJJJ%JJJJJJJJJJJWWWWW^^^^^^^^^^MMMMM%%MM%%~~~%%MUMMUMMMMMMM%%MMMMUUUMMMUUUUUUUUUUUU:UMMMMUUUUMMMMMMMMMMMMMMMMMMMMUUUUUUUUUUUUUMMU%%MMMUUUUUUUU^
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ss^^^^^^s^^sss^^^^^:s^^^^^^^^^s^^^sss^sss^^^^^s^^^s^^s^^s^s^^^^^ss^s^^^^^s^^^^s^^^^^^s^^^ss^^s^^s^s^^^^^^^^RAAAAAAALLLLAAARAA#___________#^^AARRRAAAARAAALLAAAAAAAAAAAAAAAAAAAAAA^^JJJJJJJWW^^^JJWJWWWWWWWWWJJJJJWWWWWJJJJWJJJWWWWJJJJ%%%%%JJJ:WJJJJJJWWWJJJ%%%%*JW~~~J^^^^^^JJ*JJJJJJJW%%JJJJJWWWWWWWWWWW^^^^^^^^UMMUMM%MMUMUUUUUUMMMMMMMMMMM%%%%MMMUUUUUUUUUUMUUUUUUU:MMMMMUUUUUUUUMMMMUMMMMUUMMMMUUUUUUUUUUUUMMMM%%%UMUUUUUUUUU^
^,.,""",...,sssss,",,,".,.sssss,.,,""."".""","".,,.."ssss"ssssSsssssSSSSYSSSSSSS:SSSssssssssssssssssssssssss^^^^^^ssssYssssSSSSSS^^^^^^SSSSSSSSSSSSsssssssSSSssS^^^^^^^RRRAAAAAAALLAAAARAA#___________#^^AARRRAAAAAAAAAAAAAALLAAARRAAAAAAAAAAA^^JJJWJJJWWJJJJJJJWWWWWWWWJJJJJJJWWWWJWJJJJJJWWWWJJJJJ%%%%JJJ:WJJJJJJJWJJJW%%%JJJ~~~WJ^^^^^^JJJJJJJJJJJ%%JJJJJWWWWWWWWWW^^^^^UUUUUUMMMMMMMMMMUUUUUUMMMUMUMMMM%%%%MMMUUUUUUUUUMMUUUUUUU:MMMMMUUUUUUUUUUMMMMMMMMUUUUUUUUUUUUUMMUUMMMM%%%MMUUUUUUUUU^
^,.".,,.."ssssTss,,,",""ss,,sss",",,"".,.,,..",",.,,sssssssssssssssssSSSSSSSSSSY:SSSsssssssssssssssssssssss^^^^^^^sssssYsssSSSSS^^^^^^^^SSSSSSSSSSYSSSSSssSSSssSL^^^^^^^RAAAAAAAAAAAAAARAA#___________#^^AARRRAAAAAAAAAAAAALLLLAAAAAAAAAAAAAAA^^JJJJJWWWWJJJJJJJJWWWWWJJJJW*JJJWWWJJWWJWJWWWWWJJJWJJJJJJJJW:WJJJJJJJJJJJJ%%%JJ~~~WWJJ^^^^JJJJJJJJJJJJJJJJJJJWWWWWWWWWW^^^UUUUUUUUMMMMMMMMMMUUUUUUUMMMMMMMMM%%%%MMMUUUUUMMMMMMMMMMMMM:MMMMMMMMMMMMMUUMMMMMMMMUUUUUUUUUUUUUMMUMUUMM%%%MMUUUUUUUUU^
^..,".,,ssssssssssssssssss.,SS:::::::::::::::::::::::::::::::::::::::::::::::::::SSSSSSsssssSssssssSSSSssss^^^^^^^sssssssssSSSSS^^^^^^^^SSSSSSSSSSSSSSSSSSSSSsssLL^^^^^^AAAAAAAAAAAAAAARRA######:######^^AAARRAAAAAAAAAAAAALLLLAAAAARAAAAAAAAA^^JJJJWWWWW*JJJJJJJJJJJJJJ%JJJJJJWWWJJJJJJWWWJJJJJJJ########___########JWJJJWJJ~~~WWJJJ^^^^JJJJJJJJJWJJJJJJJJWWWWWWWWWJ^^^UUUUUUUUUMMMMMMMMMMUUUUUUMMMMMUMMMU%%%MMUUUUUUUMMMMMMMMMMMMM:MMMMMMMMMMMMMUUUMMMMMMMMMMUUUUUUUMMMMMMMMUMMM%MMUMUUUUUUUU^
^,""",TssssssssssssssssssSSSSS:SSsSSSSsSSS,",",sTsTssssssssTsTsssSsssSSSSSSSSSSS:SSSSSSsssssSsssssSSSSSSsSs^^^^^^^sssssssssSSSSS^^^^^^^^YSSSSSSSSSSSSSSSSSSSSssSLLLLL^^^AAAAAAAAAAAAAARRRAAARRRR:^^^^^R^^AAARAAAAAAAAAAAAAALLLLAAAAARRAAAAAAAR^^JJJJJWWJJJWJJJ*JJJJJJJJ%%%JJJJJJWJJJ*JJJJJJJWJJJJJ#_________________#JJJJJJ~~~JJWJJ*JJ^^JJJJJJJJJJJJJJJJJJWWWWWWWWWJJ^^^UUUUUUUUUMMMMMMMMMMUUUUUUMMMMMMMMM%%%UMMMMMMMUUMMMMMMMMMMMMM:MMMMMMMMMMMMMUUMMMMMMMMMMMMUUUUUMMMMMMMMMUUMM%MMMMMMUUUUUU^
^".,,sTssssssss.ssssssSSSSSsSS:SSSSSSSsSSSSS.,,TsTs."sssssssTsSSYSSsSSSSSSSSSSSS:SSSSssssssSSSssssSSSSSSSSSS^^^^^^ssssssssssSSSSS^^^^^^SSSSSSSSSSSSSSSSSSSSSSSSSLLLLL^^^AAAAAAAAAAAAAARRRAAARRRR:^^^^^^^^AAARAAAAAAAAAAAAAALLLLAAAARRRAAAAAAAR^^JJJJJJJJJJJJJJJJJJJJJJ%%%%JJWJJJJJJJJJJJJJJJJJJJJJ#__Z______________#JJJJJ~~~JJJJJJWJJJJJWWWWJJJJJJJWWWWWWWWWWWWWJJJJ^^^UUUUUUUUMMMMMMMMMMMUUUUUUUMMMMMMMMM%MMMMMMMMMUUMMM#########___#########MMMUUUUMMMMMMMMMMMUUUUMMMUMMUMUUUMMUMMMMUUUUUUUU^
^.""sssssss",,".TTssSSSSSSSSSS:SSSSSsSSSSSSsSSsssTT,".,",".TTsSSYSSSSSSSSSSSSSSS:SSSSssssssSSSsssSSSSSSSSSSSS^^^sssssssssssssSSSSS^^^^^SSSYssSSSSSSSSSSSSSSSSSSSLLLLL^^^AAAAAAAAAAAARRRRRAAAARRR:^^^^^^^^AAARRAAARRAAAAAAAALLLAAARRRRRRRAAAAAR^^JWJJJJJWJJJJJJWJJ%%JJJ%%%%WJJJJJJJJJJJ%%JJJJJJJJJJ#_________________#JJWW~~~JJJJJJJJJJJJWWWWWWJJJJJWWWWWWWWWWWWWWJJJJ^^^UUUUUUMUMMMMMMMMMMMUUUUUUUUUUMUMMMMMMMMUMMMMMMMMMM#___________________#MMMUMMMMMMMMMMMMMMMMUMMMMMMUUUUUUMMMMMMMUUUUUUUU^
^.",sssssssT,,""sSSSSSSSSSSSSs:SsSSSsSSSSsSSSSSSSSss,,".,,."sSSSSSSSSSSSSSSSSSSS:::::::::::::::::::::::::::::::::sYssssssssssSSSSSSS^SSSSSSSsSSSSSSSSSSSSSSSSSSSLL^^^^^^AAAAAAAAAAARRRRRAAAAARRR:A^^^^^L^AAARRAARRRAAAAAAALLLLAARRRRRRRRRAAAAR^^^JJJJJJJJJJJJJJ*J%%J^^%%%%JJJJJJJJWJJJ%JJJJJJJJJJJ#_________________#J*JW~~~JWJJJJJJJJ*JWWWWWWJJJJJWWWWWWWWWWWWWWJJJW^^^UUUUUUMMMUUUMMMMUUUUUUUUUUUUUUMMMMMMMMMMMMMMMMUMMM#__Z________________#MMMUMMMMMMMUMMMMMMMMMMMUMMUUUUUUUMMMMMMMUUUUUUUU^
^,"..sssSSSSSSSSSSSSSSSSSSSSsSSSSSSSSSSSSSSSSSSSSSSsSsSSSsSsSsSSSSSssSSSSSSSSSSSSSSSSssYsssSSSSsSSSSssssssssssss:ssssssSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSsL^^^^^^AAAAAAAAAAAARRRRAAAAAAAAA:AAA^^^LAAAAAAAAAARAAAAAAALLLAAAARRRRRRRRRAAAA^^^^JWWJJWWJJJJJJJJJJ%^^^%%%JJJJJJJJJJJJJWJJJJJWJJJJ#_________________#JJJ~~~WJJJJJJJJJJJJWWWWWJJJJJWWWWWWWWWWWWWWWJJJ^^^^UUUUUUMMMUUUMMMUUUUUUUUUUUUUUUMMMMMMMMMMMMMMMMMMMM#___________________#MMMMMMMMMMMUMUMMMMMMMMUMMMUUUUUUMMMUMMMMUUUUUUUU^
^,.,,SSSSsSSSsSSSSSSSSSSSSSSSSSSSSsSssSSSSSsSSsSsSSSSSSSSSSSSSYSSSYssSSSSSSSSSSSSSSSSssssssSSSSsSSYSssssssssssss:sssssSSSSSSSSSSSSSSSSSSSSSSSSSSSSYSSSSSSsssssss^^^^^^^AAAAAAAAAAALRRRAAAAAAAAAA:AAAAAAAARAAAAAAAAAAAAAAAAAAAAAAAAARRRRRRRRRAA^^^^WWWWWWWJJJJJWJJJJ%::::::::::::::::::::::::::::::___________________::===:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::%MMM%%MMM#___________________#MMMMUUUMMUMMMMMM%%%%MMMMMUUUUUUMMM%%%MMMUUUUUUUU^
^SSSSSSSSsSSSssSSSSsSSSSSsSS~~~~~~~~~~~SSSSSsSSSSSSSSSSSSSSSSSSSSSSSsSSSSSSSSSSSSSSSSsssYssSSSSSSSSSssssssssssss:SssssSSSSSSSSSSYSSSSSSSSYSSYSSSSssSSSSYs^^^ssssAAAAAAAAAAARAAAAALLLRRALLLAAAAAA:AAAAAAARRRAAAAAAAAAAAAAAAAAAARAAAAARRRRRRRRAA^^^^WWWWWWWWJJJJJJJJJJ:^^^%JJJJJJJWJJWJJJJW*JJJJJJJJ#_________________#JJ~~~JJJJJJJJJWJJJJWWWWWWJJJWWWWWJJJJ:WWWWW*JJJ^^^^UUUUUUMMMUUUUUUUUUUUUUUUUUUUUUUMMMMMMMU%:%%%%U%MMM#___________________#MMMMUUUMMMMMMMMM%%%%%%MMMUUUUUUMMM%%%MMMUUUUUUUU^
^SSsSSSSSSsSSSSSsSSSSSSSS~~~~~~~~~~~~~~~~~sSSSSSSSSSSsSSSSSSSSSSSSSSsSSSSSSSYSSSSSSSSssssssssssSSSSSSsssssSSSsss:SSSSYssssYSSSSSYSSSSSSSSSSSSSsssssSSSS^^^^^^sssAAAAAAAAAAAAAAAAALLLLRLLLLAAAAAA:AAAAAAAAAAAAAAAAAAAAAAAAAAAAARAAAARRRRRRRRRAA^^^^WWWWWWWWWJJJJJJJJJ:JJWJJJJJJJ*JJJJJJJWJJJJJJWWJJ#_________________#JJ~~~JJJWJJJJJJJJWWWWWWWWWWWJJJJJJJJJ:JWWWW*JJJ^^^^UUUUUUMMUUUUUMMUUUUUUUUUUUUUUUMMMMMMMMM%::::::::::_____________________::::::::::::::::::::::::::::::UMMM%%MUMMUUUUUUUU^
^sSSSSSSSSsSSSSSSSsSSS~~=======~~~~~~~~~~~~~SSsSSSsSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSssss^^^sssssYSSSSSSSsssSSSsss:SSSSSssssssSSSSSSSSSSSSSSSSSssssssSSS^^^^^^^^ssAAAAAAAAAAAAAAAAALLLLALLLLLAARAA:AAAAARAAAAAAAAAAAAAAAAAAAAAAARAAAARRRRRRAAAAA^^^^WWWWWWWWJJJJJJJJJJ:JJJJJJJJJJJJJW%JJJJJJJJJWWWWJ#___~~_______F____#W~~~J%JJJJJWJJJWWWWWWWWWWWWWJJJJJJJJJ:JJWWWJJJWW^^^UUUUUUUUUUUUUMMUUUMMMUMUUUUUUUMMMMMMMMMUMMMMMMMMMM#___________________#MMMMUUUUMMMUMMMMM%%MMM%MMMMMM:MMMMMMMMMMMUUUUUUU^
^SSsSSSSSSSSsSSSSSsS~~~~~~~=~~~~~~~~~~~~~~~~~~~sSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSYSSSss^^^^^ssssSSSSS###########___###########SSSSSSSSSSSSSSSSsssssSSSS^^^^^^^^ssAARRRRAAAAAAAAAALLLLLALLLLLARRRA:AAAAARAAAAAAARRRRRRRRRAAAAALARAAAARRRRRAAAAAA^^^^WWWWWWWWJJJJJJJWWJ:JJJJJJJJJJJJJJJWJJJJJJJJWWWWJ#___~~____________#WW~~~JJJJJJJJJJJJWWWWWWWWWWWWJJWJJJJJ:JJJJJJJJWW^^^UUUMMUUUUUUUMMMMMMMMMMMMUUUUUMMMMMMMMMMMMMMMUMMMMM#___________________#MMMMUUUUUUMMMMMMMMMMMM%%MMMMM:MMMMMUMMMMMMMMMMUU^
^SSSSSSSSSSSSSSSS~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSs~SSSSSSSSSSSSSSSSSSSSSSSS^^^^^ssssSSSSS#_______________________#SSSSSSSSSSSSSSSsssssYSSSS^^^^^^^^ssAAAARRAAAAAAAAAALLLLAALLLLLAARAA:AAAARRAAAAAAAAALAAARRRAAAALLLRAAAARRRRAAAAAAA^^^JWWWWWWWWWWWWWWWWWW:J*JJJJWJJJJJJJJJJ%%JJWJWWWWWW#_________________#WW~~~JJJJJJJJJJJ^^^^WWWWWWWWWWWJJJJJJ:JWJJJJJJWWW^^MMMUMMUUUUUUMUMMMMMUMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM#_____________F_____#MMMMUUUUUUMMMMMMMMMMMM%%MMMMM:MMMMMMMMMMMMMMMMMU^
^SsSSSSS~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSYSSSSYSSSSSSSSSSSSSS^^^^^ssssSYSSS#__Z____________________#SSSSSSSSSSSSSSssssssSSSSS^^^^^^^^ssAAAAARRAAAAAAAAAALLLAAALLLLAAAAA:AARRRRAAAAAAAAAAAAARRRAAAALLAAAAAAARAAAAARAAA^^^JWWWWWWJWWWWWWWWWWW:WJJJJWJJWJJJJJJW%%%JJJJJWWWWW########___########WW~~~JJJJJJJJJJ^^^^^^WWWWWWWWWWJJJWJJ:%JJJ*JJJWWWW^MMMMMMMMUUUUMMMMMMMMMMMMMMMMMMUMMMMMMMMMMMMMMMUMMM#___________________#MMMMMUUUMMUMMMMMMMMMUMMMMMMMM:MMMUU%%%%MMMMMUUMM^
^SSSS~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSYSSSSSSSSSSSSS^^^^^ssssSSSSS#_______________________#SSSSSSSSSSSSSSssssssSSSSS^^^^^^^^YsAALLLRRRRAAAAAAARLLAAAALLLRAALLA:ARLLLLLLAAAALAAAAAARRRALLAAAAAARRRAAAAAARRRAA^^^JJWWWWJJ*WWWWWWWWWW:JJWJJJJJJJJJJJJJJJJJJJWJWWWWWWJJJJJJJJ:JWWWWWWWWWWW~~~WJJJJJJJ^^^^^^^^WWWWWWWWWJJJJJJ:JJJJJJJWWWWJ^MUMMMMMMMUUMMMMMUMMMMMMMMMMMMMMMMMMMUUUUMUUUUUUMMM#___________________#MMMMMUUMMMMMMUUUMMMMMMMMMMMMM:MMMM%%%%%%MMMMUUUM^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSYSSSSSSSYSSSss^^^SssssSSSSS#______T___~~~___T______#SSsssSSSSSSSSSsssssssSSS^^^^^^^^^^sAALLLLRRRAAAAAAARRRAAAALLLAAALLL==========::===::::::::===:::::::::::::::::::::::::::::::::::::::::::JJJJJJJJJJJJJJJJJJJJJJJJWWWWJJJJJJJJJJ:JJWWJJWWWWWWW~~~WJJJJJ^^^^^^^^^^WWWWWWWJJJJJJJ:JJJJJWJJJWJJ^MMMMMMMMUUUMMMMMMMMMMMMMMMMMMMMMMUMMUUUUUUUUUUUMMM#########___#########MMM^MUUMMMMMMUUUMMUM%UMMMUMMM:MMMM%%%%MMMMMMUUMM^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sSYSSSSSSSSSSSSSSSsSSSSss^^^SSssSSSSSS#________~~~~~~~________#sssssSSSSSSSSYssssssssSS^^^^^^^^^^sAALLLLRRRRAAARRRRRRAAAAALLLLLLLLLLLLLLLLLLAALLLAAAAAAALLLLAAAAAAAA:AAA^^AAAAAA^^JJWWJJJJJJJJJJJJJJJJJJJJJJWWJWWWWJJJJJJJJWWWJWWWJJJJJWWWJJW:JJWJJJWWWWWWWW~~~WJJJ^^^^^^^^^^^WWWWWJJJJJJWJJ:WWWWJJJJJJJ^^MMMMUUMMUUUMMMMMMMUMMUMM^^^^^MMMMMMMMMMUUUMMUUUMMMMMMMMMMMMM:MMMMMMMMMMMMM^MMMMMMMMMUUUMMM%%%%%MMUMM:MMMM%%%UMMMMMMUUMM^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~YsSSSSSSSSSSSSSSSSSSSSSSsSSSSssssSSYSS________~~~~~~~~~________SsssssSSSSSSSssssssssSSS^^^^^^^^^^^AALLLLRRRRRRRRRRRRAAAAAALLLLLLLLLLLLALLLLLAAAALLLLLLLLLARAAAAAAAAA:A^^^^^AAAAA^^JWWJJJJJJJJJJJJJJJJ%JJWJJJJJWWWWWWJJJJJJJJWWWWWWJJJJJWJJJJW:JJJJJJJWWWWWWWW~~~JJ^^^^^^^^^^^^^WJJJJWJJJJJJW:WWJJJJJJJJJJ^MMMMMMMMUUUMMMMMMUMMMMM^^^^^^^UUMMUMMMMUUUMMMMUMMMMMMMMMMMMM:MMMMMMMMMMMMM^^MMMMMMMMUUUMMM%%%%%MMMMM:MMMMMMMMMMMMUMMMMM^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sssSYSSSSSSSSSSSSSSSSSSSSSSSssssssSSSS#________~~~~~~~________#SSssssssSSSSSsssssYsSSS^^^^^^^^^^^^AALLLRRRRRAARRRRRRAAAAAAALLLLLLLLLLAAALLLAAAAAALLLLLLLLAAAAAAAAAAA:^^^^^^^AAAA^^JJ*WJJJWJJJJ*JJJW%%%JJJJJJJJJWWWWWWWJJJJJJJWWWWWWWWJJJJJJJJ:%%JJJJJJWWWWWWWW~~~J^^^^^^^^^^^^^JJJJJJJJJJJJJ:WJJJJJW%JJJJ^MMMMMMMMMUMMUMMMMMMMMMM^^^^^^^MMMMUUMMMUUMMMMMMMMMMMMMMMMMMM:MMMMMMMMMMMMM^^MUMMMMMMMMMMMM%%%%UMMMMM:MMMMMMMMMMM%MMMMMM^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~ssssSYSSSSSSSSSSSSSSSSSSSSSSsssssssSSS#______T___~~~___T______#SSssss^^^^^SssssssssSSS^^^^^^^^^^^^AAALLRRAAAAAAAAAAAAAAAAAALLLLLLLLLLAAALLLAAARALLLLLLLLAAAAAAAAAA^^:^^^^^^^^AAA^^JJJJJJJJJJJJJJJJ%%W%*WJWWWWWWWWWWWWWWJJJJJJWWWWWWWWWJJJJJJ%:%%%%JJWWJWWWWWWWW~~~^^^^^^^^^^^^^JJJJJJJJJJJJW:JJJWJJ%%%WJ^^MUMMMMMMMMMMMMMMMMMMMMM^^^^^^MMMMUUUMMMUUMMMMMUMMMMMMMMMMMMM:MMMUMMM^^^^^^^^MMMMUMMM%%~~~~~%%MMMMMMM:MMMMMMUUMMM%%%MMMM^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sssSSYSSSSSSSSSSSSSSSSSSSSSSsssssssSSS#_______________________#SSsss^^^^^^^^ssssssSSS^^^^^^^^^^^^^AAAARLRAAAAAAAAAAAAARRAAAAAAALLLAAAAAAAAAAARLLLLAALLLAAAAAAA^^^^^^:^^^^R^^^AAR^^JJJJ*JJJJJJWJJJJJ%%JJJWJJJJJJJWWWWWWJWJJWJJWWWWWWWWWJJJJJJ%:%%%JJJJJJJWWWWWWWJ~~~^^^^^^^^^^^^JJJJJJJJJJWJJ:JJJWJJJWJJJJ^MMMMMMMMMMMMMMMMMMM%MMM^^^^^^UMMUUUUUMMUUMMMMMUMMMMMMMMUUUUU:MMMUMMM^^^^^^^MMMMMMMM%~~~~~~~~~%UMMMMM:MMMMUUUUMMM%%%%MMM^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sSSSSSSSSSSSSSSSSSSSSSSSSSSssSSssssSSS#_____F_________________#SSssY^^^^^^^^^^sssSSSS^^^^^^^^^^^^^AAAARLLAAAAAAAAAAAAARAAAAAAAAALAAAAAAAAAAAAALLLAAAALAAAAAA^^^^^^^^:^^^^^^^^AAR^^JJJJJJJJJJJJWJJWJJJJJJJJJJJJJJJWWWWWJJJJJJJJJWWWWWWWJJJJJJ%:%%JJJJ*WJJWJJWWWWJJ~~~^^^^^^^^^^WWWWJJJJJJWJJJ:JJJJJJJJJWJ^^MMMMMMMMMMMMMUMMUMMMMM^^^^^^^UUUUUUUUMMUMMMMMMMMMUMMMMMUUUUU:MUMMMMM^^^^^^^MMMMMMMM%~~~~~~~~~%MMMMMM:MMMUUUUUMMM%%%%MMM^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sSSSSSSSSSSSSSSsSYYSSSSSSYSssSSSsssSSS#_______________________#SSss^^^^^^^^^^^^sSSSS^^^^^^^^^^^^^^AAAAALLRAAAAAAAAAAAAAAAAAAAAAALAAAARAAAAAAAAALRRAAAAAAAAA^^^^^^^^^:^^^^^^^^^AA^^*JWWJJJJJJJJJJJJJ*JJJJJJJJJWJJJWJJJJJJJJJJWJJJWWWWWWWJJJJJ%:%JJWJWJJJJJJJJWWJJJJ~~~^^^^^^^JJWWWWWJJJJJJJJJ:JJJJJJJJJJWW^MMMMMMMMMMMMMMM^^^^^^^^^^^^^UUUUUUUUUMMUMMM%MMUUMMMMMMUMUUUU:MUMMMMU^^^^^^^MUUUUMMM%~~~~~~~~~%MMMMUM:UUMUUUUUMM%%%%MMMM^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSSSSSsSSSSSYSSSSSsSSSSSSSSSS############_############SSss^^^^^^^^^^^^sYSSS^^^^^^^^^^^^^^AAAAALLRRRAAAAAAAAAAAAAAAAAAAALAAARRRAAAAAAAALRRAAAAAAALLLLR^^^^^^:^^^^^RRRRAA^^JJWJJJJJJJJJ*JJJJJJJJJJJJJWJJJJJJJJJJJJWJJJJJJWWWWWWWWWJJJJ:%J*JJJJJJJJJJJJJJJJJJ~~~JJJJJJJJWWWWWJJJJJJJJJ:JJJJJJWJWWW^^MMMMMMMMMMMMMMU^^^^^^^^^MUUUMUUUUUUUUMMUUM%%%MMMMMMMMMMMMUUU:UMMMM%%^^^^^^^MUUUUMM%U%%~~~~~%%MMMMMMU:UMMUUUUUMM%%%MMMMU^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSSSSSSSSSSSSSSSSSsSSSSSSSSSSSSSSSSSS^^^^:SSSSSSSSSSSSSSss^^^^^^^^^^^^SSsss^^^^^^^^^^^^^^AAAAALLRRRAAAAAAAAAAAAAAAAAAAALAAAARAAAAAAAAAAAAAAAAAALLLLLR^^^^##:##^^^RRRLAA^^JJJJJJWWWWWJJJJJJJJJJJJJJJJJWJJJWJJJJJJWJWJJJJJJWWWWWWWWJJJ:%JJJJWJJJJJJJJJJJJJJJW~~~%%%JJJJWWWWWJJJJ%JJJJ:JJJJJJJJWWW^^MMMMMMMMMUUMMM^^^^^^^^^^MUUMMUUUUUUUUMMMMMMUMMUMMUUMMMMMMUUU:MMMMMM^^^^^^^^MMMUUMM%MMMMMMMMMMMMMMMMU:UMMUUUUMMM%%%MMMMU^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSSSSSSSSSSYSSSSSSsSSSSSSSSSSSSSSssss^^^^:SSSSSSSSSssSSSsss^^^^^^^^^^^SSss^^^^^^^^^^^^^^^AAAAARRRRRAAAAAAARAAAAARAAAAAAAAAAAAAAAAAAAAAAAAAAAAAALLLLLL^^^^#_>_#^^RR^^^RR^^JJJJJWWWWWWWWJJJJ*JJJJJJJJJJJJJJJJJJJJJJJWJJJJJJWWWWWWWWWJJ:%WJJJJJW%%JJW%%JJJJJJJ~~~%%%JJJWWWWWWJJJ%%%JWJ:JJJJJJJJWWWW^MMMMUUUUUUUUMM^^^^^^^^^^MMMMMUUUUUUUUMMMMMMMMMMU^^^UUUMMMUUU:MMMUMM^^^^^^^MMUMMMMMMMMMMMMMM%MMMMMMMM:U^^^^^MMMMM%MMMMMU^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSYYSSSYSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSYSSSS^^^:SSSSSSSSSSSSSSsssS^^^^^^^^^^SSss^^^^^^^^^^^^^^^AAAAARRRRRAAAAAAARRAAARRRAAAAAAAAAAAAAAAAAAAAAAAAAAAAAARLLLLL^^^^R:^^^^RR^^^RR^^JJJJWWWW^^WJJJJJJJ*JJJJJJJJJJJJJJJJJ*JJJJJJJJJJJWWWWWWWWJJJ:JJ^^^^JJ%%%J%%W%JJJJJJJ~~~%%JJJJWWWWWJJJJ%%J##_##JJJJJWWWW^^MMMUUUUUUUUUMM^^^^^^^^^^MMMMMUUUUU~~~~~%MMMUUUU^^^^^^UMMMUUU:MMMMMM^^^^^^^MMMMMMMMUMMMMMMMMUMMMMUMMM:^^^^^#####MMMMMUMU^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SYSSSSSSSsssssssSSSSSSSSSSSSSSSSssSSSSSSSSSSSSSS^S:YSSSSSSSSSSSSSssssSSSSSSSSSSS^^^^^^^^^^^^^^^^^^AAAAARRRRAAAAAAAAAAAAAARAAAAAAAAALLLAAAAAAAAAAAAAAALAAAAALLLL^^^^^:^^^^^^^^^RR^^JJJJWWWW^^^JJJJJJJJWWJJJJJJJWJJWJJJJJJWJ%%JJWWJJJWWWWWWWJJJ:J^^^^^^%%%%%%%%%JJJ*J*J~~~%JJJJJJWWWWJJJJWJJ#_>_#JJJWJWWWW^^MMMMUUUUUUUUM^^^^^^^^^^^UMMMMMUUU~~~~~~~MMMUUU^^^^^^^UUMUUUU:MMMMMM^^^^^^^MMMMMMMMMMMMMMMMM%MMMMMMMM:^^^^^#_>_#MMMMUUUU^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSsYssssssSSSSSSSSSSSSSSSsssSSSSSSSSSSSSsSS:::::::::::::::::::::::::::::::##^^^^^^^^^^^^^^^AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAARAAAAAAAAAAAALAA^^^^^^^^R^^^^^^^RR^^J*JJJWW^^^^^JJWJJJJWWWJJJJWJJJWJJWJJJJJJ%%JJWWJJJJJWWWWJJJJ:^^^^^^^%JJJ%%%%%JJJJJJJJ~~~*JJJJJ*WWWJJJJWJJ%J:JJWJJJJWWWW^^MMMMMUMMUUUUM^^^^^^^^^^^UUMMMMUUUU~~~~~%MMUUMM^^^^^^^^UUUUUU:UMMMMM^^^^^^^MMUMUMMMMMMMMMMMMMMMMMMMMM:^^^^^^M:MMMMMMUUUU^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SYSSSSSSSssssssssSSSSSSSSSSSSSSssssYSSSSSSSSssssSSSSSSSSSSSSSSSSSY:ssssSSSSSSS#_>_#^^^^^^^^^^^^^^^AAAAAAAAAAAAAA^^^^AAAAAAAAAAAAAAAAAAAAAAAAARRRAAAAAAAAAAALAAAAAAA^^RRR^^^^^^RR^^JJJJJWJ^^^^^JJWWJJJWWJJJJJJJJ*JJJJJJJJJJ%%JJJJJJJJWWWWWWJJJ:^^^^^^^JJJJJ%%%JJJJJ*JJJ~~~J*JJJJJWWWJJJJJJJJJ:JJJJJJJJJWWW^MMMMMMMMUUUUMM^^^^^^^^^UUUUMMUUUUUUUUUUMMMUUMMM^^^^^^UUUUUUU:UUMMMM^^^^^^^MUMUMMMMMMMMMMMMMMM%%MMMMM:^^^^^^M:MMMMMMUUUU^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSssSSSSSSSSSSSSSSSSSSsssssssSSssssssssssSSSSSSSSSsssssSSSs:ssssSSSSSSss.:.^^^^^^^^^^^^^^^^AAAAAAAAAAAAA^^^^^AAAAAAAAALLAAAAAAAAAAAAAAARAAAAAAAAAAAALAAAAAAAALLLR^^^^^^RR^^JJJJJJJ^^^^^JWWWJJJWWJJJJJJJJJJJJJJJJWJJ%%JJJJJWJWWWWWWWWWJ:^^^^^^^JJWJJJJJWJJJJJJJJ~~~JJJWJJJWJJJJJJJJJJJ:JJJJWJJWJ*J^^MUMMUMMMUUUUMM^^^^^^^UUUUUMMMMMUUUUUUUMMMMMUMMMMUUUUUUUUUUUU:UMMMMMM^^^^^MMMMMMMMMMMMMMMMMMMMMMMMMUM:^^^^^^M:MMMMMMUUUU^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSsssSSSSSSSSSSSSSssSsssssssssSsssssssssssSSSSSSSSsssssssSSs:sssYsSSSSSss.:.^^^^^^^^^^^^^^^^AAAARRRAAARRRR^^^^^AAAAAAAAAARAAAAAAAAAAAAAAAAAAAAAAAAAALAAAAAAAAAAARRRR^^^^RR^^WJ%JJJJ^^^^^WWWWWJJWWJJJJ%%%JJJJJWJ%JJJJ%%JJJJWJJWWWWWWWWWW:^^^^^^^JJWJJJJWJJ%%%%JJ~~~JJJJJJJWJJJJ*JJJJWWWWJJJJJJJJJ%JJ^MMMUUUUUUUUMMMM^^^^MMMMMMMMMUMMMMMUUMMMMMMMMMMMUUUUUUUUMMUUU:MMUMUMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMM:::::::::MMMMMMUUUU^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSSSSS^SSSSSSSSSSSSsssssssssssYsssssssssSSSSSYSs^^^^ssSYs:sssssSSSSSss^^^^^^^^^^^^^^^^^^^AAAARRRAARRRRRR^^^^^AAAAAAAARRRLLLRRRAAAARAAAAAAAAALLLAALAAAAARAAAAARRRR^^^RRR^^JJWJJJJ^^^^^WWWWWJJWWJJWJ%%%JJJJJJ%JJJWJJJWJJJJJJWWWWWWWWWW:^^^^^^^JJJJJJWJJ%%%%%JJ~~~JJWJJJ%JJJJJJJWWWWWWWWJJJJJJW%%%J^UUUUUUUUUUUMMMMMMMMMMMMMMUMMUMMMMMMMMMMMMMMMMMMUUUUUUUMMMMMM:MMMMMMMMUUUUUMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMMUUUU^
~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^:^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^AAAARRRRARRRR^^^^^^^AAAAAAAAAAALLLAAAAAARRAAAAAAAAALLLAAAAAAAAAAAAARRRRR^^^RRR^^JJWJJJJ^^^^^WWWWWWWWWWJJJ%%%JJ%%%%%WJJJJJJJ*JJWJJWWWWWWWJWW:WWW^^JJJJJJ%%%W%%%%W%%~~~JJJJJJJ%JJJJJJJWWWWWWWWWJJJJJJ%W%*^UUUUUUUUUUUMMMMMMUMMMMMMMMMUUUMMMMMMMMMMMMMMMMMMUUUUUUUMMMMM:MMMMMMMMUUUUUMMMMMMMMMMMMMMMMMUMMMMMMUMMMMMMMMMMUUMMMUUUUU^
^^^^^^^^^^^^^^^^^^^^^^^^^^^:^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^:^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^J^^^^^^^^^^^^W^^J^^^^^^^^%^^^W^^^^^^^^^^^*^^^^^^^^J^^:^^W^^^^^^^^^^^^%^^^^^^^^^^^^^J^^^J^^^^J^^W^^^^^^^^^^^^^W^^^^^^^U^^^UU^^^^^^^^^M^^^^M^^^^^^^^^^^M^^^^^^M^^^^^^UU^^^^^^^^^:^M^M^^^M^^^^^^^^^M^M^^M^M^^^^M^^^^^MMM^^M^^UMM^^^U^^^^^^^^^
^~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DDDDDDDD:DDDDDDsssDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDVDDDDDVDDDDDVDDDDDDDDDDDDDVVDDDDDVDDDDDDDDDDDDDDDDDDDsssssssDDDDDDD^^^^^^^^^^^^G^G^^^^^^GG^^^G^^C^^G^^^^^^^::::::::::::::::::::::G^^G^^^^^^^^^^^G^^^^^E^^^^^^^^G^^^^^^^^^^^^^^^^^^^^^^^^^^G^^^^^^D^^^^^^A^^^^^^^^^^^^^AA^^A^^^^^R^^V^V^R^^^^^^^^^^^^^^^^^:^^^^^^A^^^^^^^^^^A^^R^^^^^A^^^^^^^^^AA^A^^^^^^^^^^^^^^^^V^^
^~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DDDDDDDD:DDDDDssssDDDDDDDDDDDDDDDVVDDDDDDDDDDDDDDDVVDDDDDVDDDDDVVVDDVVDDDDDDDDVDDDDVVVYDDDDDDDDDDDDDDDDDYsssVDDDDDDDDD^V^^^^^^^^^^G^^^G^^^^^^E^^^E^E^^^^E^^E^E=^^GG^^^^^^^^^^^^^^^^^^^E^^E^^^^^^E^^^E^GCEE^E^^^E^^^^^^^C^^^^^^^G^G^^^C^^^^^^^G^^ADDDDAAAARAAAAAAAAAAAAAAAAARRAAAAAARRRRRRDDDDVVVVVVVVVAAAAAA:AAAAAAAAVVVVVVAAAAAARAAAAAAAAAAAAAALLAAAAAAAAAAAARRAAAVVVV^
^~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DDDDDDDD:DDDsssssssDDDDDDDDDDDDDDVsDDDDDDDDVVVVDDDDVDDDDDDDDDDDVVVVDDDDDDDDDDDVDDDDDVDDDDDDDDDDDDDDDDDDDDsssVDDDDDDDDDD^^^^^^GGGGGGGGGGEEEEEEEEEEEEEEEEEEEEEEE:ECEEEE^^^EEEEEEEEEGGGGEEEEEEEEEEEEEEEEECCCEEEEEEEEEEEEECCGGEEEEEGEEEEEEEGGGCCGGG^AAAAAAAARRRRRAAAAAAAAAAAAAARRRAAAAARRRRRRDDDDVVVVVVVVVAAAAAA:AAAAAAAAVVVVVVAAAAAAAAAAAAAAAAAAAARRLLAAAAAAAAAAAARAAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DDYDDDDD:DDDssssDDDDDDDDDDDDDDDDDDDDDDDVVVVVVVVVVDDVDDDDDDDDDDDDVVVDDDDDDDDDDDVDDDDDDDDDDDDDDDDDDDDDDDDDDsssDDDDDDDDDD^V^^^^GGGGGGCGGGGGEEEEEEEEEEEEEEEEEEEEEE:CCEEEE^^^EEEEEEEEGGGGGEEEEEEEEEEEECCEECCCCCCCEEEEEEEEEECCGGGEEEEEEECEEEEGGGCCGG^^AAAAAAAAARAAAAAAAAAAAAAAAAARRAAAAAARRRADDAAADVVVVVVVVVVAAAAA:AAAAAAAVVVVVVVAAAAAAAAAAAAAAAAAAAARRALLAAAAAAAAAAAAAAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~=~SSSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~VDDYDDDs::::::::::::::::::::::::::::::::::::::::::::::::::DDDssDDVVDDDDDDDDDDDVDDDDDDDDDDVVVVVVDDDDDDDDsDDDDssDDDDDDDD^^G^EEEGGGGGCGGGGEEEEEEEEEEEEEEEEEEEEEEE:ECEEEE^^^EEEEEEEEGGGGGEEEEEEEEEEEECCEEECCCCCEEEEEEEEEEECGGGGEEEEEEECEEEEGGGGGGGG^AAAAAAAAAAAAAAAAAAAAARAAAAARAAAAAAAARAAAAAAAVVVVVVVVVVVAAAAA:AARAAAVVVVVVVVVAAAAAAAADAAAAAAAARRAAAALLAAAAAAADDDAAAAARRR^
^~~~~~~~~~~~~~~~~~~~~~~~SSS:SJJJWWSSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SWSSW~~~~~~~~~~~~~~~~~~~~~~~~~VDDDDDssssssYDDDDDDDDDDDDDDDDDDDVVVVVVVVVVVVVVVVVVDDDDDDD:DDDssssVVVVVDDDDDDDDDDDDDDDDDDDDDDVVDDDDDDDDssDDDDssDDDDDDDD^V^^EEEEGGGGGGEEEEEEEEEEEEEEEEEEEEEEEEEE:EEEEEEE^EEEEEEEEEGGGGGGEEEEEEEEEEEEEEEEEEEEEEEEEEEEEGGGGGGGGEEEEEECCCEEGGGGGGGGG^RRAAAARAAAAAAAARAAAARRRRRRAAAAAAAAAAAAAAAAAVVVVVVVVVVVVVAAAA:ARRAAVVVVVVVVVVAAAAAAAADAAAAAAARRRAAAAALLAAAAAADDDDAAARRRR^
^~~~~~~~~~~~~~~~~~~~~~~SSJJ:JJJJJJWJSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSS~~~~~~~~~~~~~~~~~~~~VVDDDDDsssssDDDDDDDDDDDDDDDDDDDVVVVVVVVVVVVVVVVVVVDDDDDYD:DDDsssVVVVVVDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDVsDDDDDDDD^^^^EEEEEGGGGGCCCEEEEEEEEEEEEECEEEEECEEE:EEEEEEEEEEEEECEEEEGGGGGEECEEEEEEEEEEEEEEEEEEEEEEEEEECGGGGGGGEEEEECCCCCGGGGGGGGG^^RAAAAAAAAAAAAAAAAAAAARRAAAAAAAAAAAAAAAAAAAVVVVVVVVVVVVVVVVAA:ARRAVVVVVVVVVVVVAAAAAAAAAAAAAAAARAAAAAALLAAAAAAAADDAAAARRA^
^~~~~~~~~~~~~~~~~~~~~~SSJJW:JJJJJJJJJSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSssSSSSWSSSS~~~~~~~~~~~~~~~~~~~VVVDVVVVDsssDDDDDDDDDDDDDDDVVVDVVVVVVVVVVVVVVVVVVVDDDDDDD:DDDDDsVVVVVVVDVDDDDDDssDDDDDDDDDDDDYDDDDDDDDDDDDssVVDDDDDDDD^^^^EEEEEEEEEEECEEEEEEEEEEEEEEEEEEEEEEEE:EEEEEEEEEEEEECEEEEEEEEEEECEEEEEEEEEEEEEEEEEEEEEEEEEECEEEEGGEEEEECCCCCGGGGGGGGGGG^AAAAAAAAAAAAAAAAAAAAAAAAAAAAAADAAAAAAAARVVVVVVVVVVVVVVVVVVVV:VVVVVVVVVVVVVVVVARAAAAARDDDAAAAAAAAAAAAALLAAAAAAADDDAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~SSJJJ::::::::::::==~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSJsWsJJJJJJJSSSS~~~~~~~~~~~~~~~~~VDDDDVVDDsssDDDDDDYDDDDDDDDDDDDVVVVVVVVVVVVVVVVVVVDDDDDDD:DDDDDsVVVVVVVDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDssVDDDDDDDDD^^^EEEEEEEEEEEEEEEEEEEEEEEEEEE#########___#########EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEGGGGEGGGGEEEEEEEEEEEEECCCCGGGGGGGGGGGG^AAAAAAAAARAAAAAAAAAAAAAAAAAAADDDAAAAARVVVVVVVVVVVVVVVVVVVVVV:VVVVVVVVVVVVVVVVRRRAAARRRDDDAAAAAAARAADALLAVVVARRRRRAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~SSJJJJWJJJWJJJJSS~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSJJWWJJJJJJJWJJJJWWSSS~~~~~~~~~~~~~~~DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDVVVVVVVVVVVVVVVVVVVDDDDDDD:DDDDDsVVVVVVVDDDDYDDDDDDDDDDDVDDDDDDDDDDDDDDDDDVVsDDDDDDDDDDD^G^EECCEEEEEEEEECCCEEECCEEEEE#___________________#EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEGGCGGGGGGGEEEECCEEEEEEECCCCGGGG^^^GGGG^^AAAAAAAAAAAAAAAAAAAAAAAAAAAAADDDDAAAAVVVVVVVVVVVVVVVVVVVVVVV:VVVVVVVVVVVVVVVVVAAAAARRRDDADDAAAAAADDDALLAVVVAAARRDDAAAAA^
^~~~~~~~~~~~~~~~~~~~~~SSSJJWJJJJJJJWJW~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSJJJJJJJJJJJJWJJJJJJSSW~~~~~~~~~~~~~~~DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDVVVVVVVVVVVVVVVVV########___########VVVVDDDDVDDDDDDDDDDDVDDDDDDDDDDDDDDDDsVVsDDDDDDDDDDD^^EECCCEEEEEEEEECCEEEEEEEEEEE#__Z________________#EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEGGGCGGGGGGGEEEECEEEEEEEECCCCGGG^^^^^^GG^^AAAAAAAAAAAAAAAAAAAAAAAAAAAAADDDDAAAAVVVVVVVVVVVVVVVVVVVVVVV:VVVVVVVVVVVVVVVVVAAAAAARRAAARRDAAADDDDDLLRVVVVVAAADDDDAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~SSSSSWJJSWSSS~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSJJJWJWJJJJJWJJJJJJJJJWWW~~~~~~~~~~~~~~DDDDDDDDDDDYDDDDssDDDDDDDDDDDYDVVVVVVVVVVVVVVVVV#_________________#VVVVVDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDsssssDDDDDDDDDD^^^^CCCCCCEEEEECEEEEEEEEEEECEE#___________________#EEEEEEEEEEEEEEEEEGGEECEEEEEEEEGGCCCGGGGCGGGEECEEEEEECCCCCCCCC^^^^^^^G^^RRAAAAAAAAAAAAAAAADAAAAARAAAADDDDDDAAVVVVVVVVVVVVVVVVVVVVVVV:VVVVVVVVVVVVVVVVVAAADDARRAAARRDAAAAAARRLLRVVVVVAAAADDDAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSS~~~~~~~~===================~~~~~~~~~~~~~~~~~~~~S:::::::::::::JJJJJJJJJJSSW~~~~~~~~~~~~~~DDDDDDDDDDDDVDDDssDDDDDDDDDDDDDDVVVVVVVVVVVVVVVV#__Z______________#VVVVVVDDDDDDDDDDDDDDDDDVDDDDDDDDVDDDsssssDDDDDDDDDD^^^^CCCCCCCCCCCCCEEEEEEEEEECEE#___________________#EEEEEEEEEEEEGGEEEGGECCCEEEEEEEEGCCCGGGGCGGGEECEEEECCCCCCCCCCC^^^^^^^G^^AAAAAAAAAAAAAAAAAADAAAAADDDDDAADDDDDAVVVVVVVVVVVVVVVVVVVVVVV:VVVVVVVVVVVVVVVVVAADDDRRRAAAARAAAAAAARLLRRVVVVVAAAAADDAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSWSSS:SSSSSS~~~~~~~~~~~~~~~:WSWJWJJJJJJJJJJJJJJJJSSW~~~~~~~~~~~~~~~DDDDDDDDDDDVVVDDDDDDDDDDVVDDDDDDVVVVVVVVVVVVVVVV#_________________#VVVVVVVDDDVVVVVDDDDDDDDVDDDDDDDDVDDDDDsssDDDDDDDDDD^V^^EEEEEEEECE::::::::::::::::_____________________::::::::::::::::::::::::=::::::::::=:=====:::::::::::::::::::::::::==:::::::::::::::::::::::::::::::::::::::::::VVVVVVAAAAAAAAAAAAA:AAAAAAAAAAAAAVVVAADDDRRRRAAAAAAAAAAAALLRRRVVVVVAAAAAADAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSS:SSSSSSSSSSS~~~~~~~~~~:SSSWJJJJWJJJJJJJJJJSSSS~~~~~~~~~~~~~~~~DDDDDDDDDDVVVVDDYDDDDDDDDDDDDDDDVVVVVVVVVVVVDDDD#_________________#VVVVVVVVDDVVVVVDDDDDDDDDDDYDDDDDssDDDDsssDDDDDDDDDD^V^^EEEEEEEEEE:EEEEEEEEEEEEEEE#___________________#EEEEEEEEECCEEEEEEEEEEEGGGGEEEEEEGCGEEEEGE:EEEEEEEEEEEECEEEEEE^^^^^^GG^^AAAAAAAAAAAAAARRAAAAAAADDARRRAAADDDAAVVV:VVVVVVAAAAAAAAAAAAA:AAAAAAAAAAAAAVVVAAARRRRRRAAAADDAAAALLRRRRRVVVVVAAAARRRRAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SS#########___#########SSS~~~~~~~~=SSSWJJJJJJJJJJJJWJSSWSS~~~~~~~~~~~~~~~~DDDDDDDDVVVVVVDDDDDDDDDDDDDDDDYDVVVVVVVVVDDDDDDD#_________________#VVVVVVVVVVVVDDDDDDDDDDDDDDDDDDDDDDDDDDDsDDDDDDDDDDD^^G^EEEEEEEEEE:EEEEEEEEEEEEEEE#______________F____#GEECEEEEECCEEEEEEEEEEGGGGGGEEEEEECEEEEEEE:EEEEEECEEEEECEEEEEE^^^^^^GGC^AAAAAAAAAAAAAAAAAAAADDDAAAARAAAAADDAAVVV:VVVVVVAAAAAAAAAAAAA:AAAAAAAAAAAAAADDAAAAAAARAAAADDDAAALLRRRRRVVVVVVAAAAARRRAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSWSS#___________________#SSSWS~~~~~~=SSSSSJJJJJJJJWJJSSWSSSS~~~~~~~~~~~~~~~~DVVVVVVVVVVVVVDDDDDDDDDDDDDDDDDDVVVVVVVDDDDDDDDD___________________::::::::::::::::::::::::::::::::::::::::::::::DDDDD^^^^EEEEEEEEEE:EEEEEEEEEEEGGGE#___________________#EEEEEEEEECCEEEEEEEEEEGGGGGGEEEEEEEEEEEEEE:EEEEEECEEEEEEEEEEEEE^^^^GGGG^AAAAAAAAAAAAAAAAAAAADDDAAAAAAAAAAAAAAVVV:VVVVVVAAA#########___#########AAADDDDAAAAAAAAAAADDDRLLRRRRRRRVVVVVVAAAAAARAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSS#__Z________________#JJSSSS~~~~~=~SSSSWJJSSSSSSSSSWSSSS~~~~~~~~~~~~~~~~~VVVVVVVVVVVVVVDDDDDDDDssssssssssDVVVVVVDDDDDDDDD#_________________#VVVVVVVVVVVVVVVVVDDDDDDDDDDDDVVVVVVVVYDDDDDDV:DDDDD^V^^EEEEEEEEEE:EEEEEEEEEGGGGGE#___________________#EEEEEEEEECEEEEEEECCEEEEGGGGEEEEEEEEEEEEEE:EEGGEECEEEEEEEEEEEEE^^^GGGG^^AAARAAAAARAAAAAAAAAADDDDRAAAAAAAAAAAAVVV:VVVVVVAAA#___________________#AAADDDDAAAAAAAAAAADDDLLRRRRRRRVVVVVVVAAAAAAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSJ#___________________#JJJSSS~~~~~=~~~~SSSSSSSSSSSSS~~~~~~~~~~~~~~~~~~~~~~VVVVVVVVVVVVVVVDDDDDDDssssssssssDVVVVVVVDDDDDVDD#_________________#VVVVVVVVVVVVVVVVVDDVVDDDDDDDVVVVVVVVVDDDYDDDD:DDDDD^V^^EEEEECCCCE:EEEEEEEEEG^^^GE##########_##########EEEEEECCCEEEEEEEECCCEEEGGGGECCCEEEEEEEEEE:CGGGGECEEEEEEEEEEEEEEEEGGGGG^AAARAAAAAAAAAAAAAAAADDDDRAAAAAAAAAAADVVV:VVVVVVAAA#__Z________________#AAAAADDDDAAAAAAAAAALLRRRRRRRRVVVVVVVVAAAAAAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSJ#___________________#JssSSSS~~~~=~~~~~~~~~WS~~~~~~~~~~~~~~~~~~~~~~~~~~~~VVVVVVVVVVVVVVDDDDDDDDssssssssssVVVVVVVVDDDDDVDD#____________F____#VVVVVVVVVVVVVVVVVVVVVVDDDDDDVVVVVVVVVDDDDDDDD:DDDDD^^G^EEEEEEEEEE:EEEEEEEE^^^^^^EEEEEEEEEEE:ECCCCC^^^^^EEEEEEEEEEEEEEEEECEEEEGGGGEECCEEEEEEEECC:CEEEEEEEEEEEEEEEEEEEEEEGGGG^^AARRRRAAAAAAAAAAAAAAADDDDAAAAAAAAAAADVVV:VVVVVVAAA#___________________#AAAAADDDDAAAAAAAAALLRRRRRRRVVVVVVVVVVAAAAAAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSWSJ#___________________#sssSSSS~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~VVVVVVVVVVVVVVDDDDDDDDDsssssssssVVVVVVDVDDDDDVDD#_________________#VVVVVVVVVVVVVVVVVVVVVDDDDDDDDDVVVVVVDDDDDDDDD:DDDDDY^^^EEEEEEEEEE:EEEEEEE^^^^^^^^EEEEEEEEEE:EEEECE^^^^^^EEEEEEEEEEEEEEEEEEECEEEEEEEEEEEEEECCCCC:CCEEEEEEEEEEEEEEEEEEEEEEGGG^^ARRRRRRRAAAAARRRVVVVRRRDAAAAAARAAAAADVVV:VVVVVVAAA#___________________#AAAARDDDDAAAAAAALLVVVVVVVVVVVVVVVVVVVRRAAAAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~======::::::::_____________________:::::::=====~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DssssDDDDDDDDDDDDDDDDYDDDsssssssVVVVVVDVDDDDDDDD#_________________#VVVVVVVVVVVVVVVVVDDDDDDDDDDDDDDDVVDYDDDDDDDDV:DDDDD^^^^ECCCEEEEEE:EECCCCC^^^^^^^^EEEEEECCCC:EEEEEE^^^^^^EEEEEEEEEEEEEEEEEEECEEEEEEEEGEEEEECCCCC:CCEEEEEEEEEGGEEEEEEEEEEEEEEE^AARRRRRRRRAAAARRVVVVVRAAAAAAAAAAAAAAAVVV:VVVVVVAAA#___________________#AAAAADAAAAAAVVVLLVVVVVVVVVVVVVVVVVVVVAAAAAAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~SSSSSSSJ#___________________#JsJSSSS~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~VVDDDDDDDDDDDDDDDDVDDDDDDDDVVVVsVVVVVVDDDDDDDDDD#########_#########VVVVVVVVVVVVVVVsDDDDDDDDDDVDDDDDVVDDDDDDsVVVV:DDDDD^^^^ECCCEEEEEE:EECCCE^^^^^^^^^EEEEEECCCE:EEEEEE^^^^^^^GGEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEECCCCC:CEEEEEEEEEGGGEEEEEEEEEEEEEE^^AARRRRRRRRRAAARRVVVVVAAAAAAAAAAAARAAAAAA::::::::::_____________________:::::::::::::==:::::::::::::::VVVVVVVAAARAAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~SSSSWSS#_____________F_____#JJJSSSS~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DDDDDDDDDDDDDDDDDDDDDDDDDDDssssVVVVVVVDDDDDDDDDDDsVVVDDDD:DDDDVVVVVVVVVVVVVssssssssDDVVVVVVDDDDDDDDVDDDDDssssDVV:DDDDD^^^^ECCEEEEEEE:EECCCE^^^^^^^^^EEEEEEEEEE:EEEEEE^^^^^GGGGEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEECCCCC:EEEEEEEEEGGGGEEEEECEEEEEEEE^^AARRRRRRRRRAAARRVVVVAAAAAAAAAAAAARRAAAAAAAAVVVVAAA#___________________#AAAAAAARAAAVLLVVVVVVVVVVVVVVV:VVVVVVVAADRAAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~SSSSSSS#___________________#JJSSSSS~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DDDVDDssDDDDDDDDDDDDDDDDDDDssssVVVVVVVDDDDDDDDDDssDVVDDDD:DDDDDVVVVVVVVVVVDDssssssssDVVVVVVVDDDDDDDDDDDDDssssDDD:::::::::::::::::::::EECCEE^^^^^^^^^EECCCCEEEE:EEEEEEGGGGCGGGGEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEECCCCE:EEEEECCEEGGGEEEEEECEEEEEEEC^^AAARAADDRRRAAAARAVAAAAAAAAAAAAAAARAAAAADAAAAADDAAA#___________________#AAAAAADRDAVVLLVVVVVVVVVVVVVVV:VVVVVVVAADRDAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~SSSSS#___________________#SSWSSS~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DssVVDssssssDDDYDDDDDDDDDDDDssVVVVVVVVVDVVVsssssDDDVVDDDD:DDDDDVVVVVVVVVVVDDssssssssVVVVVVVVVDDDDDDDsDDDDssssDDDDDDDDDD^^EEEEEEEEEEEEECCCCEE^^^^^^^^EECCCEEEEE:EEEEEEGGGGGGGGGEEEECEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE:EEEEEECEEGGGGEEEEEEE^^^EEEE^^VAAAADDDAAAAAAAAAAAAAAAARAAAAARRAAAAAAADDARAADDAAA#_____________F_____#AAAAAARRRAVLLVVVVVVVVVVVVVVVV:VVVVVVVAADDDARAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~SSSS##########_##########SSSSSS~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DssDDsssssssVDDYDDssDDDDDDDDDDVVVVVVVVVVVVVsssssDDDssDDDD:DDDDDDVVVVVVVVVVDDssssssssDVVVVVVVVDDDDDDsssDDDssssDVVVVDDDD^^^^EEEEEEEEEEECCCCCEE^^^^^^^^CEEEEEEEEE:EEEEEEECGGGGGGGECCCCEEEEEEEEEEEEEEEEECEEEEEEEEEEEEE:EEEEEECCEEGGGEEEEEE^^^^^^EE^^VVAAAADDAAAAAAAAAAAAAAAARAAAARRRRAAAAAAAAARAADDAAA#___________________#AAAAAARRRAVLLVVVVVVVVVVVVVVVV:VVVVVVVAADDDRRRAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~SWSSSSJJssJJW:JJJJWSSSSSSSSS~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DssDDDssssssVDDDssssDDDDDDDDDVVVVVVVVVVVVVVsssssDDDDsDDDD:DDDDDDDVVVVVVVVDDDDsssssssDVVVVVVVVDDDVYDsssDDDssssVVVVVVDDD^^G^EEEEEEEEEEECCCCCEE^^^^^^^CCCEEEEEEEC:EEEEEEECCEGGGGEECCCCCEEEEECCCCEEEEEECCEEEEEEEEEEEEE:CEEEEECCEEGCCCCCCE^^^^^^^^EE^VVVVAAAAAAAAAAAAAAAAAAAARAAAARRRAAAAAAAAAAAADDDAAA#___________________#AAAAAARRRAVLLVVVVVVVVVVVVVVVV:VVVVVVVADDDDARAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~SSSSSSSSJJ:SSSSSSSSSS~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~VDDDDDssssDVVDDssssssVVVVVVVVVVVVVVVVVVVVVDDssssDDDDDDDDV:DDDDDDDVVVVVVVVDDDDDDDDssDDVVVVVVVVDDDVVDDDDDssVVVLLLLLLLLDV^^^^EEEEEEEEEEEEECCEEE^^^^^^^GGGEEEEEEEE:EEEEEEECCEEEEEEEEECCEEEEEEEEEEEEEEEEECEEEEEEEEEEEEE:CEEEEEEEEEECCCCCG^^^^^^^^^^C^VVVVVVVVVVAAAAAAAAAAAAAARRAAAAAAAAAAAAAAAAAAADDAAA#########___#########AAAAAAARRAVLLVVVVVVVVVVVVVVVV:VVVVVVVDDDADDAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~SSSSSSSW:SSSSSSS~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DDDDDDsssDDDVDDssssssssVVVVVsVVVVVVVVVVVVDDDDDsDDDDDDDDDD:DDDDDDDVVVVVDDDDDDDDDDDDDDLLLVVVVVVDDDVVDDDDDsssssLLLLLLLLDDD^^^EEEEEEEEEEEEEEEEEE^^^^^^GGGGEEEEEEEE:EEEEEEEEECCEEEEEEEEEEEEEEEEEEEEECCCGEEEEEEEEEEEEEEE:CEGGEEEEEEEEEEEE^^^^^^^^^^^^^VVVVVVVVVVVVAAAAAAAAAAAARRAVVAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA:AAAAAAAAAAAAAAAAARRVVVLLVVVVVVVVVVVVVVV:VVVVVVVAARRAAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~S~~~~SS:~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DDDDDDDsDDDDDDDssssssssDDDDDsVVVVVVVVVVVVDDDDDDDDDDDDDDYD:DDDDDDDVVVVVVDDDDVVDDDDssDLLLVVVVVVDDVVVDDDDDDDDDDLLLLLLLLDD^^^^EEEEEEEEEEEEEEEEEEEEEGGCGGGGGCEEEEEE:EEEEEEEEECCCCEEEEEEEEEEEEEEEEEECCCCGEEEEEEECEEEEEEE:CCGGGEEEEEEEEEE^^^^^^^^^^^^^^VVVVVVVVVVVVVAAAAAAAAAAAAAVVVVDDAAAAAAAAAAAAAAAAAAAAAAAAAAAA:AAAAAAAAAAAAAAAAAAAVVVLLVVVVVVVVVVVVVVV:VVVVVVVAAARAAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~SSSSS~~~~~~~~~~~~~~~~~~~~DDDDDDDDDDDDDDDVVVVVsDDDDDDDsVVVVVVVVVVVVDDDDDDDDDDDDDDDD:DDDDDDDVVVVVVDDDVVVsDDssssLLLVVVVVVVVVVVDDDDDDDDDDLLLLLLLLDD^^^^EEEEEEEEEEE^^EEEEEEEGGGGGGGGGGGGEEEE:EEEEEEEEEECCEEEEEEEEEEEEEEEEEEECCCCGEEEEEEEEEEEEEEE:CEGGGEEEEEEEEEE^^^^^^^^^^^^^^VVVVVVVVVVVVVAAAAAAAAAAAAAVVVVRRDDAAAAARAAAAAAAAAAAAAAAAAAAA:AAAAAAAAAAAAAAAAAAAVVVVLLVVVVVVVVVVVVVV:VVVVVVVAAAAAAAAAAA^
^~~~~~~~~~~~~~~~SSSSSWSSSSSSS~~~~~=~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~SSSSSSSWSSSSSS~~~~~~~~~~~~~~~~~DDDDDDDDDDDDDDDVVVVssDYDDDDDsDVVVVVVVVVVDDDDDDDDDDDDDDDDD::::::::::::::::::::::::::=====:::::::::::::::::::DLLLLLLLDDD^^^EEEEEEEEEEE^^^^^^EEEEGGEEGGGGGGGGGEEE:EEEEEEEEEEEEEEEEEEEECCCCEEEEEEEGGCCCEEEEEEEEEEEEEEE:EEECEEEEEEEEEE^^^^^^^^^^^^^^^VVVVVVLLVVVVVAAAAAALLLAAAVVVVLLRRRRRRRRRRRRAAAAAAAAAAAAAAAAA:AARAAAAAAAAAAAAAAAAVVVVVLLVVVVVVVVVVVVV:VVVVVVVAAAAAAAAAAA^
^~~~~~~~~~~~~~SSSSSSJWssSssSSS~~~~=~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~=~~~~~~~SSSSSSJJJJJJJSSSSS~~~~~~~~~~~~~~DDDDDDDDDDDDDDDssssssDDDDDDDDDDDDVVDDDDDDDDDDDDDDDDDDDDDDs:sssDDVVVVVVVVVDDDssDDsssLLLLLVVVDDDDDDDDDDDDDDD:DLLLLLVVssDD^^^EEEEEEEEE^^^^^^^EEEEGGEEEGCGGGGGGEEE:EEEEEEEEEEEEEEEEEEECCCCCCCCCCCEEEECCEEECCEEEEEEEEEE:EECCCEEEEEEEEE^^^^^^^^^^^^^^^VVVVVVLVVVVVVAAAAAAAARAAAAVVVVAAARRRRRRRRRRAAAAAAAAAAAAAAAAA:AAAAAAAAAAAAAAAAAAAVVVVVVLLVVVVVVVVVVVV:VVVVVVVAAAAAAAAAAA^
^~~~~~~~~~~~~SSSSJJJJW:::::::::====~~~~~~~~~~~~~~~~~~~~~~~=========~~~~~~~~~~~~~=~~~~~SSSSSSJJJJWJWJJWSSSSS~~~~~~~~~~~~~VVDDDVVVVVDDDDssssDDDssssDDVDDDDDsssssDDDVVDDDDDDDDDDDDDDV:sssDVVVVVVVVVVVVDDDDDDLLLLLLLsssDDLLLLLDDDDDDDD:DLLLLLVVssD^^^^EEEEEEEEEE^^^^^EEEEEEEEEEGGGGGGGGEEE:EEEEEEEEEEEEEEEEEEEEEEEEEEEECEEEEEEEEEECCEEEEEEEEEE:EEECCEEEEEEEEE^^^^^^^^^^^^^^^VVVVVVVVVVVVAAAAAAAAARRRAAADVAAAAAAARAALAAAAARAAAAAAAAAAAAAA:AAAAAAAAAAAAAAAAAAAVVVVVVVLLVVVVVVVVVVV:VVVVVVAAAAADDRAAAA^
^~~~~~~~~~~~SSSssWJJJJ:JJJJJsSSSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~=~~~~~SSWSSJJJJJJJJJJJWSSSS~~~~~~~~~~~~~VDDDDVVVVVDDDsssssDDDsssssDDDDDDDsssssDDDDDDDDDDDDDDDDDDDV:ssDDVVVVVVVVVVVVVVVVVLLLLLLLLsssDDLLLLLLDDDDDDD:DLLLLVVVssD^^^^EEEEEEEEEEEEEEEEEEEEEEEEEGGGGGGEEEEE:ECEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEECCCEEEEEEEEE:EEECEEEEEEEEEEE^^^^^^^^^^^^^^VVVVAAAAAAAAAAAAAAAAARRRRAAAAAAAAAAAAALLAAAARRRAAAAAAAAAAAAA:AAAAAAAAAAARAAAAAAAVVVVVVVVLLVVVVVVVVVV:VVVAAAAAAAADDRRAAA^
^~~~~~~~~~~SSSsssJWJJJ:JJJJJssWSSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~=~~~~SSSWWJJJJJJJWJJJJJJJSS~~~~~~~~~~~~~DYDDDVVVVVDDDDsVssDDDVVsssDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDs:sDDDVVVVVVVVVVVVVVVVVLLLLLLLLssDDDLLLLLLDDDDDDD:DLLLLVVVsDD^^^^CEEEECCCCEEEEEEEEEEECCCCEEGGGGGEEEEE:ECEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEECCCEEEEEEEE:::::::::::EEEEEEE^^^^^^^^^E^^VAAAAAAAAAAAAAAAAAAAARRRRAAAAAAAAAAAAAAAAAAARRRAAAAAAAAAAAAA:AAAAAAAAAAARAAAAAAAVVVVVVVVLLVVVVVVVVVV:VDDAAAAAAAAAARAAAA^
^~~~~~~~~~~SSSJJJJJJJJ:JJJJJWWSSSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~=~~~~SWSsssJJJJJJJJWWJJJJSSS~~~~~~~~~~~~DDDDDVVVVVDVVVVVVDDDDVVVDDDDDDDDDYDDDDDDDDDDDDDDDDDDDDDDDD:VVDDVVVVVVVVVVVVVVVVVVVLLLLLLLsDDDDLLLLDDDDDDDD:DDLLVVVVDDD^^^^EEEEEEEEEEEEEEEEEEEECCCCEEGGGGGEEEEE:EEEEEEEEEEEEECEEEEEEEEEEEEEEEEEEEEEEEEEECCEEEEEEEEEEEEEEEEEEE:EEEEEEEEEE^^^EEEEE^AARRRDDAAAARRRAAVVVVVRRRRAAAALLLAAAAAAAAAAAAAAAAAAAAAAAARRAA:AAAAAAAAAAARRAAARRRVVVVVVVVVLLVVVVVVVVV:DDDDDAAAAAAARRAAAA^
^~~~~~~~~~~SSSJJJsJJJJJJJJJJJJSSSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SS~=~~~~~~~~~~~~~=====::::::::::::JJJJWJJWWSS~~~~~~~~~~~~DDDDDVVVVVVVVVVVVVDDDVVDDDDDssDDDDDDDDDDDDDDDDDDDsDDDDDDDD:DVDVVVVVVVVVVVVVVVVVVVVVLLLLLLsDDDDDDDDDLLLLLLL:DDVVVVVVDDDDD^^EEEEEEEEEEEEEEEEEEECCCCEEEEEGGEEEEEE:EEEEEEEEEEECCCCCEEEEEEEEEEEEEEEEEECEEEEECEEEEEEECCEEEEEEEEEEE:EEEEGGGGEEEEEEEEEE^AARRRRAAAARRRRRVVVVVVVRRRAAALLLLLAAAAAAAAAAAAAAAAAAAAAAARRRA:AAAARRRAAAAARRRRRRRVVVVVVVVVVLLVVVVVVVV:DDDDDAAAAAAARRAAAA^
^~~~~~~~~~~SSSsssssW#####JJWJWSSSS~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSS:SSSSSS~~~~~~~~~~~~SSSssWsJJJJJJWJJJJJJSSS~~~~~~~~~~~~DDDDDDVVVVVVVVVVVVVDDVDDDDDsssVDDDYDDDDDDDDDDYDDDDsDDDDD>D:DDDVVVVVVVVVVVVVVLVVVVVVLLLLLLsVDDDDDDDDLLLLLLL=DDVVVVVVDDD^^^^EEEEEEEEEEEEEECEEEECCCCEEEEEEGEECEEE:EEEEEEEGECCCCCCCCEEEEECCEEEEEEEEEECEEEEECEEEEEECCC^^^EEEECC##_##EEGGGGEEEEEEEEE^^AARRRAAAARRRRRRVVVVLLLLLLLLLLLLLLAAAAVVVVAAAAAAAAAAAAAAARRRA:AAAAAAAAAAAAAAARRRRVVVVVVVVVVLLVVVVVVVA:DDDRR#####AADDAAAA^
^~~~~~~~~~~WSWSssssJ#_>_#JJJJWSSS~~~~~~~~~~~~~~~~~~~~~~~~~~SSJWJJJ:sssssSS~~~~~~~~~~~~SSsssssssssJJWJJJJSSSS~~~~~~~~~~~~DDDDDDDDDDVVVVVVVVVDDVDDDDDssVVsDDDDDDDDDDDDDDDDDDDVVDDDDD:DDDVVVVVVVVVVVVVVLLVVVVVLLLLLLsVVVVDDDDDLLLLLLLLLDVVVVVVDDD^^^^^^EEEEEEEEEEEEEEEEECCCCEEEEEEEEE^^^E:EEEEEEEEECCCEEEEEEEEEECEEEEEEEEEEEEEEEEECEEEEEEE^^^^^^EEEEC#_>_#EGGGGEEEEEEEEEEE^RAAAAAAARRRRRRRVVVVLLLLLLLLLLLLLLAVVVVVVVVVVAAARRAAAAAAARRRR:AAAAAAAAAAAAAAAAAAAVVVVVVVVVVLLVVVVVVVR:DDDRR#_>_#AADDDAAA^
^~~~~~~~~~~~SSSWsssJJJ:JJJJJJSSSW~~~~~~~~~~~~~~~~~~~~~~~~~SJJWJJJJ:ssWsssSS~~~~~~~~~~~WSSsssWssssJJJJJSSSSSS~~~~~~~~~~~~DDDDDDDDDsVVVVVVVVVDDVDDDDDssssssDDDDDDDDDDDDDDDDDVVVsDDDD:DDDVVVVVVVVVVVVVVLLVVVVVLLLLLLsDDDDDDDDDsLLLL#####VVVVVVDDD^^^^^^^EEEEEEEEEEEEEEEECCCCEEEEEEEE^^^^^:EEEEEEEEEECCEEEEEEEEEEEEEEEECCEEEEEEEEEEEEEEEEE^^^^^^^EEEEEEE:EGGGGGEEEEEEEEEEEE^RDAAAAAARRRRRRRVVVVLLLLLLLLLLLLLLAVVVVVVVVVVVVRRRRAAAAAARRRR:AAAAAAAAAAAAAAAAAAAVVVVVVVVVVLLVVVVVVVR:DDDRRRA:AAAADDAAAA^
^~~~~~~~~~~~~SSSSsJJJJ:JJJJJSSS~~~~~~~~~~~~~~~~~~~~~~~~~~SSJJJWJJJ:sssssssS~~~~~~~~~~~~SSSsWsssssJJJJWSSSS~~~~~~~~~~~~~~VDDDDDDDVVVVVVVVVVVDDVDDDDDssssssDDDDDDVDDDDDDDDDVVVVVDDDD:DDDVVVVVVVVVVVVVVLVVVVVVLLLLLLDDDDDDDDDDDsssL#_>_#VVVVVDDDV^^^^^^^^EEEEEEEEEEGEEECCCCCEECCCEEE^^^^^:EEEEEEEEEECEEEEEEEEEEEEEEEECCCCCEEEEEEEEEEEEEE^^^^^^^^^EEEEGE:EGGGGCCCCEEEEEEEEE^RDDDAAAARRRRRRRVVVVLLLLLRRRRRLLRRVVVVVVVVVVVVVVAAAAAAAAARRRR:AAAAAAAAAAAAAAAAAAVVVVVVVVVVLLVVVVVVVVR:DDDDRDA:AAAAAAAAAA^
^~~~~~~~~~~~~~~SWSSSJJJJJJSSSS~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSssJJWJ:WJJJJJSS~~~~~~~~~~~~SSSSSSSJJJWSSSSSS~~~~~~~~~~~~~~~~VDDDDDDDVVVVVVVVVVVDDVDDDDDDsssssDDDDDVVVDDDDDDDVVVVVVVVVV:VVDDVVVVVVVVVVVVVVVVVVVLLLLLLLDDDDDDDDDDDDDDLLD:DDDDVVDDDVV^^^^^^^^EEEEEEEEEGGGEEEEEEEEEECEEEE^^^^^:EEEEEEEEEECEEEEEEEEEEEEEEEEECCCCEEGEEEEEGEEEEE^^^^^^^^^EEEEGEEEGGGCCCEEEEEEEEEEE^DDDDDALRRRRRRRRVVVVLLLLRRRRRRRRRRVVVVVVVVVVVVVVAAAAAAAAARRRR:RDDDAAAAAAAAAAAAAAVVVVVVVVVLLVVVVVVVVAA:DRDDDDA:AAAAAAAAAA^
^~~~~~~~~~~~~~~~~~~SWSSSWSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSWsJJJ:JWWJJJSS~~~~~~~~~~~~~~SSSSSWSSSSSSSS~~~~~~~~~~~~~~~~~DDDDDDVVVVWVVVVVVVVDDssssssDDssssDDDDDDDDDDDDDDDDDDDDsssDV:DDDDDDDVVVVVVVVVVVVVLLLLLLLLLLDDDDDDDDDDDDDDLLD:DDDDDDDDDDVV^^^^^^^GEEEEEGGGGGEEEEEEEECEEEEEEE^^^^^:EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEGGGECCEGGGEEE^^^^^^^^^^EEEEEGGGGGGCCCEEEEEEEEEE^^DDDDARLLRRRRRRRVVVVLLLVRRRRRRRRRRRVVVVVVVVVVVVVAADAAAAAARRRR:RDDDAAAAAARRAAAAAAVVVVVVVVLLVVVVVVVVVAA:::::::::AAAAARAAAA^
^~~~~~~~~~~~~~~~~~~~SSSSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SWSSSS:SSSSSS~~~~~~~~~~~~~~~~~~~~~~SSS~~~~~~~~~~~~~~~~~~~~~~DDDDDDVVVVVVVVVVVVVsDsssDsDDDDsssDDDVDDDDYVssssDDDDDDDDDDD:DDDDDDDDDDDDDDVVVVVVLLLLLLLLLLDDDDDDDDDDDDDDLLDDDDDDDDDDDDD^^^^^^^^GGEEEEGGGGGEEEEEEEECEEEEECE^^^^^:ECCEEEEEEEEEEEEEEEEEEEEEEEEEEEEGGCCCCCCGGGEEEE^^^^^^^^^GEEEEGGGGGGCCCEEEEEEEEEE^^DDAAARLLRRRRRRVVVVVLLLVRRRRRRRRRRRVVVVVVVVVVVVVADDAAAAAAAARR:RAAADDAARRAAAAAAAAVVVVVVVLLVVVVVVVVVVAAADDDDDDDDAAAAAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SS:S~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DDDDDVVVVVVDVVVVVVVDDDDDVDDDDDVVDDDDVDDDDDVVssssDDYDDDVVVV:VDDDDDDDDDDDDDsDDVVVLLLLLLLLLLDDDDVDDDDDVDDDLLLLLDDDDDDDDDD^^^^^^^^GGEEEEEGGGGEEEEEEEECEEEEECE^^^^^:ECCEEEEEEEEEEEEEEEEEEEEEEEEEEEEEGGCCCCCGGGEEEEE^^^^^^^GGEEEEGGGGCCCCCEEEEEEEEEEE^ARRRRRLLRRRRRRVVVVVLLLRRRRRRRRRRRRVVVVVVVVVVVVRADDAAAAAAAAAR:AAAADDAARRAAAAAAAAVVVVVVLLVVVVVVVVVVVRADDDDDDDDDDAAAAAAAAA^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DDDDDDVVVVDDDssssssDVVVVVVVVVVVVVVVDDDDDDsVVssssDDDDVVVVVV:VDDDsssDDDDDDDDDDDVVLLLLLVVVVLLLLDVDDDDDDDDDDLLLLDDDDDDDDDDD^G^^GGGGGGEEEEEEEGEEEEEEEECCCCCCCE^^^^^:GCEEEEEEEEEEEEEEEEEEEEEEEEEECEEEEGCCCCGEEEEEEEEE^^^^^GGGGECCCCCCCCCGGCCEEEEEEEEC^RRRRRRRRRRRRRRVVVVVLLLRRRRRRRRRRRRRVVVVVVVVVVRRADDAAAAAAAAAR:AAAADAARRRAAAARAAVVVVVLLVVVVVVVVVVVVVRRRAADDDDDDDAAAAAARRR^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~DDDDDDDDDDDDDssssssVVVVVVVVVVVVVVVVVVVVDDDVVssssDDVVVVVVVV:VVDDDsDDDDDDDDDDDDDLLLLLVVVVVVLLLLLDDDDDDDDDDDVDDDDDDDDVsDD^^^^GGGGGGGEEEEEEEGEEEEEEEECCCCCCCE^^^^^:GCGGEEEEEEEEEEEEEEECCCCEEEEECEEEEGCCCCEEEEEEEEEECCGGGGGGGGCCCCCCCCGGGCCCEEEEEEC^^RRRRRRRRRVRRRVVVVVVVVVRRRRRRRRRRRRRVVVVVVVVVVRRAAAAAADDAAAAA:ADDDAAAARAAAAARAAVVVVVVVVVVVVVVVVVVVVRRAAAAAAADDDAAAAAAAAA^
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^:^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^:^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^:^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^V^^^^^^^^^^^^^^^^^^^^^^^^^V^A^^^^^^R^^^^^^^^:^^D^^^^^^^A^^^R^^^^^^^^^^V^^^^V^V^^^^^^A^^^^A^ARA^^A^^^^A^^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^y^^^^y^^^^^^^y^^^^^^^^^y^^^^^^^y^^^^y:^^^^^^^y^^^^^^^^^^^^^^T^^^^^y^^^^^^^^^^^%q^^^^^^^^^^^^^^^^^^^^^A^^^^^^B^B^^^^^^^^^^^^^^^^^^^A^^^A^^:::::::::::::::::=:=::=^^^^^^^^^^^^B^^^^^^^^^^^^^B^^^^^^^^^^^B^^A^B^R^^^R^^^^^^B^^^^^^^^^^^^H^^H^^:::::::::::::::::::::::::::::::::::::::::::::^^^^^^^^^N^^^^H^^^^^NN^^^^^^^^^^^HH^^^^N^^^^^^^^^^H^^^H^^^^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSySqqqqqqqqyyyyyyyyyyyyyyyyyTyyyyyy^^^^^^^yyyyTTyyyyyyyy:yyyyyyyyyyyyyyyqqqqqyyyyyyyyyyyyyyyqqqq%qqqqyyyyyTyyyyqqqqq^^^^AAAAAAABBBBBBBBBBBBBBBRRRRAABBAAAARRRRBBBBBBBBBBBBBBRRGGGG=GGGGGGGGGBBRBBBBBBBBBBBBBBBBBBBBBBBBBBBBBAABBGGGGGGBBBBBB^^^^HHHHHHHHHHHHHH:HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHXXXX^XXNNNNNHHHHHHNNNNNNNHHHHHHHHHHHHHHNNNNNNHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSqqqqqqqqyyyyyyyyyyyyyyyyTyyyyyyy^^^^^^yyyyTTTyyyyyyy:yyyyyyqqyyyyyyyqTqqyyyyyyyyyTyyyyyyyqqqqqqqyyyyyTTTqyqqqqqq^^^^AAAAAAABBBBBBBBBRBBBBBRRRRBBBBAAAARRRRRBBBBBBBBBBBBBRRGGGG=GGGGGGGGGBBRBBBBBRBBBBBBBBBBBBBBBBBBBBBBBBBGGGGGGGGBBBBBB^^^^HHHHHHHHHHHHHH:HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHXXHHXHHHXXXXXXXXHNHHHHHHHNNNNNNNNNNNHHHHHHHHHHNNNNNHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSqqqqqqqqqqyyyyyyyyyyyyyyyyyyyyyyy^^^^^^^yyyTTyyyyyyyy:yyyyyqqqqyyyyyyqTqqyyyyyyyyyTyyyyyyyqqqqqqqyyyyyqqqqyqqqqqq^^^^AAAAAAABBBBBBBBBRBGGGBBBRRBBBBAAAABBBBBBBBBBBBBBBBBBBBGGGG=GGGGGGGGGGBBBBBBBRBBBBBBBBBBBBBBBBBBBBBBBAGGGGGGGGGGBBBBB^^^^HHHHHHHHHHHHHH:HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHXXXXXHXXXXXXXXXHXXXXXHXXXHHHHNNNNNNNNNNNNHHHHHHHHHNNNNNHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~sS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSS~~~~~~~~~~~~~~~~~~SSSqqqqqqTqqqqqqqyqyyyyyyyyyyyyyyyyyyy^^^^^^^Tyyyyyyyyyyyy:yyyqqyyqqyyyyyqqqqyyyyyyyyyyTTTyyyyyqqqqqqqyyyyyqqqyyyqqyyy^^^^AABAAAABBBBBBBBBBBGGGBBBBBBABBAAABBBBBBBBBBBBBRRRBBBBBGGGG=GGGGGGGGGGBBBBBBBRBBBBBBBBBBBBBBBBBRBBBBBGGGGGGGGGGG#BBBBB^^^HHHH#########___#########HHHHHHHHHHHHHHHXXXXXHXXXXHHXHHXXXXXXXXHXXXXXHHXXXXHHHNNNNNNNNNNNNHHHHHHHHNNNNNHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSSSS~~~~~~~~~~~~~SSSqSSqqTTqqqqqqqqqqyTyyyyyyyyyyyyyyyy^^^^^^^TTqqqyyyyyyyy:yyqqqqqqqqqqqyqqqyyyyyyyyyyTTTTTTyyqTTq%%qqyyyTyyqqqqqqqqyy^^^^ABBBBRRRBBBBBBBBBBGGGBBBBBBABBBABBBBBBBBBBBBABRRRRRBBAAGGG=GGGGGGGGGGBBBBBBBRBBBBBRRRRBBBBBBBBRRBBBAAGGGGGGGGGGRRRBBB^^^HHHH#___________________#HHHHHHHHHXHHHHXXXXXXXXXKKKXXXHXXHKXXXXHXXXXXXHXXXXXXXXXXNNNNNNNNHHHHHHHHHNNNNNHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~SSSsSSSSWSSSSSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSJWSSSSSSS~~~~~~~~~~~SSSSSSqq*Tqyqqqq*qqqyyyyyyyyyyyyyyyyyy^^^^^^^TTqqqqyyyyyyy:yqqqqqqqqqqqqyqqyyyyyyyyyyyyTTyyyyqqqqq%%qqqyyyyyqqyqyqqqyy^^^^BBBBRRRRBBBBBBBBBBBGBBBBBBBBBBBBBBBBBBBBBBBBABRRRBBBAABRGG=GGGGGGGGG###BBBBBBBBBBBRRBBB###BBBBBBBBBAAAGGGGGGGGRRBBBB^^X^HHHH#__Z________________#HHHHHHHHXXXXXXXXXXXKKCKEEEEEEEXEEECEEEEEEXXXXXHXXHXXXHHXHXNNNNNNHHHHHHHHHNNNNNHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSSWJJSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSJJJJ###SSSSS~~~~~~~~~SSSSqqqqqqqqqqqqqqqqyyyyyyyyyyTyyyyyyy^^^^^^^TqqqqqyyyTyyy:yTqqqqqTqqqqqqqyyyyyyyyyyyyyyyyyyyyqqqq%%qqqyyyyyqqqqqqyyyy^^^BBBBBRRBBBBAABBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBABBBBAAAABBBBR=GGGGGGGGGBBBBBBBBBBBBBBBBBBBBBABBBBAAABBBAAAGGGGGGGRBBBBB^^^HHHHH#___________________#HHHHHHXHXXXXXXXXKKECECECCEEEEEEEEEEEEEEEEEEEKKKCKHXXXXHHXXXHHHHHHHHHHHHHHNNNNHHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSSJJJSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~SSSSSJWJWJJJ#W#SSSSSS~~~~~~~~SSSTqqqqqqqqTqqqqqqqqqqyyyyyyTTyyyyyyy^^^^^^^TyqqqqqqTTTqq:TTTqqqTTTqqqqTqyyyyyyyTyy~~~~~yyyyyqqq%%%qqqqyyyyqqTTqyyyyy^^^RBBBRRRBBBBARRRRBBBBBBBBBBBBBBBBBBBBBBBBBBBBBABBBBAAARRBBBR:RBGGGGGBBBBBBBRBBBBBBBBBAAAAARABBBBAAABBBAAAABGGGGRRBBBBB^^^^HHHH#___________________#HHHHHXXHHXHXXXECEEEEEEEEEEEECEEEEKKKKKKKKCKKKKKCKKKXXHHXXXXXXXXXHHHNNNNNNHHHHHHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~SSSSSSWSSSSJJJSsS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~SSSSSWJJJJJSSWW#JSSSSS~~~~~~~~SSSSqqqqqqqqqqq**qqqqyqqqyyyyTTyyyyyyy^^^^^^^Tqqqqqy*TTqq*:TTTqyqqqqqqqqTqyyyyyyyy~~~~~~~~~%yyqqq%yqqqyyyyyyqqqqqqyyyy^y^^BBBBRBBBBBAABBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBAAABBBAAAABBBBR:RBBBBBBBBBBBBBBBBBBBBBBBBBBBBRBBBBBAAABBBAAABBBBBRRBBBBBB^^^^HHHH#___________________#HHHHXXHXXEEEEEEEEEECEECEEEEEEEEKKKKKKKKKKKKKCKEKKKKKKKKXHXXXXXXXXXHNNNNNNHHHHHHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~SSSWSSSS::::::::===============================~~~~~~~~~~~~~~~~~~~~~~~SSSJJJJJJJ:JJWJJJJSSSS~~~~~~~~SSSyqqqqqqqqqqqqqyqqqqqqqyyyyTTyyyyyyy^^^^^^^qqqqqqTTqqyqq:qqqyqqyqqqqqqyyyyyyyyTy~~~~~~~~~%qqqqyqqqqqqyyyyyqqyqqqyyyy^^^^RRBBBBBBAAABBBBBBBBBBBBBBBBBBAARBBBBBBBBBBBAAABBBAAAAABBBR:BBBBBBBBBBBBBBBBBBBBBBBBBB###BBBBBBAAABBAAAABBBBBBBBBBBBBBR::::::_____________________::::::::::::::::::::::::::::::::::::::::::::::::::::::KKKKXXXXXXXXXNNNNNNHHHHHHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSsS~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SsWJJJJJJJ:JJJJJJSSSsS~~~~~~~~SSSSySTqqqqyqqqqqqqqqyqqqyyyyTTyyyyqqy^^^^^^^qqqqqTTTqyyyT:qqqqyqqyqqqqqqqqyyyyTTy~~~~~~~~~%qqqq^qqqqqyyyyyqqqqqqqqyyy^^^^RRRBBBBRAABBBBBBBBBBBBRRBBBBAAARRRBBBBBBRBBBBBBBBBBBAABBBB:BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBAAABBBAABBBBBBBBBBBBBB^R:^HHHH#___________________#HHHHHXHXHEEEEEEEEEEEEEEEEEEEEEKKKKKKKKKKCKKKKKEKKKKKK:KKKKXXXXXXXXXXNNNNNHHHHHHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~SSSS~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSS:SSsS~~~~~~~~~~~~~~~~~~~~~~~~~~SSWWJJJSJ:JJJJJJSSSSS~~~~~~~~SSSSyyyqqqqqqqqqqq%qqqqqqqyyyTTyyqqqqqq^^^^^qqqqqqqqqqyyTT:*yqqqqqqqyqq*qqyqyyyyTT%%~~~~~%%qqqq^^^qqqyyyyyyqqqq%%qqqyy^^^^BBBBBBBBBBBBBBBBBBBBBBBBBBBBBAARRRBBBBBBBBBBBBBBBBBBBBBBBB:BBBBBBBBBBBBBBBBBBBBBBBGGGGGBBBBBBBBABBBBBBBBBBBBBBBBBBBB^^:^HHHH#___________________#HHHXHXXHKEEEEECEEEKKKEEEEEEEEEEKKKKKKKKKKKKKKKKKKKKKK:KKKKKXXXXXXXXXXNNNNHHHHHHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSSS:SSSSSSSSSSSSS~~~~~~~~~~~~~~~~~SSSJJJJSJ:JJJJJSSSSS~~~~~~~~~SSSyyyyqqqqqqqqqqqqqqqqqqyyyyTTTyqqqqqq^^^^^qqqqqqqqqqqqqq:qqqqqqqqqqqqqqqqqyyyyTTyqqqqyqqq*qqq^^^^qqyyyyyyqqqq%qqqqyyy^^^BBBBBBBBBBBBBBBBBBBBBBBBBBBBBGGGRBBBBBBBBBBBBBBBBBBBBBBBBB:BBBBBBBBBBBBBBBB###BGGGGGGGGGBBBBBBBBBBBBBBBBBBBBBBBBBBBB^^:HHHHH#_____________F_____#HHHXXXXKKKKEEEEEKKKKKKKECCEEEEEKKKKKCKKKKKKKKKKKKKKKK:KKCKKKXXHXXXXXXXNNHHHHHHHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSSS:SSSSSSSSSSSSS~~~~~~~~~~~~~~~~~~~SSSJJJs:JJWSSSSSS~~~~~~~~~~SSSSyqqqqqqqyqqqqqqqqqqqqyyyyTTTqqqqqqy^^^^qqqqqqqqqqqqqqq:qqqqqqqqqqqqq%q*qqyyqqTqqqqqqyqqqqqq^^^^qqqyyyyyyqqqqqqqqyy^^^^BBBBBBBBBBBBBBBBBBBBBBBBBBBBGGGGGGBBBRBBBBBBBBBBBBBBBBBBBB:BBBBBBBBBBBBBBBBBBBGGGGGGGGGGGBBBBBBBBBBBBBBBBBBBBBBBBBBB^^:^HHHH#___________________#HHHKKKKKEKEEEEEKCKKKKKKEEECEEEKKKKKKKKKKKKCKCKKKKKKKK:KKCKKKKKKKXXXXXNNHHHHHHHHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSSSS:SSSSSSSSSSSSS~~~~~~~~~~~~~~~~~~~~~SSSSS:SSssSSS~~~~~~~~~~~~SSSySSqqqqqqqqqqqqqqq%qqqyyyyyqqqqqqyyyy^^^qqqqqqqqqqqqqqq:qqqqqqqqqqqqq%qqqyqqyqqqqqqqqqqqqqqq^^^^^qqqqyyyyqqqqqqqqyy^^^^BBBBBBBBBBBBBBBBBBBBBBBBBBBGGGGGGGGBBBBBBBBBBBBBBBBBBBBBBB:BBBBBBBBBBBBBBBBBBBGGGGGGGGGGGBBBBBBBBBBBBBBBBBBBBBBBBBBB^^:^HHHH#___________________#HHHKKKKEEECEEEEKKKKKKKKEEEEEKKKKKKKKKKKKKKKKCKKKKKKCK:KKKKKKCKKEEXX#####HHHHHHHHHHHHHHHNNNNH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~#SSSS#########___#########SSSSs~~~~~~~~~~~~~~~~~~~~S~~~=~S~~~~~~~~~~~~~~~~~SSSqqqqqqqqqqqqyqqqqqqqqqqyyyqqqqqqqyyyyq^qqqqqq#########___#########qqq%qqqqqqyqqyqqqqqqqqqqqq^^^^^qqqqyyyqqqqqqqqyyyyy^^BBBBBBBBBBBBBBBBBBBBBBBBBBBBGGGGGGRRBBBBBBBBBBBB#########___#########BBBBBBBBBBGGGGGGGGGGBBBBBRBBBBBBBRRRRRBBBBBBBBR^^:^HHHH#########___#########HHHKKKKEEEEEEEEKKKKKKKKCEEEKKKKKKKKKKKKKCKKKKKKKKKKKK:KCKEEEEKEEEXX#_>_#HHHHHHHHHHHHHNNNNNNN^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~###SSSS#___________________#SSSSSSS~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~SSSSqy%%y%%qqqqqqqqqqqqqqqqqqqqqyyyyTTqqqqqqqqqq#___________________#qqqqqqqyyqqqqqqqqqqqqTTTTq^^^^^qqqqyTyqqqqqqyqyyy^^^^BBBBBBBBBBBBBBBBBBRRBBBBBRBBBAGABRRRBBBBBBBBBBBB#___________________#BBBBBBBBBBBGGGGGGGGGBBBABRRBBBBBRRRRRRRBBBBBBBR^B:HHHHHHHHHHHHHHHHHHHHHHHHHHHHHKKKKEEEEEEEKKKKKKKKCEEEEKKKCKKKKKKKKKKKKKKKKKKKCKK:KKKKKEEEEEEEHXH:HHHHHHHHHHHNNNNNNNNNNN^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSS#__Z________________#SSSsSSSS~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~SSSqqy%%%%y%qqqqqyyyqqqqqqqqqqqqyyyyTqqqqqqqqqqq#__Z________________#qqqqqqqqqqqqqqqqqqqqqqqqqq^^^^^qqqyyTy*qqqqqqqqyy^^^^BBBBBBBBBBBBBBBBBBRRBBBBBBBBBBBBBBBBBBBBBBBBBBBB#__Z________________#BBBBBBBBBBBBBGGGGGGBBBBBBRBBBBBBBBBBBBBBBBBBBBR^^:^NHHHHHHHHHHHHHHHHHHHHHHHHHHHKKKKEEEEEEEKKKKKKKKEEEEEEKKKKKKKKKKKKKKCKKKKKKCKCK:::::::::::::::::HXHHHHHHHHNNNNNNNNNNNN^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSS#___________________#SSSSSSSSS~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~SSSSSS%%%%%qqyqqqqqqqqqqq%qqqyqyyTyyyqqyqqqqqqqq#___________________#qqqyqqqqqqqqqqqqyyqqqqqqyq*qqqqqqyyyyyqqqqqqqqqyT^^^^BAABBBBBBBBBBBBBBBRRRRRBBBBBBBBBBBBBBBBBBBBBBBBB#___________________#BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBR^^:^NHHHHHHHHHHHHHHHHHHHHHHHHHHHKKKKKEEEEEEKKKKKKKEEEEEECKKKKKKKKKKKKKKKKKCKKKKKKK:KKKKKKKEEEEEKKHHHHHHHHHHHHNNNNNNNNNNNN^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSsSSSS#___________________#SSSSSSSsS~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~SSSqS%%%%qqqqqTTqqqqqqqqq%yqqTTTTTTyyyyqyqqqqqqq#___________________#qqqqqqTqyq*qqqqqqqqqqqqqqqqTqqqqyqqqyyyqqqqyqqqTT^^^^ARAABBBBBBBBBBBBBBRRRRRRBBBBBBBBBBBBBBBBBBBBBBBB#___________________#BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB^^:^NNNNNNNNNNNNNNNNNHXXXXHXKKKKKKKKKKEEEEEKKKKKKKKEEEEEEEKKKKKCKKKKKKKKKKKKKCKKKK:KKKKKKKKKEEKKHXXXXHHHHHHHHNNNNNNNNNNNN^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sSSSSSS^SSS#___________________#SSSSSSSSS~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~SSSqSS%%%qqqqqTTqqqqqqqqqqqqqqqTTTqyyyqqqqqqqqqq#___________________#qqqqqqqqyyqqqqqqqqqqqqqyqyqqqqqqqqqqyyyyqqqqqqqqqy^^^BRBBBBBBBBBBBBBBBBBBBRRBBBBBBBBBBBBBBBBGGGGGBBBB#___________________#BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB^^:^NNNNNNNHHHHHHNNNXXXXXXXKKKKKCKKKKKEEEEEEEKKKKKKKKKKCEEKKKKKKKKKKKCKKKKEEKKKKKK:KKKKEEKKKKKKKKXXXXXHHHHHHHHNNNNNNNNNNN^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~======::::::::::_____________________:::::::::========================================::::::::::::::::::::::::::::::::::::::::::::::::_____________________qqqqqqqqqqqqqqqqqqqqqqqqqqqqqyqqqqqqyyqqqqqqqqqqq^^^^BRRBBBBBBBBBBBBBBB::::::::___::::::::::=====::::_____________________::::::::::___:::::::::::::::::::::::__::::::::::::^NNNNNNHHHHHHHHHHHXXXHHXKKKKKKKKKKKEEECEEECKKKKKKKKKKCEKKKKKKKKCKKKKKKEEEEKKKKK:KKKEEECKKKKKKKHXXXXXHHHHHHHNNNNNHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~SSSS^^SSS#___________________#SSSWSSSSS:~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~SSSqSqTTqqqy*qqqqqyqqqqqqqqqyqqqqqqyTTqqqqqqqqqq#___________________#qqqqyqqqqyqqqyqyqyqqqqqqqqqqqqyqqqqqyqqTTTqqqqqqq^^^^RRRBBBBBBBBBBBBBBB:BBBBBBBBRRBBBBBBBBBGGGGGGGBBB#___________________#BBBBBBBBAARBBBBBBBBBBBBBRRRGGGGBBBBBBRRRRBBBBBB^^^NNNNNNHHHHHHHHHHHHXXXHHKKKKKKKKKKKKKEECEEEEKKKKKKKCKKEEKKKKKKKKKKKKKKKEEEEKKKKE:KKKEEEKKKKKKKKKKXXXXXHXHHHHNNNNHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~SsSS^^SSS#___________________#SSSJSsSJJ:JJSS~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~SSSSSSTy^^qqqyyqqyyyqqyqqqqqq%%qqqqyyyqqqqyyqqqq#___________________#qqqqqqqqqqqqqyyyyqqqqqqqqqqqyyyyqqqyqqqqqTTqqqqqq^y^^BBBBBBBBBBBBBBBBBB:BBBBBBBBBRBBBBBBBBBGGGGGGGBBB#___________________#BBBBBBBBBBRBBBBBBBBBBBBBRGGGGGGGGGGGGGGGRBBBBBB^^^^NNNNNHHHHHHHHHHHXXXXXXKKKKKKKKKKKKKKEEEEEEKKKKKEEEEEEEKKKKKKGGGKKKKKKEEEEKKKKK:KKKEEEKKKKKKKKKKXXXXXXXHHHHNNNNHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~SSSS^JSSS#_____________F_____#SSSJSJJJJ:JJJSS~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~SSSqSS^^^^^^^qqqqyyyqqqqqqq%~~~~~%qyyqqqqyqq*qqq#_____________F_____#qqqqqyqqqqqyyyyyyyqyyyyyyyqqyyyyqqyqqqqq*yTTqqqqq^y^^BBBBBBBBBBBBBBBBBB:RBBBBBBBBBBBBBBBBBBGGGGGGGBBB#_____________F_____#BBBBBBBBBBRBBBBBRRRRRBBBGGGGGGGGGGGGGGGGGRBBBBB^^^^NNNNNHHHHHHHHHHHHXXXXCKKKKKKKKKKKKCKKEECEEKKKKCEEEEEEEKKGGGGGGGGKKKKCEEECKKKKK:KKKEEEKKKKKKKKKKHXHHXXHHHHHNNNHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~SSSSSSSSS#___________________#SSSSSJJJJ:JJJJS~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~SSSSq*^^^^^^^^^^qqqqqyqqqqq~~~~~~~qqq*qqqqqqqqqq#_______________~~__#qqqTqqqqqqqyTTTyyyyyyyyyyyyyyyyyqTTTTqqqqqTTqqqyT^^^^BBBBBBBBBBBBBRRBBR:RRBBBBBBB###BBBBBBBGGGGGGGBBB#___________________#BBBBBBBRRRBBBBBBRRRRRBBBGGGGGGGGGGGGGGGGGRBBBBB^^NNNNNNNHHHHHHHHHHXXXXXXKKKKKKKKKCKKKKKKCEEKKKKKKKKKKKKKKGGGGGGGGGGGKKKKKCEEKCKKK:KKKEEKKKKKKKKKKKKHHHXHXHHHHNNNHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~SSSSsSSS#___________________#SSSSSSJJWJJJJJS~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~SSS*S^^^^^^^^^^^^^^^^qqyyqq%~~~~~%yqqqqqqqqqqqqq#_______________~~__#qqqqqqqqqqqyyyTTyyyyyyyyyyyyyyyyqqqqqqqqqqTqqqqqT^^^^BBBBBBBBBBBBBBBBBB:RBBBBBBBBBBBBBBBBBBGGGGGGGBBB#___________________#BBBBBBBBBBBBBBBBRRRRRBBBGGGGGGGGGGGGGGGGGRBBBBB^^^^NNNNNNHHHHHHHHHHXXXXXKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKGGGGGGGGGGGKKKKKKECKKKKK:KKKKKKCKKKKCKKCKKKXXXHHHHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~SSSSSSS#########___#########SSSSSSSSJJJJJS~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~SSSqS^^^^^^^^^^^^^^^^^qTTTqqq%%qqqqqqyqqqqqqqqqq#########___#########qqqqqq*yqqqqyyyT^yyyyyyyTTTTyyyyyqqqqyqqqqqqqqqTT^^R^BBBBBBBBBAAAAAABBB:BBBBBBBBBBRRRBBBBBBBGGGGGGBBB#########___#########BBBBBBBBBBBBBBBBRRABBBB##GGGGGGGGGGGGGGGGGBBBBB^^^^NNNNNNHHHHHHHHXXXXXXXCCKKCKKKEKKKKKKKKKKKKKKKKKKKKKKKKGGGGGGGGGGGKKKKKKKKKCKKK:KKKCKKKKKKKKKKKKXXXXHXHHHHHHHHHHHHHHNN^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~SSSSSSSSSSSSSSSSSSSSSSSSSSSSS~~~~~S~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~SSSSS^^^^^^^^^^^^^^^^^qTTTTTq%%qqqqqqqqqqqyqqqqqqqqqqqqqqq:qqqqqqqqqqqqqqqqqqqqqqqqyT^TTyyyyTTTTTTyyyyyyqqqyqqqqqq%qTT^^R^BBBBBBBBAAAAAAAABB:BBRRBBBBBRRRRRABBBBBGGGGGGBBBBBBBBBBBBBBBBBBBBBBBBBBBBRBBBBBBBBBBBRAAABBBBBBBBBBGGGGGGGGGGGGBBAAA^^^^NNNNNNNHHHHHHHHHHXXXXXXKKKKCEEEEKKKKKKKKKKKKKKKKKKKKCKGGGGGGGGGGGKCKKKKKKKKKKK:KKKKKKKCKKKKKKKHXXXXHHHHHHHHHHHHNNNNNN^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~SSSSSSSSSSSSSSSSSSSSSSSSSSSS~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~SSSqS^^^^^^^^^^^^^qqqqqqqqqT%y%qqqqyyyy*yqqqqqqqqqqqqqqqqq:qqqqqqqqqqqqqqqqqqq%qqqqqTTTqqyyyyTTTTyyyyyyyyqqyyqyyqqqqqy^^R^BBBBBBBAAAAAAAAABB:BBBBBBBBBRRRRAABBBBBBGGGRBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBAAAABBBBBRBBBBBBBGGGGGGGGGGAAAB^R^^NNNNNNNNNNNNNNNNNXXXXXXHEEECECECEKKKKKKKKKKCKKKKKKKKKKCKGGGGGGGGGKKKEEEEEKKKKK:KKKKKKKKKKKECCEHHHXXXXHHHHHHHHHHNNNNNN^
^~~~~~~~~~~~~~~~~~~~SSSSS~~~~~~~~~=~~~~~~~~~~~~SSSSSSSSSSSSSSSSSSSSSSSSSSS~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~SSSqSq^^^^^^^^^^qqyqyTqqqqqTqqqqqqqqyyyyyqqqyqqqqqqqqqqqqq:qqqqqqqqqqqqqqqqqq%%qqyyTTTqqqyyyyyyqqqqqqyyyyqqqqqyyqqqqqq^^^^BBBBBBBBAAAAAAABBB:RBBBBBBBRRRBBBBAAAAABBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBAAA###BBRRRBBBBBBBGGGGGGGGGGABB^^^^NNNNNNNNNNNNNNNNNXXXXXXXEEEEECEEECKKKKKKKKKKKKKKKCKKKKKEGGGG#####KKKEEEEEKKKKC:KKKCKKKKKKEEEEEXXHXXXHHHHHHHHHHHNNNNNN^
^~~~~~~~~~~~~~~SSSSSsSSSSSsSSs~~~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~SS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~SSSSqq^^^^^^^^qqqqqqTTqqqqqqqqqqqqqqqqyyyyyyqqqyyyqqqqTTqq:qqqyTyyyqqqqq%qq*q%%qqTTTTTqqqyyqqqqqyqqqqyyqyyyqqqqTqqqqqy^^R^BBBBBBBBBBBBBBBBBB:RBBBBBRRRRRBBBBAAAAAABBBBBBBBBBBBBBBBBBBBBBBBBBBBBBRABBBBRBBBBBRBBAAAABBRRRRRBBBBBBBGGGGGGGGGGGBR^^^^NNNNNNNNNNNNNNNNNXXXXXXXEEECEEEEEKKKKKKKKKCKKKKKKKKCKKKGGEKK#_>_#KKKEEEEEKKKKK:KKKKKKKKKKKEEEEEHXXXXHHHHHHHHHHHNNNNNN^
^~~~~~~~~~~~~SS##^^JJJJSWSSSSSSS~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~=~~~~~~~~~~~~~~~~~~~~~~~SSSqqq^^^^^^^q*qqqqqqyyqqqqqqqqqqqqqqqyyyyyyqqqyyyyqqqqq%q:qqqqTyyyqqqqq%%qqq%%qqqyqqqqyqq*qqqy%%%%%yqqqyyyqqqq*qyqqyy^y^^BBBBBBBBBBB###BBBB:RBBBBBBBBBBBBBBAAAAABBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBRBBBBBBBBAAABBBBBRR###BBBBBGGGGGGGGGGGGG^^^^NNNNNNNNNNNNNNNNNXXXXXXXEEEEEEEKKKCKCKKKKKKKKKKKKKKKKKKKEEEKCK:KKKKCKKEEEKKKKK:KKKKKKKKKKKKKKKKHXXXHHHHHHHHHHHHNNNNNN^
^~~~~~~~~~~~SSSJ^^^JJWJSSSSSSSSSS~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSS:SSSSSS~~~~~~~~~~~~~~~~~SSSqyS^^^^^^qqq*qqTqyyyqqqqqqqqqqqyyqyyyyyyyyqqqqqqqqyqqqq:qqqyyyyyqqqqq%%qqq%%%q*qqqqTTqqqqqqqy%%%%qqyqyTyqqqqqqqqqyy^^^^BBBBBBBBBBBBBRRBBB:RBBBBBBBBBBBBBBAAARABBBBBBBBBBBBBBBBBBBBGGGGGGBBBBBBBBBBBRBBBBBBBBBBBBBBBBBBBBBBBBBBBGGGGGGGGGGGG^^^^NNNNNNNNNNNNNNHHHXXXXXXHEKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKEEKK:KKKKKKKKEKKKKKK:KKKKKKKKKKKKKKKKXXXXHHHHHHHHHHHHHNNNNN^
^~~~~~~~~~~SSsS#^^^JJJJSSJJSSSWSsS=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSS:SJSsSSSS~~~~~~~~~~~~~~~SSSqqS^^^^^^qqqqqqTqyqqqTqqqqqqqyyyyyyyyyyyyyyqqyqqqqyqqqq:yqyyyyyq*q%%%%qqqq%y%qqqqqqTTqqqqqqTTT%%%qqqyTTyqqqyyq*qqqqy^^^BBBBBBBBBBBBRRRRRR:RBBBBBBBBBBBBBBBBARRBBBRRBBBBBBBBBBBBGGGGGGGGGGBBBBB###BBRBBBBBBBBBBBBBBBBBBBBBABBBBBGGGGGGGGGGGGGG^^NNNNNHHHHHHHHHHHHHHHXXXXCKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKK:KKKKKKKKKKKKKCK:KKKKKKKKKKKKKKKXXXXXXXHHHHHHHHHHHHHHHH^
^~~~~~~~~~SSSSSW^^^JJJJWJJJJSSSSSS:~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSJSSSWWS:WSSWJSSSSS~~~~~~~~~~~~~SSSqSSq^^^^qqqyqqqTyqqqqTqqqqyqqqyyyyyyyyqqqqyqqTqqqqyqqqq:qyyyyyqqqq%%%qqqqq%%%qqqqyqqTqqqqqqqyT%qqqqyyyyyyqyyyqqqyqq^y^^BBBBBBBBBBBBRRRBBB:BBBBBBBBBBBBRBBBAAAABBBRRBBBBBBBBBGGGGGGGGGGGGGGBBBBBBBBBRBBBBBBBBBBBBBBBBBBBBAAABBB#GGGGGGGGGGGG^^^^HHHHHHHHHHHHHHHHHHHXXXXXXKCKKKKKKKKKKKKKKKKKKKKKKKKKKCKKKKKKKK:::::::::::::::::KCKKKKKKKKKKKKXXXXXXXHHHHHHHHHHHHHHHHH^
^~~~~~~~~SSSSSSS^^^JJJSSJJJJSSSSSS:~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~sSSSSSSSSS:SSSWJJJSSSS~~~~~~~~~~~~SSSSSqq^^^^qqqqqqqyyqyqqqqyqqyqqqqqyyyyyqqqqqqqTTqqqqqyqqq:qyyyyyqqqq%%%qqqyqq%qqqyyyyqq*qqqqq*qqqqqqqyyyyyyyyyyqqqqqq^y^^BBABBBBBBBBBBBBBBB:BBBBBBBBBBBBRRBBAABBBBBRRBBBBBBBGGGGGGGGGGGGGGGGBBBBBBBBBBBBBBBRBBBBBBBBBBBBBBBAABBBBGGGGGGGGGGGG^^^^HHHHHHHHHHHHHHHHHHHHHXXXXEKKKKKKKKKKKKKKKKKKKKKCKKKKKCKKCKKKKKKKKKKKKKKCKKKKKCKKKKKKKKKKKKKKXXXXXXXXHHHHHHHHHHHHHHHHH^
^~~~~~~~~SSSJSS^^^^SJSSSJJJJSSSSSS:~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSS:WSSSJJJJJSS~~~~~~~~~~~~SSSSSqq^^^qqTTTTyqqqqqqqqqqqqyqqqqqqqqqTqqqqqTTTTqqqyqTq*q:qyyyyyqqqqqq%%qqqqqyqyyyyyyyyyTTqqqq^^%%~~~yyyyyyyy*qqqqqqy^^^^BAABBBBBBBBBBBBBBB:BBBBBBRBBBABRRBBAABBBB#RRBBBBBBBBBBGGGGGGGGGGGGGBBBBBBBBBBAABBRRRBBBBRBBBBBBBBBAABBBRGGGGGGGGGGGG^^^^HHHHHHHHHHHHHHHHHHHXXXXXXEKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKCKKKKKKKKKCKKKKKKKKKKKKKKKKKKKKKKKKXXXXHXXHHHHHHHHHHHHHHHHHH^
^~~~~~~~~SSSJJS^^^^^#####JJJSSSSSS:~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSS:SSSJJJJJJSS~~~~~~~~~~~~SSSSyyq^^^qqqqyyyq#####qqqq*qyqqqqqqqqqTqq%%%%%TTqqqqqqqyq:qyyyyyqqqqqq%%qqyyqqqyyyyyyyyyyTqqq^^y~~~~~~~yyyyyyqqqqyyqy^^^^BBABBBBBBBBBBBBBBB:BBBBBBBBBBBBBBBBBBBBBRBBBBBBBBBBBBBBBGGGGGGGGGGGBBBBBBBBBBBBBBBBBBBBBRBBBBBBBBBAABBBAGGGGGGGGGGGG^^^^HHHHHHHHHHHHHHHHHHHXHHHXXEEKKKCKKKKKKKKKKKKKKKKKCKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKKXXXXHHHHHHHHHHHHHHHHHHHHH^
^~~~~~~~~SSSSSW^^^^^#_>_#JJJJSSSSS=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSSSSWSSJJJJJSS~~~~~~~~~~~~SSSTSqq^^^qqqqyyyq#_>_#Tyqqqq*qqqqqqqqyTqqq%%%%qTTqqqqqyqq:qyyyTyqqqqqqqqqqyyqqqyyyyyyyyyyyyyqq^y~~~~~~~yyyyyyqqqqqqqq^^^^BBBBAABBBBRBBBBBBB:BBBBBBBBBBBBBBBBBBBBRRBBBBBRBBBBBBBBBBGGGGGGGGGGBBBBBBBBBRRBBBBBBBBBBRBBBBBBBBBAABBBAGGGGGGGGGGBB^^^^HHHHHHHHHHHHHHHHHHHHHXHXXXEKKKKKKCKKKKKKKKKKKKKKKKKKKKKKCKKKKKKKKKKKKKKKKKKKKKKKCKKKKKKKKKKXXXXHXXHHHHHHHHHHHHHHHHHHH^
^~~~~~~~~~SSSSSS^^^^JS:JWJWJJJSSSS=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSS###SSSSSWSSJJJJSS~~~~~~~~~~~~SSSTTTTT^^yqqqqqyqqq:qTTTTTTqqqqqqqqqqTTyqqq%%%qTTTTqqyyyy:qqyyTyqqqqqqTTyqqqqqyyyyyyyyyyyyyyqyyy~~~~~~~yTTTTyyqqqqqyy^^^^ABBAAAAB#####BBBBB:BBBBBBBBBBBBBABBBBBBRRBBBBBRRBBBBBBBBBBGGGGGGGGGGBBBBBBBRRRBBBBBBBBBBRRBBBBBBBAAABBBAAGGGGGGGBBBB^R^^HHHHHHHHHHHHHHHHHHHHHHXXHHHHXKKKKKCKCKKKKKKKKKKKKKKKKKKCKKKKKKKKKKCKKKKKKCKCKKKKKKKKKKKKKKKXXXHHXHHHHHHHHHHHHHHHHHHHH^
^~~~~~~~~~~SSSSSS^^^JJ:JJJJJSSSSS~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSsSSS#JJSSSSSSSJSSS~~~~~~~~~~~~~SSSTSSTqyyyyqqqqqqqq:qTyqqqqqqyqqqqqyqqqqqqqq%qqqqqqqqyyyy:qqqqTqqqq%%qqTyqqqyyyyyyyyyyyyyyyyqyyTyy~~~yyyyyyyyyyqqT*yy^yAAAAAAAAAA#_>_#BBBBB:BBBBBBBBBBBBBBBB###BRRBBBBBRR##BBBBBBBBRGGGGGGGGGBBBBBBBBRBBBBBBBBBBBBBBBBBBBBAAAABAAAAGGGBBBBBBBB^^^HHHHHHHHHHHHHHHHHHHHHHHXXHXXXXHKKCKKKKKKKKKKKKKKKKEKCKKKKKKKKKKKKKKKCKKKKKKKKKKKKKKKKKKKKKXXXXHXHHHHHHHHHHHHHHHHHHHHH^
^~~~~~~~~~~~~SSsSSS^JJ:JJJSSSSSS~~=~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSS##SSJSSSSSSSSSS~~~~~~~~~~~~~~SSSqSSqqyyyqqyqTqqqq:qqqqqqyqqqqqq*yqqqqqqqyq%qqqqqqqqyyyy:qqqTTqqqq%%qyqqqqqyyyyyyyyyyyyyyyyqqTTyyyyyyyyyyyyyyTTTTqyy^^^^AAAAAAAAAB:BBBABBB:BBBBBBBBBBBBRBBBBBBBBRBBBBBBBBBBBBBBBBBBGGGGGGGGGGBBBBBBBBBBRRBBBBBBBBBBBBBBBBBBAAAAAAAAABBBBBBBB^^^^HHHHHHHHHHHHHHHHHHHHHHHXXXXXXXXXKKKCKKKKKKKKKCKKKKEEKKKEEEKKKKKKKKKKKKKKKKKKKKKKKKKKECXXXHXXXXHHHHHHHHHHHHHHHHHHHHHHH^
^~~~~~~~~~~~~~~~SSSSSS:::::::======~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSSSSSSSSSS~~~~~~~~~~~~~~~~~SSSSSSqqqyqqqqTTqqqq:::::::::::::::::::::::::::::::::::::::qqyTTTqyq%TTqqqyyyyTyyyyyTyyyqqqqqqyTTyyyyyyyyyyyyyTTTTTTyy^^^^AAAAAAAAAA:BBRAABB:BBBBBRRRBBBRRRRRBBBBBBBBBBBBBBBBBBBBBBBBBGGGGGGGGGGBBBBBBBBBRRRRBBBBBBBBBBBBBBRBAAAARBAAAABBBBBBB^^HHHHHHHHHHHHHHHHHHHHHHHHXXXXHXXXXXXKKKKKCKKKKKKKKKKEEEKKKKEKCKKKKKKKKCKKKKCKCKKKKKKKXHHHXXXHHXHHHHHHHNNNNNNNHHHHHHHHHHH^
^~~~~~~~~~~~~~~~~~ss~~~SSS~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SS~~~~~~~~~~~~~~~~~~~~~~~SSSqySqqqqqqqqqTqqqqqyqqqqqyyyyqqqqq%qqqqq%%qqqqqqqqqyyqqqqqqqqqqqqq%Tqyqyyyyyyyyyyyqqqqqqqqqqqqyyyyyyyyyy^^^yyyyTTyyy^^^^AAAAABBBBB:BRRABBB:BBBBBRRRBBBRRRRBBBBBBB###BBBBBBBBBBBBBBBBGGGGGGGGGGGBBBBB###RRBBBBBBBBBBBBBBBBBBAAAARBBAABBBBBBBB^R^^HHHHHNNNNNNNHHHHHHHHHHHHHHHXXXXXXKCKKKKKKKKKKCKEEEECKKKKKKKKKKKKKKKKKKEEEKKKKKKKKXXXXXXXXXHHHHHHHHNNNNNNNNNNNHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSqSqqqqqqyqqqqqqqqqqqqqqyyyyyqqqqqqqqqqqqqqTqqqqqqqyyqqqqq%%yqyqqq%%qqqyyyyyyyyyyyyqqqqqqqqqqqyyyyyyTyy^^^^^yyyyTyyyy^^^BAAABBBBBR:::::::::BBBBBRRRRRRRRRBBBBBBBRRBBBBBBBRRBBBBBBBBBGGGGGGGGGGGGGGGGBBBBBBBBBBBBBBBBBBGGGGGGBBRRRRRBBBBBBBBB^^^^HHHHHNNNNNNNHHHHHHHHHHHHHHHXXXXXXXKKKKEEEEKKCKEEEEEKKKKKKKCEKKKKKEKKKKEEEKKKKKKKXXXXXXXXHHHHHHHHHHNNNNNNNNNNNHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSSqSqqqqqqqyqyqqqqqqqqqyyyyyyqqqqTTTqqqqqqqTTqqqyyy*qqqTTT%%qqqqqqq%qqqqqqyyyyyyyyqqqqqqqqqyqqqyyyyyTTT^^^^^^yyyTyyy^^^^BBABBBBBBRRRRRBBBBBBBBBBRRRRRRRRBBBBBBBBRRBBBBBBRRRBBBBBBBRBGGGGGGGGGGGGGGGGGBBBBBBBBBBBBBBBBBGGGGGGGBRRRRRBBBBBBBBB^^^^HHHHHNNNNNNNHHHHHHHHHHHHHHHHHXHXXXXHXXHEEEKKKKKEEEEKKKKKKKKEEKKKEEEEEECEEKKKKKKKHXXXXXXXXHHHHHHHHHNNNNNNNNNNNHHHHHHHH^
^~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~SSSqqyqqqqqqyqqqqqqqyqqqyyyyyyTqyqqqTq%%qqqqqqqqqyyyy*qqqTTq%%qqqqqqqqqqqqqqyyyyyyyq*qyqqqqqqyqqqyyyyyTyy^^^^^^yyyyyyyy^^^BBBBBBBBBBRRRRBBBBBBBBBBBBRRRRRRBBBBBBBBBBBBBBBBBBBBBBBBBBRBGGGGGGGGGGGGGGGGGBBBBBBBBBBBRBBBBGGGGGGGGBRRRRRBBBBBBBBB^^^^HHHHHHNNNNNNHHHHHHHHHHHHHHHHHHHXXXXXXXXKCKKKKKKKKEEEEEKKKKEEEEEEEEEEEEEEEKKKKKKKXXXXXXXXHHHHHHHHHHNNNNNNNNNNNNHHHHHHH^
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
WORLD
}

# ---------------------------------------------------------------------------
#  Module 06 - start: pick the main loop for the mode the arguments chose
# ---------------------------------------------------------------------------
shopt -u patsub_replacement 2>/dev/null
# SHELLMMO_LIB=1 + "source shellmmorpg.sh": load every function and table, start nothing (tests)
[[ $SHELLMMO_LIB == 1 ]] && return 0 2>/dev/null
case $MODE in
  world)  server_main ;;
  server) dedicated_main ;;
  *)      client_main ;;
esac
