#!/bin/bash
# Phase 3 L1: checkout target (I/O on shipping/currency/payment path).
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
exec bash "$SLOWPOKE_TOP/evaluation/io_gap/run_io_medium.sh" boutique L1 "${1:-results/boutique_io_L1_medium.log}"
