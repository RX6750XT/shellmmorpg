# ---------------------------------------------------------------------------
#  Module 01h - v8.0 data: Beyond the Edge. The level cap rises to 50. Four new
#  lands east of everything (the world grows to 600x200): the Shroudmarch
#  (40-42), the Gilded Expanse (42-45), the Rimewastes (45-47) and the Aether
#  Reach (47-50) - 24 creatures, 8 rare elites, 4 world bosses, 4 towns, a new
#  faction (the Horizon Watch), 5 dungeons and a second raid (the Sundered
#  Sky), gear tiers 13-15, 10 materials, 25 uniques, 5 mounts, a fifth room at
#  the inn, act III of the story, 4 questlines, collectables and achievements.
#  Pure data, appended to the tables before it (indexes never move). Runs after
#  01g - the classifier has run already, so every new creature names its own
#  element here.
# ---------------------------------------------------------------------------
MAXLVL=50 MAXTIER=15 MYTH_LVL=50 PROF_MAX=50
TIER_Q+=(Mythforged Primordial Ascendant)                   # tiers 13-15: levels 42, 46, 50 (tier_for)
_SL+=(50) _SH+=(4800) _SD+=(255) _SX+=(4400) _SG+=(360)    # base_stats up to level 50

m8() {  # var name glyph color level hp% dmg% aggro move atk emoji  el weak resist ability range [healer]
  m4 "$1" "$2" "$3" "$4" "$5" 0 "$6" "$7" "$8" "$9" "${10}" "${11}"
  local t=${!1}
  M_EL[t]=${12} M_WK[t]=${13} M_RS[t]=${14} M_AB[t]=${15/-/} M_RNG[t]=${16:-0} M_HEALR[t]=${17:-0} M_SUMM[t]=0
}
mb8() {  # var name glyph color level boss(0|1|2|w) hp% dmg% aggro move atk emoji  el weak resist ability range
  m4 "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" "$9" "${10}" "${11}" "${12}"
  local t=${!1}
  M_EL[t]=${13} M_WK[t]=${14} M_RS[t]=${15} M_AB[t]=${16/-/} M_RNG[t]=${17:-0} M_HEALR[t]=0 M_SUMM[t]=0
  (( M_BOSS[t] == 1 )) && M_SUMM[t]=1
  return 0
}
#  elements: 0 physical 1 fire 2 frost 3 nature 4 shadow 5 holy 6 arcane

# --- the creatures of the four lands ---------------------------------------------------------------------------
#   var        name                  gly color         lvl  hp% dmg% ag move  atk  emoji  el wk rs ability rng heal
m8 SH_STALK   "Mist Stalker"          s "1;38;5;250"     40  100  110  9  340 1000 🐺     4 5 4 bleed
m8 SH_WIGHT   "Bog Wight"             W "1;38;5;108"     41  130  105  6  600 1300 🧟     4 5 3 weaken
m8 SH_WISP    "Lantern Wisp"          w "1;38;5;222"     40   80  110  9  380  900 🏮     1 2 1 burn   5
m8 SH_HAG     "Shroud Hag"            H "1;38;5;139"     41   90  110  7  520 1200 🧙     4 5 4 weaken 5   1
m8 SH_LEECH   "Void Leech"            l "1;38;5;97"      42  110  105  6  640 1200 🐛     4 5 4 drain
m8 SH_TREANT  "Hollow Treant"         T "1;38;5;95"      42  170  110  5  820 1600 🌳     3 1 3 stun
m8 GE_SCORP   "Gilded Scorpion"       x "1;38;5;220"     42  110  110  8  380 1000 🦂     3 1 3 poison
m8 GE_BASIL   "Sunscale Basilisk"     b "1;38;5;214"     43  130  110  7  480 1200 🦎     1 2 1 stun
m8 GE_DJINN   "Mirage Djinn"          J "1;38;5;123"     43  100  110  8  420 1100 🧞     6 0 6 weaken 5
m8 GE_GUARD   "Tomb Guardian"         G "1;38;5;180"     44  170  110  5  800 1600 🗿     5 4 5 stun
m8 GE_PRIEST  "Sunsworn Priest"       P "1;38;5;229"     44   90  110  8  520 1200 👳     5 4 5 burn   5   1
m8 GE_WURM    "Dune Wurm"             W "1;38;5;137"     45  160  115  6  600 1400 🐍     0 6 0 bleed
m8 RW_WOLF    "Rime Wolf"             w "1;38;5;195"     45  100  110  9  330 1000 🐺     2 1 2 chill
m8 RW_TROLL   "Glacier Troll"         T "1;38;5;153"     46  170  110  6  680 1500 👹     2 1 2 stun
m8 RW_WYRM    "Frost Wyrmling"        d "1;38;5;117"     46  110  110  8  380 1100 🐲     2 1 2 chill  4
m8 RW_SHAMAN  "Rimeborn Shaman"       S "1;38;5;45"      46   90  110  7  520 1200 🧙     2 1 2 chill  5   1
m8 RW_WRAITH  "Ice Wraith"            R "1;38;5;189"     47   90  115  8  460 1100 👻     2 1 2 weaken 5
m8 RW_MAMMOTH "Mammoth Bull"          M "1;38;5;137"     47  190  110  5  700 1600 🦣     0 1 -1 stun
m8 AR_ROC     "Storm Roc"             R "1;38;5;229"     47  110  110  9  320 1000 🦅     6 0 6 stun
m8 AR_DRAKE   "Aether Drake"          D "1;38;5;141"     48  130  115  8  380 1100 🐉     6 4 6 burn   4
m8 AR_SENT    "Sky Sentinel"          S "1;38;5;250"     49  180  110  6  720 1500 🤖     6 0 6 stun
m8 AR_SERAPH  "Star Seraph"           A "1;38;5;230"     49   90  115  9  460 1100 👼     5 4 5 weaken 5
m8 AR_HORROR  "Rift Horror"           H "1;38;5;99"      50  140  115  8  480 1200 👾     4 5 4 drain
m8 AR_GOLEM   "Aetherglass Golem"     G "1;38;5;159"     50  200  115  5  800 1700 💎     6 0 6 weaken
WORLD_TYPES+=($SH_STALK $SH_WIGHT $SH_WISP $SH_HAG $SH_LEECH $SH_TREANT $GE_SCORP $GE_BASIL $GE_DJINN $GE_GUARD $GE_PRIEST $GE_WURM
              $RW_WOLF $RW_TROLL $RW_WYRM $RW_SHAMAN $RW_WRAITH $RW_MAMMOTH $AR_ROC $AR_DRAKE $AR_SENT $AR_SERAPH $AR_HORROR $AR_GOLEM)
