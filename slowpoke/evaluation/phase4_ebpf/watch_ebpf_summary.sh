#!/usr/bin/env bash
# Live Phase 4 numbers table (residual I/O + RMSE) — third SSH session.
#
#   export WATCH_INTERVAL=10
#   cd ~/slowpoke/evaluation
#   ./phase4_ebpf/watch_ebpf_summary.sh
#
# Scrollable history (recommended for third SSH):
#   ./phase4_ebpf/watch_ebpf_summary.sh --append
#
# One shot:
#   ./phase4_ebpf/watch_ebpf_summary.sh --once
#
set -u

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$EVAL_DIR/results}"
INTERVAL="${WATCH_INTERVAL:-10}"
MODE="fullscreen"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) MODE=once; shift ;;
    --append) MODE=append; shift ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *)
      if [[ -d "$1" ]]; then
        RESULTS_DIR="$1"
      fi
      shift
      ;;
  esac
done

print_block() {
  echo "── Phase 4 numbers $(date '+%Y-%m-%d %H:%M:%S') ──"
  if [[ -f "$RESULTS_DIR/.slowpoke_active_log" ]]; then
    echo "Active log: $(cat "$RESULTS_DIR/.slowpoke_active_log")"
  elif pgrep -f 'python3.*main\.py' >/dev/null 2>&1; then
    echo "Active: main.py running"
  else
    echo "Active: (idle between runs)"
  fi
  echo ""
  if python3 "$EVAL_DIR/phase4_ebpf/summarize_ebpf_residual.py" "$RESULTS_DIR" 2>/dev/null; then
    :
  else
    echo "No *_ebpf_L2_residual.jsonl yet — waiting for first benchmark..."
  fi
  echo ""
  echo "Refresh every ${INTERVAL}s · Ctrl+C to stop · results: $RESULTS_DIR"
}

case "$MODE" in
  once)
    print_block
    ;;
  append)
    while true; do
      print_block
      echo ""
      sleep "$INTERVAL"
    done
    ;;
  fullscreen)
    while true; do
      clear
      print_block
      sleep "$INTERVAL"
    done
    ;;
esac
