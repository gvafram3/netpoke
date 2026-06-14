#!/usr/bin/env bash
# Copy canonical poker sources from src/poker to app/slowpoke/poker (Docker build tree).
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DST="$(cd "$SRC/../../app/slowpoke/poker" && pwd)"

cp -f "$SRC/poker.c" "$SRC/net_hold.c" "$SRC/net_hold.h" "$DST/"
echo "Synced poker sources -> $DST"
