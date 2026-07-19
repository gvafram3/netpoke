#!/usr/bin/env bash
# Phase 5/6: re-run the standard L2 I/O-gap accuracy benchmark with NetPoke's
# egress hold enabled, across all four apps, so the resulting RMSE can be
# compared directly against the SIGSTOP-only L2 numbers already recorded in
# netpoke/results/cluster/io_gap/tables/TABLE_IO_GAP_MATRIX.md.
#
# This is deliberately the *same* accuracy run as Phase 3 (io_gap/run_io_medium.sh,
# same targets, same netem injection) with one difference: SLOWPOKE_NETPOKE=1,
# which makes src/run.sh deploy the netpoke-tagged image/yaml (poker.c's
# sch_plug egress hold armed on every SIGSTOP/SIGCONT) instead of the plain
# SIGSTOP-only image. That is the same deployment path already exercised
# successfully for all four apps by phase6_netpoke/run_residual_check.sh
# (Table N1) -- this script runs the accuracy benchmark on top of it instead
# of the residual-I/O sampler.
#
# SSH 1 (screen) — monitor prints on your terminal automatically:
#   cd ~/slowpoke/evaluation
#   export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
#   screen -S slowpoke-netpoke-rmse
#   WATCH_INTERVAL=10 ./io_gap/run_io_gap_netpoke_L2.sh
#   Ctrl+A D
#
# SSH 2 — live, accumulating dashboard:
#   cd ~/slowpoke/evaluation
#   ./watch_progress.sh --append results/
#
set -euo pipefail

if [[ -z "${SLOWPOKE_MONITOR_STARTED:-}" && -z "${SLOWPOKE_NO_MONITOR:-}" ]]; then
  export SLOWPOKE_MONITOR_STARTED=1
  EVAL_DIR="$(cd "${BASH_SOURCE%/*}/.." && pwd)"
  exec "$EVAL_DIR/run_with_monitor.sh" bash "$0" "$@"
fi

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
export SLOWPOKE_NETPOKE=1
export PYTHONUNBUFFERED=1

IO_GAP="$(cd "${BASH_SOURCE%/*}" && pwd)"
EVAL="$(cd "$IO_GAP/.." && pwd)"
RESULTS="${RESULTS_DIR:-$EVAL/results}"
SAVED="$RESULTS/saved"
mkdir -p "$RESULTS" "$SAVED"

APPS=(boutique hotel social movie)

log_complete() {
  [[ -f "$1" ]] && grep -q 'Error Perc:' "$1" 2>/dev/null
}

save_log() {
  local bench="$1" src="$2" ts
  ts=$(date +%Y%m%d-%H%M%S)
  sync "$src" 2>/dev/null || true
  cp -a "$src" "$SAVED/${bench}_io_L2_netpoke_medium.log"
  cp -a "$src" "$SAVED/${bench}_io_L2_netpoke_medium-${ts}.log"
  echo "[netpoke_rmse] Saved -> $SAVED/${bench}_io_L2_netpoke_medium.log"
}

if [[ ! -f "$SLOWPOKE_TOP/src/main.py" ]]; then
  echo "[netpoke_rmse] FATAL: SLOWPOKE_TOP=$SLOWPOKE_TOP invalid"
  exit 1
fi
if pgrep -f '[p]ython3.*main\.py' >/dev/null; then
  echo "[netpoke_rmse] FATAL: main.py already running (stop stuck run first)"
  pgrep -af '[p]ython3.*main\.py' || true
  exit 1
fi
bash "$IO_GAP/restore_io_injection.sh" || true
bash "$EVAL/safe_delete_workloads.sh"
cd "$EVAL"

for bench in "${APPS[@]}"; do
  log="$RESULTS/${bench}_io_L2_netpoke_medium.log"

  echo ""
  echo "================================================================"
  echo "[netpoke_rmse] $bench L2, SLOWPOKE_NETPOKE=1"
  echo "[netpoke_rmse] Log: $log"
  echo "[netpoke_rmse] Started: $(date -Is)"
  echo "================================================================"

  if log_complete "$log"; then
    echo "[netpoke_rmse] SKIP: already complete"
    save_log "$bench" "$log"
    continue
  fi
  if [[ -f "$log" && ! -s "$log" ]]; then
    rm -f "$log"
  fi

  if ! time bash "$IO_GAP/run_io_medium.sh" "$bench" L2 "$log"; then
    echo "[netpoke_rmse] FATAL: $bench L2 failed"
    bash "$IO_GAP/restore_io_injection.sh" || true
    exit 1
  fi
  if ! log_complete "$log"; then
    echo "[netpoke_rmse] FATAL: $bench L2 ended without Error Perc:"
    bash "$IO_GAP/restore_io_injection.sh" || true
    exit 1
  fi

  save_log "$bench" "$log"
  echo "[netpoke_rmse] Finished $bench L2 ($(date -Is))"
  bash "$EVAL/safe_delete_workloads.sh" || true
done

echo ""
echo "[netpoke_rmse] All 4 NetPoke-on L2 runs complete."
echo "[netpoke_rmse] Compare against SIGSTOP-only L2 RMSE in"
echo "[netpoke_rmse]   netpoke/results/cluster/io_gap/tables/TABLE_IO_GAP_MATRIX.md"
echo "[netpoke_rmse] Per-app tables:"
for bench in "${APPS[@]}"; do
  echo "  python3 summarize_results.py $RESULTS/${bench}_io_L2_netpoke_medium.log"
done
