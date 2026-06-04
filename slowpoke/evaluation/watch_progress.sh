#!/usr/bin/env bash
# SlowPoke progress counters (parse main.py logs).
#
# One SSH session — use with run_with_monitor.sh (prints to your terminal).
# Two sessions — run this alone in the other SSH.
#
#   ./watch_progress.sh
#   ./watch_progress.sh --once
#   ./watch_progress.sh --loop-tty results/

set -u

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$EVAL_DIR/results}"
LOG_FILE=""
INTERVAL="${WATCH_INTERVAL:-15}"
MODE="fullscreen"  # fullscreen | once | loop-tty

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) MODE=once; shift ;;
    --loop-tty) MODE=loop-tty; shift ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *)
      if [[ -f "$1" ]]; then
        LOG_FILE="$1"
      elif [[ -d "$1" ]]; then
        RESULTS_DIR="$1"
      fi
      shift
      ;;
  esac
done

REPRO_BENCHES=(boutique hotel social movie)

pick_active_log() {
  local dir="$1" name f bench
  if [[ -n "${SLOWPOKE_ACTIVE_LOG:-}" && -f "${SLOWPOKE_ACTIVE_LOG}" ]]; then
    echo "$SLOWPOKE_ACTIVE_LOG"
    return
  fi
  # Match the benchmark main.py is actually running (best for run_reproducible_remaining).
  bench=$(ps aux 2>/dev/null | grep -E '[p]ython3.*main\.py -b ' | sed -n 's/.*-b \([a-z]*\).*/\1/p' | head -1)
  if [[ -n "$bench" ]]; then
    f="$dir/${bench}_medium.log"
    if [[ -f "$f" ]]; then
      echo "$f"
      return
    fi
  fi
  for name in "${REPRO_BENCHES[@]}"; do
    f="$dir/${name}_medium.log"
    if [[ -f "$f" ]] && ! grep -q 'Error Perc:' "$f" 2>/dev/null; then
      echo "$f"
      return
    fi
  done
  ls -t "$dir"/*.log 2>/dev/null | head -1
}

# Sets globals: P_LOG, P_BENCHMARK, P_TARGET, P_NUM_EXP, P_FINISHED_OPT, P_THROUGHPUTS,
# P_TOTAL_WORKLOADS, P_PCT_WORKLOADS, P_PCT_OPT, P_PHASE, P_LAST_TP, P_LAST_ERR,
# P_LOG_DONE, P_SIZE, P_LINES, P_MTIME
parse_log() {
  local log="$1"
  P_LOG="" P_BENCHMARK="" P_TARGET="" P_LAST_TP="" P_LAST_ERR="" P_PHASE=""
  P_LOG_DONE=0 P_FINISHED_OPT=0 P_THROUGHPUTS=0 P_NUM_EXP=10
  [[ -f "$log" ]] || return 1

  P_LOG="$log"
  P_NUM_EXP=$(grep -m1 '^target_num_exp' "$log" 2>/dev/null | sed -E 's/.*: *//')
  P_NUM_EXP=${P_NUM_EXP:-10}
  P_FINISHED_OPT=$(grep -c 'Finished running .*th optmization experiment' "$log" 2>/dev/null || true)
  P_THROUGHPUTS=$(grep -c '\[exp\] Throughput:' "$log" 2>/dev/null || true)
  P_TOTAL_WORKLOADS=$((1 + P_NUM_EXP * 2))
  if (( P_TOTAL_WORKLOADS > 0 )); then
    P_PCT_WORKLOADS=$((P_THROUGHPUTS * 100 / P_TOTAL_WORKLOADS))
  else
    P_PCT_WORKLOADS=0
  fi
  if (( P_NUM_EXP > 0 )); then
    P_PCT_OPT=$((P_FINISHED_OPT * 100 / P_NUM_EXP))
  else
    P_PCT_OPT=0
  fi

  P_PHASE=$(grep -E '\[test\.py\]|\[run\.sh\] Running |\[run\.sh\] Test finished|\[exp\] Throughput:' "$log" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')
  P_BENCHMARK=$(grep -m1 '^benchmark' "$log" 2>/dev/null | sed -E 's/.*: *//')
  P_TARGET=$(grep -m1 '^target_service' "$log" 2>/dev/null | sed -E 's/.*: *//')
  P_LAST_TP=$(grep '\[exp\] Throughput:' "$log" 2>/dev/null | tail -1 | sed 's/.*Throughput: //')
  if grep -q 'Error Perc:' "$log" 2>/dev/null; then
    P_LOG_DONE=1
    P_LAST_ERR=$(grep 'Error Perc:' "$log" 2>/dev/null | tail -1 | sed 's/.*Error Perc:[[:space:]]*//')
  fi
  P_SIZE=$(wc -c <"$log" | tr -d ' ')
  P_LINES=$(wc -l <"$log" | tr -d ' ')
  P_MTIME=$(date -r "$log" '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo '?')
  return 0
}

repro_summary() {
  local dir="$1" name f status done_count=0
  for name in "${REPRO_BENCHES[@]}"; do
    f="$dir/${name}_medium.log"
    if [[ ! -f "$f" ]]; then
      status="pending"
    elif grep -q 'Error Perc:' "$f" 2>/dev/null; then
      status="DONE"
      done_count=$((done_count + 1))
    else
      local fo
      fo=$(grep -c 'Finished running .*th optmization experiment' "$f" 2>/dev/null) || fo=0
      status="running (${fo}/10)"
    fi
    printf "  %-8s %s\n" "$name" "$status"
  done
  REPRO_DONE_COUNT=$done_count
}

render_bar() {
  local pct=$1 width=20
  local filled=$((pct * width / 100))
  local i
  printf '['
  for ((i=0; i<width; i++)); do
    if (( i < filled )); then printf '#'; else printf '.'; fi
  done
  printf ']%3d%%' "$pct"
}

# Compact block for --once / --loop-tty (fits one SSH + screen session).
# Optional arg: output path (e.g. /dev/tty); default is stdout.
print_compact() {
  local out="${1:-}"
  if [[ -z "${LOG_FILE:-}" ]]; then
    LOG_FILE=$(pick_active_log "$RESULTS_DIR")
  fi

  _pc_emit() {
    echo "── SlowPoke $(date '+%H:%M:%S') ──"
    local name done_total=0 f
    for name in "${REPRO_BENCHES[@]}"; do
      f="$RESULTS_DIR/${name}_medium.log"
      if [[ -f "$f" ]] && grep -q 'Error Perc:' "$f" 2>/dev/null; then
        done_total=$((done_total + 1))
      fi
    done
    echo "Suite: ${done_total}/4 benchmarks finished (boutique→hotel→social→movie)"
    if [[ -z "${LOG_FILE:-}" || ! -f "$LOG_FILE" ]]; then
      echo "Active log: (none yet — run starting?)"
      return
    fi
    parse_log "$LOG_FILE" || true
    [[ -z "$P_BENCHMARK" ]] && P_BENCHMARK=$(basename "$P_LOG" _medium.log)
    [[ -z "$P_TARGET" ]] && P_TARGET=$(grep -m1 '^target_service' "$LOG_FILE" 2>/dev/null | sed -E 's/.*: *//' || echo "…")
    echo "Now:  $(basename "$P_LOG")  ($P_BENCHMARK / $P_TARGET)"
    if (( P_LOG_DONE )); then
      echo "      FINISHED — Error Perc: ${P_LAST_ERR:0:80}"
    else
      printf "      workloads %s/%s " "$P_THROUGHPUTS" "$P_TOTAL_WORKLOADS"
      render_bar "$P_PCT_WORKLOADS"
      echo ""
      printf "      opt points %s/%s " "$P_FINISHED_OPT" "$P_NUM_EXP"
      render_bar "$P_PCT_OPT"
      echo ""
      echo "      phase: ${P_PHASE:-…}"
      echo "      last throughput: ${P_LAST_TP:-n/a}"
    fi
  }

  if [[ -n "$out" ]]; then
    _pc_emit >"$out"
  else
    _pc_emit
  fi
}

print_fullscreen() {
  if [[ -z "${LOG_FILE:-}" ]]; then
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
    echo "No active .log yet."
    return
  fi
  parse_log "$LOG_FILE"
  echo "Active log: $(basename "$P_LOG")"
  echo "  benchmark=$P_BENCHMARK  target=$P_TARGET"
  echo ""
  if (( P_LOG_DONE )); then
    echo "Status: FINISHED"
    echo "  Error Perc: $P_LAST_ERR"
  else
    echo "Status: RUNNING — ${P_PHASE:-}"
    echo "  Last throughput: ${P_LAST_TP:-n/a}"
  fi
  echo ""
  echo "Workload runs:  $P_THROUGHPUTS / $P_TOTAL_WORKLOADS"
  render_bar "$P_PCT_WORKLOADS"
  echo ""
  echo "Opt points done: $P_FINISHED_OPT / $P_NUM_EXP"
  render_bar "$P_PCT_OPT"
  echo ""
  echo "Log: ${P_SIZE} bytes, ${P_LINES} lines"
}

prev_size=0
stall_count=0

if [[ "$MODE" == "once" ]]; then
  print_compact
  exit 0
fi

if [[ "$MODE" == "loop-tty" ]]; then
  tty_out=/dev/tty
  [[ -w "$tty_out" ]] 2>/dev/null || tty_out=/dev/stdout
  echo "[slowpoke] Progress updates every ${INTERVAL}s on your terminal (one SSH is enough)." >"$tty_out"
  while true; do
    print_compact "$tty_out"
    echo "" >"$tty_out"
    if [[ -n "${LOG_FILE:-}" && -f "$LOG_FILE" ]]; then
      size=$(wc -c <"$LOG_FILE" | tr -d ' ')
      if [[ "$size" == "$prev_size" ]]; then
        stall_count=$((stall_count + 1))
        if (( stall_count >= 8 )); then
          echo "  (no log growth ~$((stall_count * INTERVAL))s — normal during long wrk; worry if >15 min)" >"$tty_out"
        fi
      else
        stall_count=0
      fi
      prev_size=$size
    fi
    sleep "$INTERVAL"
  done
fi

# fullscreen loop (second SSH or tmux pane)
while true; do
  print_fullscreen
  sleep "$INTERVAL"
done
