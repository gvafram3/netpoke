#!/usr/bin/env bash
# Re-run boutique L1/L2 only (product_catalog path injection — replaces shipping runs).
#
# On netpoke-control:
#   export SLOWPOKE_TOP=~/slowpoke
#   cd ~/slowpoke/evaluation
#   bash io_gap/run_boutique_io_rerun.sh
#
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
IO_GAP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL="$(cd "$IO_GAP/.." && pwd)"
RESULTS="${RESULTS_DIR:-$EVAL/results}"
ARCH="$RESULTS/saved/boutique_shipping_inject_20260607"

mkdir -p "$ARCH" "$RESULTS/saved"

archive_if_exists() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  echo "[boutique_rerun] Archive -> $ARCH/$(basename "$f")"
  cp -a "$f" "$ARCH/"
  rm -f "$f"
}

echo "[boutique_rerun] Archive prior boutique io_gap logs (shipping injection)"
archive_if_exists "$RESULTS/boutique_io_L1_medium.log"
archive_if_exists "$RESULTS/boutique_io_L2_medium.log"

bash "$IO_GAP/restore_io_injection.sh" || true
pkill -f 'python3.*main\.py' 2>/dev/null || true
bash "$EVAL/safe_delete_workloads.sh"

for level in L1 L2; do
  log="$RESULTS/boutique_io_${level}_medium.log"
  echo ""
  echo "================================================================"
  echo "[boutique_rerun] boutique $level -> $log"
  echo "================================================================"
  time bash "$EVAL/boutique/run-boutique-medium-io-${level}.sh" "$log"
  cp -a "$log" "$RESULTS/saved/boutique_io_${level}_medium.log"
done

python3 "$IO_GAP/summarize_io_gap_matrix.py" "$RESULTS"
echo "[boutique_rerun] Done."