L80_SH="482 152 597 197" L80_GE="482 102 597 147" L80_RW="482 52 597 97" L80_AR="482 2 597 47"   # the four lands
ZONES+=("$SH_STALK $L80_SH 7" "$SH_WIGHT $L80_SH 6" "$SH_WISP $L80_SH 5" "$SH_HAG $L80_SH 4" "$SH_LEECH $L80_SH 5" "$SH_TREANT $L80_SH 4"
        "$GE_SCORP $L80_GE 7" "$GE_BASIL $L80_GE 5" "$GE_DJINN $L80_GE 4" "$GE_GUARD $L80_GE 4" "$GE_PRIEST $L80_GE 4" "$GE_WURM $L80_GE 5"
        "$RW_WOLF $L80_RW 7" "$RW_TROLL $L80_RW 5" "$RW_WYRM $L80_RW 5" "$RW_SHAMAN $L80_RW 4" "$RW_WRAITH $L80_RW 5" "$RW_MAMMOTH $L80_RW 4"
        "$AR_ROC $L80_AR 6" "$AR_DRAKE $L80_AR 5" "$AR_SENT $L80_AR 5" "$AR_SERAPH $L80_AR 5" "$AR_HORROR $L80_AR 5" "$AR_GOLEM $L80_AR 4")
UNDEAD+="$SH_WIGHT $RW_WRAITH "
QI_NAME+=([$SH_STALK]="Mist Pelt" [$SH_WIGHT]="Bog Lantern" [$SH_WISP]="Lantern Flame" [$SH_HAG]="Shroud Thread"
  [$SH_LEECH]="Void Ichor" [$SH_TREANT]="Hollow Heartwood" [$GE_SCORP]="Golden Stinger" [$GE_BASIL]="Sunscale"
  [$GE_DJINN]="Mirage Glass" [$GE_GUARD]="Tomb Seal" [$GE_PRIEST]="Sun Sigil" [$GE_WURM]="Wurm Tooth"
  [$RW_WOLF]="Rime Pelt" [$RW_TROLL]="Glacier Tusk" [$RW_WYRM]="Wyrmling Scale" [$RW_SHAMAN]="Rime Totem"
  [$RW_WRAITH]="Frozen Wail" [$RW_MAMMOTH]="Mammoth Wool" [$AR_ROC]="Storm Plume" [$AR_DRAKE]="Aether Scale"
  [$AR_SENT]="Sentinel Core" [$AR_SERAPH]="Starlit Feather" [$AR_HORROR]="Rift Eye" [$AR_GOLEM]="Aetherglass Shard")

# --- five dungeons and their bosses ---------------------------------------------------------------------------
#   var         name                          gly color                    lvl boss hp%  dmg% ag move atk  emoji  el wk rs ability rng
mb8 E_LANTERN  "Abbey Lanternbearer"           L "1;38;5;222;48;5;58"      41 2  420 120  9 520 1200 🏮     1 2 1 burn   4
mb8 B_ABBESS   "Abbess Morwyn the Veiled"      M "1;38;5;231;48;5;96"      42 1 1800 120 10 560 1200 🧕     4 5 4 weaken 5
mb8 E_GILDED   "Gilded Champion"               C "1;38;5;220;48;5;94"      43 2  440 120  9 520 1200 🤺     5 4 5 bleed
mb8 B_RAMAHET  "Ramahet the Sun King"          R "1;38;5;231;48;5;136"     44 1 1900 120 10 560 1200 🤴     5 4 5 burn   5
mb8 E_RIMEG    "Rimeguard Captain"             C "1;38;5;195;48;5;24"      46 2  460 120  9 560 1300 💂     2 1 2 chill
mb8 B_SKADI    "Skadi, the Winter Unending"    S "1;38;5;231;48;5;31"      47 1 2000 122 10 560 1200 👸     2 1 2 chill  5
mb8 E_ASTRO    "Clockwork Astrolabe"           A "1;38;5;229;48;5;60"      48 2  480 122  9 600 1300 🤖     6 0 6 stun
mb8 B_STARW    "The Starwright"                W "1;38;5;231;48;5;54"      49 1 2100 122 10 560 1200 🧙     6 4 6 weaken 5
mb8 E_EDGEW    "Edgewalker"                    E "1;38;5;189;48;5;53"      50 2  500 125 10 460 1100 🧛     4 5 4 bleed
mb8 B_OBLIV    "Oblivion, the Last Horizon"    O "1;38;5;16;48;5;189"      50 1 2400 125 11 600 1200 🌑     4 5 4 weaken 5
D80=$NDT
D_NAME+=("Shroud Abbey" "Tomb of the Sun Kings" "Hall of Endless Winter" "The Starwright's Observatory" "The World's Edge")
D_REQ+=(41 43 46 48 50)
D_POOL+=("$SH_WIGHT $SH_HAG $SH_WISP $SH_LEECH" "$GE_GUARD $GE_PRIEST $GE_SCORP $GE_WURM" "$RW_WRAITH $RW_TROLL $RW_SHAMAN $RW_WYRM"
         "$AR_SENT $AR_SERAPH $AR_DRAKE $AR_GOLEM" "$AR_HORROR $AR_GOLEM $AR_SERAPH $SH_STALK")
D_BOSS+=($B_ABBESS $B_RAMAHET $B_SKADI $B_STARW $B_OBLIV) D_ELITE+=($E_LANTERN $E_GILDED $E_RIMEG $E_ASTRO $E_EDGEW)
D_ENTX+=(584 584 584 584 584) D_ENTY+=(184 134 84 10 38)
D_WHERE+=("the Shroudmarch, east of Lanternfall" "the Gilded Expanse, east of Sunhollow" "the Rimewastes, east of Rimeholt"
          "the Aether Reach, north-east of Zenith" "the Aether Reach, east of Zenith - the very edge of the world")
