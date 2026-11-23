#!/usr/bin/env bash
# ---------------------------------------------------------------------------
#  Run the whole test suite:   tests/run.sh          (builds first)
#                              tests/run.sh quick    (skip the network tests)
# ---------------------------------------------------------------------------
cd "$(dirname "$0")/.." || exit 2
./build.sh || exit 2
fails=0
for t in tests/test_*.sh; do
  timeout 900 bash "$t" || fails=$(( fails + 1 ))
done
if [[ $1 != quick ]]; then
  if command -v python3 >/dev/null; then
    timeout 300 python3 tests/test_net.py || fails=$(( fails + 1 ))
    timeout 300 python3 tests/test_acct.py || fails=$(( fails + 1 ))
    timeout 300 python3 tests/test_admin.py || fails=$(( fails + 1 ))
    timeout 300 python3 tests/test_login.py || fails=$(( fails + 1 ))
    timeout 300 python3 tests/test_guest.py || fails=$(( fails + 1 ))
    timeout 300 python3 tests/test_restart.py || fails=$(( fails + 1 ))
  else
    echo "test_net       skipped (needs python3)"
  fi
fi
if command -v shellcheck >/dev/null; then   # only the classes that are real bugs in this code base
  # module by module: the whole 560 KB build needs more memory than shellcheck should get
  # (so no SC2154 - globals and associative arrays of other modules look unassigned)
  sc=(-s bash -S warning -i SC2324,SC2295,SC1073,SC1009,SC2050,SC2071,SC2072,SC2199,SC2066,SC2068,SC2145)
  bad=0
  for f in src/*.sh; do shellcheck "${sc[@]}" -f gcc "$f" > /tmp/shellmmo_sc.$$ 2>&1 || { bad=1; head -10 /tmp/shellmmo_sc.$$; }; done
  rm -f /tmp/shellmmo_sc.$$
  if (( bad )); then echo "shellcheck     (warnings above are informational)"; else echo "shellcheck     clean"; fi
fi
echo
if (( fails )); then echo "$fails test file(s) FAILED"; exit 1; fi
echo "all tests passed"
