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
