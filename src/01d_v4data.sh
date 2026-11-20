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
