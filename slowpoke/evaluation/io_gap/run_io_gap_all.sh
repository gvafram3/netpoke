#!/usr/bin/env bash
# Phase 3: run all eight I/O-gap experiments sequentially (boutique L1 → … → movie L2).
#
# SSH 1 (screen) — monitor prints on your terminal automatically:
#   cd ~/slowpoke/evaluation
#   export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
#   screen -S slowpoke-io-gap
#   WATCH_INTERVAL=10 ./io_gap/run_io_gap_all.sh
#   Ctrl+A D
#
# SSH 2 — same counters, auto-follows the active run's log:
#   cd ~/slowpoke/evaluation
#   WATCH_INTERVAL=10 ./watch_progress.sh --loop-tty
#
set -euo pipefail

if [[ -z "${SLOWPOKE_MONITOR_STARTED:-}" && -z "${SLOWPOKE_NO_MONITOR:-}" ]]; then
  export SLOWPOKE_MONITOR_STARTED=1
  export SLOWPOKE_IO_GAP_SUITE=1
  EVAL_DIR="$(cd "${BASH_SOURCE%/*}/.." && pwd)"
  exec "$EVAL_DIR/run_with_monitor.sh" bash "$0" "$@"
fi

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
export SLOWPOKE_IO_GAP_SUITE=1
export PYTHONUNBUFFERED=1

IO_GAP="$(cd "${BASH_SOURCE%/*}" && pwd)"
EVAL="$(cd "$IO_GAP/.." && pwd)"
RESULTS="${RESULTS_DIR:-$EVAL/results}"
SAVED="$RESULTS/saved"
ACTIVE_STAMP="$RESULTS/.slowpoke_active_log"
mkdir -p "$RESULTS" "$SAVED"

# shellcheck source=io_levels.conf
source "$IO_GAP/io_levels.conf"

ORDER=(
  boutique:L1
  boutique:L2
  hotel:L1
  hotel:L2
  social:L1
  social:L2
  movie:L1
  movie:L2
)

log_complete() {
  local f="$1"
  [[ -f "$f" ]] && grep -q 'Error Perc:' "$f" 2>/dev/null
}

set_active_log() {
  local log="$1"
  export SLOWPOKE_ACTIVE_LOG="$log"
  echo "$log" >"$ACTIVE_STAMP"
}

preflight_or_exit() {
  if [[ ! -f "$SLOWPOKE_TOP/src/main.py" ]]; then
    echo "[io_gap_all] FATAL: SLOWPOKE_TOP=$SLOWPOKE_TOP invalid"
    exit 1
  fi
  if pgrep -f '[p]ython3.*main\.py' >/dev/null; then
    echo "[io_gap_all] FATAL: main.py already running (stop stuck run first)"
    pgrep -af '[p]ython3.*main\.py' || true
    exit 1
  fi
  rm -f "$SLOWPOKE_TOP/evaluation/boutique/yamls/shipping_io_l2.yaml"
  bash "$IO_GAP/disable_boutique_l2_io.sh" || true
  bash "$IO_GAP/preflight_io_gap.sh" "$RESULTS"
}

save_log() {
  local bench="$1" level="$2" src="$3"
  local ts
  ts=$(date +%Y%m%d-%H%M%S)
  sync "$src" 2>/dev/null || true
  cp -a "$src" "$SAVED/${bench}_io_${level}_medium.log"
  cp -a "$src" "$SAVED/${bench}_io_${level}_medium-${ts}.log"
  echo "[io_gap_all] Saved -> $SAVED/${bench}_io_${level}_medium.log"
}

run_one() {
  local bench="$1" level="$2"
  local log="$RESULTS/${bench}_io_${level}_medium.log"
  local script="$EVAL/${bench}/run-${bench}-medium-io-${level}.sh"

  echo ""
  echo "================================================================"
  echo "[io_gap_all] Run $(run_index "$bench" "$level")/8: $bench $level"
  echo "[io_gap_all] Log: $log"
  echo "[io_gap_all] Started: $(date -Is)"
  echo "================================================================"

  if log_complete "$log"; then
    echo "[io_gap_all] SKIP: already complete"
    save_log "$bench" "$level" "$log" || true
    set_active_log "$log"
    return 0
  fi

  if [[ -f "$log" ]]; then
    if [[ ! -s "$log" ]]; then
      rm -f "$log"
    elif ! log_complete "$log"; then
      local bak="${log}.bak-$(date +%Y%m%d-%H%M%S)"
      echo "[io_gap_all] Archiving incomplete log -> $bak"
      mv "$log" "$bak"
    fi
  fi

  set_active_log "$log"

  if [[ ! -x "$script" ]]; then
    echo "[io_gap_all] FATAL: missing $script"
    exit 1
  fi

  if ! time bash "$script" "$log"; then
    echo "[io_gap_all] FATAL: $bench $level failed (exit $?)"
    bash "$IO_GAP/disable_boutique_l2_io.sh" || true
    exit 1
  fi

  if ! log_complete "$log"; then
    echo "[io_gap_all] FATAL: $bench $level ended without Error Perc:"
    bash "$IO_GAP/disable_boutique_l2_io.sh" || true
    exit 1
  fi

  save_log "$bench" "$level" "$log"
  echo "[io_gap_all] Finished $bench $level ($(date -Is))"
  bash "$EVAL/safe_delete_workloads.sh" || true
}

run_index() {
  local b="$1" l="$2" i=1 entry bb ll
  for entry in "${ORDER[@]}"; do
    bb="${entry%%:*}"
    ll="${entry##*:}"
    if [[ "$bb" == "$b" && "$ll" == "$l" ]]; then
      echo "$i"
      return
    fi
    i=$((i + 1))
  done
  echo "?"
}

echo "[io_gap_all] SLOWPOKE_TOP=$SLOWPOKE_TOP"
preflight_or_exit

if ! grep -q 'Waiting for all pod containers to be ready' "$SLOWPOKE_TOP/src/run.sh" 2>/dev/null; then
  echo "[io_gap_all] WARN: run.sh may not accept 2/2 pods (boutique L2). Patch from latest io_gap branch."
fi

bash "$EVAL/safe_delete_workloads.sh"
cd "$EVAL"

for entry in "${ORDER[@]}"; do
  bench="${entry%%:*}"
  level="${entry##*:}"
  run_one "$bench" "$level"
done

rm -f "$ACTIVE_STAMP"
echo ""
echo "[io_gap_all] All 8 runs complete."
bash "$IO_GAP/verify_io_gap_results.sh" "$RESULTS"
python3 "$IO_GAP/summarize_io_gap_matrix.py" "$RESULTS" \
  -o "$RESULTS/final_package/io_gap_matrix.csv" 2>/dev/null || \
  python3 "$IO_GAP/summarize_io_gap_matrix.py" "$RESULTS"
