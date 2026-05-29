#!/bin/bash
set -e
cd "$(dirname "$0")/../.."
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$(pwd)}"
python3 src/main.py -b social -x frontend -r mix -t 8 -c 512 \
  --num_exp 1 --repetitions 1 --num_req 10000 \
  2>&1 | tee "$1"