D_WALL+=("38;5;96" "38;5;178" "38;5;153" "38;5;141" "38;5;189") D_FLOOR+=("38;5;236" "38;5;94" "38;5;24" "38;5;17" "38;5;16")
D_WE_X+=(🟪 🟨 🟦 🟪 ⬛) D_W+=(120 124 126 128 132) D_H+=(42 44 44 44 46) D_ROOMS+=(18 18 19 19 20) D_CHESTS+=(5 5 5 5 6)
NDT=${#D_NAME[@]}

# --- the second raid: the Sundered Sky (Aurelion) -------------------------------------------------------------------
mb8 RD2_ADEPT  "Sunsworn Adept"                a "1;38;5;229"              50 0  110 115  9 420 1100 🧝     5 4 5 burn   5
mb8 RD2_COLOS  "Gilded Colossus"               C "1;38;5;220"              50 0  240 120  6 700 1600 🗿     5 4 5 stun
mb8 RD2_GRIF   "Skyborn Griffon"               G "1;38;5;230"              50 0  130 115  9 340 1000 🦅     6 0 6 bleed
mb8 RD2_KNIGHT "Dawnsworn Knight"              K "1;38;5;223"              50 0  160 115  8 480 1300 🤺     5 4 5 -
mb8 RD2_WARD   "Sky Warden"                    W "1;38;5;231;48;5;136"     50 2  750 125 10 520 1200 👼     5 4 5 stun
mb8 RD2_AUR    "Aurelion, the Sundered Sun"    A "1;38;5;16;48;5;220"      50 1 4800 122 12 600 1200 🌞     1 2 1 burn
M_RAID[$RD2_AUR]=2
D_NAME+=("The Sundered Sky") D_REQ+=(50) D_POOL+=("$RD2_ADEPT $RD2_COLOS $RD2_GRIF $RD2_KNIGHT")
D_BOSS+=($RD2_AUR) D_ELITE+=($RD2_WARD) D_ENTX+=(500) D_ENTY+=(8) D_WHERE+=("the Aether Reach, north-west of Zenith (raid)")
D_WALL+=("38;5;220") D_FLOOR+=("38;5;130") D_WE_X+=(🟧) D_W+=(104) D_H+=(42) D_ROOMS+=(10) D_CHESTS+=(3)
NDT=${#D_NAME[@]} RAID2_DT=$(( NDT - 1 ))
declare -A D_RAID=([$RAID_DT]=1 [$RAID2_DT]=2)               # dungeon type -> raid number
RAID_NAME=("" "Nyxara, Queen of the Eclipse" "Aurelion, the Sundered Sun")
RAID_ANN=("" "The sky is clear again." "The sun rises whole again over the Aether Reach.")
RAID_SHIELD=("" "hides behind a shield of night - kill her guards!" "wraps himself in sunfire - kill his wardens!")

# --- four world bosses -------------------------------------------------------------------------------------------
mb8 W_GRIM     "Grimvane the Mistlord"         G "1;38;5;231;48;5;59"      42 w 2200 115 10 520 1200 👻     4 5 4 weaken 5
mb8 W_KHEPRA   "Khepra the Golden Colossus"    K "1;38;5;16;48;5;220"      45 w 2400 118 10 700 1500 🪲     5 4 5 stun
mb8 W_FROST    "Frostmaw the Glacier Titan"    F "1;38;5;231;48;5;31"      47 w 2500 118 10 650 1500 🦣     2 1 2 chill
mb8 W_ZEPH     "Zephyrion the Storm Eternal"   Z "1;38;5;231;48;5;61"      50 w 2600 120 11 400 1100 🐉     6 0 6 stun   5
UNDEAD+="$W_GRIM "
WB80=${#WB_LIST[@]}
WB_LIST+=($W_GRIM $W_KHEPRA $W_FROST $W_ZEPH)
WB_RECT+=("$L80_SH" "$L80_GE" "$L80_RW" "$L80_AR")
WB_ADDS+=("$SH_WIGHT $SH_WIGHT $SH_HAG" "$GE_GUARD $GE_GUARD $GE_PRIEST" "$RW_WOLF $RW_WOLF $RW_TROLL" "$AR_ROC $AR_ROC $AR_DRAKE")

# --- two rare elites for every land --------------------------------------------------------------------------------
R80=${#M_NAME[@]}
add_rares "The Drowned Lamplighter:$SH_WISP:42:562:160" "Mother Mire:$SH_HAG:42:500:182" \
          "Sekhet the Sunscale:$GE_BASIL:44:506:110" "The Glass Wurm:$GE_WURM:45:566:140" \
          "Hraeth the Pale Wolf:$RW_WOLF:46:500:90" "Old Ironhide:$RW_MAMMOTH:47:566:60" \
          "Nimbus Rex:$AR_ROC:49:500:34" "The Last Watcher:$AR_HORROR:50:566:30"
for (( _t = R80; _t < ${#M_NAME[@]}; _t++ )); do             # (the classifier ran already: they take their kind's element)
  _b=${RARE_BASE[$_t]}
  M_EL[_t]=${M_EL[_b]} M_WK[_t]=${M_WK[_b]} M_RS[_t]=${M_RS[_b]} M_AB[_t]=${M_AB[_b]} M_RNG[_t]=${M_RNG[_b]} M_HEALR[_t]=0 M_SUMM[_t]=0
done; unset _t _b
NRARE=${#RARE_T[@]}
NM=${#M_NAME[@]}

# --- ten materials for levels 40-50, and their nodes -------------------------------------------------------------
M80=${#MAT_NAME[@]}
MAT_NAME+=("Shadowsteel Ore" "Sunbrass Ore" "Aetherium Ore" "Gloomlily" "Goldthorn" "Frostpetal" "Skybloom"
           "Mistfin Eel" "Golden Koi" "Glacier Pike")
MAT_VAL+=(120 150 220 110 130 150 210 100 150 180) MAT_RARE+=(1 1 2 1 1 1 2 0 1 1)
NMAT=${#MAT_NAME[@]}
MAT_PK+=(1 1 1 2 2 2 2 0 0 0)
MAT_GRP[1]+="$M80 $(( M80 + 1 )) $(( M80 + 2 )) " MAT_GRP[2]+="$(( M80 + 3 )) $(( M80 + 4 )) $(( M80 + 5 )) $(( M80 + 6 )) "
MAT_GRP[0]+="$(( M80 + 7 )) $(( M80 + 8 )) $(( M80 + 9 )) "
N80=${#M_NAME[@]}
M_NAME+=("Shadowsteel Vein" "Sunbrass Vein" "Aetherium Vein" "Gloomlily" "Goldthorn" "Frostpetal" "Skybloom")
M_GLY+=(◆ ◆ ◆ ♣ ♣ ♣ ♣) M_COL+=("1;38;5;60" "1;38;5;178" "1;38;5;159" "1;38;5;97" "1;38;5;220" "1;38;5;153" "1;38;5;219")
M_LVL+=(41 44 48 41 44 46 48) M_HP+=(3 3 3 3 3 3 3) M_DMG+=(0 0 0 0 0 0 0) M_XP+=(60 66 80 60 66 72 80) M_GOLD+=(0 0 0 0 0 0 0)
M_AGGRO+=(0 0 0 0 0 0 0) M_MOVE+=(900 900 900 900 900 900 900) M_ATK+=(1000 1000 1000 1000 1000 1000 1000)
M_BOSS+=(0 0 0 0 0 0 0) M_KIND+=(3 3 3 3 3 3 3)
MEMO_X[N80]=⚫ MEMO_X[N80+1]=🟡 MEMO_X[N80+2]=💠 MEMO_X[N80+3]=🥀 MEMO_X[N80+4]=🌼 MEMO_X[N80+6]=🌸
MEMO_X[N80+5]=🧊
for (( _i = 0; _i < 7; _i++ )); do
  NODE_MAT[$(( N80 + _i ))]=$(( M80 + _i )) NODE_PK[$(( N80 + _i ))]=$(( _i < 3 ? 1 : 2 )); NODE_T+=($(( N80 + _i )))
  M_EL[N80+_i]=0 M_WK[N80+_i]=-1 M_RS[N80+_i]=-1 M_AB[N80+_i]="" M_RNG[N80+_i]=0 M_HEALR[N80+_i]=0 M_SUMM[N80+_i]=0
done; unset _i
NM=${#M_NAME[@]}
ZONES+=("$N80 $L80_SH 6" "$(( N80 + 3 )) $L80_SH 6" "$(( N80 + 1 )) $L80_GE 6" "$(( N80 + 4 )) $L80_GE 6"
        "$(( N80 + 1 )) $L80_RW 4" "$(( N80 + 5 )) $L80_RW 7" "$(( N80 + 2 )) $L80_AR 6" "$(( N80 + 6 )) $L80_AR 6")
FISHW[swamp]+=" $(( M80 + 7 )):40:0" FISHW[oasis]+=" $(( M80 + 8 )):43:1" FISHW[ice]+=" $(( M80 + 9 )):45:1"
FORGE_X+=("13:$M80:6 $(( M60 + 1 )):3" "14:$(( M80 + 1 )):6 $M80:3" "15:$(( M80 + 2 )):6 $(( M80 + 1 )):4")
ALCH_X+=("gh3:3x Greater health potion:$(( M80 + 3 )):2" "gm3:3x Greater mana potion:$(( M80 + 4 )):2"
         "grand:Grand Elixir (Strength + Iron Skin + Swiftness):$(( M80 + 5 )):2 $(( M80 + 6 )):1"
         "tveil:Sand Veil (see far in storms/night):$(( M80 + 4 )):1")

# --- a new faction: the Horizon Watch ------------------------------------------------------------------------------
FAC_NAME+=("The Horizon Watch") FAC_E+=(🌄) FAC_COL+=("38;5;216")
NFAC=${#FAC_NAME[@]} FAC80=$(( NFAC - 1 ))
declare -A FAC_UQX=()                                       # faction -> its quartermaster's unique (01c: FAC_UQ0 + faction)

# --- four towns and their people ------------------------------------------------------------------------------------
T8_NAME=(Lanternfall Sunhollow Rimeholt Zenith)
T8_X=(520 520 520 520) T8_Y=(166 116 68 18)
T8_DX=(10 4 17 7 17 4 10) T8_DY=(4 9 3 7 8 4 9)            # where they stand: slot 0 the town's questgiver, 5 the questline
NPC80=${#M_NAME[@]}
n8() {  # town slot role "Full Name" short glyph color emoji
  local t=${#M_NAME[@]}
  M_NAME+=("$5") M_GLY+=("$6") M_COL+=("1;38;5;$7;$NPCBG") M_LVL+=($(( 40 + $1 * 3 ))) M_HP+=(3000) M_DMG+=(150)
  M_XP+=(300) M_GOLD+=(800) M_AGGRO+=(0) M_MOVE+=(900) M_ATK+=(1000) M_BOSS+=(0) M_KIND+=(1)
  MEMO_X[t]=$8 N_ROLE[$t]=$3 N_FULL[$t]=$4 N_HOME[$t]=${T8_NAME[$1]}
  M_EL[t]=0 M_WK[t]=-1 M_RS[t]=-1 M_AB[t]="" M_RNG[t]=0 M_HEALR[t]=0 M_SUMM[t]=0
  NPC_SPAWNS+=("$t $(( T8_X[$1] + T8_DX[$2] )) $(( T8_Y[$1] + T8_DY[$2] )) 0")
}
n8 0 0 questgiver "Lamplighter Odessa"        Odessa    O 222 👩
n8 0 1 smith      "Brother Anvel"             Anvel     A 180 👷
n8 0 2 inn        "Mother Hollis"             Hollis    H 217 💁
n8 0 3 bank       "Penny the Banker"          Penny     '$' 220 🤵
n8 0 4 stable     "Wren the Mistrider"        Wren      W 152 🧑
n8 0 5 questgiver "Sister Ysolde"             Ysolde    Y 139 🧕
n8 0 6 alchemist  "Old Marrow"                Marrow    M 118 🧓
n8 1 0 questgiver "Vizier Khalun"             Khalun    K 222 👳
n8 1 1 smith      "Goldhand Tarik"            Tarik     T 180 👷
n8 1 2 inn        "Lady Saffra"               Saffra    S 217 💃
n8 1 3 bank       "Dinar the Banker"          Dinar     '$' 220 🤵
n8 1 4 trader     "Caravaneer Zahra"          Zahra     Z 179 🧕
n8 1 5 questgiver "Archaeologist Pim"         Pim       P 137 🧐
n8 1 6 general    "Old Dates"                 Dates     D 214 🙋
n8 2 0 questgiver "Jarl Sigrun"               Sigrun    S 153 👸
n8 2 1 smith      "Rimehammer Bodvar"         Bodvar    B 180 👷
n8 2 2 inn        "Old Astrid"                Astrid    A 217 👵
n8 2 3 bank       "Krona the Banker"          Krona     '$' 220 🤵
n8 2 4 general    "Furrier Halvard"           Halvard   H 137 🧔
n8 2 5 questgiver "Seer Ulla"                 Ulla      U 75  🧙
n8 2 6 alchemist  "Frostherb Ylva"            Ylva      Y 118 🧝
n8 3 0 questgiver "Archon Celestine"          Celestine C 229 👼
n8 3 1 smith      "Starsmith Vael"            Vael      V 180 👷
n8 3 2 inn        "Keeper Elowen"             Elowen    E 217 💁
n8 3 3 bank       "Aurum the Banker"          Aurum     '$' 220 🤵
n8 3 4 valor      "Castor the Valor Quartermaster" Castor V 220 💂
n8 3 5 questgiver "Astronomer Quill"          Quill     Q 147 🧐
n8 3 6 general    "Nimbus the Provisioner"    Nimbus    N 214 🙋
for (( _i = 0; _i < 4; _i++ )); do                         # two guards at every north gate
  NPC_SPAWNS+=("19 $(( T8_X[_i] + 9 )) $(( T8_Y[_i] + 2 )) 1" "19 $(( T8_X[_i] + 11 )) $(( T8_Y[_i] + 2 )) 1")
done
Q_LANT=$NPC80 Q_YSOLDE=$(( NPC80 + 5 )) Q_SUN=$(( NPC80 + 7 )) Q_PIM=$(( NPC80 + 12 ))
Q_RIME=$(( NPC80 + 14 )) Q_ULLA=$(( NPC80 + 19 )) Q_ZEN=$(( NPC80 + 21 )) Q_QUILL=$(( NPC80 + 26 ))
NM=${#M_NAME[@]}
N_QK+=([$Q_LANT]="$SH_STALK $SH_WIGHT $SH_WISP $SH_LEECH" [$Q_YSOLDE]="$SH_HAG $SH_TREANT"
       [$Q_SUN]="$GE_SCORP $GE_BASIL $GE_GUARD $GE_WURM" [$Q_PIM]="$GE_DJINN $GE_PRIEST"
       [$Q_RIME]="$RW_WOLF $RW_TROLL $RW_WYRM $RW_MAMMOTH" [$Q_ULLA]="$RW_SHAMAN $RW_WRAITH"
       [$Q_ZEN]="$AR_ROC $AR_DRAKE $AR_SENT $AR_GOLEM" [$Q_QUILL]="$AR_SERAPH $AR_HORROR")
N_QD+=([$Q_LANT]=$D80 [$Q_SUN]=$(( D80 + 1 )) [$Q_RIME]=$(( D80 + 2 )) [$Q_ZEN]=$(( D80 + 3 )) [$Q_QUILL]=$(( D80 + 4 )))
N_QT+=([$Q_LANT]=$Q_SUN [$Q_SUN]=$Q_RIME [$Q_RIME]=$Q_ZEN [$Q_ZEN]=$Q_LANT
       [$Q_YSOLDE]=$Q_PIM [$Q_PIM]=$Q_ULLA [$Q_ULLA]=$Q_QUILL [$Q_QUILL]=$Q_YSOLDE)
N_SAY[stable]+="|Out east, a horse is not enough. Out east, you want something that can see in the mist."

# --- the new lands on the map --------------------------------------------------------------------------------------
for (( _i = 0; _i < 4; _i++ )); do
  _x=${T8_X[_i]} _y=${T8_Y[_i]} _n=${T8_NAME[_i]}
  SAFE_RECTS+=("$_x $_y $(( _x + 20 )) $(( _y + 12 ))")
  REGIONS+=("$_x $_y $(( _x + 20 )) $(( _y + 12 )) $_n safe")
  WAYSTONES+=("$_n $(( _x + 3 )) $(( _y + 2 ))")
  TOWN_FAC[$_n]=$FAC80
done; unset _i _x _y _n
REGIONS+=("480 150 599 199 Shroudmarch 40-42" "480 100 599 149 Gilded_Expanse 42-45" "480 50 599 99 Rimewastes 45-47"
          "480 0 599 49 Aether_Reach 47-50")
WEA_REG+=(Shroudmarch Gilded_Expanse Rimewastes Aether_Reach)
WEA_KIND+=("fog rain" "sand storm" "snow storm" "storm fog")
WATER_OF+=([Shroudmarch]=swamp [Gilded_Expanse]=oasis [Rimewastes]=ice [Aether_Reach]=ice)
REGION_FAC+=([Shroudmarch]=$FAC80 ["Gilded Expanse"]=$FAC80 [Rimewastes]=$FAC80 ["Aether Reach"]=$FAC80)
DLY_REG+=(Shroudmarch "Gilded Expanse" Rimewastes "Aether Reach")

# --- gear: the uniques of the edge (66-90) ----------------------------------------------------------------------------
U80=$NUQ
U_NAME+=("Veil of the Abbess" "Lanternbearer's Censer" "Ramahet's Sun Disk" "Khopesh of the Sun Kings"
         "Skadi's Frozen Longbow" "Heart of Endless Winter" "The Starwright's Orrery" "Lens of the Starwright"
         "Oblivion's Edge" "Mantle of the Last Horizon"
         "Aurelion's Sunfire Crown" "Skyborn Jerkin" "Dawnbreaker" "Heart of the Sundered Sun"
         "Grimvane's Mistcloak" "Khepra's Golden Scarab" "Frostmaw's Tusk" "Eye of the Storm Eternal"
         "Ysolde's Mistlantern" "Pim's Lucky Trowel" "Ulla's Runebone Charm" "Quill's Star Chart"
         "Signet of the Horizon" "Crown of the Last Horizon" "The Starwright's Compass")
U_SLOT+=(H O J W  W J W H  W A  H A W J  A J W J  O W J O  J H J)
U_KIND+=(3 3 2 0  6 1 9 3  28 3  3 1 0 3  0 0 1 1  3 5 3 1  0 3 2)
U_TIER+=(13 13 14 14  14 14 15 15  15 15  15 15 15 15  13 14 14 15  13 14 14 15  14 15 15)
U_BT+=(mp light crit crit  crit hp mp crit  dmg hp  crit crit dmg mp  mp crit crit dmg  mp crit mp mp  dmg hp crit)
U_FL+=("Behind it, the world is soft and grey and very quiet." "Its smoke smells of old prayers and wet stone."
       "It still warms itself on a sun that set three thousand years ago." "The sun kings carried it into battle and into their graves."
       "The string is a single icicle that never breaks." "It beats once a winter. This winter, it beats for you."
       "Every planet on it still turns, slowly, around a star that is not there." "Through it, the night sky is full of doors."
       "One side cuts. The other side simply ends." "Woven from the last light before the world's edge."
       "It burns, but never the one who wears it." "Light as a cloud, hard as the sky." "It was forged in the first sunrise."
       "It shines, steadily, even in the dark of a closed fist."
       "Wear it and the mist parts for you - and closes behind you." "A little golden beetle that only ever walks towards treasure."
       "The titan's tusk, cold enough to frost the air around it." "The storm looks out through it. It is not impressed."
       "Its light shows the way, and only the way." "It has dug up more history than any library holds."
       "Carved from the rib of a frost giant, singing softly of snow." "Every star is marked on it. One of them is new: you."
       "The Horizon Watch gives it only to those who have seen the edge." "The horizon itself, bent into a circle."
       "It does not point north. It points to wherever you have not been yet.")
NUQ=${#U_NAME[@]}
U_DROP+=("$B_ABBESS:$U80:25" "$B_ABBESS:$(( U80 + 1 )):25" "$B_RAMAHET:$(( U80 + 2 )):25" "$B_RAMAHET:$(( U80 + 3 )):25"
         "$B_SKADI:$(( U80 + 4 )):25" "$B_SKADI:$(( U80 + 5 )):25" "$B_STARW:$(( U80 + 6 )):25" "$B_STARW:$(( U80 + 7 )):25"
         "$B_OBLIV:$(( U80 + 8 )):20" "$B_OBLIV:$(( U80 + 9 )):20"
         "$W_GRIM:$(( U80 + 14 )):25" "$W_KHEPRA:$(( U80 + 15 )):25" "$W_FROST:$(( U80 + 16 )):25" "$W_ZEPH:$(( U80 + 17 )):25")
RAID2_UQ=($(( U80 + 10 )) $(( U80 + 11 )) $(( U80 + 12 )) $(( U80 + 13 )))
FAC_UQX[$FAC80]=$(( U80 + 22 ))

# --- mounts 8-12 ------------------------------------------------------------------------------------------------------
MNT_NAME+=("Mist Stalker" "Gilded Scarab" "Woolly Mammoth" "Aurora Unicorn" "Sunfire Wyrm")
MNT_E+=(🐺 🪲 🦣 🦄 🐲)
MNT_SPD+=(100 100 100 110 120)
MNT_GOLD+=(25000 20000 0 0 0)
MNT_REQ+=("lvl:42" "rep:$FAC80:4500" "" "" "")
MNT_SRC+=("Wren the Mistrider in Lanternfall, 25000 gold, from level 42" "Wren, 20000 gold - for the Honored of the Horizon Watch"
          "sometimes left behind by Frostmaw the Glacier Titan" "a Valor Quartermaster, 3000 valor"
          "sometimes left behind by Aurelion, the Sundered Sun")
NMNT=${#MNT_NAME[@]}
MNT_KEYS=123456789abcd                                     # the stable's keys, one per mount

# --- valor: the wares follow the highest tier now ----------------------------------------------------------------
VW_NAME=("Perfect gem (random)" "${TIER_Q[MAXTIER]} weapon, epic, 2 sockets" "${TIER_Q[MAXTIER]} armor, epic, 2 sockets"
         "${TIER_Q[MAXTIER]} helmet, epic, 2 sockets" "${TIER_Q[MAXTIER]} offhand, epic, 2 sockets" "${TIER_Q[MAXTIER]} trinket, epic, 2 sockets"
         "${TIER_Q[MAXTIER]} weapon, LEGENDARY, 3 sockets" "Storm Gryphon (mount)" "Ember Drake (mount)" "Aurora Unicorn (mount)")
VW_COST+=(3000) VW_WHAT+=(m11)
N_SAY[valor]+="|The Sundered Sky pays in valor too, if you live to collect it."

# --- dailies and weeklies -----------------------------------------------------------------------------------------------
DLY_T+=("edge:1:Clear a level 40+ dungeon")
WKY_T+=("raid2:1:Defeat Aurelion, the Sundered Sun")

# --- a fifth room at the inn --------------------------------------------------------------------------------------------
ROOM_NAME+=("Skyward Manor") ROOM_LVL+=(45) ROOM_COST+=(150000) ROOM_RENT+=(8000) ROOM_CAP+=(90) ROOM_REST+=(30)
ROOM_DESC+=("a manor above the clouds: a gallery, a great hearth, banners and a view of the edge of the world")
ROOM_LAY+=('############################################/#F...D...D...D...D...D...D...D...D...D....K#/#..........................................#/#B....D............................D......P#/#..........................................#/#C...D.....T..T........T..T........D......L#/#..........................................#/#L...D....A..........................A.D..P#/#..........................................#/#P...D.....T..T........T..T........D......L#/#..........................................#/#F..............D...........D.............K#/#..........................................#/#..D....D....D....G....D....D....D....D....#/#P........................................P#/######################<#####################')
for (( _i = 0; _i < ${#ROOM_LAY[@]}; _i++ )); do _r=${ROOM_LAY[_i]//[^D]/}; ROOM_NDSP[_i]=${#_r}; done; unset _i _r
NROOM=$(( ${#ROOM_NAME[@]} - 1 ))

# --- scouting spots for the questlines -----------------------------------------------------------------------------------
SP80=${#SPT_NAME[@]}
for _s in "the Sunken Chapel:566:186" "the Lantern Tree:494:172" "the Broken Colossus:556:106" "the Sun King's Road:500:132" \
          "the Frozen Giant:500:62" "the Singing Ice:565:72" "the Fallen Lens:566:42" "the Edge of the Sky:590:24"; do
  IFS=: read -r _n _x _y <<< "$_s"; SPT_NAME+=("$_n") SPT_X+=("$_x") SPT_Y+=("$_y")
done; unset _s _n _x _y
NSPOT=${#SPT_NAME[@]}

# --- four questlines (faction: the Horizon Watch) -------------------------------------------------------------------------
_r8() { printf -v "$1" '%d' "$(( R80 + $2 ))"; }           # rare n of v8.0
_r8 RR_LAMP 0; _r8 RR_MIRE 1; _r8 RR_SEKHET 2; _r8 RR_GLASS 3; _r8 RR_HRAETH 4; _r8 RR_IRON 5; _r8 RR_NIMBUS 6; _r8 RR_WATCH 7
ql_add "The Drowned Lanterns" "$Q_YSOLDE" "$FAC80" 41
qs_add K.$SH_WIGHT.10 "Bog wights carry our lanterns away into the mist - lanterns we light for the dead. Ten of them, before the dead are lost." \
  "The wights are fewer. But every lantern they took was carried east, towards the old abbey." 800
qs_add E.$SP80 "There was a chapel in the marsh before the marsh. It sank. Find what is left of it, south-east of here." \
  "Only the bell tower stands above the water. Inside, a thousand drowned lanterns, all still burning." 800
qs_add C.$SH_WISP.6 "Lantern wisps are the flames of those lanterns, gone wild. Bring me six - gently. They were people once." \
  "Ysolde cups the flames in her hands. 'They remember their names,' she whispers. 'All but one.'" 900
qs_add D.$D80 "The Abbess Morwyn keeps the lanterns from going out - and the dead from going on. Shroud Abbey lies east of town. Let them rest." \
  "The Abbess falls, and across the marsh the lanterns flicker - and go out, one by one, peacefully." 1000
qs_add B.$RR_LAMP "One flame did not go out: the Drowned Lamplighter, who lit the first lantern. He wanders north-east of the chapel." \
  "The Lamplighter's flame gutters and dies. In the ashes lies a lantern that burns without oil." 1200 \
  "Ysolde offers you the Lamplighter's own lantern - or the Watch's thanks and the town's gold." \
  "Take Ysolde's Mistlantern|Take the Watch's thanks" \
  "uq:$(( U80 + 18 )),rep:$FAC80:400|rep:$FAC80:1500,gold:5000" \
  "'Let it show you the way,' Ysolde says.|'The Horizon Watch will remember,' Ysolde says, and bows."
ql_add "Sands of the Sun Kings" "$Q_PIM" "$FAC80" 43
qs_add K.$GE_SCORP.10 "Gilded scorpions nest in my dig site. Ten of them, please, before they sting another student." \
  "The site is safe. Under one of the nests: a golden tablet with a sun on it." 900
qs_add G.$(( M80 + 1 )).5 "The tablet is sunbrass - and so are the doors of the tomb. Five pieces of sunbrass ore, and I can make a key." \
  "Pim melts the ore into a little golden key. 'Now we only need the door.'" 900
qs_add E.$(( SP80 + 2 )) "A colossus of the sun kings lies broken in the dunes north-east of here. Its face points to the tomb. Look where it looks." \
  "The colossus has one eye left. It stares east - straight at the Tomb of the Sun Kings." 1000
qs_add T.$Q_SUN "Show the key to Vizier Khalun. The vizier's family served the sun kings - he will know what the key unlocks." \
  "Khalun goes pale. 'Not a door, friend. A coffin. Ramahet's. And Ramahet's guardian still lives in the sand.'" 1000
qs_add B.$RR_SEKHET "Sekhet the Sunscale, the tomb's guardian, basks north of town. Pim insists on coming. Pim hides behind you." \
  "Sekhet falls with a sound like a sunset. Pim takes notes, very fast, with shaking hands." 1300 \
  "Pim offers you the trowel that found the tablet - or a share in the museum's money." \
  "Take Pim's Lucky Trowel|Take the museum's gold" \
  "uq:$(( U80 + 19 )),rep:$FAC80:400|gold:8000,rep:$FAC80:1200" \
  "'It digs up history,' Pim says. 'Mostly by accident.'|'For the museum!' Pim cheers, and counts the coins."
ql_add "The Long Winter" "$Q_ULLA" "$FAC80" 46
qs_add K.$RW_WOLF.10 "The rime wolves howl the winter closer every night. Ten of them, and the howling will stop for a while." \
  "The howling stops. In the silence, Ulla hears something else - singing, under the ice." 1000
qs_add C.$RW_SHAMAN.6 "The Rimeborn shamans sing to the ice. Bring me six of their totems, and I will hear the song." \
  "Ulla listens to the totems all night. 'They sing to Skadi. They sing her awake.'" 1000
qs_add E.$(( SP80 + 4 )) "A frost giant froze in the north-west long ago, they say, listening to that song. Find him." \
  "The giant is still there, frozen mid-step, his ear turned east - towards the Hall of Endless Winter." 1100
qs_add D.$(( D80 + 2 )) "Skadi sleeps in the Hall of Endless Winter, east of Rimeholt - and while she sleeps, it never thaws. Wake her. Then put her to sleep again." \
  "Skadi falls, and for the first time in an age, water drips from the eaves of Rimeholt." 1300
qs_add B.$RR_IRON "Old Ironhide, the mammoth that carried Skadi into battle, still roams the north-east. He is the last of her winter." \
  "Old Ironhide kneels in the snow, and the snow under him turns to water." 1500 \
  "Ulla offers you a charm carved from a giant's rib - or the blessing of Rimeholt's seers." \
  "Take Ulla's Runebone Charm|Take the seers' blessing" \
  "uq:$(( U80 + 20 )),rep:$FAC80:400|rep:$FAC80:1500,gem:3" \
  "'It sings of snow,' Ulla says. 'Let it.'|The seers sing your name into the ice. It will be there for a thousand years."
ql_add "Charting the Heavens" "$Q_QUILL" "$FAC80" 48
qs_add K.$AR_SENT.10 "Sky sentinels smash my telescopes. Ten of them, and I can see the sky again." \
  "The sentinels are scrap. Inside one: a lens, ground by a hand far finer than mine." 1100
qs_add E.$(( SP80 + 6 )) "A great lens fell from the sky south-east of here. The sentinels guard it. Find it before they do." \
  "The lens is as tall as a house. Through it the sky looks wrong - the stars are moving." 1100
qs_add G.$(( M80 + 6 )).4 "Skybloom grows only where the stars touch the ground. Four of them, and I can see what the lens sees." \
  "Quill grinds the skybloom into ink. On his chart, a new star appears - one that moves towards us." 1200
qs_add C.$AR_SERAPH.6 "The star seraphs carry the light of that star. Six of their feathers, and I can tell what it is." \
  "Quill reads the feathers and drops his quill. 'It is not a star. It is an eye. And it is watching the edge.'" 1200
qs_add B.$RR_WATCH "The Last Watcher stares at the world from the cliffs east of town. Close its eye." \
  "The Last Watcher's eye closes. On Quill's chart, the moving star goes dark." 1600 \
  "Quill offers you his star chart - with your name on it - or to polish your gems with stardust." \
  "Take Quill's Star Chart|Have your gems polished" \
  "uq:$(( U80 + 21 )),rep:$FAC80:400|gem:4,rep:$FAC80:1200" \
  "'Every star is marked,' Quill says. 'Even you.'|Quill's stardust makes every gem sing."
unset -f _r8
NQL=${#QL_NAME[@]}

# --- the story, act III: Beyond the Edge (chapters 43-55, levels 40-50) ------------------------------------------------------
ST_DONE[41]=${ST_DONE[41]/ THE END./ But that night, far in the east beyond the edge of the map, a light starts to burn.}
ST80=${#ST_TITLE[@]}
ST_TITLE+=("Beyond the Edge" "The Veiled Abbess" "Lanterns in the Mist" "The Golden Road" "Tomb of the Sun Kings"
           "Children of Winter" "The Rimeborn" "Endless Winter" "The City Above the Clouds" "The Starwright"
           "Sentinels of the Sky" "The World's Edge" "The Last Horizon")
ST_LVL+=(40 41 41 42 43 44 45 46 47 48 49 50 50)
ST_OBJ+=("T.$Q_LANT" "D.$D80" "K.$SH_WIGHT.12" "T.$Q_SUN" "D.$(( D80 + 1 ))" "T.$Q_RIME" "K.$RW_SHAMAN.10" "D.$(( D80 + 2 ))"
         "T.$Q_ZEN" "D.$(( D80 + 3 ))" "K.$AR_SENT.15" "D.$(( D80 + 4 ))" "T.23")
ST_XP+=(30000 80000 50000 32000 90000 34000 60000 100000 36000 110000 70000 150000 50000)
ST_GOLD+=(6000 12000 9000 6500 13000 7000 10000 14000 7500 15000 12000 25000 15000)
ST_REW+=("" G.W.13 "" "" G.A.14 "" "" G.W.14 "" "U.$(( U80 + 24 ))" "" "U.$(( U80 + 23 ))" "")
ST_TEXT+=(
 "Lumen sends for you. 'The crown is quiet, Crownbearer - but the sky is not. East of the crater, past the edge of every map, a light has started to burn. Something is coming from the edge of the world. Go east from Dawnspire, into the mist. Lamplighter Odessa keeps the lanterns of Lanternfall there.'"
 "Odessa: 'The mist came the night the star died. With it came the Abbess Morwyn, who says she guards the dead. She keeps them, more like. Shroud Abbey lies east of town - find out what she knows about the light in the east.'"
 "Odessa: 'Morwyn's wights are still out there, carrying our lanterns into the mist. Twelve of them, and the marsh will remember what quiet is.'"
 "Odessa: 'The Abbess spoke of a road of gold north of here, and a king who sleeps under the sun. Vizier Khalun of Sunhollow knows the old roads. Follow the road north.'"
 "Khalun: 'Ramahet the Sun King had a piece of the sky buried with him - he called it the Sun's Tear. If the light in the east wants something, it wants that. The Tomb of the Sun Kings lies east of Sunhollow.'"
 "Khalun: 'The Sun's Tear points north, into the cold. The Rimewastes. Jarl Sigrun of Rimeholt has kept the winter at bay for forty years. She will know why the tear burns towards her.'"
 "Sigrun: 'The Rimeborn sing to the ice and the ice listens. Since the light in the east, they sing louder. Ten of their shamans, and the singing stops long enough for us to think.'"
 "Sigrun: 'They sing to Skadi, the Winter Unending, asleep in her hall east of Rimeholt. She dreams the cold. She also holds the second tear of the sky. Take it - she will not give it.'"
 "Sigrun: 'Two tears of the sky, and both pull north, up - above the clouds. There is a city up there, Zenith, on islands that float over the edge of the world. Archon Celestine rules it. Take the road north.'"
 "Celestine: 'The tears were made by the Starwright, who built the sky - every star, every cloud. He lives in his observatory, north-east of here. He has not spoken to anyone in a thousand years. Make him speak.'"
 "Celestine: 'The Starwright's sentinels have woken - fifteen of them guard the last road. Break them, and the way to the edge is open.'"
 "Celestine: 'The Starwright said it plainly: at the edge of the world something called Oblivion is eating the horizon, and the tears of the sky are the only thing it fears. Go to the World's Edge, east of Zenith. End it.'"
 "Celestine: 'The horizon is whole again. Go home, Worldwalker. Old Tom will want to hear this one. Twice.'")
ST_DONE+=(
 "Odessa lights a lantern for you. 'Every traveller gets one. Most of them come back for a second.'"
 "Morwyn's veil falls away. Behind it is nothing but mist - and a voice: 'It is coming from the edge. It eats the light. It will eat yours.'"
 "The last wight drops its lantern. Odessa picks it up and lights it again. 'There. Home.'"
 "Khalun bows deeply. 'A Crownbearer. My grandmother told me one would come. She also told me to have tea ready.' He has tea ready."
 "Ramahet falls into his own gold, and in his hand lies the Sun's Tear - a drop of warm light that will not cool."
 "Sigrun looks at the tear for a long time. 'So that is why the snow has been warm,' she says."
 "The last shaman's song breaks mid-note. Across the Rimewastes the wind drops, and for a moment, it is almost spring."
 "Skadi melts like the end of winter. The second tear lies in the frost where her heart was. Rimeholt hears its first thaw in a hundred years."
 "Celestine floats down from her throne. 'Two tears. And you carried them up here on foot. Remarkable.'"
 "The Starwright sets down his tools. 'I made the sky,' he says, 'and I made the edge, so the sky would stay in. Something is eating the edge. Take my compass. It points to what is not there yet.'"
 "The last sentinel falls and the sky above Zenith opens like a door. Beyond it, very far away, the horizon is missing a piece."
 "Oblivion folds into the tears of the sky like night into morning. Where it stood, the horizon closes, seamless. On the ground lies a crown of light."
 "Old Tom does not say anything for a long time. Then he pours two mugs, and a third for the empty chair. 'For the edge of the world,' he says. 'And for whoever is next.' THE END - for now.")
NST=${#ST_TITLE[@]}

# --- collectables ----------------------------------------------------------------------------------------------------------
C80=$NCOL
cl 0 2 🏮 'L' $D80             "The Abbess's Last Lantern"  "It went out the moment she fell. It lights itself again on quiet nights."
cl 0 3 🌞 'O' $(( D80 + 1 ))   "The Sun's Tear"             "A drop of warm light, three thousand years old. It is never cold."
cl 0 3 🥶 'S' $(( D80 + 2 ))   "Skadi's Frozen Breath"      "Her last breath, caught in a glass. The glass is always frosted."
cl 0 3 🔭 'W' $(( D80 + 3 ))   "The Starwright's Astrolabe" "It measures stars that have not been made yet."
cl 0 3 🌅 'H' $(( D80 + 4 ))   "A Piece of the Last Horizon" "A sliver of sky, gold at the bottom, blue at the top. It is always dawn in it."
cl 0 3 🌄 'A' $RAID2_DT         "Aurelion's Sunfeather"       "A feather of pure sunlight. It makes the room a little warmer."
cl 1 2 🏺 'G' $WB80              "Grimvane's Mist Jar"        "Open it and the room fills with fog. Close it quickly."
cl 1 2 🪲 'K' $(( WB80 + 1 ))    "Khepra's Golden Carapace"   "Polished by three thousand years of sand. You can see yourself in it."
cl 1 3 🦷 'F' $(( WB80 + 2 ))    "Frostmaw's Ice Tusk"        "It frosts the shelf it lies on. Every shelf."
cl 1 3 🌀 'Z' $(( WB80 + 3 ))    "Zephyrion's Storm Pearl"    "A storm, rolled up small. It rumbles when it is about to rain."
cl 2 2 🧪 'm' "Shroudmarch"      "Bottled Mist"               "Mist from the Shroudmarch. Shake it and you hear distant bells."
cl 2 2 🪙 'c' "Gilded Expanse"   "Sun King's Coin"            "A king's face on one side, the sun on the other. Both are smiling."
cl 2 2 🌌 'a' "Rimewastes"       "Frozen Aurora"              "A ribbon of northern light, frozen in a block of clear ice."
cl 2 2 🪶 'f' "Aether Reach"     "Sky Whale Feather"          "From something very large that swims through the clouds."
cl 3 2 🐙 'q' -                  "Tiny Pet Octopus"           "It came up on the line and refused to go back. It likes you."
cl 3 2 🏆 'T' -                  "Golden Angler's Trophy"     "Awarded to nobody in particular. You found it on a hook."
cl 4 2 🌻 'y' -                  "Sunhollow Sunflower"        "It turns to face you, wherever you stand."
cl 4 3 💠 'G' -                  "Heart of the Glacier"       "Blue all the way through, and colder than it should be."
cl 5 3 🔥 'e' $(( ST80 + 5 ))     "Everlit Ember"              "From Odessa's own lantern. It has never gone out."
cl 5 3 📜 's' $(( ST80 + 10 ))    "Celestine's Star Map"       "The whole sky, drawn by an Archon - with one star missing."
cl 5 3 🌅 'h' $(( ST80 + 13 ))    "The Edge of the World"      "A little glass globe. Inside, a horizon, whole again."
_fl=("Proof that it hunts no more." "Taken from the hunter's own hunting ground." "The bounty boards still talk about it."
     "Hung over the fireplace, it still looks angry." "Every scratch on it is a story.")
for (( _t = R80; _t < R80 + 8; _t++ )); do                 # a hunter's trophy for every new rare elite (set 6, as in 01g)
  _n=${M_NAME[_t]%% the *}; _n=${_n#The }
  if [[ $_n == *s ]]; then _n="$_n' Trophy"; else _n="$_n's Trophy"; fi
  cl 6 3 "" "${M_GLY[_t]}" "$_t" "$_n" "${_fl[_t % 5]}"
done; unset _t _n _fl
col_index

# --- achievements ----------------------------------------------------------------------------------------------------------
ACH[8]="Starbreaker:Finish the second act of the story:Starbreaker"
ACH[20]="Friend of All:Be exalted with every faction:Friend of All"
ACH[21]="Artisan:Reach $PROF_MAX in a profession:" ACH[22]="Master Artisan:Reach $PROF_MAX in all three professions:Master Artisan"
ACH[24]="Stablemaster:Own every mount:the Stablemaster"
ACH80=$NACH
ACH+=("Ascended:Reach level 50:the Ascended" "Worldwalker:Finish the third act of the story:the Worldwalker"
      "Sunbreaker:Defeat Aurelion, the Sundered Sun:Sunbreaker" "Sky Veteran:Defeat Aurelion 10 times:"
      "Edgewalker:Clear the World's Edge:the Edgewalker" "Waywise:Attune every waystone:the Waywise"
      "Lord of the Manor:Rent the Skyward Manor:Lord of the Manor" "Ascendant Arms:Wear Ascendant gear in all five slots:the Radiant"
      "Keeper of the Horizon:Be exalted with the Horizon Watch:Keeper of the Horizon"
      "Curator of the Edge:Every collectable of the edge:the Curator")
NACH=${#ACH[@]}

RUMORS+=("East of Starfall Crater the mist never lifts. Lanterns burn in it - Lanternfall, they call the town. Nobody knows who lights them."
         "North of the mist lies the Gilded Expanse, where the sun kings sleep under golden sand. Archaeologists keep digging. Some keep coming back."
         "Beyond the sands, the Rimewastes: a winter that never ends, and a jarl who refuses to let it win."
         "Above the Rimewastes, islands float over the edge of the world. The city of Zenith sits on the highest one."
         "The heroes say the old limits are gone: level 50, and gear that the smiths of the west have never even heard of."
         "Above Zenith, the sky is cracked. They call it the Sundered Sky. Something burns behind the crack - and it is waiting for a raid."
         "Wren the Mistrider in Lanternfall sells mounts that can find their way through the mist. A horse would just walk into a bog.")
