#!/bin/bash
# Social → movie only (skip boutique/hotel). Saves each log when complete.
#
# Usage (on netpoke-control, in screen):
#   cd ~/slowpoke/evaluation
#   bash preflight_social_movie.sh
#   export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
#   WATCH_INTERVAL=10 ./run_social_movie.sh
#
if [[ -z "${SLOWPOKE_MONITOR_STARTED:-}" && -z "${SLOWPOKE_NO_MONITOR:-}" ]]; then
  export SLOWPOKE_MONITOR_STARTED=1
  exec "$(cd "${BASH_SOURCE%/*}" && pwd)/run_with_monitor.sh" bash "$0"
fi

set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
export PYTHONUNBUFFERED=1

EVAL_DIR="$(cd "${BASH_SOURCE%/*}" && pwd)"
RESULTS="$EVAL_DIR/results"
SAVED="$RESULTS/saved"
BENCHES=(social movie)

log_complete() {
  local f="$1"
  [[ -f "$f" ]] && grep -q 'Error Perc:' "$f" 2>/dev/null
}

preflight_or_exit() {
  if [[ ! -f "$SLOWPOKE_TOP/src/main.py" ]]; then
    echo "[run_social_movie] FATAL: SLOWPOKE_TOP=$SLOWPOKE_TOP invalid (no src/main.py)"
    exit 1
  fi
  if pgrep -f '[p]ython3.*main\.py' >/dev/null; then
    echo "[run_social_movie] FATAL: main.py already running"
    exit 1
  fi
  if ! kubectl cluster-info >/dev/null 2>&1; then
    echo "[run_social_movie] FATAL: kubectl cluster not reachable"
    exit 1
  fi
  for prereq in boutique hotel; do
    if ! log_complete "$RESULTS/${prereq}_medium.log"; then
      echo "[run_social_movie] FATAL: ${prereq}_medium.log not complete"
      exit 1
    fi
  done
}

save_completed_log() {
  local bench="$1"
  local src="$RESULTS/${bench}_medium.log"
  local ts
  ts=$(date +%Y%m%d-%H%M%S)

  if ! log_complete "$src"; then
    echo "[run_social_movie] ERROR: $src missing Error Perc — not saving"
    return 1
  fi

  mkdir -p "$SAVED"
  sync "$src" 2>/dev/null || true
  cp -a "$src" "$SAVED/${bench}_medium.log"
  cp -a "$src" "$SAVED/${bench}_medium-${ts}.log"
  echo "[run_social_movie] Saved $bench -> $SAVED/${bench}_medium.log (+ timestamped copy)"
}

run_benchmark() {
  local bench="$1"
  local log="$RESULTS/${bench}_medium.log"
  local script="$EVAL_DIR/${bench}/run-${bench}-medium.sh"

  if log_complete "$log"; then
    echo "[run_social_movie] SKIP: $bench already complete"
    save_completed_log "$bench" || true
    return 0
  fi

  if [[ -f "$log" ]]; then
    if [[ ! -s "$log" ]]; then
      echo "[run_social_movie] Removing empty $log"
      rm -f "$log"
    else
      local bak="${log}.bak-$(date +%Y%m%d-%H%M%S)"
      echo "[run_social_movie] Archiving incomplete $log -> $bak"
      mv "$log" "$bak"
    fi
  fi

  echo "[run_social_movie] Starting $bench ($(date -Is))"
  export SLOWPOKE_TOP
  if ! time bash "$script" "$log"; then
    echo "[run_social_movie] FATAL: $bench script failed (exit $?)"
    exit 1
  fi
  if ! log_complete "$log"; then
    echo "[run_social_movie] FATAL: $bench finished but log has no Error Perc"
    exit 1
  fi
  save_completed_log "$bench"
  echo "[run_social_movie] Finished $bench ($(date -Is))"
}

echo "[run_social_movie] SLOWPOKE_TOP=$SLOWPOKE_TOP"
preflight_or_exit

if ! grep -q 'start_rust_proxy' "$SLOWPOKE_TOP/src/run.sh" 2>/dev/null; then
  echo "[run_social_movie] FATAL: missing proxy fix in $SLOWPOKE_TOP/src/run.sh"
  echo "  Run: bash $EVAL_DIR/install_netpoke_fixes.sh"
  exit 1
fi

for prereq in boutique hotel; do
  echo "[run_social_movie] OK: $prereq already complete"
done

bash "$EVAL_DIR/safe_delete_workloads.sh"
cd "$EVAL_DIR"
mkdir -p results "$SAVED"

for bench in "${BENCHES[@]}"; do
  f="$RESULTS/${bench}_medium.log"
  if [[ -f "$f" ]] && ! log_complete "$f"; then
    if [[ ! -s "$f" ]]; then
      rm -f "$f"
    else
      bak="${f}.bak-$(date +%Y%m%d-%H%M%S)"
      echo "[run_social_movie] Archiving incomplete $f -> $bak"
      mv "$f" "$bak"
    fi
  fi
done

for bench in "${BENCHES[@]}"; do
  run_benchmark "$bench"
  bash "$EVAL_DIR/safe_delete_workloads.sh"
done

echo ""
echo "[run_social_movie] All done. Logs:"
echo "  results/social_medium.log"
echo "  results/movie_medium.log"
echo "  results/saved/   (canonical + timestamped backups)"
echo ""
bash "$EVAL_DIR/verify_benchmark_results.sh" "$RESULTS"
echo "Plots: bash $EVAL_DIR/plot_fig8_png.sh $RESULTS"
