#!/usr/bin/env bash
# Compile POKER + NetPoke net_hold helper (Linux only).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

OUT="${1:-./poker}"
gcc poker.c net_hold.c -O2 -Wall -Wextra -o "$OUT"
echo "Built $OUT"
