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
