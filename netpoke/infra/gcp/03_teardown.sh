#!/bin/bash
# NetPoke GCP cluster: tear everything down to stop all charges.
#
# This DELETES the VMs (and their boot disks) and removes the firewall rule.
# Run this whenever you are not actively running experiments.
#
# Usage:
#   cd netpoke/infra/gcp
#   ./03_teardown.sh

set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f config.env ]]; then
  echo "ERROR: config.env not found. Run:  cp config.env.example config.env"
  exit 1
fi
# shellcheck disable=SC1091
source config.env

gcloud config set project "$GCP_PROJECT" >/dev/null

NAMES=("${CLUSTER_PREFIX}-control" "${CLUSTER_PREFIX}-loadgen")
for i in $(seq 1 "$NUM_WORKERS"); do NAMES+=("${CLUSTER_PREFIX}-worker${i}"); done

echo "About to DELETE these VMs in $GCP_ZONE:"
printf '   %s\n' "${NAMES[@]}"
read -r -p "Type 'yes' to confirm: " ans
[[ "$ans" == "yes" ]] || { echo "Aborted."; exit 1; }

gcloud compute instances delete "${NAMES[@]}" --zone "$GCP_ZONE" --quiet || true

FW_RULE="${NETWORK_TAG}-allow-internal"
if gcloud compute firewall-rules describe "$FW_RULE" >/dev/null 2>&1; then
  gcloud compute firewall-rules delete "$FW_RULE" --quiet || true
fi

echo ""
echo "Teardown complete. Remaining instances tagged ${NETWORK_TAG} (should be none):"
gcloud compute instances list --filter="tags.items=${NETWORK_TAG}" || true
echo ""
echo "TIP: also remember to STOP your slowpoke-vm when idle:"
echo "    gcloud compute instances stop slowpoke-vm --zone ${GCP_ZONE}"
