#!/usr/bin/env bash
# Step 2 of the corrected NetPoke plan (see netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md).
#
# Reads each non-target service pod's POKER logs and reports whether the
# fixed net_hold.c is actually toggling sch_plug via netlink (microseconds)
# or fell back to the tc CLI (milliseconds) on this cluster's kernel, plus
# the real per-toggle latency distribution either way. This does NOT re-run
# any experiment -- run phase6_netpoke/run_toggle_smoke.sh first (or any
# SLOWPOKE_NETPOKE=1 run), then run this against the still-live pods.
#
# Usage (on netpoke-control):
#   bash phase6_netpoke/check_toggle_latency.sh <boutique|hotel|social|movie>
set -euo pipefail

BENCH="${1:?benchmark required (boutique|hotel|social|movie)}"
EVAL="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IO_GAP="$EVAL/io_gap"

# shellcheck source=../io_gap/io_levels.conf
source "$IO_GAP/io_levels.conf"
var="IO_${BENCH^^}_L2_TARGET"
TARGET="${!var}"

echo "=== NetPoke toggle-latency check: $BENCH (target=$TARGET excluded) ==="

pods=$(kubectl get pods -n default -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.phase}{"\n"}{end}' \
  | awk '$2=="Running"{print $1}')

if [[ -z "$pods" ]]; then
  echo "FAIL: no running pods in namespace 'default'. Deploy first (run_toggle_smoke.sh)."
  exit 1
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

any_logs=0
for pod in $pods; do
  svc="${pod%%-*}"
  [[ "$svc" == "$TARGET" ]] && continue
  ctr=$(kubectl get pod -n default "$pod" -o jsonpath='{.spec.containers[0].name}' 2>/dev/null || echo "")
  [[ -z "$ctr" ]] && continue
  if kubectl logs -n default "$pod" -c "$ctr" 2>/dev/null | grep -q 'netpoke:'; then
    any_logs=1
    kubectl logs -n default "$pod" -c "$ctr" 2>/dev/null | grep 'netpoke:' | sed "s/^/$svc: /" >>"$tmp"
  fi
done

if (( ! any_logs )); then
  echo "FAIL: no 'netpoke:' lines found in any non-target pod log."
  echo "Check: was SLOWPOKE_NETPOKE=1 set for this deploy? Is the *-netpoke image running (kubectl describe pod)?"
  exit 1
fi

echo ""
echo "--- init / fallback events ---"
grep -E 'sch_plug ready|falling back to tc CLI|failed to install' "$tmp" || echo "(none)"

echo ""
echo "--- toggle latency (took_ns), by path ---"
for via in netlink cli; do
  grep "via=$via " "$tmp" \
    | grep -oE 'took_ns=[0-9]+' \
    | cut -d= -f2 \
    | awk -v via="$via" '
        { n++; sum+=$1; if (min==""||$1<min) min=$1; if ($1>max) max=$1 }
        END { if (n>0) printf "%-8s n=%-8d min_ns=%-10d avg_ns=%-10d max_ns=%-10d (avg=%.3fms)\n", via, n, min, sum/n, max, (sum/n)/1e6 }
      '
done

echo ""
n_netlink=$(grep -c 'via=netlink' "$tmp" || true)
n_cli=$(grep -c 'via=cli' "$tmp" || true)
echo "--- verdict ---"
if (( n_cli == 0 && n_netlink > 0 )); then
  echo "PASS: all $n_netlink toggles used netlink. F1 fix confirmed on this kernel."
elif (( n_netlink == 0 && n_cli > 0 )); then
  echo "STILL BROKEN: all $n_cli toggles fell back to the tc CLI -- netlink is still rejected on this kernel."
  echo "Check the 'falling back to tc CLI' reason above (likely EINVAL/ENOENT/EPERM) and report it back before scaling up."
else
  echo "MIXED: $n_netlink netlink, $n_cli cli -- some toggles fell back mid-run. Inspect the fallback reason above."
fi
