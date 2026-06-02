#!/bin/bash
# Show why Kubernetes nodes are not all Ready. Run from Cloud Shell:
#   cd netpoke/infra/gcp && ./diagnose_k8s.sh
set -euo pipefail
cd "$(dirname "$0")"
[[ -f config.env ]] && source config.env
GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project)}"
CLUSTER_PREFIX="${CLUSTER_PREFIX:-netpoke}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
ENABLE_LOADGEN="${ENABLE_LOADGEN:-1}"

ssh_vm () {
  rrun "$1" "$2" 2>&1 || true
}

REPORT="k8s-diagnose-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$REPORT") 2>&1

echo "Kubernetes cluster diagnosis — $(date -u)"
echo ""

echo "======== 1. VM power state ========"
gcloud compute instances list --filter="tags.items=netpoke-cluster" \
  --format="table(name,zone.basename(),status,machineType.basename())"

echo ""
echo "======== 2. Nodes registered on control ========"
ssh_vm "${CLUSTER_PREFIX}-control" "kubectl get nodes -o wide 2>/dev/null || echo NO_KUBECTL"

echo ""
echo "======== 3. Per-worker checks (need kubeadm + cri-docker socket) ========"
WORKERS=("${CLUSTER_PREFIX}-worker1" "${CLUSTER_PREFIX}-worker2" "${CLUSTER_PREFIX}-worker3")
[[ "$ENABLE_LOADGEN" == "1" ]] && WORKERS=("${CLUSTER_PREFIX}-loadgen" "${WORKERS[@]}")

for vm in "${WORKERS[@]}"; do
  z="$(vm_zone "$vm")"
  echo "--- $vm (zone $z) ---"
  st="$(gcloud compute instances describe "$vm" --zone "$z" --format='get(status)' 2>/dev/null || echo MISSING)"
  echo "  VM status: $st"
  [[ "$st" != "RUNNING" ]] && echo "  >> START THIS VM FIRST" && continue
  ssh_vm "$vm" '
    echo -n "  kubeadm: "; command -v kubeadm >/dev/null && kubeadm version -o short || echo MISSING
    echo -n "  cri-docker.sock: "; [[ -S /var/run/cri-dockerd.sock ]] && echo OK || echo MISSING
    echo -n "  ip_forward: "; cat /proc/sys/net/ipv4/ip_forward
    echo -n "  cri-docker: "; systemctl is-active cri-docker.service 2>/dev/null || echo inactive
    echo -n "  kubelet: "; systemctl is-active kubelet 2>/dev/null || echo inactive
  '
done

echo ""
echo "======== 4. What you need ========"
echo "  Goal: 4 nodes Ready (control + worker1 + worker2 + worker3)"
echo "  loadgen: optional (ENABLE_LOADGEN=0 is OK)"
echo ""
echo "  If workers show kubeadm OK but not in kubectl get nodes:"
echo "    ./repair_worker_join.sh"
echo ""
echo "Report saved: $(pwd)/$REPORT"
