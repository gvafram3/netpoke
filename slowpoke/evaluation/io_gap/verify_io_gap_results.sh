#!/usr/bin/env bash
# Verify Phase 3 I/O-gap logs (L1 and L2 per benchmark).
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
RESULTS="${1:-$EVAL/results}"
FAIL=0

check_log() {
  local label="$1"
  local f="$2"
  echo "--- $label ---"
  if [[ ! -f "$f" ]]; then
    echo "  MISSING: $f"
    FAIL=1
    return
  fi
  if ! grep -q 'Error Perc:' "$f"; then
    echo "  INCOMPLETE: no Error Perc: ($(wc -l <"$f") lines)"
    FAIL=1
    return
  fi
  local tp
  tp=$(grep -c '\[exp\] Throughput:' "$f" 2>/dev/null || echo 0)
  echo "  OK: complete (throughput lines: $tp)"
  grep 'Baseline throughput:' "$f" | tail -1 | sed 's/^/  /'
  grep 'Error Perc:' "$f" | tail -1 | cut -c1-90 | sed 's/^/  /'
}

echo "=== Phase 3 I/O-gap verification ==="
echo "RESULTS=$RESULTS"
echo ""

for b in boutique hotel social movie; do
  check_log "$b L1" "$RESULTS/${b}_io_L1_medium.log"
  check_log "$b L2" "$RESULTS/${b}_io_L2_medium.log"
done

echo ""
if (( FAIL )); then
  echo "VERIFICATION FAILED"
  exit 1
fi

echo "VERIFICATION PASSED — all eight I/O-gap logs complete."
if [[ -f "$EVAL/io_gap/summarize_io_gap_matrix.py" ]]; then
  echo ""
  python3 "$EVAL/io_gap/summarize_io_gap_matrix.py" "$RESULTS"
fi
