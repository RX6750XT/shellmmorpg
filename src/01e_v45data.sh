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
