#!/usr/bin/env bash
# Build and optionally push NetPoke poker images to Docker Hub (gvafram3/mucache).
#
# On netpoke-control:
#   export SLOWPOKE_TOP=~/slowpoke
#   cd ~/slowpoke/evaluation
#   bash phase5_netpoke/build_netpoke_images.sh boutique
#   bash phase5_netpoke/build_netpoke_images.sh all
#   PUSH=1 bash phase5_netpoke/build_netpoke_images.sh all
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/images.env"

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
APP="$SLOWPOKE_TOP/app"
DOCKERFILE="$SLOWPOKE_TOP/scripts/build/PrebuiltDockerfile"
TARGET="${1:-boutique}"

if [[ ! -f "$DOCKERFILE" ]]; then
  echo "FAIL: missing $DOCKERFILE"
  exit 1
fi

cp -f "$SLOWPOKE_TOP/src/poker/"{poker.c,net_hold.c,net_hold.h} \
  "$APP/slowpoke/poker/"

build_one() {
  local bench="$1"
  local tag="${DOCKER_USER}/${DOCKER_REPO}:${bench}-pokerpp-netpoke"
  echo "=== build $tag ==="
  (cd "$APP" && sudo docker build --build-arg "BENCHMARK=$bench" \
    -f "$DOCKERFILE" -t "$tag" .)
  if [[ "${PUSH:-0}" == "1" ]]; then
    echo "=== push $tag ==="
    sudo docker push "$tag"
  fi
}

case "$TARGET" in
  boutique|social|hotel|movie) build_one "$TARGET" ;;
  all)
    for b in boutique social hotel movie; do
      build_one "$b"
    done
    ;;
  *)
    echo "usage: $0 {boutique|social|hotel|movie|all}"
    exit 1
    ;;
esac

echo ""
echo "Images tagged under ${DOCKER_USER}/${DOCKER_REPO}:*-pokerpp-netpoke"
if [[ "${PUSH:-0}" != "1" ]]; then
  echo "Push with: PUSH=1 $0 $TARGET"
  echo "Login first: sudo docker login"
fi
