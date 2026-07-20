#!/usr/bin/env bash
# SlowPoke progress counters (parse main.py logs).
#
# One SSH session — use with run_with_monitor.sh (prints to your terminal).
# Two sessions — run this alone in the other SSH.
#
#   ./watch_progress.sh
#   ./watch_progress.sh --once
#   ./watch_progress.sh --append          # second SSH: scrollable history
#   ./watch_progress.sh --loop-tty results/

set -u

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$EVAL_DIR/results}"
LOG_FILE=""
PINNED_LOG=0
INTERVAL="${WATCH_INTERVAL:-15}"
MODE="fullscreen"  # fullscreen | once | loop-tty | append

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) MODE=once; shift ;;
    --append) MODE=append; shift ;;
    --loop-tty) MODE=loop-tty; shift ;;
    -h|--help)
      sed -n '2,13p' "$0"
      exit 0
      ;;
    *)
      if [[ -f "$1" ]]; then
        LOG_FILE="$1"
        PINNED_LOG=1
      elif [[ -d "$1" ]]; then
        RESULTS_DIR="$1"
      fi
      shift
      ;;
  esac
done

REPRO_BENCHES=(boutique hotel social movie)
IO_GAP_LEVELS=(L1 L2)

main_py_benchmark() {
  ps aux 2>/dev/null | grep -E '[p]ython3.*main\.py -b ' | sed -n 's/.*-b \([a-z]*\).*/\1/p' | head -1
}

