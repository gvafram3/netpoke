#!/usr/bin/env bash
# Run all Phase 3 I/O-gap experiments sequentially (8 logs: 4 apps × L1/L2).
# Prefer screen + run_with_monitor.sh per run; this script is for unattended batch.
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
IO_GAP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL="$(cd "$IO_GAP/.." && pwd)"
RESULTS="${RESULTS_DIR:-$EVAL/results}"
mkdir -p "$RESULTS/saved"

echo "=== Phase 3 I/O-gap suite (sequential) ==="
echo "Results: $RESULTS"
bash "$IO_GAP/preflight_io_gap.sh" "$RESULTS"

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

for entry in "${ORDER[@]}"; do
  bench="${entry%%:*}"
  level="${entry##*:}"
  log="$RESULTS/${bench}_io_${level}_medium.log"
  echo ""
  echo ">>> $bench $level → $log"
  if [[ -f "$log" ]] && grep -q 'Error Perc:' "$log"; then
    echo "    SKIP: already complete"
    continue
  fi
  bash "$IO_GAP/run_io_medium.sh" "$bench" "$level" "$log"
  if grep -q 'Error Perc:' "$log"; then
    cp -a "$log" "$RESULTS/saved/${bench}_io_${level}_medium-$(date +%Y%m%d).log"
  fi
  bash "$SLOWPOKE_TOP/evaluation/safe_delete_workloads.sh" || true
done

bash "$IO_GAP/verify_io_gap_results.sh" "$RESULTS"
