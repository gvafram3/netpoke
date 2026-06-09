#!/usr/bin/env bash
# Phase 4: one benchmark L2 medium run + residual I/O sampler.
# Usage: bash phase4_ebpf/run_ebpf_one_L2.sh <boutique|hotel|social|movie> [smoke]
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
P4="$EVAL/phase4_ebpf"
IO_GAP="$EVAL/io_gap"
RESULTS="${RESULTS_DIR:-$EVAL/results}"
BENCH="${1:?benchmark required}"
SMOKE="${2:-}"

mkdir -p "$RESULTS" "$RESULTS/saved"

LOG="$RESULTS/${BENCH}_ebpf_L2_medium.log"
RESIDUAL="$RESULTS/${BENCH}_ebpf_L2_residual.jsonl"
ACTIVE_STAMP="$RESULTS/.slowpoke_active_log"

# shellcheck source=io_levels.conf
source "$IO_GAP/io_levels.conf"
var="IO_${BENCH^^}_L2_TARGET"
TARGET="${!var}"

log_complete() {
  [[ -f "$1" ]] && grep -q 'Error Perc:' "$1" 2>/dev/null
}

if log_complete "$LOG" && [[ -s "$RESIDUAL" ]] && [[ "$SMOKE" != "smoke" ]]; then
  echo "[ebpf_one] SKIP: $LOG and $RESIDUAL already exist"
  exit 0
fi

if [[ -f "$LOG" ]] && ! log_complete "$LOG"; then
  bak="${LOG}.bak-$(date +%Y%m%d-%H%M%S)"
  echo "[ebpf_one] Archive incomplete log -> $bak"
  mv -f "$LOG" "$bak"
fi
rm -f "$RESIDUAL"

export SLOWPOKE_ACTIVE_LOG="$LOG"
echo "$LOG" >"$ACTIVE_STAMP"

echo "[ebpf_one] benchmark=$BENCH target=$TARGET level=L2"
echo "[ebpf_one] slowpoke log: $LOG"
echo "[ebpf_one] residual jsonl: $RESIDUAL"

bash "$IO_GAP/restore_io_injection.sh" || true
pkill -f 'python3.*main\.py' 2>/dev/null || true
bash "$EVAL/safe_delete_workloads.sh"

SAMPLER_EXTRA=()
if [[ "$SMOKE" == "smoke" ]]; then
  SAMPLER_EXTRA=(--max-seconds 600)
  echo "[ebpf_one] SMOKE mode: short sampler window"
fi

python3 "$P4/residual_io_sampler.py" \
  -b "$BENCH" -x "$TARGET" -o "$RESIDUAL" \
  --interval 0.2 --wait-main "${SAMPLER_EXTRA[@]}" &
SAMPLER_PID=$!

cleanup() {
  kill "$SAMPLER_PID" 2>/dev/null || true
  wait "$SAMPLER_PID" 2>/dev/null || true
  bash "$IO_GAP/restore_io_injection.sh" || true
}
trap cleanup EXIT INT TERM

if [[ "$SMOKE" == "smoke" ]]; then
  # Short SlowPoke run: 1 opt point, fewer requests
  export SLOWPOKE_IO_GAP_LEVEL=L2
  export SLOWPOKE_IO_GAP_BENCHMARK="$BENCH"
  bash "$IO_GAP/apply_io_injection.sh" "$BENCH" L2
  {
    echo "# phase4 smoke: benchmark=$BENCH target=$TARGET level=L2"
    echo "# started: $(date -Is)"
  } >"$LOG"
  cd "$EVAL"
  var_req="IO_NUM_REQ_${BENCH^^}"
  NUM_REQ="${!var_req:-10000}"
  python3 -u "$SLOWPOKE_TOP/src/main.py" \
    -b "$BENCH" -r mix -x "$TARGET" \
    --num_exp 1 -t "$IO_THREAD" -c "$IO_CONN" \
    --poker_batch_req "$IO_POKER_BATCH_REQ" \
    --repetitions 1 --num_req 5000 >>"$LOG"
  echo "# finished: $(date -Is)" >>"$LOG"
else
  bash "$IO_GAP/run_io_medium.sh" "$BENCH" L2 "$LOG"
fi

kill "$SAMPLER_PID" 2>/dev/null || true
wait "$SAMPLER_PID" 2>/dev/null || true
SAMPLER_PID=""

if [[ "$SMOKE" != "smoke" ]] && ! log_complete "$LOG"; then
  echo "[ebpf_one] FATAL: $LOG missing Error Perc:"
  exit 1
fi

if [[ ! -s "$RESIDUAL" ]]; then
  echo "[ebpf_one] FATAL: empty residual file $RESIDUAL"
  exit 1
fi

ts=$(date +%Y%m%d-%H%M%S)
cp -a "$RESIDUAL" "$RESULTS/saved/${BENCH}_ebpf_L2_residual-${ts}.jsonl"
cp -a "$LOG" "$RESULTS/saved/${BENCH}_ebpf_L2_medium-${ts}.log" 2>/dev/null || true

python3 "$P4/summarize_ebpf_residual.py" "$RESULTS" || true
echo "[ebpf_one] Done: $BENCH"
