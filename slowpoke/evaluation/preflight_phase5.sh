#!/usr/bin/env bash
# Full audit before Phase 5 (NetPoke). Run on netpoke-control only.
#
#   export SLOWPOKE_TOP=~/slowpoke
#   cd ~/slowpoke/evaluation
#   bash preflight_phase5.sh
#
set -u

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
RESULTS="$EVAL/results"
FAIL=0
WARN=0

ok()   { echo "  OK: $*"; }
fail() { echo "  FAIL: $*"; FAIL=$((FAIL + 1)); }
warn() { echo "  WARN: $*"; WARN=$((WARN + 1)); }

echo "=== NetPoke preflight Phase 5 $(date -Is) ==="
echo "SLOWPOKE_TOP=$SLOWPOKE_TOP"
echo ""

echo "--- Slowpoke tree ---"
[[ -f "$SLOWPOKE_TOP/src/main.py" ]] && ok "src/main.py" || fail "missing $SLOWPOKE_TOP/src/main.py"
[[ -f "$SLOWPOKE_TOP/src/poker/poker.c" ]] && ok "poker.c" || fail "missing poker.c"
if [[ -f "$SLOWPOKE_TOP/src/poker/net_hold.c" ]]; then
  ok "net_hold.c (NetPoke)"
else
  fail "net_hold.c missing — sync src/poker from repo"
fi
echo ""

echo "--- Phase 5 scripts ---"
for f in phase5_netpoke/test_sch_plug.sh phase5_netpoke/patch_netpoke_caps.py; do
  [[ -f "$EVAL/$f" ]] && ok "$f" || warn "missing $f (sync from git/scp)"
done
echo ""

echo "--- Kubernetes ---"
if kubectl get nodes >/dev/null 2>&1; then
  ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready' || true)
  ok "nodes Ready: $ready"
else
  fail "kubectl get nodes"
fi
if pgrep -f 'python3.*main\.py' >/dev/null; then
  warn "main.py still running: $(pgrep -af 'python3.*main\.py' | head -1)"
else
  ok "no active main.py"
fi
pod_count=$(kubectl get pods -A --no-headers 2>/dev/null | wc -l | tr -d ' ')
(( pod_count < 20 )) && ok "pod count modest ($pod_count)" || warn "many pods running ($pod_count) — consider safe_delete_workloads.sh"
echo ""

echo "--- Phase 1 L0 baselines ---"
for app in boutique hotel social movie; do
  log="$RESULTS/${app}_medium.log"
  if [[ -f "$log" ]] && grep -q 'Error Perc:' "$log"; then
    ok "$app L0"
  else
    fail "$app L0 incomplete"
  fi
done
echo ""

echo "--- Phase 3 I/O gap (8 runs) ---"
for app in boutique hotel social movie; do
  for level in L1 L2; do
    log="$RESULTS/${app}_io_${level}_medium.log"
    if [[ -f "$log" ]] && grep -q 'Error Perc:' "$log"; then
      ok "$app $level"
    else
      fail "$app $level missing"
    fi
  done
done
echo ""

echo "--- Phase 4 eBPF (4 apps) ---"
P4_OK=0
for app in social hotel movie boutique; do
  log="$RESULTS/${app}_ebpf_L2_medium.log"
  jsonl="$RESULTS/${app}_ebpf_L2_residual.jsonl"
  if [[ ! -f "$log" ]] || ! grep -q 'Error Perc:' "$log"; then
    fail "$app ebpf log incomplete"
    continue
  fi
  tp=$(grep -c '\[exp\] Throughput:' "$log" 2>/dev/null || echo 0)
  if (( tp != 21 )); then
    warn "$app ebpf: $tp/21 throughput lines"
  fi
  if [[ ! -s "$jsonl" ]]; then
    fail "$app ebpf jsonl empty"
    continue
  fi
  ok "$app ebpf (tp=$tp jsonl=$(wc -l <"$jsonl") lines)"
  P4_OK=$((P4_OK + 1))
done
echo ""

echo "--- Phase 4 summary ---"
if [[ -f "$RESULTS/final_package/ebpf_residual_summary.csv" ]]; then
  ok "ebpf_residual_summary.csv"
else
  warn "run: python3 phase4_ebpf/summarize_ebpf_residual.py results/ -o results/final_package/ebpf_residual_summary.csv"
fi
if ls ~/netpoke_phase4_complete_*.tar.gz >/dev/null 2>&1; then
  ok "archive: $(ls -t ~/netpoke_phase4_complete_*.tar.gz | head -1)"
else
  warn "no ~/netpoke_phase4_complete_*.tar.gz on VM"
fi
echo ""

echo "--- Helper scripts on VM ---"
for f in \
  phase4_ebpf/plot_ebpf_residual.py \
  phase4_ebpf/finalize_phase4_results.sh \
  scripts/build_presentation_pack.sh \
  watch_progress.sh \
  install_netpoke_fixes.sh; do
  [[ -f "$EVAL/$f" ]] && ok "$f" || warn "missing $f (sync from git/scp)"
done
echo ""

echo "--- sch_plug quick test ---"
if [[ -x "$EVAL/phase5_netpoke/test_sch_plug.sh" ]]; then
  echo "  bash phase5_netpoke/test_sch_plug.sh boutique/shipping"
else
  echo "  Run manually in a running pod:"
  echo "  tc qdisc add dev eth0 root plug limit 1000 && tc qdisc del dev eth0 root"
fi
echo ""

echo "=== Summary ==="
echo "Phase 4 complete: $P4_OK/4"
echo "Failures: $FAIL  Warnings: $WARN"
if (( FAIL == 0 && P4_OK == 4 )); then
  echo ""
  echo "READY for Phase 5 implementation (NetPoke in poker.c) + sch_plug pod test."
  echo "NOT READY for Phase 6 until NetPoke is built and images redeployed."
  exit 0
elif (( P4_OK == 4 )); then
  echo ""
  echo "Phase 4 data OK; fix FAIL items above before Phase 6."
  exit 1
else
  echo ""
  echo "NOT READY — complete Phase 4 first."
  exit 1
fi
