#!/usr/bin/env bash
# L0 RMSE overhead check: does NetPoke's egress hold cost prediction accuracy
# even with NO I/O-gap injection at all, across all four apps? Table N1 already
# checked L0 *residual I/O* overhead for boutique only (flat, no regression).
# This checks the same question at the *RMSE* level, all four apps -- directly
# motivated by Table N2's L2 finding that NetPoke regresses boutique's RMSE
# (3.53% -> 10.26%): is that L2-specific, or does the mechanism cost boutique
# accuracy even at baseline?
#
# Replicates the exact same main.py invocation Phase 1's per-app scripts use
# (run-<bench>-medium.sh: same target/thread/conn/num_req/num_exp, no netem),
# inlined directly rather than delegating to those files -- ~/slowpoke on the
# VM is not a git checkout, so files present in this repo aren't guaranteed
# to exist there (the same lesson run_residual_check.sh's L0 support already
# hit once: "L0 uses run-*-medium.sh ... so L0's full-scale run now
# replicates that script's main.py invocation directly instead of delegating
# to it" -- METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md). One difference from Phase
# 1: SLOWPOKE_NETPOKE=1. Compare the resulting RMSE against the existing
# SIGSTOP-only L0 numbers in
# netpoke/results/cluster/baseline/tables/TABLE_L0_SUMMARY.md.
#
# SSH 1 (screen):
#   cd ~/slowpoke/evaluation
#   export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
#   screen -S slowpoke-l0-overhead
#   WATCH_INTERVAL=10 ./run_netpoke_l0_overhead.sh
#   Ctrl+A D
#
# SSH 2:
#   cd ~/slowpoke/evaluation
#   ./watch_progress.sh --append results/
#
set -euo pipefail

if [[ -z "${SLOWPOKE_MONITOR_STARTED:-}" && -z "${SLOWPOKE_NO_MONITOR:-}" ]]; then
  export SLOWPOKE_MONITOR_STARTED=1
  EVAL_DIR="$(cd "${BASH_SOURCE%/*}" && pwd)"
  exec "$EVAL_DIR/run_with_monitor.sh" bash "$0" "$@"
fi

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
export SLOWPOKE_NETPOKE=1
export PYTHONUNBUFFERED=1

EVAL="$(cd "${BASH_SOURCE%/*}" && pwd)"
RESULTS="${RESULTS_DIR:-$EVAL/results}"
SAVED="$RESULTS/saved"
ACTIVE_STAMP="$RESULTS/.slowpoke_active_log"
mkdir -p "$RESULTS" "$SAVED"

APPS=(boutique hotel social movie)

# target, num_req -- everything else (thread/conn/repetitions/poker_batch_req/
# num_exp) is identical across all four apps' run-*-medium.sh scripts.
target_for() {
  case "$1" in
    boutique) echo cart ;;
    hotel) echo profile ;;
    social) echo hometimeline ;;
    movie) echo moviereviews ;;
  esac
}
num_req_for() {
  case "$1" in
    boutique) echo 100000 ;;
    hotel) echo 10000 ;;
    social) echo 30000 ;;
    movie) echo 20000 ;;
  esac
}

log_complete() {
  [[ -f "$1" ]] && grep -q 'Error Perc:' "$1" 2>/dev/null
}

# See run_io_gap_netpoke_L2.sh for why this stamp is required: without it,
# watch_progress.sh's bench-matching fallback finds the already-complete
# plain *_medium.log (the real Phase 1 baseline) and gets stuck displaying
# that stale, finished log instead of tracking this run.
set_active_log() {
  export SLOWPOKE_ACTIVE_LOG="$1"
  echo "$1" >"$ACTIVE_STAMP"
}

save_log() {
  local bench="$1" src="$2" ts
  ts=$(date +%Y%m%d-%H%M%S)
  sync "$src" 2>/dev/null || true
  cp -a "$src" "$SAVED/${bench}_netpoke_medium.log"
  cp -a "$src" "$SAVED/${bench}_netpoke_medium-${ts}.log"
  echo "[l0_overhead] Saved -> $SAVED/${bench}_netpoke_medium.log"
}

if [[ ! -f "$SLOWPOKE_TOP/src/main.py" ]]; then
  echo "[l0_overhead] FATAL: SLOWPOKE_TOP=$SLOWPOKE_TOP invalid"
  exit 1
fi
if pgrep -f '[p]ython3.*main\.py' >/dev/null; then
  echo "[l0_overhead] FATAL: main.py already running (stop stuck run first)"
  pgrep -af '[p]ython3.*main\.py' || true
  exit 1
fi
bash "$EVAL/safe_delete_workloads.sh"
cd "$EVAL"

for bench in "${APPS[@]}"; do
  log="$RESULTS/${bench}_netpoke_medium.log"
  target="$(target_for "$bench")"
  num_req="$(num_req_for "$bench")"

  echo ""
  echo "================================================================"
  echo "[l0_overhead] $bench L0 (target=$target, num_req=$num_req), SLOWPOKE_NETPOKE=1"
  echo "[l0_overhead] Log: $log"
  echo "[l0_overhead] Started: $(date -Is)"
  echo "================================================================"

  if log_complete "$log"; then
    echo "[l0_overhead] SKIP: already complete"
    save_log "$bench" "$log"
    continue
  fi
  if [[ -f "$log" && ! -s "$log" ]]; then
    rm -f "$log"
  fi

  set_active_log "$log"
  bash "$EVAL/safe_delete_workloads.sh"

  if ! time python3 -u "$SLOWPOKE_TOP/src/main.py" \
      -b "$bench" -x "$target" -r mix \
      -t 8 -c 1024 --num_exp 10 --repetitions 1 --num_req "$num_req" \
      --poker_batch_req 100 >"$log"; then
    echo "[l0_overhead] FATAL: $bench L0 failed"
    exit 1
  fi
  if ! log_complete "$log"; then
    echo "[l0_overhead] FATAL: $bench L0 ended without Error Perc:"
    exit 1
  fi

  save_log "$bench" "$log"
  echo "[l0_overhead] Finished $bench L0 ($(date -Is))"
  bash "$EVAL/safe_delete_workloads.sh" || true
done

rm -f "$ACTIVE_STAMP"
echo ""
echo "[l0_overhead] All 4 NetPoke-on L0 runs complete."
echo "[l0_overhead] Compare against SIGSTOP-only L0 RMSE in"
echo "[l0_overhead]   netpoke/results/cluster/baseline/tables/TABLE_L0_SUMMARY.md"
echo "[l0_overhead] Per-app tables:"
for bench in "${APPS[@]}"; do
  echo "  python3 summarize_results.py $RESULTS/${bench}_netpoke_medium.log"
done
