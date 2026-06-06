#!/usr/bin/env bash
# Verify cluster + repo state before social → movie. Exit non-zero on any blocker.
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
RESULTS="$EVAL/results"
FAIL=0

ok() { echo "  OK: $*"; }
bad() { echo "  FAIL: $*"; FAIL=1; }
warn() { echo "  WARN: $*"; }

echo "=== SlowPoke preflight: social → movie ==="
echo "Host: $(hostname)  SLOWPOKE_TOP=$SLOWPOKE_TOP"
echo ""

# --- repo paths ---
[[ -f "$SLOWPOKE_TOP/src/main.py" ]] && ok "main.py" || bad "missing $SLOWPOKE_TOP/src/main.py"
[[ -f "$EVAL/safe_delete_workloads.sh" ]] && ok "safe_delete_workloads.sh" \
  || bad "missing safe_delete_workloads.sh"
[[ -x "$EVAL/run_with_monitor.sh" ]] && ok "run_with_monitor.sh" \
  || bad "missing or not executable: run_with_monitor.sh"
[[ -x "$EVAL/watch_progress.sh" ]] && ok "watch_progress.sh" \
  || bad "missing or not executable: watch_progress.sh"

for script in social/run-social-medium.sh movie/run-movie-medium.sh; do
  f="$EVAL/$script"
  if [[ -f "$f" ]] && grep -q '\-\-repetitions' "$f"; then
    ok "$script"
  else
    bad "$script missing or missing --repetitions"
  fi
done

RUN_SH="$SLOWPOKE_TOP/src/run.sh"
if grep -q 'start_rust_proxy' "$RUN_SH" 2>/dev/null && grep -q 'nohup.*proxy' "$RUN_SH" 2>/dev/null; then
  ok "run.sh proxy fix"
else
  bad "run.sh missing nohup proxy fix — run: bash $EVAL/install_netpoke_fixes.sh"
fi

for data in social/data/analysis.txt movie/data/analysis.txt; do
  [[ -f "$EVAL/$data" ]] && ok "$data" || bad "missing $EVAL/$data"
done

# --- run_social_movie.sh integrity ---
RSM="$EVAL/run_social_movie.sh"
if [[ ! -f "$RSM" ]]; then
  bad "missing $RSM — run: bash $EVAL/setup_social_movie_run.sh"
elif [[ $(wc -l < "$RSM") -lt 100 ]]; then
  bad "run_social_movie.sh looks truncated ($(wc -l < "$RSM") lines) — re-run setup_social_movie_run.sh"
elif ! grep -q 'save_completed_log' "$RSM" || ! grep -q 'BENCHES=(social movie)' "$RSM"; then
  bad "run_social_movie.sh corrupt — re-run setup_social_movie_run.sh"
else
  ok "run_social_movie.sh ($(wc -l < "$RSM") lines)"
fi

# --- prerequisite results ---
for prereq in boutique hotel; do
  pf="$RESULTS/${prereq}_medium.log"
  if [[ -f "$pf" ]] && grep -q 'Error Perc:' "$pf"; then
    ok "${prereq}_medium.log complete"
  else
    bad "${prereq}_medium.log missing or incomplete (required before social/movie)"
  fi
done

# --- social/movie status ---
for bench in social movie; do
  f="$RESULTS/${bench}_medium.log"
  if [[ -f "$f" ]] && grep -q 'Error Perc:' "$f"; then
    ok "${bench}_medium.log already complete (will skip)"
  elif [[ -f "$f" ]] && [[ ! -s "$f" ]]; then
    warn "${bench}_medium.log is empty — will be removed before run"
  else
    ok "${bench}_medium.log will run (incomplete or missing)"
  fi
done

# --- no duplicate run ---
if pgrep -f '[p]ython3.*main\.py' >/dev/null; then
  bad "main.py already running — wait or stop it before starting"
  ps aux | grep '[p]ython3.*main\.py' || true
else
  ok "no main.py process running"
fi

# --- kubectl ---
if kubectl cluster-info >/dev/null 2>&1; then
  ok "kubectl cluster reachable"
  npods=$(kubectl get pods -n default --no-headers 2>/dev/null | wc -l)
  echo "       pods in default namespace: $npods"
  if (( npods > 0 )); then
    warn "cluster has pods — setup will run safe_delete_workloads.sh"
    kubectl get pods -n default 2>/dev/null | head -8
  fi
else
  bad "kubectl cluster-info failed"
fi

# --- nodes ---
nodes=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || echo 0)
if (( nodes >= 1 )); then
  ok "kubernetes nodes Ready: $nodes"
  kubectl get nodes 2>/dev/null || true
else
  bad "no Ready kubernetes nodes"
fi

echo ""
if (( FAIL )); then
  echo "PREFLIGHT FAILED — fix items above before running."
  exit 1
fi

echo "PREFLIGHT PASSED — safe to run:"
echo "  cd $EVAL"
echo "  screen -S slowpoke-social-movie"
echo "  export SLOWPOKE_TOP=$SLOWPOKE_TOP PYTHONUNBUFFERED=1"
echo "  WATCH_INTERVAL=10 ./run_social_movie.sh"
