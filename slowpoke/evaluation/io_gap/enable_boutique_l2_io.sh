#!/usr/bin/env bash
# Swap shipping deployment to L2 I/O-heavy variant (netem sidecar on shipping pod).
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
IO_GAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
YAML_DIR="$SLOWPOKE_TOP/evaluation/boutique/yamls"
L2_SRC="$IO_GAP_DIR/shipping_io_l2.yaml"
STAMP="$YAML_DIR/.shipping_l2_active"

if [[ -f "$STAMP" ]]; then
  echo "[io_gap] boutique L2 shipping netem already enabled"
  exit 0
fi

if [[ ! -f "$L2_SRC" ]]; then
  echo "ERROR: missing $L2_SRC" >&2
  exit 1
fi

cp -a "$YAML_DIR/shipping.yaml" "$YAML_DIR/shipping.yaml.l0bak"
cp -a "$L2_SRC" "$YAML_DIR/shipping.yaml"
date -Is >"$STAMP"
echo "[io_gap] boutique L2: shipping.yaml → netem sidecar (50ms delay on eth0)"