pick_active_log() {
  local dir="$1" name f bench level stamp running=0
  if pgrep -f '[p]ython3.*main\.py' >/dev/null; then
    running=1
  fi
  if [[ -n "${SLOWPOKE_ACTIVE_LOG:-}" && -f "${SLOWPOKE_ACTIVE_LOG}" ]]; then
    if ! grep -q 'Error Perc:' "${SLOWPOKE_ACTIVE_LOG}" 2>/dev/null \
        || (( running )); then
      echo "$SLOWPOKE_ACTIVE_LOG"
      return
    fi
  fi
  # Phase 4: follow the benchmark main.py is actually running.
  if [[ -n "${SLOWPOKE_PHASE4_EBPF:-}" ]]; then
    bench=$(main_py_benchmark)
    if [[ -n "$bench" ]]; then
      echo "$dir/${bench}_ebpf_L2_medium.log"
      return
    fi
  fi
  stamp="$dir/.slowpoke_active_log"
  # Phase 5/6: run_io_gap_netpoke_L2.sh writes this stamp before each app, so
  # it takes the same "trust the stamp" path as the Phase 3 orchestrator
  # below -- called out separately only because its *_io_L2_netpoke_medium.log
  # naming doesn't match the plain *_io_L1/L2_medium.log pattern the
  # bench-matching fallback further down checks, and would otherwise fall
  # through to (already-complete) *_medium.log and get stuck there.
  if [[ -f "$stamp" ]]; then
    f=$(tr -d '\n' <"$stamp")
    # Do not stick on a finished log while main.py moved to the next benchmark.
    if [[ -n "$f" ]] && grep -q 'Error Perc:' "$f" 2>/dev/null && (( running )); then
      f=""
    fi
    # Do not trust a stamp left over from an earlier, unrelated run just
    # because *some* main.py process happens to be running now (e.g. a
    # phase6_netpoke smoke test's stamp pointing at a *_netpoke_medium.log
    # while Phase 1/3 is actually running boutique_medium.log) -- verify the
    # stamped log's benchmark actually matches what's running.
    if [[ -n "$f" ]] && (( running )); then
      bench=$(main_py_benchmark)
      if [[ -n "$bench" && "$(basename "$f")" != "${bench}"_* ]]; then
        f=""
      fi
    fi
    if [[ -n "$f" ]] && { [[ ! -f "$f" ]] \
        || ! grep -q 'Error Perc:' "$f" 2>/dev/null \
        || (( running )); }; then
      echo "$f"
      return
    fi
  fi
  if [[ -n "${SLOWPOKE_PHASE4_EBPF:-}" ]]; then
    for name in social hotel movie boutique; do
      f="$dir/${name}_ebpf_L2_medium.log"
      if [[ ! -f "$f" ]] || ! grep -q 'Error Perc:' "$f" 2>/dev/null; then
        echo "$f"
        return
      fi
    done
  fi
  # Match the benchmark main.py is actually running -- checked BEFORE the
  # fixed-order guess below. Previously this fixed-order loop ran first and
  # would immediately match e.g. boutique_io_L1_medium.log (because it
  # simply doesn't exist yet) even while hotel's Phase 1 baseline was
  # genuinely still running, jumping the display straight to a Phase 3
  # target that hadn't actually started. Knowing what's really running is
  # always a better signal than guessing from a static enumeration order.
  bench=$(main_py_benchmark)
  if [[ -n "$bench" ]]; then
    # Only probe this benchmark's io_L1/L2 files if I/O-gap output already
    # exists SOMEWHERE on disk (i.e. Phase 3 has actually begun) -- during
    # Phase 1, ${bench}_io_L1_medium.log doesn't exist for anyone yet
    # either, which would otherwise be misread as "that's the target."
    local any_io=0 rname
    for rname in "${REPRO_BENCHES[@]}"; do
      if [[ -f "$dir/${rname}_io_L1_medium.log" ]]; then
        any_io=1
        break
      fi
    done
    if (( any_io )); then
      for level in "${IO_GAP_LEVELS[@]}"; do
        f="$dir/${bench}_io_${level}_medium.log"
        if [[ ! -f "$f" ]] || ! grep -q 'Error Perc:' "$f" 2>/dev/null; then
          echo "$f"
          return
        fi
      done
    fi
    echo "$dir/${bench}_medium.log"
    return
  fi
  # Fallback only when we can't tell what's actually running (e.g. between
  # runs): first incomplete I/O-gap log in fixed order.
  for name in "${REPRO_BENCHES[@]}"; do
    for level in "${IO_GAP_LEVELS[@]}"; do
      f="$dir/${name}_io_${level}_medium.log"
      if [[ ! -f "$f" ]] || ! grep -q 'Error Perc:' "$f" 2>/dev/null; then
        echo "$f"
        return
      fi
    done
  done
  for name in "${REPRO_BENCHES[@]}"; do
    f="$dir/${name}_medium.log"
    if [[ -f "$f" ]] && ! grep -q 'Error Perc:' "$f" 2>/dev/null; then
      echo "$f"
      return
    fi
  done
  for f in $(ls -t "$dir"/*_medium.log 2>/dev/null); do
    [[ -f "$f" ]] && ! grep -q 'Error Perc:' "$f" 2>/dev/null && { echo "$f"; return; }
  done
  echo ""
}

io_gap_summary_line() {
  local dir="$1" done=0 entry bench level f
  local -a order=(
    boutique:L1 boutique:L2 hotel:L1 hotel:L2
    social:L1 social:L2 movie:L1 movie:L2
  )
  for entry in "${order[@]}"; do
    bench="${entry%%:*}"
    level="${entry##*:}"
    f="$dir/${bench}_io_${level}_medium.log"
    if [[ -f "$f" ]] && grep -q 'Error Perc:' "$f" 2>/dev/null; then
      done=$((done + 1))
    fi
  done
  echo "I/O-gap: ${done}/8 runs complete (boutique L1→L2 → hotel → social → movie)"
}

netpoke_rmse_summary_line() {
  local dir="$1" done=0 bench f
  local -a order=(boutique hotel social movie)
  for bench in "${order[@]}"; do
    f="$dir/${bench}_io_L2_netpoke_medium.log"
    if [[ -f "$f" ]] && grep -q 'Error Perc:' "$f" 2>/dev/null; then
      done=$((done + 1))
    fi
  done
  echo "NetPoke-on RMSE run: ${done}/4 L2 runs complete (boutique → hotel → social → movie)"
}

netpoke_l0_overhead_summary_line() {
  local dir="$1" done=0 bench f
  local -a order=(boutique hotel social movie)
  for bench in "${order[@]}"; do
    f="$dir/${bench}_netpoke_medium.log"
    if [[ -f "$f" ]] && grep -q 'Error Perc:' "$f" 2>/dev/null; then
      done=$((done + 1))
    fi
  done
  echo "NetPoke-on L0 overhead check: ${done}/4 runs complete (boutique → hotel → social → movie)"
}

phase4_ebpf_summary_line() {
  local dir="$1" done=0 bench f
  local -a order=(social hotel movie boutique)
  for bench in "${order[@]}"; do
    f="$dir/${bench}_ebpf_L2_medium.log"
    if [[ -f "$f" ]] && grep -q 'Error Perc:' "$f" 2>/dev/null \
        && [[ -s "$dir/${bench}_ebpf_L2_residual.jsonl" ]]; then
      done=$((done + 1))
    fi
  done
  echo "Phase-4 eBPF: ${done}/4 L2 runs complete (social → hotel → movie → boutique)"
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
  if (( ! PINNED_LOG )); then
    LOG_FILE=$(pick_active_log "$RESULTS_DIR")
  fi

  _pc_emit() {
    echo "── SlowPoke $(date '+%H:%M:%S') ──"
    local name done_total=0 f show_io=0 show_netpoke_rmse=0 show_l0_overhead=0
    for name in "${REPRO_BENCHES[@]}"; do
      f="$RESULTS_DIR/${name}_io_L1_medium.log"
      [[ -f "$f" ]] && show_io=1
      f="$RESULTS_DIR/${name}_io_L2_netpoke_medium.log"
      [[ -f "$f" ]] && show_netpoke_rmse=1
      f="$RESULTS_DIR/${name}_netpoke_medium.log"
      [[ -f "$f" ]] && show_l0_overhead=1
      f="$RESULTS_DIR/${name}_medium.log"
      if [[ -f "$f" ]] && grep -q 'Error Perc:' "$f" 2>/dev/null; then
        done_total=$((done_total + 1))
      fi
    done
    if [[ -n "${SLOWPOKE_PHASE4_EBPF:-}" ]]; then
      phase4_ebpf_summary_line "$RESULTS_DIR"
    elif (( show_netpoke_rmse )); then
      netpoke_rmse_summary_line "$RESULTS_DIR"
    elif (( show_l0_overhead )); then
      netpoke_l0_overhead_summary_line "$RESULTS_DIR"
    elif (( show_io )) || [[ -n "${SLOWPOKE_IO_GAP_SUITE:-}" ]]; then
      io_gap_summary_line "$RESULTS_DIR"
    else
      echo "Suite: ${done_total}/4 benchmarks finished (boutique→hotel→social→movie)"
    fi
    if [[ -z "${LOG_FILE:-}" ]]; then
      echo "Active log: (none — waiting for hotel/social/movie to start)"
      return
    fi
    if [[ ! -f "$LOG_FILE" ]]; then
      P_BENCHMARK=$(basename "$LOG_FILE" _medium.log)
      echo "Now:  $(basename "$LOG_FILE")  ($P_BENCHMARK / …)"
      echo "      log file not created yet (run just started)"
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
  if (( ! PINNED_LOG )); then
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
prev_log=""

if [[ "$MODE" == "once" ]]; then
  print_compact
  exit 0
fi

if [[ "$MODE" == "append" ]]; then
  echo "[slowpoke] Append mode — new snapshot every ${INTERVAL}s (scroll up for history)."
  while true; do
    echo "======== $(date '+%Y-%m-%d %H:%M:%S') ========"
    print_compact
    echo ""
    if [[ -n "${LOG_FILE:-}" && -f "$LOG_FILE" ]]; then
      if [[ "$LOG_FILE" != "$prev_log" ]]; then
        prev_log="$LOG_FILE"
        prev_size=0
        stall_count=0
      fi
      size=$(wc -c <"$LOG_FILE" | tr -d ' ')
      if [[ "$size" == "$prev_size" ]]; then
        stall_count=$((stall_count + 1))
        if (( stall_count >= 8 )); then
          echo "  (no log growth ~$((stall_count * INTERVAL))s — normal during long wrk; worry if >15 min)"
          echo ""
        fi
      else
        stall_count=0
      fi
      prev_size=$size
    fi
    sleep "$INTERVAL"
  done
fi

if [[ "$MODE" == "loop-tty" ]]; then
  tty_out=/dev/tty
  [[ -w "$tty_out" ]] 2>/dev/null || tty_out=/dev/stdout
  echo "[slowpoke] Progress updates every ${INTERVAL}s on your terminal (one SSH is enough)." >"$tty_out"
  while true; do
    print_compact "$tty_out"
    echo "" >"$tty_out"
    if [[ -n "${LOG_FILE:-}" && -f "$LOG_FILE" ]]; then
      if [[ "$LOG_FILE" != "$prev_log" ]]; then
        prev_log="$LOG_FILE"
        prev_size=0
        stall_count=0
      fi
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
