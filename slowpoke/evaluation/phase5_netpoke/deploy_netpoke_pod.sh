#!/usr/bin/env bash
# Deploy one NetPoke-patched service: strip netem sidecar, NET_ADMIN, envsubst, apply.
#
#   export SLOWPOKE_TOP=~/slowpoke
#   cd ~/slowpoke/evaluation
#   bash phase5_netpoke/deploy_netpoke_pod.sh shipping boutique
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SERVICE="${1:-shipping}"
BENCH="${2:-boutique}"
SRC="$EVAL/$BENCH/yamls/${SERVICE}.yaml"
DST="$EVAL/$BENCH/yamls/netpoke/${SERVICE}.yaml"

if [[ ! -f "$SRC" ]]; then
  echo "FAIL: missing $SRC"
  exit 1
fi

mkdir -p "$(dirname "$DST")"

# Defaults for envsubst (same as deploy_smoke_pod.sh).
export SLOWPOKE_PRERUN="${SLOWPOKE_PRERUN:-0}"
export SLOWPOKE_PROCESSING_MICROS_SHIPPING="${SLOWPOKE_PROCESSING_MICROS_SHIPPING:-0}"
export SLOWPOKE_DELAY_MICROS_SHIPPING="${SLOWPOKE_DELAY_MICROS_SHIPPING:-0}"
export SLOWPOKE_POKER_BATCH_THRESHOLD_SHIPPING="${SLOWPOKE_POKER_BATCH_THRESHOLD_SHIPPING:-100}"
export SLOWPOKE_IS_TARGET_SERVICE_SHIPPING="${SLOWPOKE_IS_TARGET_SERVICE_SHIPPING:-false}"
export SLOWPOKE_PROCESSING_MICROS_FRONTEND="${SLOWPOKE_PROCESSING_MICROS_FRONTEND:-0}"
export SLOWPOKE_DELAY_MICROS_FRONTEND="${SLOWPOKE_DELAY_MICROS_FRONTEND:-0}"
export SLOWPOKE_POKER_BATCH_THRESHOLD_FRONTEND="${SLOWPOKE_POKER_BATCH_THRESHOLD_FRONTEND:-100}"
export SLOWPOKE_IS_TARGET_SERVICE_FRONTEND="${SLOWPOKE_IS_TARGET_SERVICE_FRONTEND:-false}"

if [[ -f "$EVAL/boutique/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$EVAL/boutique/.env"
  set +a
fi

echo "=== NetPoke deploy: $BENCH/$SERVICE ==="
python3 "$SCRIPT_DIR/patch_netpoke_caps.py" "$SRC" "$DST" "$BENCH"

if grep -q tc-netem-sidecar "$DST"; then
  echo "FAIL: sidecar still in $DST — sync phase5_netpoke/patch_netpoke_caps.py from git"
  exit 1
fi
if ! grep -q 'NET_ADMIN' "$DST"; then
  echo "FAIL: NET_ADMIN missing from $DST"
  exit 1
fi

kubectl delete "deployment/$SERVICE" "svc/$SERVICE" --ignore-not-found --wait=true 2>/dev/null || true

envsubst <"$DST" | kubectl apply -f -
kubectl wait --for=condition=ready "pod" -l "app=$SERVICE" --timeout=180s
POD=$(kubectl get pods -l "app=$SERVICE" --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')
kubectl get pods -l "app=$SERVICE" -o wide

echo ""
echo "Logs from $POD (look for: netpoke: sch_plug ready on eth0; no tc errors):"
kubectl logs "$POD" --tail=40
