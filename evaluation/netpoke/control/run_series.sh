#!/bin/bash
# Run one or more experiment arms for several repetitions, INTERLEAVED, stop early if a run fails, then print the summary tables.
#   run_series.sh REPS label:yamls-dir [label:yamls-dir ...]
#   run_series.sh 3 phase1_nolock:yamls-orig
#   run_series.sh 3 phase5_hold:yamls-hold phase5_freeze:yamls-freeze
# Start it inside screen on the control node; watch it from the other window with ./cluster/watch.sh
REPS="${1:?repetitions}"; shift; [ $# -ge 1 ] || { echo "give at least one label:yamls-dir"; exit 1; }
START=$(date +%s)
for rep in $(seq 1 "$REPS"); do
  for spec in "$@"; do
    label="${spec%%:*}"; y="${spec#*:}"
    "$HOME/kit/control/run_arm.sh" "$label" "$y" "$rep" || true
    if ! grep -q "Error percentage" "$HOME/results/${label}_rep${rep}.log" 2>/dev/null; then
      echo "[series] $label rep$rep did NOT finish -> stopping so no time is wasted. Read the end of ~/results/${label}_rep${rep}.log"; exit 1; fi
    if grep -q "Pods already healthy" "$HOME/results/${label}_rep${rep}.log"; then
      echo "[series] $label rep$rep SKIPPED a redeploy (stale settings) -> result invalid, stopping."; exit 1; fi
    if grep -qE "Speed is 0(\.0*)?," "$HOME/results/${label}_rep${rep}.log"; then
      echo "[series] $label rep$rep had a warm-up with 0 req/s (a stalled measurement) -> result invalid, stopping."; exit 1; fi
    echo "[series] $label rep$rep finished ($(( ($(date +%s)-START)/60 )) min since start)"
  done
done
files=""; for spec in "$@"; do files="$files $HOME/results/${spec%%:*}_rep*.log"; done
python3 "$HOME/kit/control/summarize_runs.py" $files
