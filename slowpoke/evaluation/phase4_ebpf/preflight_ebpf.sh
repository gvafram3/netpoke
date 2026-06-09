#!/usr/bin/env bash
# Preflight before Phase 4 eBPF runs on netpoke-control.
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
P4="$EVAL/phase4_ebpf"
RESULTS="${1:-$EVAL/results}"
FAIL=0

echo "=== Phase 4 eBPF preflight ==="
echo "SLOWPOKE_TOP=$SLOWPOKE_TOP"
echo ""

need() {
  [[ -e "$1" ]] && echo "  OK: $1" || { echo "  FAIL: missing $1"; FAIL=1; }
}

echo "--- scripts ---"
need "$P4/residual_io_sampler.py"
need "$P4/summarize_ebpf_residual.py"
need "$P4/run_ebpf_smoke.sh"
need "$P4/run_ebpf_all_L2.sh"
need "$EVAL/io_gap/run_io_medium.sh"
need "$EVAL/run_with_monitor.sh"
need "$EVAL/watch_progress.sh"

echo ""
echo "--- Phase 3 L2 baselines (reference RMSE) ---"
for b in social hotel movie boutique; do
  f="$RESULTS/${b}_io_L2_medium.log"
  if [[ -f "$f" ]] && grep -q 'Error Perc:' "$f"; then
    echo "  OK: ${b}_io_L2_medium.log"
  else
    echo "  WARN: ${b}_io_L2_medium.log missing — Phase 3 L2 not complete"
  fi
done

echo ""
echo "--- tools ---"
command -v kubectl >/dev/null && echo "  OK: kubectl" || { echo "  FAIL: kubectl"; FAIL=1; }
python3 -c "import json" 2>/dev/null && echo "  OK: python3" || { echo "  FAIL: python3"; FAIL=1; }
if command -v bpftrace >/dev/null; then
  echo "  OK: bpftrace (optional — /proc sampler used if absent)"
else
  echo "  OK: bpftrace not installed — using /proc SIGSTOP sampler (sufficient for Phase 4)"
fi

echo ""
echo "--- cluster ---"
if kubectl get nodes >/dev/null 2>&1; then
  kubectl get nodes | sed 's/^/  /'
  pgrep -f '[p]ython3.*main\.py' >/dev/null && {
    echo "  FAIL: main.py already running"
    FAIL=1
  } || echo "  OK: no active main.py"
else
  echo "  FAIL: cannot reach cluster"
  FAIL=1
fi

echo ""
if (( FAIL )); then
  echo "PREFLIGHT FAILED"
  exit 1
fi
echo "PREFLIGHT OK — run: bash phase4_ebpf/run_ebpf_smoke.sh"
