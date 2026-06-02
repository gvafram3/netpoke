#!/bin/bash
# Collect factual state before/after Kubernetes init and before SlowPoke runs.
# Run from Cloud Shell; saves a timestamped report you can share for debugging.
#
#   cd ~/netpoke/netpoke/infra/gcp
#   ./preflight_cluster.sh              # VMs only (before step 2)
#   ./preflight_cluster.sh --after-k8s  # also SSH to control for kubectl state
#
# Optional: upload report
#   gsutil cp preflight-*.txt gs://YOUR_BUCKET/ 2>/dev/null || cat preflight-*.txt

set -euo pipefail
cd "$(dirname "$0")"

AFTER_K8S=0
[[ "${1:-}" == "--after-k8s" ]] && AFTER_K8S=1

if [[ -f config.env ]]; then
  # shellcheck disable=SC1091
  source config.env
else
  GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
  GCP_ZONE="${GCP_ZONE:-us-central1-a}"
  CLUSTER_PREFIX="${CLUSTER_PREFIX:-netpoke}"
  NETWORK_TAG="${NETWORK_TAG:-netpoke-cluster}"
  LOADGEN_ZONE="${LOADGEN_ZONE:-us-central1-b}"
fi

REPORT="preflight-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$REPORT") 2>&1

echo "NetPoke / SlowPoke cluster preflight report"
echo "Generated: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "Project:   $GCP_PROJECT"
echo ""

section () { echo ""; echo "======== $1 ========"; echo ""; }

section "A. GCP quotas (us-central1)"
gcloud compute regions describe us-central1 --format="yaml(quotas)" 2>/dev/null | \
  grep -E "metric:|usage:|limit:" | head -80 || echo "(quota describe failed)"

section "B. All netpoke-tagged VMs"
gcloud compute instances list --filter="tags.items=${NETWORK_TAG}" \
  --format="table(name,zone.basename(),machineType.basename(),status,INTERNAL_IP,networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP,tags.items.list():label=TAGS)"

section "C. Per-zone instance count (limit often 4/zone)"
gcloud compute instances list --filter="tags.items=${NETWORK_TAG}" \
  --format="csv[no-heading](zone.basename(),name,status)" | sort | \
  awk -F, '{k=$1; if($3=="RUNNING") r[k]++; t[k]++} END {for(z in t) print z": "t[z]" total, "r[z]+0" RUNNING"}'

section "D. Regional external IPs (IN_USE_ADDRESSES)"
echo "RUNNING VMs with NAT IP in project:"
gcloud compute instances list --filter="status=RUNNING" \
  --format="table(name,zone.basename(),networkInterfaces[0].accessConfigs[0].natIP)" | grep -v '^$' || true

section "E. Firewall rules for cluster + IAP"
for fw in "${NETWORK_TAG}-allow-internal" "default-allow-iap"; do
  if gcloud compute firewall-rules describe "$fw" >/dev/null 2>&1; then
    echo "--- $fw ---"
    gcloud compute firewall-rules describe "$fw" \
      --format="yaml(name,direction,sourceRanges,sourceTags,targetTags,allowed)"
  else
    echo "MISSING: $fw"
  fi
done

section "F. SSH reachability"
CONTROL="${CLUSTER_PREFIX}-control"
ctrl_zone="$(gcloud compute instances list --filter="name=${CONTROL}" --format="value(zone.basename())")"
test_ssh () {
  local vm=$1 z=$2 extra=()
  [[ -z "$z" ]] && return
  local ip
  ip="$(gcloud compute instances describe "$vm" --zone "$z" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || true)"
  if [[ -z "$ip" ]]; then
    extra=(--tunnel-through-iap)
    echo -n "$vm ($z, no public IP, IAP): "
  else
    echo -n "$vm ($z, public IP): "
  fi
  if gcloud compute ssh "$vm" --zone "$z" "${extra[@]}" --quiet --command "hostname" 2>/dev/null; then
    echo "SSH OK"
  else
    echo "SSH FAILED"
  fi
}

test_ssh "$CONTROL" "$ctrl_zone"
for vm in "${CLUSTER_PREFIX}-loadgen" "${CLUSTER_PREFIX}-worker1" \
          "${CLUSTER_PREFIX}-worker2" "${CLUSTER_PREFIX}-worker3"; do
  z="$(gcloud compute instances list --filter="name=${vm}" --format="value(zone.basename())")"
  test_ssh "$vm" "$z"
done

section "G. Repo layout on Cloud Shell (for step 2)"
for p in "$HOME/netpoke" "$HOME/netpoke/netpoke/infra/gcp" "$HOME/netpoke/slowpoke/scripts/setup/init_control.sh"; do
  if [[ -e "$p" ]]; then echo "  EXISTS: $p"; else echo "  MISSING: $p"; fi
done

if [[ "$AFTER_K8S" -eq 0 ]]; then
  section "H. Kubernetes"
  echo "Skipped (run ./preflight_cluster.sh --after-k8s after 02_initialize_cluster.sh)"
  section "DONE (pre-K8s)"
  echo "Report saved: $(pwd)/$REPORT"
  echo "If section F shows SSH OK for all nodes, proceed: ./02_initialize_cluster.sh"
  exit 0
fi

section "H. Kubernetes on control plane"
if [[ -z "$ctrl_zone" ]]; then
  echo "Control VM not found"
  exit 1
fi

K8S_CMD='
set -e
echo "--- hostname ---"
hostname
echo "--- kubectl version ---"
kubectl version 2>/dev/null || echo "kubectl not installed"
echo "--- kubectl get nodes -o wide ---"
kubectl get nodes -o wide 2>/dev/null || true
echo "--- expected node names ---"
echo "Need: control-plane (or control), loadgen, worker1, worker2, worker3 — all Ready"
echo "--- cluster info ---"
kubectl cluster-info 2>/dev/null || true
echo "--- slowpoke clone on control? ---"
ls -d ~/netpoke/slowpoke ~/slowpoke 2>/dev/null || echo "slowpoke not cloned on control yet"
'

gcloud compute ssh "$CONTROL" --zone "$ctrl_zone" --quiet --command "$K8S_CMD" || \
  echo "Could not SSH to control for kubectl checks"

section "DONE (post-K8s)"
echo "Report saved: $(pwd)/$REPORT"
echo ""
echo "SlowPoke smoke test (on control, after clone):"
echo "  cd slowpoke && export SLOWPOKE_TOP=\$(pwd) && cd evaluation && ./run_functional.sh"
