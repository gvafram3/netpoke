#!/usr/bin/env bash
# Patch evaluation YAMLs for NetPoke: NET_ADMIN, SLOWPOKE_NETPOKE=1, gvafram3 images.
#
#   export SLOWPOKE_TOP=~/slowpoke
#   cd ~/slowpoke/evaluation
#   bash phase5_netpoke/patch_all_netpoke_yamls.sh boutique
#   bash phase5_netpoke/patch_all_netpoke_yamls.sh all
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL="${SLOWPOKE_TOP:-$HOME/slowpoke}/evaluation"
BENCH="${1:-boutique}"

patch_bench() {
  local b="$1"
  local ydir="$EVAL/$b/yamls"
  local outdir="$EVAL/$b/yamls/netpoke"
  if [[ ! -d "$ydir" ]]; then
    echo "SKIP: no $ydir"
    return
  fi
  mkdir -p "$outdir"
  for src in "$ydir"/*.yaml; do
    [[ -f "$src" ]] || continue
    base=$(basename "$src")
    [[ "$base" == *.off ]] && continue
    dst="$outdir/$base"
    python3 "$SCRIPT_DIR/patch_netpoke_caps.py" "$src" "$dst" "$b"
    echo "  $dst"
  done
}

case "$BENCH" in
  boutique|social|hotel|movie) patch_bench "$BENCH" ;;
  all)
    for b in boutique social hotel movie; do
      echo "=== $b ==="
      patch_bench "$b"
    done
    ;;
  *)
    echo "usage: $0 {boutique|social|hotel|movie|all}"
    exit 1
    ;;
esac

echo ""
echo "Apply example: kubectl apply -f $EVAL/boutique/yamls/netpoke/"
