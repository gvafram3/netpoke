#!/bin/bash
# Phase 3 L1: search target (Mongo/Redis on hotel search path).
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
exec bash "$SLOWPOKE_TOP/evaluation/io_gap/run_io_medium.sh" hotel L1 "${1:-results/hotel_io_L1_medium.log}"
