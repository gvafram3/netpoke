#!/bin/bash
# Shared gcloud ssh helpers. Source from other scripts:
#   source "$(dirname "$0")/gcp_ssh_lib.sh"

# Allow: source gcp_ssh_lib.sh (from infra/gcp directory)

_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$_LIB_DIR/config.env" ]]; then
  # shellcheck disable=SC1091
  source "$_LIB_DIR/config.env"
fi
GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
CLUSTER_PREFIX="${CLUSTER_PREFIX:-netpoke}"
GCP_ZONE="${GCP_ZONE:-us-central1-a}"
GCP_REGION="${GCP_REGION:-${GCP_ZONE%-*}}"

gcloud config set project "$GCP_PROJECT" >/dev/null 2>&1 || true

vm_zone () {
  local vm="$1" override=""
  case "$vm" in
    "${CLUSTER_PREFIX}-control") override="${CONTROL_ZONE:-}" ;;
    "${CLUSTER_PREFIX}-loadgen") override="${LOADGEN_ZONE:-}" ;;
    "${CLUSTER_PREFIX}-worker1") override="${WORKER1_ZONE:-}" ;;
    "${CLUSTER_PREFIX}-worker2") override="${WORKER2_ZONE:-}" ;;
    "${CLUSTER_PREFIX}-worker3") override="${WORKER3_ZONE:-}" ;;
  esac
  if [[ -n "$override" ]]; then echo "$override"; return; fi
  local z
  z="$(gcloud compute instances list --filter="name=${vm}" --format="value(zone.basename())" 2>/dev/null | head -1)"
  [[ -n "$z" ]] && echo "$z" || echo "$GCP_ZONE"
}

vm_has_external_ip () {
  local ip
  ip="$(gcloud compute instances describe "$1" --zone "$(vm_zone "$1")" \
    --format='get(networkInterfaces[0].accessConfigs[0].natIP)' 2>/dev/null || true)"
  [[ -n "$ip" ]]
}

gcloud_remote_args () {
  local -n _out=$1 vm=$2
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

rrun () {
  local vm=$1 args=()
  shift
  gcloud_remote_args args "$vm"
  gcloud compute ssh "$vm" "${args[@]}" --command "$*"
}
