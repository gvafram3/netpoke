#!/bin/bash
# Phase 3 L2: socialgraph target (graph store I/O).
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
exec bash "$SLOWPOKE_TOP/evaluation/io_gap/run_io_medium.sh" social L2 "${1:-results/social_io_L2_medium.log}"
