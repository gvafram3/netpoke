#!/bin/bash
# Copy ~/results from the control node into evaluation/results/netpoke/ (kept separate from the paper's data in
# evaluation/netpoke/results/, so a new run never overwrites the published logs).
# Uses tar over ssh: newer OpenSSH scp refuses the remote path "~/results/." ("unexpected filename").
source "$(dirname "$0")/lib.sh"
DEST="$REPO_ROOT/evaluation/results/netpoke"; mkdir -p "$DEST"
if ssh_run control 'tar -czf - -C ~/results .' | tar -xzf - -C "$DEST"; then echo "copied into $DEST"
else echo "copy FAILED (is the control machine running, and is your IP allowed in the security group?)"; exit 1; fi
ls -la "$DEST" | tail -n 30
