#!/bin/bash
# Phase 3 L2: checkout target + shipping netem sidecar (heavy I/O).
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
exec bash "$SLOWPOKE_TOP/evaluation/io_gap/run_io_medium.sh" boutique L2 "${1:-results/boutique_io_L2_medium.log}"
