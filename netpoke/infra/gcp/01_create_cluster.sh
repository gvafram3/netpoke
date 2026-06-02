#!/bin/bash
# NetPoke GCP cluster: STEP 1 of 2 -- create the virtual machines.
#
# This script only creates VMs and a firewall rule. It does NOT install
# Kubernetes (that is step 2, 02_initialize_cluster.sh).
#
# Usage:
#   cd netpoke/infra/gcp
#   cp config.env.example config.env   # first time only
#   ./01_create_cluster.sh
#
# Cost note: VMs cost money only while RUNNING. When you are done with a
# batch of experiments, run ./03_teardown.sh to delete everything.

set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f config.env ]]; then
  echo "ERROR: config.env not found. Run:  cp config.env.example config.env"
  exit 1
fi
# shellcheck disable=SC1091
source config.env

echo "==> Project: $GCP_PROJECT   Zone: $GCP_ZONE"
echo "==> Creating 1 control + 1 loadgen + $NUM_WORKERS workers"

gcloud config set project "$GCP_PROJECT" >/dev/null

# --- Firewall: allow all traffic between cluster nodes (kubeadm needs many ports) ---
FW_RULE="${NETWORK_TAG}-allow-internal"
if ! gcloud compute firewall-rules describe "$FW_RULE" >/dev/null 2>&1; then
  echo "==> Creating firewall rule $FW_RULE (node-to-node traffic)"
  gcloud compute firewall-rules create "$FW_RULE" \
    --network=default \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=all \
    --source-tags="$NETWORK_TAG" \
    --target-tags="$NETWORK_TAG"
else
  echo "==> Firewall rule $FW_RULE already exists, skipping"
fi

# Only the control plane needs a public IP for easy SSH from Cloud Shell.
# Workers/loadgen use internal IPs (saves IN_USE_ADDRESSES quota, default limit 4).
create_vm () {
  local name="$1" machine="$2" zone="$3" extra_args="${4:-}"
  if gcloud compute instances describe "$name" --zone "$zone" >/dev/null 2>&1; then
    echo "    $name already exists, skipping"
    return
  fi
  echo "    creating $name ($machine) in $zone"
  # shellcheck disable=SC2086
  gcloud compute instances create "$name" \
    --zone="$zone" \
    --machine-type="$machine" \
    --image-family="$IMAGE_FAMILY" \
    --image-project="$IMAGE_PROJECT" \
    --boot-disk-size="$DISK_SIZE" \
    --boot-disk-type="$DISK_TYPE" \
    --tags="$NETWORK_TAG" \
    $extra_args \
    --quiet
}

LOADGEN_ZONE="${LOADGEN_ZONE:-$GCP_ZONE}"

create_vm "${CLUSTER_PREFIX}-control" "$CONTROL_MACHINE" "$GCP_ZONE"
create_vm "${CLUSTER_PREFIX}-loadgen" "$LOADGEN_MACHINE" "$LOADGEN_ZONE" "--no-address"
for i in $(seq 1 "$NUM_WORKERS"); do
  create_vm "${CLUSTER_PREFIX}-worker${i}" "$WORKER_MACHINE" "$GCP_ZONE" "--no-address"
done

echo ""
echo "==> All VMs requested. Current state:"
gcloud compute instances list --filter="tags.items=${NETWORK_TAG}" \
  --format="table(name,machineType.basename(),status,INTERNAL_IP,EXTERNAL_IP)"

echo ""
echo "Next: wait ~60 seconds for the VMs to finish booting, then run:"
echo "    ./02_initialize_cluster.sh"
