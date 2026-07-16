#!/usr/bin/env bash
# Phase 6, Step 3: validate + run the corrected in-pod residual-I/O sampler.
#
# Starts residual_sampler_inpod.sh inside every non-target pod, watching for
# pod replacement across the baseline -> groundtruth -> slowdown redeploy
# cycles (run.sh fully redeploys between each), runs a NetPoke experiment,
# collects each pod's samples plus POKER's own hold/release log, and
# correlates them so residual I/O can be attributed strictly to real pause
# windows -- unlike the deprecated kubectl-exec-per-sample sampler (finding
# F2 in netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md).
#
# Usage: bash phase6_netpoke/run_residual_check.sh <bench> [smoke|full]
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
P6="$EVAL/phase6_netpoke"
IO_GAP="$EVAL/io_gap"
RESULTS="${RESULTS_DIR:-$EVAL/results}"
BENCH="${1:?benchmark required}"
MODE="${2:-smoke}"
IFACE="${SLOWPOKE_NET_IFACE:-eth0}"
INTERVAL="${SAMPLER_INTERVAL:-0.01}"

OUTDIR="$RESULTS/residual/$BENCH"
mkdir -p "$OUTDIR"
STARTED_FILE="$OUTDIR/.started_pods"
: > "$STARTED_FILE"

LOG="$RESULTS/${BENCH}_ebpf_L2_netpoke_medium.log"

# shellcheck source=../io_gap/io_levels.conf
source "$IO_GAP/io_levels.conf"
var="IO_${BENCH^^}_L2_TARGET"
TARGET="${!var}"

echo "=== residual check: benchmark=$BENCH target=$TARGET (excluded) mode=$MODE ==="

NP="$EVAL/$BENCH/yamls/netpoke"
if [[ ! -d "$NP" ]] || [[ -z "$(ls -A "$NP"/*.yaml 2>/dev/null)" ]]; then
  echo "[residual] generating $NP ..."
  bash "$EVAL/phase5_netpoke/patch_all_netpoke_yamls.sh" "$BENCH"
fi

start_sampler_on_pod() {
  local pod="$1" ctr
  grep -qx "$pod" "$STARTED_FILE" 2>/dev/null && return
  case "$pod" in
    "$TARGET"-*|ubuntu-client-*) return ;;
  esac
  ctr=$(kubectl get pod -n default "$pod" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null) || return
  [[ -z "$ctr" ]] && return
  kubectl cp "$P6/residual_sampler_inpod.sh" "default/$pod:/tmp/residual_sampler_inpod.sh" -c "$ctr" >/dev/null 2>&1 || return
  kubectl exec -n default "$pod" -c "$ctr" -- sh -c \
    "chmod +x /tmp/residual_sampler_inpod.sh; nohup sh /tmp/residual_sampler_inpod.sh $INTERVAL /tmp/netpoke_residual.jsonl $IFACE >/tmp/sampler.log 2>&1 &" \
    >/dev/null 2>&1 || return
  echo "$pod" >> "$STARTED_FILE"
  echo "  [sampler] started on $pod ($ctr)"
}

watch_and_start() {
  local pod
  while IFS= read -r pod; do
    [[ -n "$pod" ]] && start_sampler_on_pod "$pod"
  done < <(kubectl get pods -n default --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
}

(
  while :; do
    watch_and_start
    sleep 2
  done
) &
WATCHER_PID=$!
cleanup() {
  kill "$WATCHER_PID" 2>/dev/null || true
  wait "$WATCHER_PID" 2>/dev/null || true
  bash "$IO_GAP/restore_io_injection.sh" || true
}
trap cleanup EXIT

export SLOWPOKE_NETPOKE=1
export SLOWPOKE_ACTIVE_LOG="$LOG"
echo "$LOG" > "$RESULTS/.slowpoke_active_log"
bash "$IO_GAP/restore_io_injection.sh" || true
pkill -f 'python3.*main\.py' 2>/dev/null || true
bash "$EVAL/safe_delete_workloads.sh"

{
  echo "# phase6 residual check: benchmark=$BENCH target=$TARGET level=L2 mode=$MODE"
  echo "# started: $(date -Is)"
} > "$LOG"

bash "$IO_GAP/apply_io_injection.sh" "$BENCH" L2

cd "$EVAL"
if [[ "$MODE" == "smoke" ]]; then
  var_req="IO_NUM_REQ_${BENCH^^}"
  echo "[residual] SMOKE mode: 1 opt point, 5000 requests"
  python3 -u "$SLOWPOKE_TOP/src/main.py" -b "$BENCH" -r mix -x "$TARGET" \
    --num_exp 1 -t "$IO_THREAD" -c "$IO_CONN" --poker_batch_req "$IO_POKER_BATCH_REQ" \
    --repetitions 1 --num_req 5000 >> "$LOG"
else
  echo "[residual] FULL L2 medium run"
  bash "$IO_GAP/run_io_medium.sh" "$BENCH" L2 "$LOG"
fi
echo "# finished: $(date -Is)" >> "$LOG"

kill "$WATCHER_PID" 2>/dev/null || true
wait "$WATCHER_PID" 2>/dev/null || true
sleep 3  # let each pod's sampler flush its last iteration

echo "=== collecting samples + POKER logs ==="
while IFS= read -r pod; do
  [[ -z "$pod" ]] && continue
  ctr=$(kubectl get pod -n default "$pod" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null) || continue
  kubectl exec -n default "$pod" -c "$ctr" -- cat /tmp/netpoke_residual.jsonl \
    > "$OUTDIR/${pod}.jsonl" 2>/dev/null || echo "  WARN: no samples from $pod (likely replaced before collection)"
  kubectl logs -n default "$pod" -c "$ctr" 2>/dev/null | grep 'netpoke:' > "$OUTDIR/${pod}.netpoke.log" || true
  echo "  collected $pod"
done < "$STARTED_FILE"

echo "=== correlating ==="
python3 "$P6/correlate_residual.py" "$OUTDIR"
