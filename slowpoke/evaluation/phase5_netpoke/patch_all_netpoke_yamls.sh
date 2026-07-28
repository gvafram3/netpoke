#!/usr/bin/env bash
# Patch evaluation YAMLs for NetPoke variants:
#   yamls/netpoke/          — gvafram3 image, NET_ADMIN, SLOWPOKE_NETPOKE=1 (egress hold ON)
#   yamls/netpoke-sigstop/  — gvafram3 image, NET_ADMIN, SLOWPOKE_NETPOKE=0 (egress hold OFF)
#
# Both directories must exist before running any experiment. The netpoke-sigstop/
# variant is required for the SIGSTOP-only baseline runs (runs 1 and 3 in the
# experiment runbook) so they deploy the same instrumented image as the NetPoke-on
# runs — without it, run.sh silently falls back to the plain yizhengx images which
# lack the pause-window markers poker.c emits.
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
  local outdir_sigstop="$EVAL/$b/yamls/netpoke-sigstop"
  if [[ ! -d "$ydir" ]]; then
    echo "SKIP: no $ydir"
    return
  fi
  mkdir -p "$outdir" "$outdir_sigstop"
  for src in "$ydir"/*.yaml; do
    [[ -f "$src" ]] || continue
    base=$(basename "$src")
    [[ "$base" == *.off ]] && continue
    # nginx.yaml (and similar) are comment-only stubs — skip without aborting the bench.
    if ! grep -q 'kind: Deployment' "$src" 2>/dev/null; then
      echo "  SKIP $base (no Deployment)"
      continue
    fi
    if ! python3 "$SCRIPT_DIR/patch_netpoke_caps.py" "$src" "$outdir/$base" "$b"; then
      echo "  SKIP $base (patch failed)" >&2
      continue
    fi
    if ! python3 "$SCRIPT_DIR/patch_netpoke_caps.py" "$src" "$outdir_sigstop/$base" "$b" --sigstop; then
      echo "  SKIP $base sigstop (patch failed)" >&2
      continue
    fi
    echo "  $outdir/$base"
    echo "  $outdir_sigstop/$base"
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
echo "netpoke/       (SLOWPOKE_NETPOKE=1): kubectl apply -f $EVAL/boutique/yamls/netpoke/"
echo "netpoke-sigstop/ (SLOWPOKE_NETPOKE=0): kubectl apply -f $EVAL/boutique/yamls/netpoke-sigstop/"
