#!/bin/bash
# NetPoke GCP cluster: STEP 2 of 2 -- install Kubernetes and form the cluster.
#
# This reuses SlowPoke's own setup scripts (slowpoke/scripts/setup/init_control.sh
# and init_worker.sh), which install Docker, cri-dockerd, kubeadm (v1.29), the
# Weave network plugin, Istio, and supporting tools. It then joins every worker
# to the control plane with stable node names.
#
# Node names produced:
#   control-plane   (the control node, runs no services by default)
#   loadgen         (dedicated workload-generator node, runs the wrk client)
#   worker1..workerN(service nodes, matching the benchmark YAML node affinity)
#
# Usage (run AFTER 01_create_cluster.sh and a ~60s boot wait):
#   cd netpoke/infra/gcp
#   ./02_initialize_cluster.sh
#
# If control is already Ready but workers never joined (no internet earlier):
#   ./fix_network_egress.sh
#   ./02_initialize_cluster.sh --workers-only

set -euo pipefail
cd "$(dirname "$0")"

WORKERS_ONLY=0
[[ "${1:-}" == "--workers-only" ]] && WORKERS_ONLY=1

if [[ ! -f config.env ]]; then
  echo "ERROR: config.env not found. Run:  cp config.env.example config.env"
  exit 1
fi
# shellcheck disable=SC1091
source config.env
GCP_REGION="${GCP_REGION:-${GCP_ZONE%-*}}"

REPO_ROOT="$(cd ../../.. && pwd)"
SETUP_DIR="${REPO_ROOT}/slowpoke/scripts/setup"
INIT_CONTROL="${SETUP_DIR}/init_control.sh"
INIT_WORKER="${SETUP_DIR}/init_worker.sh"

for f in "$INIT_CONTROL" "$INIT_WORKER"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f (is the slowpoke/ folder present?)"; exit 1; }
done

gcloud config set project "$GCP_PROJECT" >/dev/null

# VMs must reach the internet to apt-install Docker/kubeadm. See fix_network_egress.sh.
if [[ "${SKIP_NETWORK_FIX:-0}" != "1" ]] && [[ -x "./fix_network_egress.sh" ]]; then
  echo "==> Checking outbound internet (Cloud NAT + apt IPv4) ..."
  ./fix_network_egress.sh
fi

CONTROL="${CLUSTER_PREFIX}-control"
LOADGEN="${CLUSTER_PREFIX}-loadgen"
WORKERS=()
for i in $(seq 1 "$NUM_WORKERS"); do WORKERS+=("${CLUSTER_PREFIX}-worker${i}"); done

# Resolve zone per VM (config override, else GCP_ZONE, else discover from GCP).
vm_zone () {
  local vm="$1"
  local var override=""
  case "$vm" in
    "${CLUSTER_PREFIX}-control") override="${CONTROL_ZONE:-}" ;;
    "${CLUSTER_PREFIX}-loadgen") override="${LOADGEN_ZONE:-}" ;;
    "${CLUSTER_PREFIX}-worker1") override="${WORKER1_ZONE:-}" ;;
    "${CLUSTER_PREFIX}-worker2") override="${WORKER2_ZONE:-}" ;;
    "${CLUSTER_PREFIX}-worker3") override="${WORKER3_ZONE:-}" ;;
    "${CLUSTER_PREFIX}-worker4") override="${WORKER4_ZONE:-}" ;;
  esac
  if [[ -n "$override" ]]; then
    echo "$override"
    return
  fi
  local z
  z="$(gcloud compute instances list --filter="name=${vm}" --format="value(zone.basename())" 2>/dev/null | head -1)"
  if [[ -n "$z" ]]; then
    echo "$z"
  else
    echo "$GCP_ZONE"
  fi
}

vm_has_external_ip () {
  local vm="$1" z ip
  z="$(vm_zone "$vm")"
  ip="$(gcloud compute instances describe "$vm" --zone "$z" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || true)"
  [[ -n "$ip" ]]
}

# Build gcloud ssh/scp args; use IAP when the VM has no public IP (common on
# free-tier projects with IN_USE_ADDRESSES quota of 4).
gcloud_remote_args () {
  local -n _out=$1
  local vm=$2
  _out=(--zone "$(vm_zone "$vm")" --quiet)
  if ! vm_has_external_ip "$vm"; then
    _out+=(--tunnel-through-iap)
  fi
}

rcopy () {
  local src=$1 vm=$2 args=()
  gcloud_remote_args args "$vm"
  gcloud compute scp "${args[@]}" "$src" "$vm:~/"
}
rrun  () {
  local vm=$1 args=()
  shift
  gcloud_remote_args args "$vm"
  gcloud compute ssh "$vm" "${args[@]}" --command "$*"
}

if [[ "$WORKERS_ONLY" -eq 0 ]]; then
  echo "==> [1/5] Initialising the control plane ($CONTROL). This takes several minutes."
  rcopy "$INIT_CONTROL" "$CONTROL"
  rrun  "$CONTROL" "bash ~/init_control.sh"
else
  echo "==> [1/5] Skipping control init (--workers-only). Current nodes:"
  rrun "$CONTROL" "kubectl get nodes -o wide || true"
fi

echo "==> [2/5] Installing Kubernetes on loadgen and worker nodes (in parallel)."
for node in "$LOADGEN" "${WORKERS[@]}"; do
  rcopy "$INIT_WORKER" "$node"
  rrun  "$node" "bash ~/init_worker.sh" &
done
wait
echo "    worker installation complete."

echo "==> [3/5] Generating the cluster join command."
JOIN_CMD="$(rrun "$CONTROL" "sudo kubeadm token create --print-join-command" | tr -d '\r')"
JOIN_SUFFIX="--cri-socket unix:///var/run/cri-dockerd.sock"

join_node () {
  local node="$1" nodename="$2"
  echo "    joining $node as kubernetes node '$nodename'"
  rrun "$node" "sudo swapoff -a; sudo ${JOIN_CMD} ${JOIN_SUFFIX} --node-name ${nodename}"
}

echo "==> [4/5] Joining nodes to the cluster."
join_node "$LOADGEN" "loadgen"
idx=1
for node in "${WORKERS[@]}"; do
  join_node "$node" "worker${idx}"
  idx=$((idx+1))
done

echo "==> [5/5] Labelling nodes and showing cluster state."
rrun "$CONTROL" "kubectl label node loadgen netpoke-role=loadgen --overwrite || true"
idx=1
for _ in "${WORKERS[@]}"; do
  rrun "$CONTROL" "kubectl label node worker${idx} netpoke-role=worker --overwrite || true"
  idx=$((idx+1))
done

echo ""
echo "==> Cluster nodes (allow a minute for all to become Ready):"
rrun "$CONTROL" "kubectl get nodes -o wide"

echo ""
echo "Done. To work on the cluster, SSH into the control node:"
echo "    gcloud compute ssh ${CONTROL} --zone $(vm_zone ${CONTROL})"
echo ""
echo "When finished with this batch of experiments, delete everything with:"
echo "    ./03_teardown.sh"
