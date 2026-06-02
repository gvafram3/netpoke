#!/bin/bash
# Fix "Cannot initiate connection" / apt / wget timeouts during cluster init.
#
# Two common causes on student GCP projects:
#   1. VMs without a public IP need Cloud NAT to reach the internet.
#   2. Broken IPv6 makes apt fail before trying IPv4 — we force IPv4.
#
# Run from Cloud Shell BEFORE ./02_initialize_cluster.sh (or before retry):
#   cd ~/netpoke/netpoke/infra/gcp
#   ./fix_network_egress.sh
#   ./fix_network_egress.sh --test-only    # only test, no changes

set -euo pipefail
cd "$(dirname "$0")"

TEST_ONLY=0
[[ "${1:-}" == "--test-only" ]] && TEST_ONLY=1

if [[ -f config.env ]]; then
  # shellcheck disable=SC1091
  source config.env
else
  GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
  CLUSTER_PREFIX="${CLUSTER_PREFIX:-netpoke}"
  NETWORK_TAG="${NETWORK_TAG:-netpoke-cluster}"
  GCP_REGION="${GCP_REGION:-us-central1}"
fi

gcloud config set project "$GCP_PROJECT" >/dev/null

ROUTER="${CLUSTER_PREFIX}-router"
NAT="${CLUSTER_PREFIX}-nat"

vm_zone () {
  gcloud compute instances list --filter="name=$1" --format="value(zone.basename())" | head -1
}

vm_has_nat_ip () {
  local ip
  ip="$(gcloud compute instances describe "$1" --zone "$(vm_zone "$1")" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || true)"
  [[ -n "$ip" ]]
}

gcloud_ssh () {
  local vm=$1 cmd=$2 z args=(--zone "$(vm_zone "$vm")" --quiet)
  if ! vm_has_nat_ip "$vm"; then
    args+=(--tunnel-through-iap)
  fi
  gcloud compute ssh "$vm" "${args[@]}" --command "$cmd"
}

echo "==> [1/3] Internet test from each VM (IPv4 curl to google.com)"
VMS=("${CLUSTER_PREFIX}-control" "${CLUSTER_PREFIX}-loadgen" \
     "${CLUSTER_PREFIX}-worker1" "${CLUSTER_PREFIX}-worker2" "${CLUSTER_PREFIX}-worker3")
FAIL=0
for vm in "${VMS[@]}"; do
  z="$(vm_zone "$vm")"
  [[ -z "$z" ]] && continue
  echo -n "    $vm: "
  if gcloud_ssh "$vm" 'curl -4 -sS -o /dev/null -w "%{http_code}" --connect-timeout 10 https://www.google.com || echo FAIL'; then
    :
  else
    echo "SSH or curl failed"
    FAIL=$((FAIL + 1))
  fi
done

echo ""
echo "==> [2/3] Cloud NAT (lets VMs without public IP download packages)"
if gcloud compute routers describe "$ROUTER" --region="$GCP_REGION" >/dev/null 2>&1; then
  echo "    Router $ROUTER already exists"
else
  if [[ "$TEST_ONLY" -eq 1 ]]; then
    echo "    WOULD CREATE router $ROUTER in $GCP_REGION (run without --test-only)"
  else
    echo "    Creating router $ROUTER ..."
    gcloud compute routers create "$ROUTER" \
      --network=default \
      --region="$GCP_REGION" \
      --quiet
  fi
fi

if gcloud compute routers nats describe "$NAT" --router="$ROUTER" --region="$GCP_REGION" >/dev/null 2>&1; then
  echo "    NAT $NAT already exists"
else
  if [[ "$TEST_ONLY" -eq 1 ]]; then
    echo "    WOULD CREATE NAT $NAT (run without --test-only)"
  else
    echo "    Creating NAT $NAT ..."
    gcloud compute routers nats create "$NAT" \
      --router="$ROUTER" \
      --region="$GCP_REGION" \
      --auto-allocate-nat-external-ips \
      --nat-all-subnet-ip-ranges \
      --quiet
  fi
fi

echo ""
echo "==> [3/3] Force apt to use IPv4 on all cluster VMs"
APT_FIX='echo "Acquire::ForceIPv4 \"true\";" | sudo tee /etc/apt/apt.conf.d/99force-ipv4'
if [[ "$TEST_ONLY" -eq 1 ]]; then
  echo "    WOULD apply apt IPv4 fix on each VM"
else
  for vm in "${VMS[@]}"; do
    z="$(vm_zone "$vm")"
    [[ -z "$z" ]] && continue
    echo "    $vm"
    gcloud_ssh "$vm" "$APT_FIX" || true
  done
fi

echo ""
if [[ "$TEST_ONLY" -eq 1 ]]; then
  echo "Test-only done. If curl failed above, run:  ./fix_network_egress.sh"
  exit 0
fi

echo "Done. Wait ~30 seconds, then re-test one VM:"
echo "  gcloud compute ssh netpoke-control --zone=us-central1-a --command \\"
echo "    'curl -4 -sS -I --connect-timeout 10 https://github.com | head -1'"
echo ""
echo "If that works, re-run:  ./02_initialize_cluster.sh"
