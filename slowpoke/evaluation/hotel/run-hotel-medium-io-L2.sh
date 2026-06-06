#!/bin/bash
# Phase 3 L2: reservation target (heavier DB writes).
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
exec bash "$SLOWPOKE_TOP/evaluation/io_gap/run_io_medium.sh" hotel L2 "${1:-results/hotel_io_L2_medium.log}"
