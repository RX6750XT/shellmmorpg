# ---------------------------------------------------------------------------
#  Module 04c - graphics (since v1.4): HD mode (every tile is 2 columns: emoji
#  sprites, colored ground) and the classic 1-column ASCII mode ([v] switches),
#  text width helpers, and the tile-row cache that makes map frames cheap.
# ---------------------------------------------------------------------------
GFX_FILE="$DATA_DIR/config"; [[ $MODE == session ]] && GFX_FILE="$DATA_DIR/prefs/${MY_NAME,,}.gfx"   # v7.0: per player on the server
GFX_NEW=0 TW=1 TW2=0 MW=81 PLX=x
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

save_gfx() { mkdir -p "${GFX_FILE%/*}" 2>/dev/null; printf 'GFX=%s\n' "$GFX" > "$GFX_FILE" 2>/dev/null; }

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
