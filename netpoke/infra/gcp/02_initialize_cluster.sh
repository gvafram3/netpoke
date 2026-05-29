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

set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f config.env ]]; then
  echo "ERROR: config.env not found. Run:  cp config.env.example config.env"
  exit 1
fi
# shellcheck disable=SC1091
source config.env

REPO_ROOT="$(cd ../../.. && pwd)"
SETUP_DIR="${REPO_ROOT}/slowpoke/scripts/setup"
INIT_CONTROL="${SETUP_DIR}/init_control.sh"
INIT_WORKER="${SETUP_DIR}/init_worker.sh"

for f in "$INIT_CONTROL" "$INIT_WORKER"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f (is the slowpoke/ folder present?)"; exit 1; }
done

gcloud config set project "$GCP_PROJECT" >/dev/null

CONTROL="${CLUSTER_PREFIX}-control"
LOADGEN="${CLUSTER_PREFIX}-loadgen"
WORKERS=()
for i in $(seq 1 "$NUM_WORKERS"); do WORKERS+=("${CLUSTER_PREFIX}-worker${i}"); done

# Helper wrappers around gcloud ssh/scp so the rest of the script stays readable.
rcopy () { gcloud compute scp --zone "$GCP_ZONE" --quiet "$1" "$2:~/" ; }
rrun  () { gcloud compute ssh "$1" --zone "$GCP_ZONE" --quiet --command "$2" ; }

echo "==> [1/5] Initialising the control plane ($CONTROL). This takes several minutes."
rcopy "$INIT_CONTROL" "$CONTROL"
rrun  "$CONTROL" "bash ~/init_control.sh"

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
echo "    gcloud compute ssh ${CONTROL} --zone ${GCP_ZONE}"
echo ""
echo "When finished with this batch of experiments, delete everything with:"
echo "    ./03_teardown.sh"
