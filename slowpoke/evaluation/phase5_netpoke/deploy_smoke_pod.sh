#!/usr/bin/env bash
# Deploy a single boutique SlowPoke service for Phase 5 smoke tests.
#
#   export SLOWPOKE_TOP=~/slowpoke
#   cd ~/slowpoke/evaluation
#   bash phase5_netpoke/deploy_smoke_pod.sh shipping
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"
SERVICE="${1:-shipping}"
YAML="$EVAL/boutique/yamls/${SERVICE}.yaml"

if [[ ! -f "$YAML" ]]; then
  echo "FAIL: missing $YAML"
  exit 1
fi

# Defaults so envsubst produces valid YAML when main.py is not driving the run.
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

echo "=== Deploy smoke pod: boutique/$SERVICE (namespace default) ==="
envsubst <"$YAML" | kubectl apply -f -
kubectl wait --for=condition=ready "pod" -l "app=$SERVICE" --timeout=180s
kubectl get pods -l "app=$SERVICE" -o wide
echo ""
echo "Run: bash phase5_netpoke/test_sch_plug.sh $SERVICE"
