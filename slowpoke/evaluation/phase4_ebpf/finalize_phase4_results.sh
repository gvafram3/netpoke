#!/usr/bin/env bash
# Run when all four Phase 4 L2 runs are complete (including boutique).
#
# On netpoke-control:
#   export SLOWPOKE_TOP=~/slowpoke
#   cd ~/slowpoke/evaluation
#   bash phase4_ebpf/finalize_phase4_results.sh
#
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
P4="$EVAL/phase4_ebpf"
RESULTS="${RESULTS_DIR:-$EVAL/results}"
FP="$RESULTS/final_package"

mkdir -p "$FP"

echo "=== Phase 4 finalize — verify logs ==="
for app in social hotel movie boutique; do
  log="$RESULTS/${app}_ebpf_L2_medium.log"
  jsonl="$RESULTS/${app}_ebpf_L2_residual.jsonl"
  if [[ ! -f "$log" ]] || ! grep -q 'Error Perc:' "$log"; then
    echo "FAIL: incomplete $log"
    exit 1
  fi
  tp=$(grep -c '\[exp\] Throughput:' "$log" || true)
  if (( tp != 21 )); then
    echo "WARN: $log has $tp throughput lines (expected 21)"
  fi
  [[ -s "$jsonl" ]] || { echo "FAIL: missing $jsonl"; exit 1; }
  echo "  OK: $app"
done

echo ""
echo "=== Summary table + CSV ==="
python3 "$P4/summarize_ebpf_residual.py" "$RESULTS" | tee "$FP/ebpf_residual_summary.txt"
python3 "$P4/summarize_ebpf_residual.py" "$RESULTS" -o "$FP/ebpf_residual_summary.csv"

echo ""
echo "=== Figures (PNG + PDF) ==="
python3 "$P4/plot_ebpf_residual.py" "$RESULTS" -o "$FP"

echo ""
echo "=== Presentation pack ==="
bash "$EVAL/scripts/build_presentation_pack.sh"

echo ""
echo "Phase 4 finalize complete."
echo "  CSV:  $FP/ebpf_residual_summary.csv"
echo "  Figs: $FP/fig_ebpf_*.png"
echo "  Pack: ~/netpoke_presentation_pack_*.tar.gz"
