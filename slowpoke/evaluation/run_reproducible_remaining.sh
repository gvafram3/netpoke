#!/bin/bash
# Hotel → social → movie only (skip boutique). Use after boutique_medium.log is complete.
if [[ -z "${SLOWPOKE_MONITOR_STARTED:-}" && -z "${SLOWPOKE_NO_MONITOR:-}" ]]; then
  export SLOWPOKE_MONITOR_STARTED=1
  exec "$(cd "${BASH_SOURCE%/*}" && pwd)/run_with_monitor.sh" bash "$0"
fi

export SLOWPOKE_TOP=${SLOWPOKE_TOP:-$(cd "${BASH_SOURCE%/*}/.." && pwd -P)}
export PYTHONUNBUFFERED=1

EVAL_DIR="$(cd "${BASH_SOURCE%/*}" && pwd)"
RESULTS="$EVAL_DIR/results"
BOUTIQUE_LOG="$RESULTS/boutique_medium.log"

if [[ ! -f "$BOUTIQUE_LOG" ]] || ! grep -q 'Error Perc:' "$BOUTIQUE_LOG" 2>/dev/null; then
  echo "[run_reproducible_remaining] WARN: $BOUTIQUE_LOG missing or incomplete."
  if [[ -t 0 ]]; then
    read -r -t 15 -p "Continue anyway? [y/N] " ans || ans=n
    [[ "${ans,,}" == y ]] || exit 1
  else
    echo "  Aborting (non-interactive). Run boutique first."
    exit 1
  fi
else
  echo "[run_reproducible_remaining] OK: boutique already complete."
fi

if ! grep -q 'start_rust_proxy' "$SLOWPOKE_TOP/src/run.sh" 2>/dev/null; then
  echo "[run_reproducible_remaining] ERROR: ~/slowpoke/src/run.sh missing proxy fix (start_rust_proxy)."
  echo "  Run: bash $EVAL_DIR/install_netpoke_fixes.sh"
  exit 1
fi

bash "$EVAL_DIR/safe_delete_workloads.sh"
cd "$EVAL_DIR"
mkdir -p results

for partial in hotel social movie; do
  f="$RESULTS/${partial}_medium.log"
  if [[ -f "$f" ]] && ! grep -q 'Error Perc:' "$f" 2>/dev/null; then
    bak="${f}.bak-$(date +%Y%m%d-%H%M%S)"
    echo "[run_reproducible_remaining] Archiving incomplete $f -> $bak"
    mv "$f" "$bak"
  fi
done

time bash hotel/run-hotel-medium.sh results/hotel_medium.log
time bash social/run-social-medium.sh results/social_medium.log
time bash movie/run-movie-medium.sh results/movie_medium.log

echo ""
echo "The results are stored in $(realpath ./results)"
echo "Summarize: python3 $(realpath ./summarize_results.py) results/*_medium.log"
echo "Plot (complete logs only): python3 $(realpath ./draw.py) $(realpath ./results)"
