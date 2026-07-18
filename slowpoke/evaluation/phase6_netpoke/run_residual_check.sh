#!/usr/bin/env bash
# Phase 6, Step 3/4: run the corrected in-pod residual-I/O sampler under
# either the SIGSTOP-only baseline or NetPoke, at a chosen I/O-gap level, so
# residual I/O during real pause windows can be directly measured and
# compared -- not just inferred from an RMSE number (see the "does Phase 3
# actually measure this" discussion in
# netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md).
#
# Starts residual_sampler_inpod.sh inside every non-target pod, watching for
# pod replacement across the baseline -> groundtruth -> slowdown redeploy
# cycles (run.sh fully redeploys between each), runs the experiment,
# collects each pod's samples plus POKER's own pause-window log, and
# correlates them so residual I/O can be attributed strictly to real pause
# windows -- unlike the deprecated kubectl-exec-per-sample sampler (finding
# F2 in netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md).
#
# Usage: bash phase6_netpoke/run_residual_check.sh <bench> <level:L1|L2> [mode:smoke|full] [netpoke:0|1]
#   netpoke=0 (default) -- SIGSTOP-only baseline, the number this project has
#     never actually measured directly before. Still uses the *-netpoke
#     image (it has the unconditional poker: pause_start/pause_end fix) but
#     with SLOWPOKE_NETPOKE forced to "0", so the egress-hold mechanism
#     itself stays inert.
#   netpoke=1 -- NetPoke on, for the before/after comparison later.
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
P6="$EVAL/phase6_netpoke"
IO_GAP="$EVAL/io_gap"
RESULTS="${RESULTS_DIR:-$EVAL/results}"
BENCH="${1:?benchmark required}"
LEVEL="${2:?level required (L1|L2)}"
MODE="${3:-smoke}"
NETPOKE="${4:-0}"
IFACE="${SLOWPOKE_NET_IFACE:-eth0}"
INTERVAL="${SAMPLER_INTERVAL:-0.01}"

case "$LEVEL" in L1|L2) ;; *) echo "ERROR: level must be L1 or L2" >&2; exit 1 ;; esac
case "$NETPOKE" in 0|1) ;; *) echo "ERROR: netpoke must be 0 or 1" >&2; exit 1 ;; esac

TAG="sigstop"; [[ "$NETPOKE" == "1" ]] && TAG="netpoke"

OUTDIR="$RESULTS/residual/${BENCH}_${LEVEL}_${TAG}"
mkdir -p "$OUTDIR"
STARTED_FILE="$OUTDIR/.started_pods"
DEBUG_LOG="$OUTDIR/.attach_debug.log"
: > "$STARTED_FILE"
: > "$DEBUG_LOG"

LOG="$RESULTS/${BENCH}_io_${LEVEL}_residual_${TAG}_medium.log"

# shellcheck source=../io_gap/io_levels.conf
source "$IO_GAP/io_levels.conf"
var="IO_${BENCH^^}_${LEVEL}_TARGET"
TARGET="${!var}"

echo "=== residual check: benchmark=$BENCH level=$LEVEL netpoke=$NETPOKE target=$TARGET (excluded) mode=$MODE ==="

SRC_NP="$EVAL/$BENCH/yamls/netpoke"
if [[ ! -d "$SRC_NP" ]] || [[ -z "$(ls -A "$SRC_NP"/*.yaml 2>/dev/null)" ]]; then
  echo "[residual] generating $SRC_NP ..."
  bash "$EVAL/phase5_netpoke/patch_all_netpoke_yamls.sh" "$BENCH"
fi

if [[ "$NETPOKE" == "1" ]]; then
  NP="$SRC_NP"
