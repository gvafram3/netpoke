#!/bin/bash
# Start an experiment series DETACHED on the control node. Nothing you type afterwards can stop it by accident.
#   ./cluster/start_run.sh 3 phase1_nolock:yamls-orig
#   ./cluster/start_run.sh 3 phase5_hold:yamls-hold phase5_freeze:yamls-freeze
# Then:   ./cluster/watch.sh                                   live dashboard (Ctrl-C only stops the dashboard)
#         ./cluster/ssh.sh control 'tail -f ~/results/series_console.txt'   raw console output
#         ./cluster/stop_run.sh                                stop the run on purpose
source "$(dirname "$0")/lib.sh"
[ $# -ge 2 ] || { echo "usage: $0 REPS label:yamls-dir [label:yamls-dir ...]"; exit 1; }
if ssh_run control 'screen -ls 2>/dev/null | grep -q "[.]run[[:space:]]"'; then
  echo "A run named 'run' is already going on control. Watch it (./cluster/watch.sh) or stop it (./cluster/stop_run.sh) first."; exit 1; fi
ssh_run control "mkdir -p ~/results; screen -dmS run bash -lc '~/kit/control/run_series.sh $* 2>&1 | tee -a ~/results/series_console.txt'"
sleep 3
if ssh_run control 'screen -ls 2>/dev/null | grep "[.]run[[:space:]]"'; then
  echo "Started, detached. Now run:  ./cluster/watch.sh"
else echo "The run did not start. Check: ./cluster/ssh.sh control 'ls ~/kit/control'   (did you run 05_sync_repo.sh?)"; exit 1; fi
