#!/bin/bash
# Phase 3 L1: poststorage target (sync state I/O).
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
exec bash "$SLOWPOKE_TOP/evaluation/io_gap/run_io_medium.sh" social L1 "${1:-results/social_io_L1_medium.log}"
