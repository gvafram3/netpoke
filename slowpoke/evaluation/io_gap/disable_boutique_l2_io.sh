#!/usr/bin/env bash
# Restore standard shipping.yaml after boutique L2 run.
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
YAML_DIR="$SLOWPOKE_TOP/evaluation/boutique/yamls"
STAMP="$YAML_DIR/.shipping_l2_active"

if [[ ! -f "$STAMP" ]]; then
  exit 0
fi

if [[ -f "$YAML_DIR/shipping.yaml.l0bak" ]]; then
  mv -f "$YAML_DIR/shipping.yaml.l0bak" "$YAML_DIR/shipping.yaml"
fi
rm -f "$STAMP"
echo "[io_gap] boutique L2: restored standard shipping.yaml"
