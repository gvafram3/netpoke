#!/usr/bin/env bash
# Pull latest Phase 4 scripts from GitHub (netpoke/experiments) on netpoke-control.
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
DEST="$SLOWPOKE_TOP/evaluation/phase4_ebpf"
BASE="https://raw.githubusercontent.com/gvafram3/netpoke/netpoke/experiments/slowpoke/evaluation/phase4_ebpf"

mkdir -p "$DEST"
for f in residual_io_sampler.py summarize_ebpf_residual.py run_ebpf_smoke.sh \
         run_ebpf_one_L2.sh run_ebpf_all_L2.sh preflight_ebpf.sh; do
  echo "Fetching $f ..."
  curl -fsSL "$BASE/$f" -o "$DEST/$f"
done
chmod +x "$DEST"/*.sh "$DEST"/*.py
echo "OK: updated $DEST (includes sampler bugfix ae7effa+)"