else
  # SIGSTOP-only but still instrumented: reuse the *-netpoke image (has the
  # unconditional poker: pause_start/pause_end fix) with SLOWPOKE_NETPOKE
  # forced to "0", so net_hold()/net_release() stay no-ops but pause-window
  # timestamps are still logged. Derived from the netpoke yamls so the two
  # runs are otherwise identical (same image, same caps, same everything
  # except the one env var that turns the egress hold on).
  NP="$EVAL/$BENCH/yamls/netpoke-sigstop"
  mkdir -p "$NP"
  for f in "$SRC_NP"/*.yaml; do
    [[ -f "$f" ]] || continue
    sed '/name: SLOWPOKE_NETPOKE/{n;s/value: "1"/value: "0"/}' "$f" > "$NP/$(basename "$f")"
  done
  echo "[residual] SIGSTOP-only yamls generated in $NP (SLOWPOKE_NETPOKE=0, same *-netpoke image)"
fi

# Streams the sampler script over `kubectl exec`'s stdin (via `cat > file`)
# instead of `kubectl cp`, which shells out to `tar` inside the target
# container -- a dependency these images don't explicitly install and that
# we have no way to verify from here. `sh`/`cat` are guaranteed present.
start_sampler_on_pod() {
  local pod="$1" ctr out lockdir="$OUTDIR/.lock.$pod"
  grep -qx "$pod" "$STARTED_FILE" 2>/dev/null && return
  case "$pod" in
    "$TARGET"-*|ubuntu-client-*) return ;;
  esac
  # Atomic claim BEFORE the slow kubectl calls below. watch_and_start() fires
  # attempts every 1s in parallel; without this, the same pod appearing in
  # two consecutive cycles (still in-flight from the first, several seconds
  # of kubectl exec) could start two sampler processes writing the same
  # output file at once, interleaving records into garbled-but-parseable
  # JSON (observed: correlate_residual.py KeyError on a missing "ts" field).
  # mkdir is atomic at the filesystem level -- only one concurrent caller
  # can win it.
  mkdir "$lockdir" 2>/dev/null || return
  if ! ctr=$(kubectl get pod -n default "$pod" -o jsonpath='{.spec.containers[0].name}' 2>&1) || [[ -z "$ctr" ]]; then
    echo "$(date -Is) $pod: get container name failed: $ctr" >> "$DEBUG_LOG"
    return
  fi
  if ! out=$(kubectl exec -i -n default "$pod" -c "$ctr" -- sh -c 'cat > /tmp/residual_sampler_inpod.sh' \
    < "$P6/residual_sampler_inpod.sh" 2>&1); then
    echo "$(date -Is) $pod: stream-in failed: $out" >> "$DEBUG_LOG"
    return
  fi
  if ! out=$(kubectl exec -n default "$pod" -c "$ctr" -- sh -c \
    "chmod +x /tmp/residual_sampler_inpod.sh; nohup sh /tmp/residual_sampler_inpod.sh $INTERVAL /tmp/netpoke_residual.jsonl $IFACE >/tmp/sampler.log 2>&1 &" \
    2>&1); then
    echo "$(date -Is) $pod: launch failed: $out" >> "$DEBUG_LOG"
    return
  fi
  echo "$pod" >> "$STARTED_FILE"
  echo "  [sampler] started on $pod ($ctr)"
}

# Fire off attach attempts for all currently-Running candidate pods in
# parallel (not one at a time) -- each attach is 2 kubectl round-trips
# (several seconds); doing them serially across ~8 pods could take longer
# than a fast smoke-mode phase lasts before it's replaced by the next one.
watch_and_start() {
  local pod
  while IFS= read -r pod; do
    [[ -n "$pod" ]] && start_sampler_on_pod "$pod" &
  done < <(kubectl get pods -n default --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' 2>/dev/null)
}

(
  while :; do
    watch_and_start
    sleep 1
  done
) &
WATCHER_PID=$!
cleanup() {
  kill "$WATCHER_PID" 2>/dev/null || true
  wait "$WATCHER_PID" 2>/dev/null || true
  bash "$IO_GAP/restore_io_injection.sh" || true
}
trap cleanup EXIT

# run.sh only switches to yamls/netpoke when SLOWPOKE_NETPOKE is exactly
# "1" -- for the SIGSTOP-only case (netpoke=0) that would silently fall
# through to the plain (non *-netpoke) image, which has none of our poker.c
# fixes. SLOWPOKE_YAML_SUBDIR (added to run.sh) selects the directory
# directly, independent of the netpoke=0/1 semantic flag.
export SLOWPOKE_NETPOKE="$NETPOKE"
if [[ "$NETPOKE" == "1" ]]; then
  export SLOWPOKE_YAML_SUBDIR=netpoke
else
  export SLOWPOKE_YAML_SUBDIR=netpoke-sigstop
fi
export SLOWPOKE_ACTIVE_LOG="$LOG"
echo "$LOG" > "$RESULTS/.slowpoke_active_log"
bash "$IO_GAP/restore_io_injection.sh" || true
pkill -f 'python3.*main\.py' 2>/dev/null || true
bash "$EVAL/safe_delete_workloads.sh"

{
  echo "# phase6 residual check: benchmark=$BENCH level=$LEVEL netpoke=$NETPOKE target=$TARGET mode=$MODE"
  echo "# started: $(date -Is)"
} > "$LOG"

bash "$IO_GAP/apply_io_injection.sh" "$BENCH" "$LEVEL"

cd "$EVAL"
if [[ "$MODE" == "smoke" ]]; then
  echo "[residual] SMOKE mode: 1 opt point, 5000 requests"
  python3 -u "$SLOWPOKE_TOP/src/main.py" -b "$BENCH" -r mix -x "$TARGET" \
    --num_exp 1 -t "$IO_THREAD" -c "$IO_CONN" --poker_batch_req "$IO_POKER_BATCH_REQ" \
    --repetitions 1 --num_req 5000 >> "$LOG"
else
  echo "[residual] FULL $LEVEL medium run"
  bash "$IO_GAP/run_io_medium.sh" "$BENCH" "$LEVEL" "$LOG"
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
  kubectl logs -n default "$pod" -c "$ctr" 2>/dev/null | grep -E 'poker: pause_|netpoke:' > "$OUTDIR/${pod}.netpoke.log" || true
  echo "  collected $pod"
done < "$STARTED_FILE"

echo "=== correlating ==="
CORRELATE_ARGS=("$OUTDIR")
[[ "$NETPOKE" == "1" ]] && CORRELATE_ARGS+=(--netpoke)
# Don't let one inconclusive correlation (e.g. a stale image that hasn't
# been rebuilt yet) kill an `&&`-chained multi-run sequence -- the actual
# experiment (main.py) already succeeded and its log is safely on disk
# regardless of whether this particular run's residual data correlated.
python3 "$P6/correlate_residual.py" "${CORRELATE_ARGS[@]}" || \
  echo "[residual] WARN: correlate_residual.py found nothing for this run (exit $?) -- continuing"
