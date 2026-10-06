#!/bin/bash
# Runs the whole leak matrix on ONE machine and prints one RESULT line per run. Run as root from ~/tests:  sudo bash leak_suite.sh
cd "$(dirname "$0")"
run(){ bash ./topo_leak.sh >/dev/null 2>&1; env "$@" python3 kernel_leak_test.py 2>&1 | grep -E "^RESULT|NOT AVAILABLE" || echo "RESULT-FAILED $*"; }
run SCEN=idle HOLD=0
for k in 1 2 3; do run SCEN=sender HOLD=0; done
for k in 1 2 3; do run SCEN=sender HOLD=1; done
run SCEN=sender HOLD=1 PAUSE_MS=200 CYCLES=8
run SCEN=sender HOLD=1 PAUSE_MS=1000 CYCLES=6
run SCEN=receiver HOLD=0
run SCEN=receiver HOLD=1
