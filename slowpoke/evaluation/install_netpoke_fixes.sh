#!/usr/bin/env bash
# Verify / apply fixes required for hotel, social, movie on netpoke-control.
set -euo pipefail

SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
RUN_SH="$SLOWPOKE_TOP/src/run.sh"
FAIL=0

ok() { echo "  OK: $*"; }
warn() { echo "  WARN: $*"; }
bad() { echo "  FAIL: $*"; FAIL=1; }

echo "=== NetPoke SlowPoke fix check (SLOWPOKE_TOP=$SLOWPOKE_TOP) ==="

[[ -f "$RUN_SH" ]] && ok "run.sh exists" || { bad "missing $RUN_SH"; exit 1; }

if grep -q 'start_rust_proxy' "$RUN_SH" && grep -q 'nohup.*proxy' "$RUN_SH"; then
  ok "run.sh proxy fix (nohup + start_rust_proxy)"
else
  bad "run.sh still uses blocking kubectl exec for proxy"
  echo "       Update from repo branch cursor/cluster-diagnose-multi-zone-eab9:"
  echo "       git -C ~/slowpoke pull   # or scp slowpoke/src/run.sh from your laptop"
fi

[[ -x "$EVAL/safe_delete_workloads.sh" ]] && ok "safe_delete_workloads.sh" \
  || bad "missing $EVAL/safe_delete_workloads.sh"

for script in hotel/run-hotel-medium.sh social/run-social-medium.sh movie/run-movie-medium.sh; do
  f="$EVAL/$script"
  if [[ -f "$f" ]] && grep -q '\-\-repetitions' "$f" && grep -q 'safe_delete_workloads' "$f"; then
    ok "$script"
  else
    bad "$script needs --repetitions and safe_delete_workloads.sh"
  fi
done

[[ -f "$EVAL/summarize_results.py" ]] && ok "summarize_results.py" \
  || warn "summarize_results.py not installed (optional)"

[[ -f "$EVAL/run_reproducible_remaining.sh" ]] && ok "run_reproducible_remaining.sh" \
  || warn "run_reproducible_remaining.sh not installed"

[[ -f "$EVAL/run_social_movie.sh" ]] && ok "run_social_movie.sh" \
  || warn "run_social_movie.sh not installed"

for data in hotel/data/analysis.txt movie/data/analysis.txt social/data/analysis.txt; do
  [[ -f "$SLOWPOKE_TOP/evaluation/${data#$SLOWPOKE_TOP/evaluation/}" ]] && ok "$data" || bad "missing $data"
done

if [[ -f "$EVAL/boutique/yamls/shipping_netpoke.yaml" ]]; then
  bad "shipping_netpoke.yaml still present (breaks boutique shipping image)"
  echo "       Run: mv $EVAL/boutique/yamls/shipping_netpoke.yaml{,.off}"
elif [[ -f "$EVAL/boutique/yamls/shipping.yaml" ]]; then
  ok "boutique shipping.yaml"
else
  warn "boutique shipping.yaml missing"
fi

echo ""
if (( FAIL )); then
  echo "Fix failures above, then re-run this script."
  exit 1
fi

echo "All checks passed. Preflight hotel:"
bash "$EVAL/diagnose_benchmark.sh" hotel 2>/dev/null || true
echo ""
echo "Run remaining benchmarks:"
echo "  cd $EVAL && screen -S slowpoke-rest"
echo "  export SLOWPOKE_TOP=$SLOWPOKE_TOP PYTHONUNBUFFERED=1"
echo "  WATCH_INTERVAL=10 ./run_reproducible_remaining.sh"
echo ""
echo "Or social → movie only (saves to results/saved/ on each finish):"
echo "  cd $EVAL && screen -S slowpoke-social-movie"
echo "  export SLOWPOKE_TOP=$SLOWPOKE_TOP PYTHONUNBUFFERED=1"
echo "  WATCH_INTERVAL=10 ./run_social_movie.sh"
