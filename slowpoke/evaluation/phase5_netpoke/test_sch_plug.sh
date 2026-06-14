#!/usr/bin/env bash
# Smoke-test sch_plug inside a pod on the cluster.
#
# Usage (on netpoke-control):
#   export SLOWPOKE_TOP=~/slowpoke
#   cd ~/slowpoke/evaluation
#
#   # Fastest: ephemeral netshoot pod (no boutique deploy)
#   bash phase5_netpoke/test_sch_plug.sh --netshoot
#
#   # Or against a SlowPoke service pod (default namespace):
#   bash phase5_netpoke/deploy_smoke_pod.sh shipping
#   bash phase5_netpoke/test_sch_plug.sh shipping
#
# Target format: [namespace/]app   (namespace defaults to "default")
set -euo pipefail

IFACE="${SLOWPOKE_NET_IFACE:-eth0}"
LIMIT="${SLOWPOKE_PLUG_LIMIT:-1000}"

run_tc_test() {
  local ns="$1"
  local pod="$2"

  echo "=== sch_plug smoke test: $ns/$pod dev=$IFACE limit=$LIMIT ==="
  echo "Pod: $pod"

  kubectl -n "$ns" exec "$pod" -- sh -c "
    set -e
    IFACE='$IFACE'
    LIMIT='$LIMIT'
    echo '--- interfaces ---'
    ip link show \"\$IFACE\"
    echo '--- add plug qdisc ---'
    tc qdisc del dev \"\$IFACE\" root 2>/dev/null || true
    tc qdisc add dev \"\$IFACE\" root plug limit \"\$LIMIT\"
    tc qdisc show dev \"\$IFACE\"
    echo '--- block + release ---'
    tc qdisc change dev \"\$IFACE\" root plug block
    tc qdisc change dev \"\$IFACE\" root plug release_indefinite
    echo '--- cleanup ---'
    tc qdisc del dev \"\$IFACE\" root
    echo 'PASS: sch_plug add/block/release/delete on '\$IFACE
  "

  echo ""
  echo "Next: rebuild images with NetPoke poker, set SLOWPOKE_NETPOKE=1, add NET_ADMIN."
}

if [[ "${1:-}" == "--netshoot" ]]; then
  POD="sch-plug-smoke-$$"
  echo "=== sch_plug smoke test (netshoot pod) dev=$IFACE limit=$LIMIT ==="
  kubectl run "$POD" --restart=Never --image=nicolaka/netshoot:latest \
    --overrides='{"spec":{"containers":[{"name":"'"$POD"'","image":"nicolaka/netshoot:latest","command":["sleep","600"],"securityContext":{"capabilities":{"add":["NET_ADMIN"]}}}]}}' \
    >/dev/null
  trap 'kubectl delete pod '"$POD"' --ignore-not-found --wait=false 2>/dev/null || true' EXIT
  kubectl wait --for=condition=ready "pod/$POD" --timeout=120s
  run_tc_test default "$POD"
  exit 0
fi

TARGET="${1:-shipping}"
if [[ "$TARGET" == */* ]]; then
  NS="${TARGET%%/*}"
  DEPLOY="${TARGET#*/}"
else
  NS="${KUBE_NAMESPACE:-default}"
  DEPLOY="$TARGET"
fi

POD=$(kubectl -n "$NS" get pods -l "app=$DEPLOY" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || true)
if [[ -z "$POD" ]]; then
  echo "FAIL: no pod for app=$DEPLOY in namespace $NS"
  echo ""
  echo "Cluster looks idle. Either:"
  echo "  bash phase5_netpoke/test_sch_plug.sh --netshoot"
  echo "  bash phase5_netpoke/deploy_smoke_pod.sh $DEPLOY"
  echo "  bash phase5_netpoke/test_sch_plug.sh $DEPLOY"
  exit 1
fi

run_tc_test "$NS" "$POD"
