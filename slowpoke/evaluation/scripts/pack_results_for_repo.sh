#!/usr/bin/env bash
# Pack netpoke-control results for scp into netpoke/results/cluster/ in git.
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
RESULTS="$EVAL/results"
STAMP=$(date +%Y%m%d)
OUT=~/netpoke_results_pack_${STAMP}.tar.gz

cd "$EVAL"
mkdir -p results/final_package

# Regenerate figures/tables if logs exist
if ls results/*_medium.log 1>/dev/null 2>&1; then
  python3 summarize_results.py results/*_medium.log >results/final_package/TABLE_L0_summary.txt 2>/dev/null || true
  bash plot_fig8_png.sh results/ 2>/dev/null || true
fi
if ls results/*_io_L*_medium.log 1>/dev/null 2>&1; then
  python3 io_gap/summarize_io_gap_matrix.py results/ -o results/final_package/io_gap_matrix.csv
  python3 io_gap/plot_io_gap_rmse.py results/ -o results/fig_io_gap_rmse.png 2>/dev/null || true
fi

tar czf "$OUT" \
  results/*_medium.log \
  results/*_io_L*_medium.log \
  results/*.png \
  results/plot_macro.pdf \
  results/fig_io_gap_rmse.png \
  results/final_package/ \
  2>/dev/null || true

echo "Packed: $OUT"
ls -lh "$OUT"
