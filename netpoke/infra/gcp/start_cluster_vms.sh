#!/bin/bash
# Start all cluster VMs (handles optional loadgen).
#   cd netpoke/infra/gcp && ./start_cluster_vms.sh
set -euo pipefail
cd "$(dirname "$0")"
[[ -f config.env ]] && source config.env
CLUSTER_PREFIX="${CLUSTER_PREFIX:-netpoke}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
LOADGEN_ZONE="${LOADGEN_ZONE:-us-central1-b}"
ENABLE_LOADGEN="${ENABLE_LOADGEN:-1}"

gcloud config set project "${GCP_PROJECT:-$(gcloud config get-value project)}" >/dev/null

echo "==> Starting control + workers in $GCP_ZONE"
gcloud compute instances start \
  "${CLUSTER_PREFIX}-control" \
  "${CLUSTER_PREFIX}-worker1" \
  "${CLUSTER_PREFIX}-worker2" \
  "${CLUSTER_PREFIX}-worker3" \
  --zone="$GCP_ZONE"

if [[ "$ENABLE_LOADGEN" == "1" ]]; then
  echo "==> Starting loadgen in $LOADGEN_ZONE"
  if ! gcloud compute instances start "${CLUSTER_PREFIX}-loadgen" --zone="$LOADGEN_ZONE" 2>&1; then
    echo ""
    echo "loadgen failed to start (often: no e2-standard-4 in that zone)."
    echo "Fix options:"
    echo "  A) Skip loadgen (fine for SlowPoke):  echo 'ENABLE_LOADGEN=0' >> config.env"
    echo "  B) Smaller type:  gcloud compute instances set-machine-type ${CLUSTER_PREFIX}-loadgen \\"
    echo "       --zone=$LOADGEN_ZONE --machine-type=e2-standard-2"
    echo "     then run this script again."
    exit 1
  fi
else
  echo "==> loadgen disabled (ENABLE_LOADGEN=0)"
fi

gcloud compute instances list --filter="tags.items=netpoke-cluster" \
  --format="table(name,zone.basename(),status,machineType.basename())"
