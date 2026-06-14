#!/usr/bin/env bash
# Smoke-test sch_plug inside a running SlowPoke pod on the cluster.
#
# Usage (on netpoke-control):
#   export SLOWPOKE_TOP=~/slowpoke
#   bash phase5_netpoke/test_sch_plug.sh [namespace/deployment]
#
# Default target: boutique/shipping (I/O-heavy, worker3).
set -euo pipefail

TARGET="${1:-boutique/shipping}"
NS="${TARGET%%/*}"
DEPLOY="${TARGET#*/}"
IFACE="${SLOWPOKE_NET_IFACE:-eth0}"
LIMIT="${SLOWPOKE_PLUG_LIMIT:-1000}"

echo "=== sch_plug smoke test: $NS/$DEPLOY dev=$IFACE limit=$LIMIT ==="

POD=$(kubectl -n "$NS" get pods -l "app=$DEPLOY" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
  echo "FAIL: no pod for app=$DEPLOY in namespace $NS"
  exit 1
fi
echo "Pod: $POD"

kubectl -n "$NS" exec "$POD" -- sh -c "
  set -e
  IFACE='$IFACE'
  LIMIT='$LIMIT'
  echo '--- interfaces ---'
  ip link show \"\$IFACE\"
  echo '--- add plug qdisc ---'
  tc qdisc del dev \"\$IFACE\" root 2>/dev/null || true
  tc qdisc add dev \"\$IFACE\" root plug limit \"\$LIMIT\"
  tc qdisc show dev \"\$IFACE\"
  echo '--- buffer + release ---'
  tc qdisc change dev \"\$IFACE\" root plug buffer
  tc qdisc change dev \"\$IFACE\" root plug release_indefinite
  echo '--- cleanup ---'
  tc qdisc del dev \"\$IFACE\" root
  echo 'PASS: sch_plug add/buffer/release/delete on '\$IFACE
"

echo ""
echo "Next: rebuild images with NetPoke poker, set SLOWPOKE_NETPOKE=1, add NET_ADMIN."
