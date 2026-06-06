#!/bin/bash
# Phase 3 L2: moviereviews target + reviewstorage 50ms + movieinfo 30ms netem.
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
exec bash "$SLOWPOKE_TOP/evaluation/io_gap/run_io_medium.sh" movie L2 "${1:-results/movie_io_L2_medium.log}"
