#!/bin/bash
# Phase 3 L2: profile target + rate 50ms + user 30ms netem.
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
exec bash "$SLOWPOKE_TOP/evaluation/io_gap/run_io_medium.sh" hotel L2 "${1:-results/hotel_io_L2_medium.log}"
