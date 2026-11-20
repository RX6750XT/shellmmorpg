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
