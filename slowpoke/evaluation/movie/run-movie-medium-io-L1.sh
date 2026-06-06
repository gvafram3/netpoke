#!/bin/bash
# Phase 3 L1: moviereviews target + reviewstorage netem 30ms.
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
exec bash "$SLOWPOKE_TOP/evaluation/io_gap/run_io_medium.sh" movie L1 "${1:-results/movie_io_L1_medium.log}"
