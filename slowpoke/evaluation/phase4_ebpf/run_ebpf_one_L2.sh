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

if [[ "${SLOWPOKE_NETPOKE:-}" == "1" ]]; then
  LOG="$RESULTS/${BENCH}_ebpf_L2_netpoke_medium.log"
  RESIDUAL="$RESULTS/${BENCH}_ebpf_L2_netpoke_residual.jsonl"
else
  LOG="$RESULTS/${BENCH}_ebpf_L2_medium.log"
  RESIDUAL="$RESULTS/${BENCH}_ebpf_L2_residual.jsonl"
fi
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
  echo "[ebpf_one] Archive or delete them to re-run, or use SLOWPOKE_NETPOKE=1 for netpoke logs"
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

if [[ "${SLOWPOKE_NETPOKE:-}" == "1" ]]; then
  NP="$EVAL/$BENCH/yamls/netpoke"
  if [[ ! -d "$NP" ]] || [[ -z "$(ls -A "$NP"/*.yaml 2>/dev/null)" ]]; then
    echo "[ebpf_one] NetPoke: generating $NP ..."
    bash "$EVAL/phase5_netpoke/patch_all_netpoke_yamls.sh" "$BENCH"
  fi
  if [[ ! -d "$NP" ]]; then
    echo "[ebpf_one] FATAL: SLOWPOKE_NETPOKE=1 but $NP missing — run patch_all_netpoke_yamls.sh"
    exit 1
  fi
  echo "[ebpf_one] NetPoke: run.sh will deploy from $NP"
fi

bash "$IO_GAP/restore_io_injection.sh" || true
pkill -f 'python3.*main\.py' 2>/dev/null || true
bash "$EVAL/safe_delete_workloads.sh"

# No --max-seconds cap: sampler must stay alive through the SLOWDOWN phase
# (where POKER sends SIGSTOP); it exits when main.py exits (--wait-main).
# A 600s cap previously expired during baseline/groundtruth → with_state_T=0.
SAMPLER_EXTRA=()
if [[ "$SMOKE" == "smoke" ]]; then
  echo "[ebpf_one] SMOKE mode: 1 opt point, sampler runs until main.py exits"
  # Fewer pods per cycle → faster polling → better odds of landing on a pause.
  case "$BENCH" in
    boutique) SAMPLER_EXTRA=(--services "frontend,productcatalog,currency") ;;
    social)   SAMPLER_EXTRA=(--services "poststorage,socialgraph,frontend") ;;
    hotel)    SAMPLER_EXTRA=(--services "rate,user,frontend") ;;
    movie)    SAMPLER_EXTRA=(--services "reviewstorage,movieinfo,frontend") ;;
  esac
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
  bash "$IO_GAP/restore_io_injection.sh" || true
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

SAMPLER_EXIT=0
kill "$SAMPLER_PID" 2>/dev/null || true
wait "$SAMPLER_PID" 2>/dev/null || SAMPLER_EXIT=$?
SAMPLER_PID=""

if (( SAMPLER_EXIT != 0 )); then
  echo "[ebpf_one] FATAL: residual sampler exited $SAMPLER_EXIT (update residual_io_sampler.py from netpoke/experiments)"
  exit 1
fi

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
