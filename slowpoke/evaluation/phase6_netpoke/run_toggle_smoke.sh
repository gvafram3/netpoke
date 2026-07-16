#!/usr/bin/env bash
# Step 2 (mechanistic smoke test) of the corrected NetPoke plan.
# See netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md before running.
#
# Deploys one benchmark with the (fixed) *-pokerpp-netpoke image via the
# existing Phase 4 smoke path (reused as-is: it already knows how to deploy
# from yamls/netpoke and run a tiny 1-point SlowPoke experiment), then reports
# whether net_hold()/net_release() actually toggled sch_plug over netlink
# (the fix) or fell back to the tc CLI (still broken on this kernel).
#
# Prerequisite: images rebuilt from the fixed slowpoke/src/poker/net_hold.c
# and pushed as gvafram3/mucache:<bench>-pokerpp-netpoke, e.g.:
#   bash phase5_netpoke/build_netpoke_images.sh boutique
#   PUSH=1 bash phase5_netpoke/build_netpoke_images.sh boutique
#
# Usage (on netpoke-control):
#   export SLOWPOKE_TOP=~/slowpoke
#   cd ~/slowpoke/evaluation
#   bash phase6_netpoke/run_toggle_smoke.sh boutique
set -euo pipefail

BENCH="${1:?benchmark required (boutique|hotel|social|movie)}"
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"

echo "=== NetPoke toggle smoke test: $BENCH ==="
echo "[1/2] deploy + tiny run with SLOWPOKE_NETPOKE=1 (reusing phase4_ebpf smoke path)"
SLOWPOKE_NETPOKE=1 SLOWPOKE_NET_IFACE=eth0 bash "$EVAL/phase4_ebpf/run_ebpf_one_L2.sh" "$BENCH" smoke

echo ""
echo "[2/2] checking POKER logs for netlink vs CLI toggle path"
bash "$EVAL/phase6_netpoke/check_toggle_latency.sh" "$BENCH"

echo ""
echo "Pods are still running (this script does not tear down) -- re-run"
echo "check_toggle_latency.sh directly to inspect again, or 'kubectl logs <pod>'"
echo "for the full netpoke: trace."
