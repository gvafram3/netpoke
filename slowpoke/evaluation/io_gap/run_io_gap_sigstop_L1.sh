#!/usr/bin/env bash
# Run 3: SIGSTOP-only L1 accuracy benchmark, all four apps.
# Compare resulting RMSE against Run 4 (NetPoke-on L1) logs.
#
# SSH 1 (screen):
#   cd ~/slowpoke/evaluation
#   export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
#   export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
#   screen -S rep-l1-sigstop
#   WATCH_INTERVAL=10 ./io_gap/run_io_gap_sigstop_L1.sh
#   Ctrl+A D
#
# SSH 2:
#   cd ~/slowpoke/evaluation
#   export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
#   ./watch_progress.sh --append
#
set -euo pipefail

if [[ -z "${SLOWPOKE_MONITOR_STARTED:-}" && -z "${SLOWPOKE_NO_MONITOR:-}" ]]; then
  export SLOWPOKE_MONITOR_STARTED=1
  EVAL_DIR="$(cd "${BASH_SOURCE%/*}/.." && pwd)"
  exec "$EVAL_DIR/run_with_monitor.sh" bash "$0" "$@"
fi

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
export SLOWPOKE_NETPOKE=0
export SLOWPOKE_YAML_SUBDIR=netpoke-sigstop
export PYTHONUNBUFFERED=1

IO_GAP="$(cd "${BASH_SOURCE%/*}" && pwd)"
EVAL="$(cd "$IO_GAP/.." && pwd)"
RESULTS="${RESULTS_DIR:-}"
if [[ -z "$RESULTS" ]]; then
  echo "ERROR: RESULTS_DIR is not set." >&2
  echo "  Fix: export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/\$REP" >&2
  exit 1
fi
SAVED="$RESULTS/saved"
ACTIVE_STAMP="$RESULTS/.slowpoke_active_log"
mkdir -p "$RESULTS" "$SAVED"

APPS=(boutique hotel social movie)

log_complete() {
  [[ -f "$1" ]] && grep -q 'Error Perc:' "$1" 2>/dev/null
}

set_active_log() {
  export SLOWPOKE_ACTIVE_LOG="$1"
  echo "$1" >"$ACTIVE_STAMP"
}

save_log() {
  local bench="$1" src="$2" ts
  ts=$(date +%Y%m%d-%H%M%S)
  sync "$src" 2>/dev/null || true
  cp -a "$src" "$SAVED/${bench}_io_L1_sigstop_medium.log"
  cp -a "$src" "$SAVED/${bench}_io_L1_sigstop_medium-${ts}.log"
  echo "[sigstop_l1] Saved -> $SAVED/${bench}_io_L1_sigstop_medium.log"
}

if [[ ! -f "$SLOWPOKE_TOP/src/main.py" ]]; then
  echo "[sigstop_l1] FATAL: SLOWPOKE_TOP=$SLOWPOKE_TOP invalid"
  exit 1
fi
if pgrep -f '[p]ython3.*main\.py' >/dev/null; then
  echo "[sigstop_l1] FATAL: main.py already running (stop stuck run first)"
  pgrep -af '[p]ython3.*main\.py' || true
  exit 1
fi
bash "$IO_GAP/restore_io_injection.sh" || true
bash "$EVAL/safe_delete_workloads.sh"
cd "$EVAL"

for bench in "${APPS[@]}"; do
  log="$RESULTS/${bench}_io_L1_sigstop_medium.log"

  echo ""
  echo "================================================================"
  echo "[sigstop_l1] $bench L1, SLOWPOKE_NETPOKE=0 (SIGSTOP-only)"
  echo "[sigstop_l1] Log: $log"
  echo "[sigstop_l1] Started: $(date -Is)"
  echo "================================================================"

  if log_complete "$log"; then
    echo "[sigstop_l1] SKIP: already complete"
    save_log "$bench" "$log"
    continue
  fi
  if [[ -f "$log" && ! -s "$log" ]]; then
    rm -f "$log"
  fi

  set_active_log "$log"

  if ! time bash "$IO_GAP/run_io_medium.sh" "$bench" L1 "$log"; then
    echo "[sigstop_l1] FATAL: $bench L1 failed"
    bash "$IO_GAP/restore_io_injection.sh" || true
    exit 1
  fi
  if ! log_complete "$log"; then
    echo "[sigstop_l1] FATAL: $bench L1 ended without Error Perc:"
    bash "$IO_GAP/restore_io_injection.sh" || true
    exit 1
  fi

  save_log "$bench" "$log"
  echo "[sigstop_l1] Finished $bench L1 ($(date -Is))"
  bash "$EVAL/safe_delete_workloads.sh" || true
done

rm -f "$ACTIVE_STAMP"
echo ""
echo "[sigstop_l1] All 4 SIGSTOP-only L1 runs complete."
echo "[sigstop_l1] Per-app tables:"
for bench in "${APPS[@]}"; do
  echo "  python3 summarize_results.py $RESULTS/${bench}_io_L1_sigstop_medium.log"
done
