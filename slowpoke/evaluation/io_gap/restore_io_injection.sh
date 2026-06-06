#!/usr/bin/env bash
# Restore yamls after apply_io_injection.sh (also replaces legacy boutique L2 restore).
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
IO_GAP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$IO_GAP/.io_injection_active"

# Legacy boutique-only stamp
YAML_DIR="$SLOWPOKE_TOP/evaluation/boutique/yamls"
if [[ -f "$YAML_DIR/.shipping_l2_active" ]]; then
  if [[ -f "$YAML_DIR/shipping.yaml.l0bak" ]]; then
    mv -f "$YAML_DIR/shipping.yaml.l0bak" "$YAML_DIR/shipping.yaml"
  fi
  rm -f "$YAML_DIR/.shipping_l2_active"
  echo "[io_gap] restored legacy boutique shipping.yaml"
fi

[[ -f "$STAMP" ]] || exit 0

while IFS='|' read -r rel bak; do
  [[ "$rel" == *"|"* ]] && continue
  [[ -z "$rel" || -z "$bak" ]] && continue
  if [[ -f "$bak" ]]; then
    mv -f "$bak" "$SLOWPOKE_TOP/evaluation/$rel"
    echo "[io_gap] restored $rel"
  fi
done < <(grep '|' "$STAMP" || true)

rm -f "$STAMP"
echo "[io_gap] io injection restore complete"
