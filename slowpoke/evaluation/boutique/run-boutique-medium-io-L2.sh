#!/bin/bash
# Phase 3 L2: cart target + product_catalog 50ms + currency 30ms netem.
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
exec bash "$SLOWPOKE_TOP/evaluation/io_gap/run_io_medium.sh" boutique L2 "${1:-results/boutique_io_L2_medium.log}"
