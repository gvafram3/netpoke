#!/bin/bash
# Social → movie only (skip boutique/hotel). Saves each log when complete.
#
# Usage (on netpoke-control, in screen):
#   cd ~/slowpoke/evaluation
#   export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
#   WATCH_INTERVAL=10 ./run_social_movie.sh
#
if [[ -z "${SLOWPOKE_MONITOR_STARTED:-}" && -z "${SLOWPOKE_NO_MONITOR:-}" ]]; then
  export SLOWPOKE_MONITOR_STARTED=1
  exec "$(cd "${BASH_SOURCE%/*}" && pwd)/run_with_monitor.sh" bash "$0"
fi

set -euo pipefail

export SLOWPOKE_TOP=${SLOWPOKE_TOP:-$(cd "${BASH_SOURCE%/*}/.." && pwd -P)}
export PYTHONUNBUFFERED=1

EVAL_DIR="$(cd "${BASH_SOURCE%/*}" && pwd)"
RESULTS="$EVAL_DIR/results"
SAVED="$RESULTS/saved"
BENCHES=(social movie)

log_complete() {
  local f="$1"
  [[ -f "$f" ]] && grep -q 'Error Perc:' "$f" 2>/dev/null
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
    local bak="${log}.bak-$(date +%Y%m%d-%H%M%S)"
    echo "[run_social_movie] Archiving incomplete $log -> $bak"
    mv "$log" "$bak"
  fi

  echo "[run_social_movie] Starting $bench ($(date -Is))"
  time bash "$script" "$log"
  save_completed_log "$bench"
  echo "[run_social_movie] Finished $bench ($(date -Is))"
}

echo "[run_social_movie] SLOWPOKE_TOP=$SLOWPOKE_TOP"

if ! grep -q 'start_rust_proxy' "$SLOWPOKE_TOP/src/run.sh" 2>/dev/null; then
  echo "[run_social_movie] ERROR: missing proxy fix in $SLOWPOKE_TOP/src/run.sh"
  echo "  Run: bash $EVAL_DIR/install_netpoke_fixes.sh"
  exit 1
fi

for prereq in boutique hotel; do
  pf="$RESULTS/${prereq}_medium.log"
  if ! log_complete "$pf"; then
    echo "[run_social_movie] WARN: $pf missing or incomplete (expected before social/movie)"
  else
    echo "[run_social_movie] OK: $prereq already complete"
  fi
done

bash "$EVAL_DIR/safe_delete_workloads.sh"
cd "$EVAL_DIR"
mkdir -p results "$SAVED"

for bench in "${BENCHES[@]}"; do
  f="$RESULTS/${bench}_medium.log"
  if [[ -f "$f" ]] && ! log_complete "$f"; then
    bak="${f}.bak-$(date +%Y%m%d-%H%M%S)"
    echo "[run_social_movie] Archiving incomplete $f -> $bak"
    mv "$f" "$bak"
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
if [[ -f "$EVAL_DIR/summarize_results.py" ]]; then
  python3 "$EVAL_DIR/summarize_results.py" \
    "$RESULTS/boutique_medium.log" \
    "$RESULTS/hotel_medium.log" \
    "$RESULTS/social_medium.log" \
    "$RESULTS/movie_medium.log" || true
fi
echo "Plots: bash $EVAL_DIR/plot_fig8_png.sh $RESULTS"
