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
#  ./shellmmorpg.sh --admin add|remove|list [NAME]   who is admin on this server
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

VERSION="6.4"
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
        if (t == "ALOAD" || t == "ASAVE" || t == "ADM") { if (who() != "srv") next }
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
      ALOAD|ASAVE|ADM) [[ $me == srv ]] && continue ;;
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
    --admin) MODE=admin ADM_OP=$2 ADM_ARG=""; [[ -n $2 ]] && shift
             if [[ $ADM_OP == @(add|remove) ]]; then ADM_ARG=$2; [[ -n $2 ]] && shift; fi ;;
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
