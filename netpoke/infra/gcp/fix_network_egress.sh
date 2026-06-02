#!/bin/bash
# Give every cluster VM outbound internet (Cloud NAT + apt IPv4).
# Exit 0 only when all VMs return HTTP 200 from inside the VM.
set -euo pipefail
cd "$(dirname "$0")"

if [[ -f config.env ]]; then
  # shellcheck disable=SC1091
  source config.env
fi
GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
CLUSTER_PREFIX="${CLUSTER_PREFIX:-netpoke}"
NETWORK_TAG="${NETWORK_TAG:-netpoke-cluster}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
GCP_REGION="${GCP_REGION:-${GCP_ZONE%-*}}"

gcloud config set project "$GCP_PROJECT" >/dev/null

ROUTER="${CLUSTER_PREFIX}-router"
NAT="${CLUSTER_PREFIX}-nat"
VMS=("${CLUSTER_PREFIX}-control" "${CLUSTER_PREFIX}-loadgen" \
     "${CLUSTER_PREFIX}-worker1" "${CLUSTER_PREFIX}-worker2" "${CLUSTER_PREFIX}-worker3")

vm_zone () {
  gcloud compute instances list --filter="name=$1" --format="value(zone.basename())" | head -1
}

vm_has_public_ip () {
  local ip
  ip="$(gcloud compute instances describe "$1" --zone "$(vm_zone "$1")" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || true)"
  [[ -n "$ip" ]]
}

run_on_vm () {
  local vm=$1 cmd=$2 args=(--zone "$(vm_zone "$vm")" --quiet)
  if ! vm_has_public_ip "$vm"; then
    args+=(--tunnel-through-iap)
  fi
  gcloud compute ssh "$vm" "${args[@]}" --command "$cmd" 2>/dev/null
}

echo "==> Cloud NAT"
if ! gcloud compute routers describe "$ROUTER" --region="$GCP_REGION" >/dev/null 2>&1; then
  gcloud compute routers create "$ROUTER" --network=default --region="$GCP_REGION" --quiet
fi
NAT_NEW=0
if ! gcloud compute routers nats describe "$NAT" --router="$ROUTER" --region="$GCP_REGION" >/dev/null 2>&1; then
  gcloud compute routers nats create "$NAT" --router="$ROUTER" --region="$GCP_REGION" \
    --auto-allocate-nat-external-ips --nat-all-subnet-ip-ranges --quiet
  NAT_NEW=1
  sleep 90
fi

FW="default-allow-iap"
if ! gcloud compute firewall-rules describe "$FW" >/dev/null 2>&1; then
  gcloud compute firewall-rules create "$FW" --network=default --direction=INGRESS \
    --action=ALLOW --rules=tcp:22 --source-ranges=35.235.240.0/20 \
    --target-tags="$NETWORK_TAG" --quiet
fi

APT_FIX='echo "Acquire::ForceIPv4 \"true\";" | sudo tee /etc/apt/apt.conf.d/99force-ipv4 >/dev/null'
for vm in "${VMS[@]}"; do
  [[ -z "$(vm_zone "$vm")" ]] && continue
  run_on_vm "$vm" "$APT_FIX" || true
done

[[ "$NAT_NEW" -eq 0 ]] && sleep 10

echo "==> Internet test (from inside each VM)"
FAIL=0
for vm in "${VMS[@]}"; do
  [[ -z "$(vm_zone "$vm")" ]] && continue
  code="$(run_on_vm "$vm" \
    'curl -4 -sS -o /dev/null -w "%{http_code}" --connect-timeout 20 https://www.google.com' \
    | tr -d '\r\n' | tail -1)"
  if [[ "$code" == "200" ]]; then
    echo "    $vm  PASS"
  else
    echo "    $vm  FAIL ($code)"
    FAIL=$((FAIL + 1))
  fi
done

if [[ "$FAIL" -eq 0 ]]; then
  echo "SUCCESS — all VMs have internet."
  exit 0
fi
echo "Wait 2 min and run again."
exit 1
