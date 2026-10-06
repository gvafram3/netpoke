#!/bin/bash
# One command: run the whole leak matrix on worker2 (about 3 minutes) and print + save a labelled table.
source "$(dirname "$0")/lib.sh"
OUTD="$REPO_ROOT/evaluation/results/netpoke"; mkdir -p "$OUTD"; RAW="$OUTD/leak_raw_$(date +%Y%m%d_%H%M).txt"
scp_to "$KIT/tests" worker2 '~/' >/dev/null || exit 1
ssh_run worker2 'cd ~/tests && sudo bash ./leak_suite.sh' | tee "$RAW"
echo; python3 "$KIT/tests/format_leak.py" "$RAW" --out "$OUTD"
