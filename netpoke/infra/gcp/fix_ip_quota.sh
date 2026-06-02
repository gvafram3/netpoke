#!/bin/bash
# Free regional external IP quota (IN_USE_ADDRESSES) for student GCP projects.
#
# Default layout: only netpoke-control keeps a public IP. Workers and loadgen
# use internal IPs; gcloud ssh/scp uses IAP (--tunnel-through-iap) in step 2.
#
# Usage (Cloud Shell):
#   cd netpoke/infra/gcp
#   cp config.env.example config.env   # if needed
#   ./fix_ip_quota.sh                  # dry-run: shows plan
#   ./fix_ip_quota.sh --apply          # remove NAT from non-control VMs
#   gcloud compute instances start netpoke-worker3 --zone=us-central1-a

set -euo pipefail
cd "$(dirname "$0")"

APPLY=0
[[ "${1:-}" == "--apply" ]] && APPLY=1

if [[ -f config.env ]]; then
  # shellcheck disable=SC1091
  source config.env
else
  CLUSTER_PREFIX="${CLUSTER_PREFIX:-netpoke}"
fi

CONTROL="${CLUSTER_PREFIX}-control"
OTHERS=(
  "${CLUSTER_PREFIX}-loadgen"
  "${CLUSTER_PREFIX}-worker1"
  "${CLUSTER_PREFIX}-worker2"
  "${CLUSTER_PREFIX}-worker3"
)

vm_zone () {
  local vm="$1"
  gcloud compute instances list --filter="name=${vm}" \
    --format="value(zone.basename())" 2>/dev/null | head -1
}

echo "==> External IPs in use (region us-central1, all projects VMs)"
gcloud compute addresses list --regions=us-central1 2>/dev/null || true
echo ""
gcloud compute instances list \
  --filter="tags.items=netpoke-cluster OR name~'^netpoke-'" \
  --format="table(name,zone.basename(),status,networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)"

echo ""
echo "==> Plan: keep public IP on ${CONTROL} only"
for vm in "${OTHERS[@]}"; do
  z="$(vm_zone "$vm")"
  [[ -z "$z" ]] && continue
  nat="$(gcloud compute instances describe "$vm" --zone "$z" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || true)"
  if [[ -n "$nat" ]]; then
    echo "  REMOVE NAT on $vm ($z)  currently $nat"
  else
    echo "  skip $vm ($z) — no external IP"
  fi
done

if [[ "$APPLY" -eq 0 ]]; then
  echo ""
  echo "Dry run only. To apply:  ./fix_ip_quota.sh --apply"
  echo "Then start worker3:  gcloud compute instances start netpoke-worker3 --zone=us-central1-a"
  exit 0
fi

echo ""
echo "==> Applying (instances must be RUNNING or TERMINATED for delete-access-config)"
for vm in "${OTHERS[@]}"; do
  z="$(vm_zone "$vm")"
  [[ -z "$z" ]] && continue
  nat="$(gcloud compute instances describe "$vm" --zone "$z" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || true)"
  [[ -z "$nat" ]] && continue
  echo "    delete-access-config $vm ($z)"
  gcloud compute instances delete-access-config "$vm" \
    --zone "$z" \
    --access-config-name="External NAT" \
    --quiet
done

echo ""
echo "==> Ensure IAP SSH firewall (needed for nodes without public IP)"
FW="default-allow-iap"
if ! gcloud compute firewall-rules describe "$FW" >/dev/null 2>&1; then
  echo "    creating $FW"
  gcloud compute firewall-rules create "$FW" \
    --network=default \
    --direction=INGRESS \
    --action=ALLOW \
    --rules=tcp:22 \
    --source-ranges=35.235.240.0/20 \
    --target-tags=netpoke-cluster \
    --quiet
else
  echo "    $FW already exists"
fi

echo ""
echo "Done. External IP count should be 1 (${CONTROL}). Start worker3 if needed."
