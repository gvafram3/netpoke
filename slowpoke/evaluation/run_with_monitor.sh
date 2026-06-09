#!/usr/bin/env bash
# Run SlowPoke evaluation in ONE SSH session with live counters on your terminal.
#
# The experiment still writes to results/*.log (scripts use ">log"). A background
# task reads those logs and prints workload/point counters to /dev/tty every
# WATCH_INTERVAL seconds (default 20).
#
# Usage (on netpoke-control, inside screen recommended):
#   cd ~/slowpoke/evaluation
#   ./run_with_monitor.sh
#   ./run_with_monitor.sh ./run_functional.sh
#
# Optional: split terminal with tmux (still one SSH):
#   SLOWPOKE_TMUX=1 ./run_with_monitor.sh
#
# Disable auto-monitor:
#   SLOWPOKE_NO_MONITOR=1 ./run_reproducible.sh

set -euo pipefail

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RESULTS_DIR="${RESULTS_DIR:-$EVAL_DIR/results}"
INTERVAL="${WATCH_INTERVAL:-20}"

usage() {
  cat <<EOF
Usage: $0 [command ...]

Default command: ./run_reproducible.sh

Examples:
  $0
  $0 ./run_functional.sh
  WATCH_INTERVAL=10 $0 bash boutique/run-boutique-medium.sh results/boutique_medium.log
  SLOWPOKE_TMUX=1 $0    # tmux: run on top, watch_progress below (one SSH)

Environment:
  WATCH_INTERVAL     seconds between counter updates (default 20)
  SLOWPOKE_NO_MONITOR  set to skip this wrapper
  SLOWPOKE_TMUX=1    use tmux split if available
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ "${SLOWPOKE_TMUX:-}" == "1" ]] && command -v tmux >/dev/null \
    && [[ -t 1 ]] && [[ -z "${SLOWPOKE_MONITOR_ACTIVE:-}" ]]; then
  export SLOWPOKE_MONITOR_ACTIVE=1
  cmd=("$0" --no-tmux)
  (( $# > 0 )) && cmd+=("$@") || cmd+=(./run_reproducible.sh)
  exec tmux new-session -d -s slowpoke -c "$EVAL_DIR" "${cmd[@]}" \; \
    split-window -v -c "$EVAL_DIR" "WATCH_INTERVAL=5 $EVAL_DIR/watch_progress.sh" \; \
    select-pane -t 0 \; attach -t slowpoke
fi

if [[ "${1:-}" == "--no-tmux" ]]; then
  shift
fi

if (( $# == 0 )); then
  set -- ./run_reproducible.sh
fi

mkdir -p "$RESULTS_DIR"
export WATCH_INTERVAL="$INTERVAL"
export PYTHONUNBUFFERED=1

# Pin the log file the monitor parses (avoids sticking on a finished boutique log).
case " $* " in
  *run_functional*) export SLOWPOKE_ACTIVE_LOG="$RESULTS_DIR/boutique_tiny.log" ;;
  *boutique_medium*) export SLOWPOKE_ACTIVE_LOG="$RESULTS_DIR/boutique_medium.log" ;;
  *hotel_medium*) export SLOWPOKE_ACTIVE_LOG="$RESULTS_DIR/hotel_medium.log" ;;
  *social_medium*) export SLOWPOKE_ACTIVE_LOG="$RESULTS_DIR/social_medium.log" ;;
  *movie_medium*) export SLOWPOKE_ACTIVE_LOG="$RESULTS_DIR/movie_medium.log" ;;
  *io_L1_medium*) export SLOWPOKE_ACTIVE_LOG="" ;;  # set per-run by run_io_gap_all.sh
  *io_L2_medium*) export SLOWPOKE_ACTIVE_LOG="" ;;
  *run_io_gap_all*|*run_io_gap_suite*) export SLOWPOKE_ACTIVE_LOG="" SLOWPOKE_IO_GAP_SUITE=1 ;;
  *run_ebpf_all*|*phase4_ebpf*) export SLOWPOKE_ACTIVE_LOG="" SLOWPOKE_PHASE4_EBPF=1 ;;
  *ebpf_L2_medium*) export SLOWPOKE_ACTIVE_LOG="" SLOWPOKE_PHASE4_EBPF=1 ;;
  *run_reproducible_remaining*|*run_social_movie*) export SLOWPOKE_ACTIVE_LOG="" ;;  # pick via main.py -b
  *) export SLOWPOKE_ACTIVE_LOG="" ;;
esac

"${EVAL_DIR}/watch_progress.sh" --loop-tty "$RESULTS_DIR" &
wpid=$!
cleanup() {
  kill "$wpid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

cd "$EVAL_DIR"
echo "Starting: $*"
echo "Logs: $RESULTS_DIR/*.log  |  counters every ${INTERVAL}s below"
echo "Monitor log: ${SLOWPOKE_ACTIVE_LOG:-auto (first incomplete *_medium.log)}"
echo ""

"$@"

echo ""
echo "[slowpoke] Run finished. Final status:"
"${EVAL_DIR}/watch_progress.sh" --once "$RESULTS_DIR"
