#!/usr/bin/env bash
# Phase 4: all four benchmarks at L2 with residual I/O sampling (~3–4 h).
#
# SSH 1 (screen):
#   export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
#   cd ~/slowpoke/evaluation
#   screen -S phase4-ebpf
#   WATCH_INTERVAL=10 ./phase4_ebpf/run_ebpf_all_L2.sh
#   Ctrl+A D
#
# SSH 2 (append monitor):
#   export WATCH_INTERVAL=10 SLOWPOKE_PHASE4_EBPF=1
#   cd ~/slowpoke/evaluation
#   ./watch_progress.sh --append results/
#
set -euo pipefail

if [[ -z "${SLOWPOKE_MONITOR_STARTED:-}" && -z "${SLOWPOKE_NO_MONITOR:-}" ]]; then
  export SLOWPOKE_MONITOR_STARTED=1
  export SLOWPOKE_PHASE4_EBPF=1
  EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  exec "$EVAL_DIR/run_with_monitor.sh" bash "$0" "$@"
fi

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
export SLOWPOKE_PHASE4_EBPF=1
export PYTHONUNBUFFERED=1

EVAL="$SLOWPOKE_TOP/evaluation"
P4="$EVAL/phase4_ebpf"
RESULTS="${RESULTS_DIR:-$EVAL/results}"
ACTIVE_STAMP="$RESULTS/.slowpoke_active_log"

ORDER=(social hotel movie boutique)

echo "[ebpf_all] Phase 4 — L2 + residual I/O (${#ORDER[@]} benchmarks)"
bash "$P4/preflight_ebpf.sh" "$RESULTS"

for bench in "${ORDER[@]}"; do
  echo ""
  echo "================================================================"
  echo "[ebpf_all] $(date -Is) — $bench L2"
  echo "================================================================"
  export SLOWPOKE_ACTIVE_LOG="$RESULTS/${bench}_ebpf_L2_medium.log"
  echo "$SLOWPOKE_ACTIVE_LOG" >"$ACTIVE_STAMP"
  bash "$P4/run_ebpf_one_L2.sh" "$bench"
  bash "$EVAL/safe_delete_workloads.sh" || true
done

rm -f "$ACTIVE_STAMP"
echo ""
echo "[ebpf_all] All Phase 4 L2 runs complete."
python3 "$P4/summarize_ebpf_residual.py" "$RESULTS" \
  -o "$RESULTS/final_package/ebpf_residual_summary.csv"
bash "$EVAL/scripts/pack_results_for_repo.sh" 2>/dev/null || true
