#!/usr/bin/env bash
# Authors' per-benchmark + macro plots (INSTRUCTIONS.md §5.1 / Fig. 8).
set -euo pipefail
RESULTS="${1:-$(cd "$(dirname "$0")" && pwd)/results}"
cd "$(dirname "$0")"
echo "=== SlowPoke plots (complete *_medium.log only) ==="
echo "Results: $RESULTS"
python3 draw.py "$RESULTS"
echo ""
echo "=== Fig. 8 macro PDF (skips incomplete benchmarks) ==="
python3 plot_macro.py -r "$RESULTS"
echo ""
echo "PNG files in: $RESULTS/*.png"
echo "Macro PDF:    $RESULTS/plot_macro.pdf"
ls -lh "$RESULTS"/*.png "$RESULTS"/plot_macro.pdf 2>/dev/null || true
