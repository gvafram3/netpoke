#!/usr/bin/env bash
# Build a single downloadable tarball: tables (CSV/MD), figures (PNG/PDF), sample logs.
#
# On netpoke-control (after logs exist):
#   export SLOWPOKE_TOP=~/slowpoke
#   bash ~/slowpoke/evaluation/scripts/build_presentation_pack.sh
#
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
RESULTS="$EVAL/results"
STAMP=$(date +%Y%m%d)
PACK=~/netpoke_presentation_pack_${STAMP}
OUT=~/netpoke_presentation_pack_${STAMP}.tar.gz

rm -rf "$PACK"
mkdir -p "$PACK"/{baseline,io_gap,ebpf,reference_note}

cd "$EVAL"
mkdir -p results/final_package

# --- Baseline (paper Fig. 8 style) ---
if ls results/*_medium.log 1>/dev/null 2>&1; then
  python3 summarize_results.py results/boutique_medium.log results/hotel_medium.log \
    results/social_medium.log results/movie_medium.log \
    >"$PACK/baseline/TABLE_L0_summary.txt" 2>/dev/null || true
  bash plot_fig8_png.sh results/ 2>/dev/null || true
  cp -a results/boutique_medium.png results/hotel_medium.png \
        results/social_medium.png results/movie_medium.png \
        results/plot_macro.pdf "$PACK/baseline/" 2>/dev/null || true
  cp -a results/boutique_medium.log results/hotel_medium.log \
        results/social_medium.log results/movie_medium.log \
        "$PACK/baseline/" 2>/dev/null || true
fi

# --- Phase 3 I/O gap (thesis Fig I1) ---
if ls results/*_io_L*_medium.log 1>/dev/null 2>&1; then
  python3 io_gap/summarize_io_gap_matrix.py results/ \
    -o "$PACK/io_gap/io_gap_matrix.csv" 2>/dev/null || true
  python3 io_gap/plot_io_gap_rmse.py results/ -o "$PACK/io_gap/fig_io_gap_rmse.png" 2>/dev/null || true
fi

# --- Phase 4 eBPF ---
if ls results/*_ebpf_L2_residual.jsonl 1>/dev/null 2>&1; then
  python3 phase4_ebpf/summarize_ebpf_residual.py results/ \
    -o "$PACK/ebpf/ebpf_residual_summary.csv" 2>/dev/null || true
  python3 phase4_ebpf/summarize_ebpf_residual.py results/ \
    >"$PACK/ebpf/ebpf_residual_summary.txt" 2>/dev/null || true
  python3 phase4_ebpf/plot_ebpf_residual.py results/ -o "$PACK/ebpf" 2>/dev/null || true
  cp -a results/*_ebpf_L2_medium.log results/*_ebpf_L2_residual.jsonl "$PACK/ebpf/" 2>/dev/null || true
fi

cat >"$PACK/reference_note/HOW_TO_READ.txt" <<'EOF'
NetPoke presentation pack — figure guide

baseline/     SlowPoke paper §5.1 style (Fig. 8 panels + macro PDF)
io_gap/       Thesis Phase 3 — RMSE vs I/O level (not in base paper)
ebpf/         Thesis Phase 4 — residual I/O during SIGSTOP (not in base paper)

Per-app panel: X = optimisation point; Y = throughput; Groundtruth vs Predicted.
RMSE: summarize_results.py over 10 Error Perc values.

See netpoke/docs/figures-and-tables-master.md in git for full mapping.
EOF

tar czf "$OUT" -C "$(dirname "$PACK")" "$(basename "$PACK")"
echo "Packed: $OUT"
ls -lh "$OUT"
