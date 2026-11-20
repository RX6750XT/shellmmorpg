# ---------------------------------------------------------------------------
#  Module 06 - start: pick the main loop for the mode the arguments chose
# ---------------------------------------------------------------------------
shopt -u patsub_replacement 2>/dev/null
# SHELLMMO_LIB=1 + "source shellmmorpg.sh": load every function and table, start nothing (tests)
[[ $SHELLMMO_LIB == 1 ]] && return 0 2>/dev/null
case $MODE in
  world)  server_main ;;
  server) dedicated_main ;;
  *)      client_main ;;
esac
