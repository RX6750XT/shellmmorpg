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
unset -f cl
NCOL=${#CL_NAME[@]}
CL_VAL=() CL_SRC=() COL_SETL=() COL_W=(50 30 15 5)    # sell value, where it comes from, the members of every set, pick weights
declare -A COL_BOSS=() COL_CUR=()                     # monster type -> trophy, region name -> curio
for (( _i = 0; _i < NCOL; _i++ )); do
  _r=${CL_REF[_i]}
  CL_VAL[_i]=$(( ${CL_RR[_i]} == 0 ? 80 : (${CL_RR[_i]} == 1 ? 300 : (${CL_RR[_i]} == 2 ? 1000 : 3500)) ))
  COL_SETL[CL_SET[_i]]+="$_i "
  case ${CL_SET[_i]} in
    0) _t=${D_BOSS[_r]}; COL_BOSS[$_t]=$_i; _n=${D_NAME[_r]}; [[ $_n == The\ * ]] || _n="the $_n"
       CL_SRC[_i]="${M_NAME[_t]}, the master of $_n" ;;
    1) _t=${WB_LIST[_r]}; COL_BOSS[$_t]=$_i; CL_SRC[_i]="${M_NAME[_t]}, a world boss" ;;
    2) COL_CUR[$_r]=$_i; CL_SRC[_i]="the creatures of the $_r" ;;
    3) CL_SRC[_i]="fishing, anywhere" ;;
    4) CL_SRC[_i]="mining and herbalism, anywhere" ;;
    5) CL_SRC[_i]="chapter $_r of the story" ;;
  esac
done
unset _i _r _t _n

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
