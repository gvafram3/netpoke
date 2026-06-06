#!/usr/bin/env bash
# Preflight before Phase 3 I/O-gap runs on netpoke-control.
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
IO_GAP="$EVAL/io_gap"
RESULTS="${1:-$EVAL/results}"
FAIL=0

echo "=== Phase 3 I/O-gap preflight ==="
echo "SLOWPOKE_TOP=$SLOWPOKE_TOP"
echo "RESULTS=$RESULTS"
echo ""

need() {
  local f="$1"
  if [[ ! -e "$f" ]]; then
    echo "  FAIL: missing $f"
    FAIL=1
  else
    echo "  OK: $f"
  fi
}

echo "--- scripts ---"
for s in io_gap/run_io_medium.sh io_gap/io_levels.conf io_gap/apply_io_injection.sh \
         io_gap/restore_io_injection.sh io_gap/patch_netem_yaml.py \
         io_gap/run_io_gap_all.sh io_gap/summarize_io_gap_matrix.py \
         safe_delete_workloads.sh run_with_monitor.sh watch_progress.sh; do
  need "$EVAL/$s"
done

echo ""
echo "--- L0 baselines (Phase 1, read-only reference) ---"
for b in boutique hotel social movie; do
  f="$RESULTS/${b}_medium.log"
  if [[ -f "$f" ]] && grep -q 'Error Perc:' "$f"; then
    echo "  OK: ${b}_medium.log complete"
  else
    echo "  WARN: ${b}_medium.log missing or incomplete — finish Phase 1 first"
    FAIL=1
  fi
done

echo ""
echo "--- cluster ---"
if command -v kubectl >/dev/null 2>&1; then
  kubectl get nodes 2>/dev/null | sed 's/^/  /' || { echo "  FAIL: kubectl get nodes"; FAIL=1; }
  pgrep -f 'python3.*main.py' >/dev/null && {
    echo "  FAIL: main.py still running — wait or stop before starting io_gap"
    FAIL=1
  } || echo "  OK: no active main.py"
else
  echo "  SKIP: kubectl not available (run on netpoke-control)"
fi

echo ""
if (( FAIL )); then
  echo "PREFLIGHT FAILED — fix items above before Phase 3 runs"
  exit 1
fi
echo "PREFLIGHT PASSED — ready for io_gap L1/L2 runs"
