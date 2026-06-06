#!/bin/bash
# Phase 3 L2: hometimeline target + poststorage 50ms + socialgraph 30ms netem.
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
exec bash "$SLOWPOKE_TOP/evaluation/io_gap/run_io_medium.sh" social L2 "${1:-results/social_io_L2_medium.log}"
