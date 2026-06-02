#!/bin/bash
# Show why Kubernetes nodes are not all Ready.
#   cd netpoke/infra/gcp && ./diagnose_k8s.sh
set -u
cd "$(dirname "$0")"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck disable=SC1091
[[ -f "$SCRIPT_DIR/config.env" ]] && source "$SCRIPT_DIR/config.env"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/gcp_ssh_lib.sh" || { echo "ERROR: cannot load gcp_ssh_lib.sh"; exit 1; }

ENABLE_LOADGEN="${ENABLE_LOADGEN:-0}"

REPORT="$SCRIPT_DIR/k8s-diagnose-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee "$REPORT") 2>&1

echo "Kubernetes cluster diagnosis — $(date -u)"
echo ""

echo "======== 1. VM power state ========"
gcloud compute instances list --filter="tags.items=netpoke-cluster" \
  --format="table(name,zone.basename(),status,machineType.basename())"

echo ""
echo "======== 2. Nodes on control (kubectl get nodes) ========"
rrun "${CLUSTER_PREFIX}-control" "kubectl get nodes -o wide 2>/dev/null || echo NO_KUBECTL" || true

echo ""
echo "======== 3. Each worker: kubeadm + cri-docker ========"
WORKERS=("${CLUSTER_PREFIX}-worker1" "${CLUSTER_PREFIX}-worker2" "${CLUSTER_PREFIX}-worker3")

for vm in "${WORKERS[@]}"; do
  z="$(vm_zone "$vm")"
  echo "--- $vm (zone $z) ---"
  st="$(gcloud compute instances describe "$vm" --zone "$z" --format='get(status)' 2>/dev/null || echo MISSING)"
  echo "  VM status: $st"
  if [[ "$st" != "RUNNING" ]]; then
    echo "  >> Start: gcloud compute instances start $vm --zone=$z"
    continue
  fi
  rrun "$vm" 'echo -n "  kubeadm: "; command -v kubeadm >/dev/null && kubeadm version -o short || echo MISSING
echo -n "  cri-docker.sock: "; [[ -S /var/run/cri-dockerd.sock ]] && echo OK || echo MISSING
echo -n "  ip_forward: "; cat /proc/sys/net/ipv4/ip_forward
echo -n "  cri-docker: "; systemctl is-active cri-docker.service 2>/dev/null || echo inactive
echo -n "  kubelet: "; systemctl is-active kubelet 2>/dev/null || echo inactive' || echo "  SSH failed"
done

echo ""
echo "======== 4. Next step ========"
echo "  Need 4 nodes Ready: netpoke-control + worker1 + worker2 + worker3"
echo "  If kubeadm OK but not in kubectl list, run:"
echo "    ./repair_worker_join.sh"
echo ""
echo "Report: $REPORT"
