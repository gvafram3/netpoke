#!/usr/bin/env bash
# Verify all four *_medium.log files after a full reproducible run.
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
RESULTS="${1:-$EVAL/results}"
FAIL=0

check_log() {
  local bench="$1"
  local f="$RESULTS/${bench}_medium.log"
  local saved="$RESULTS/saved/${bench}_medium.log"
  local tp

  echo "--- $bench ---"
  if [[ ! -f "$f" ]]; then
    echo "  FAIL: missing $f"
    FAIL=1
    return
  fi
  if ! grep -q 'Error Perc:' "$f"; then
    echo "  FAIL: incomplete (no Error Perc)"
    echo "  lines: $(wc -l < "$f")  size: $(wc -c < "$f") bytes"
    tail -3 "$f" | sed 's/^/    /'
    FAIL=1
    return
  fi
  tp=$(grep -c '\[exp\] Throughput:' "$f" 2>/dev/null || echo 0)
  echo "  OK: complete"
  echo "  throughput lines: $tp (expect ~21 for medium benchmarks)"
  grep 'Baseline throughput:' "$f" | tail -1 | sed 's/^/  /'
  grep 'Error Perc:' "$f" | tail -1 | cut -c1-100 | sed 's/^/  /'
  if [[ -f "$saved" ]]; then
    echo "  saved copy: $saved ($(wc -c < "$saved") bytes)"
  fi
}

echo "=== SlowPoke results verification ==="
echo "RESULTS=$RESULTS"
echo ""

for b in boutique hotel social movie; do
  check_log "$b"
done

echo ""
if (( FAIL )); then
  echo "VERIFICATION FAILED"
  exit 1
fi

echo "VERIFICATION PASSED — all four benchmarks complete."
if [[ -f "$EVAL/summarize_results.py" ]]; then
  echo ""
  python3 "$EVAL/summarize_results.py" \
    "$RESULTS/boutique_medium.log" \
    "$RESULTS/hotel_medium.log" \
    "$RESULTS/social_medium.log" \
    "$RESULTS/movie_medium.log"
fi
