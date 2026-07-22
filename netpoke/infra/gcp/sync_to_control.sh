#!/usr/bin/env bash
# Run from Cloud Shell, from anywhere, after `git pull` in this checkout.
# Packs slowpoke/, sends it to netpoke-control, extracts it, and marks every
# script executable, in one command instead of four manual steps.
#
#   cd ~/netpoke/netpoke/infra/gcp
#   ./sync_to_control.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/config.env" ]] && source "$SCRIPT_DIR/config.env"

GCP_ZONE="${GCP_ZONE:-us-central1-a}"
CLUSTER_PREFIX="${CLUSTER_PREFIX:-netpoke}"
CONTROL="${CLUSTER_PREFIX}-control"

# Repo root is three levels up from netpoke/infra/gcp: gcp -> infra -> netpoke -> repo root,
# where slowpoke/ lives as a sibling of the inner netpoke/ directory.
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [[ ! -d "$REPO_ROOT/slowpoke" ]]; then
  echo "FATAL: expected $REPO_ROOT/slowpoke to exist, but it doesn't." >&2
  echo "This script assumes the netpoke/slowpoke layout; check REPO_ROOT above." >&2
  exit 1
fi

TARBALL="/tmp/slowpoke_sync_$(date +%s).tgz"

echo "==> Packing $REPO_ROOT/slowpoke ..."
tar czf "$TARBALL" -C "$REPO_ROOT" slowpoke/

echo "==> Sending to $CONTROL ($GCP_ZONE) ..."
gcloud compute scp --zone="$GCP_ZONE" "$TARBALL" "${CONTROL}:~/slowpoke_sync.tgz"

echo "==> Extracting and marking scripts executable on $CONTROL ..."
gcloud compute ssh "$CONTROL" --zone="$GCP_ZONE" --command="
  set -euo pipefail
  tar xzf ~/slowpoke_sync.tgz -C ~/
  chmod +x ~/slowpoke/evaluation/*.sh ~/slowpoke/evaluation/*/*.sh 2>/dev/null || true
  rm -f ~/slowpoke_sync.tgz
  echo SYNC_OK
"

rm -f "$TARBALL"
echo ""
echo "==> Sync complete. ~/slowpoke on $CONTROL now matches this checkout's slowpoke/ tree."
