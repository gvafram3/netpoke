#!/bin/bash
# Join worker1-3 one by one (skips loadgen unless ENABLE_LOADGEN=1).
#
#   cd netpoke/infra/gcp
#   echo 'ENABLE_LOADGEN=0' >> config.env
#   gcloud compute instances start netpoke-control netpoke-worker1 netpoke-worker2 netpoke-worker3 --zone=us-central1-a
#   ./repair_worker_join.sh

set -euo pipefail
cd "$(dirname "$0")"

[[ -f config.env ]] || { echo "cp config.env.example config.env"; exit 1; }
# shellcheck disable=SC1091
source config.env
ENABLE_LOADGEN="${ENABLE_LOADGEN:-0}"

# shellcheck source=gcp_ssh_lib.sh
source "$(dirname "$0")/gcp_ssh_lib.sh"

REPO_ROOT="$(cd ../../.. && pwd)"
INIT_WORKER="${REPO_ROOT}/slowpoke/scripts/setup/init_worker.sh"
[[ -f "$INIT_WORKER" ]] || { echo "Missing $INIT_WORKER"; exit 1; }

CONTROL="${CLUSTER_PREFIX}-control"
WORKERS=("${CLUSTER_PREFIX}-worker1" "${CLUSTER_PREFIX}-worker2" "${CLUSTER_PREFIX}-worker3")

echo "==> Internet check"
if [[ -x ./fix_network_egress.sh ]]; then
  ./fix_network_egress.sh || { echo "Fix internet first"; exit 1; }
fi

echo "==> Control cluster"
rrun "$CONTROL" "kubectl get nodes -o wide"

JOIN_CMD="$(rrun "$CONTROL" "sudo kubeadm token create --print-join-command" | tr -d '\r')"
JOIN_SUFFIX="--cri-socket unix:///var/run/cri-dockerd.sock"

prepare_and_join () {
  local vm=$1 k8s_name=$2
  local z st
  z="$(vm_zone "$vm")"
  st="$(gcloud compute instances describe "$vm" --zone "$z" --format='get(status)' 2>/dev/null || true)"
  if [[ "$st" != "RUNNING" ]]; then
    echo "SKIP $vm (not RUNNING) — run: gcloud compute instances start $vm --zone=$z"
    return 1
  fi

  echo ""
  echo "======== $vm  ->  $k8s_name ========"
  rcopy "$INIT_WORKER" "$vm"
  echo "    [1/4] init_worker.sh ..."
  rrun "$vm" "export DEBIAN_FRONTEND=noninteractive; bash ~/init_worker.sh"

  echo "    [2/4] kubeadm reset (clean prior failed join) ..."
  rrun "$vm" "sudo kubeadm reset -f --cri-socket unix:///var/run/cri-dockerd.sock" || true

  echo "    [3/4] start CRI ..."
  rrun "$vm" "sudo swapoff -a; \
    sudo sysctl -w net.ipv4.ip_forward=1; \
    sudo systemctl enable docker cri-docker.socket cri-docker.service; \
    sudo systemctl restart docker; \
    sudo systemctl restart cri-docker.service; \
    sleep 8; test -S /var/run/cri-dockerd.sock"

  echo "    [4/4] kubeadm join ..."
  rrun "$vm" "sudo ${JOIN_CMD} ${JOIN_SUFFIX} --node-name ${k8s_name}"
  echo "    JOIN OK: $k8s_name"
}

FAIL=0
prepare_and_join "${WORKERS[0]}" "worker1" || FAIL=$((FAIL + 1))
prepare_and_join "${WORKERS[1]}" "worker2" || FAIL=$((FAIL + 1))
prepare_and_join "${WORKERS[2]}" "worker3" || FAIL=$((FAIL + 1))

if [[ "$ENABLE_LOADGEN" == "1" ]]; then
  prepare_and_join "${CLUSTER_PREFIX}-loadgen" "loadgen" || FAIL=$((FAIL + 1))
fi

echo ""
echo "==> Waiting 90s ..."
sleep 90
rrun "$CONTROL" "kubectl get nodes -o wide"

if [[ "$FAIL" -eq 0 ]]; then
  echo "Done. Expect: netpoke-control + worker1 + worker2 + worker3 all Ready."
  exit 0
fi
echo "$FAIL join(s) failed. Run ./diagnose_k8s.sh"
exit 1
