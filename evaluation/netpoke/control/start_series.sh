#!/bin/bash
# Start a run_series.sh on the control node, detached, guarded against a second concurrent copy (the flock in run_series.sh
# is the real guard; this also refuses if a 'run' screen session already exists, so a retried SSH command cannot start two).
#   usage: start_series.sh REPS label:yamls-dir [label:yamls-dir ...]      (same args as run_series.sh)
if screen -ls 2>/dev/null | grep -q '[.]run[[:space:]]'; then echo "ALREADY RUNNING - not starting another (screen -ls shows a 'run' session)"; exit 1; fi
ARGS="$*"
screen -dmS run bash -lc "NUM_REQ=60000 ~/kit/control/run_series.sh $ARGS 2>&1 | tee -a ~/results/series_console.txt"
sleep 20
if screen -ls 2>/dev/null | grep -q '[.]run[[:space:]]'; then echo "started: $ARGS"; else echo "FAILED to start (no 'run' session after 20s) - check ~/results/series_console.txt"; exit 1; fi
