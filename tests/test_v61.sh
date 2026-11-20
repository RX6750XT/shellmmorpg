#!/usr/bin/env bash
# v6.1: multiplayer with player ids that start with a digit (e.g. 151add, 9e1715) - these used to crash every client
source "$(dirname "$0")/lib.sh"
stub_client
new_hero 0 20
errs=$(mktemp); layout
{
for id in 151add 9e1715 000abc 12e456 aaaaaa 0123ab; do
  cli_line "SM1|HELLO|$id|bob$id|1|30"
  cli_line "SM1|POS|$id|bob$id|1|30|W|81|34|50|50|0|@|0|-1|0|0|-"
  cli_line "SM1|POS|$id|bob$id|1|30|W|82|34|50|50|0|@|0|-1|0|0|4"
  cli_line "SM1|POS|$id|bob$id|1|30|W|82|35|50|50|1|@|0|-1|0|0|-"
  cli_line "SM1|CHAT|$id|bob$id|hello"
  cli_line "SM1|FX|$id|W|x|82,35"
  [[ -n ${OP_NAME[$id]} ]] && ok || fail "$id was not registered"
  eq "mount of $id" "${OP_MNT[$id]:-none}" none
  cli_line "SM1|POS|$id|bob$id|1|30|W|82|35|50|50|0|@|0|-1|0|0|4"; eq "mount of $id set" "${OP_MNT[$id]}" 4
  render >/dev/null
  op_del "$id"; eq "$id removed" "${OP_NAME[$id]:-gone}" gone; eq "mount of $id removed" "${OP_MNT[$id]:-gone}" gone
done
} 2>"$errs"
if [[ -s $errs ]]; then fail "bash errors: $(head -3 "$errs")"; else ok; fi
t_end
