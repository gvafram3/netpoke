#!/usr/bin/env bash
# Live SlowPoke progress dashboard (run in a second SSH session on netpoke-control).
#
# Usage:
#   cd ~/slowpoke/evaluation
#   ./watch_progress.sh                  # refresh every 10s
#   WATCH_INTERVAL=5 ./watch_progress.sh results/boutique_medium.log
#
# Counters are derived from main.py log lines (see sample_output/boutique_medium.log).

set -u

RESULTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/results"
LOG_FILE=""
INTERVAL="${WATCH_INTERVAL:-10}"

if [[ $# -ge 1 && -f "$1" ]]; then
  LOG_FILE="$1"
elif [[ $# -ge 1 ]]; then
  RESULTS_DIR="$1"
fi

REPRO_BENCHES=(boutique hotel social movie)

pick_active_log() {
  local dir="$1"
  local f best="" best_mtime=0 mtime
  shopt -s nullglob
  for f in "$dir"/*.log; do
    [[ -f "$f" ]] || continue
    if grep -q 'Error Perc:' "$f" 2>/dev/null; then
      continue
    fi
    mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
    if (( mtime > best_mtime )); then
      best_mtime=$mtime
      best="$f"
    fi
  done
  shopt -u nullglob
  if [[ -n "$best" ]]; then
    echo "$best"
    return
  fi
  ls -t "$dir"/*.log 2>/dev/null | head -1
}

parse_log() {
  local log="$1"
  [[ -f "$log" ]] || return 1

  local num_exp finished throughputs total_workloads pct_workloads pct_opt
  num_exp=$(grep -m1 '^target_num_exp' "$log" 2>/dev/null | sed -E 's/.*: *//')
  num_exp=${num_exp:-10}
  finished=$(grep -c 'Finished running .*th optmization experiment' "$log" 2>/dev/null || true)
  throughputs=$(grep -c '\[exp\] Throughput:' "$log" 2>/dev/null || true)
  total_workloads=$((1 + num_exp * 2))
  if (( total_workloads > 0 )); then
    pct_workloads=$((throughputs * 100 / total_workloads))
  else
    pct_workloads=0
  fi
  if (( num_exp > 0 )); then
    pct_opt=$((finished * 100 / num_exp))
  else
    pct_opt=0
  fi

  local phase benchmark target
  phase=$(grep -E '\[test\.py\]|\[run\.sh\] Running |\[run\.sh\] Test finished|\[exp\] Throughput:' "$log" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')
  benchmark=$(grep -m1 '^benchmark' "$log" 2>/dev/null | sed -E 's/.*: *//')
  target=$(grep -m1 '^target_service' "$log" 2>/dev/null | sed -E 's/.*: *//')

  local last_tp last_err log_done=0
  last_tp=$(grep '\[exp\] Throughput:' "$log" 2>/dev/null | tail -1 | sed 's/.*Throughput: //')
  if grep -q 'Error Perc:' "$log" 2>/dev/null; then
    log_done=1
    last_err=$(grep 'Error Perc:' "$log" 2>/dev/null | tail -1 | sed 's/.*Error Perc:[[:space:]]*//')
  fi

  local size lines mtime_human
  size=$(wc -c <"$log" | tr -d ' ')
  lines=$(wc -l <"$log" | tr -d ' ')
  mtime_human=$(date -r "$log" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -r "$(stat -f %m "$log")" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '?')

  echo "LOG=$log"
  echo "BENCHMARK=$benchmark"
  echo "TARGET=$target"
  echo "NUM_EXP=$num_exp"
  echo "FINISHED_OPT=$finished"
  echo "THROUGHPUTS=$throughputs"
  echo "TOTAL_WORKLOADS=$total_workloads"
  echo "PCT_WORKLOADS=$pct_workloads"
  echo "PCT_OPT=$pct_opt"
  echo "PHASE=$phase"
  echo "LAST_TP=$last_tp"
  echo "LAST_ERR=$last_err"
  echo "LOG_DONE=$log_done"
  echo "SIZE=$size"
  echo "LINES=$lines"
  echo "MTIME=$mtime_human"
}

repro_summary() {
  local dir="$1" name f status
  for name in "${REPRO_BENCHES[@]}"; do
    f="$dir/${name}_medium.log"
    if [[ ! -f "$f" ]]; then
      status="pending"
    elif grep -q 'Error Perc:' "$f" 2>/dev/null; then
      status="DONE"
    else
      local fo
      fo=$(grep -c 'Finished running .*th optmization experiment' "$f" 2>/dev/null || echo 0)
      status="running (${fo}/10 points)"
    fi
    printf "  %-8s %s\n" "$name" "$status"
  done
}

render_bar() {
  local pct=$1 width=30
  local filled=$((pct * width / 100))
  local i
  printf '['
  for ((i=0; i<width; i++)); do
    if (( i < filled )); then printf '#'; else printf '.'; fi
  done
  printf '] %3d%%' "$pct"
}

prev_size=0
stall_count=0

while true; do
  if [[ -z "$LOG_FILE" ]]; then
    LOG_FILE=$(pick_active_log "$RESULTS_DIR")
  fi

  clear
  echo "SlowPoke progress  ($(date '+%H:%M:%S'))  refresh=${INTERVAL}s"
  echo "================================================================"
  echo "Results dir: $RESULTS_DIR"
  echo ""

  echo "Full reproducible (run_reproducible.sh):"
  repro_summary "$RESULTS_DIR"
  echo ""

  if [[ -z "${LOG_FILE:-}" || ! -f "$LOG_FILE" ]]; then
    echo "No active .log yet. Start a run, e.g.:"
    echo "  ./run_reproducible.sh   # or run-boutique-medium.sh results/boutique_medium.log"
    sleep "$INTERVAL"
    continue
  fi

  eval "$(parse_log "$LOG_FILE")"

  echo "Active log: $(basename "$LOG")"
  echo "  benchmark=$BENCHMARK  target=$TARGET  log_mtime=$MTIME"
  echo ""

  if (( LOG_DONE )); then
    echo "Status: FINISHED (this benchmark)"
    echo "  Error Perc: $LAST_ERR"
  else
    echo "Status: RUNNING"
    echo "  Phase: ${PHASE:-(deploying or between steps — see kubectl)}"
    echo "  Last throughput: ${LAST_TP:-n/a}"
  fi
  echo ""

  echo "Workload runs:  $THROUGHPUTS / $TOTAL_WORKLOADS  (baseline + ${NUM_EXP}× groundtruth + ${NUM_EXP}× slowdown)"
  render_bar "$PCT_WORKLOADS"
  echo ""
  echo "Opt points done: $FINISHED_OPT / $NUM_EXP"
  render_bar "$PCT_OPT"
  echo ""
  echo "Log size: ${SIZE} bytes, ${LINES} lines"

  if [[ -n "${SIZE:-}" ]]; then
    if (( SIZE == prev_size )); then
      stall_count=$((stall_count + 1))
    else
      stall_count=0
    fi
    prev_size=$SIZE
    if (( stall_count >= 6 )); then
      echo ""
      echo "⚠ No log growth for ~$((stall_count * INTERVAL))s."
      echo "  Normal during long wrk runs (1–3 min). Worry if >15 min with no kubectl activity."
      echo "  Check: kubectl get pods -A | head"
    fi
  fi

  echo ""
  echo "Tip: pass a specific log:  ./watch_progress.sh results/boutique_medium.log"
  sleep "$INTERVAL"
done
