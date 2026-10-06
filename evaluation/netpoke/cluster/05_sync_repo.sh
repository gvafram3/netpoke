#!/bin/bash
# Copies this repository (as ~/slowpoke) and the NetPoke harness (control/, tests/ as ~/kit) to the control node.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
[ -f "$REPO_ROOT/src/main.py" ] || { echo "ERROR: $REPO_ROOT/src/main.py not found. Run this from a checkout of the NetPoke repository."; exit 1; }
COMMIT=$(git -C "$REPO_ROOT" rev-parse HEAD 2>/dev/null || echo unknown); DIRTY=$(git -C "$REPO_ROOT" status --porcelain 2>/dev/null | wc -l)
echo "[05] repo commit $COMMIT (uncommitted changes: $DIRTY)"
NAME="$(basename "$REPO_ROOT")"
tar -C "$(dirname "$REPO_ROOT")" --exclude=.git --exclude="$NAME/evaluation/results" --exclude="$NAME/evaluation/netpoke/results" \
    --transform "s,^$NAME,slowpoke," -czf /tmp/slowpoke.tgz "$NAME"
scp_to /tmp/slowpoke.tgz control '~/slowpoke.tgz' >/dev/null
ssh_run control "rm -rf ~/slowpoke ~/kit && tar -xzf ~/slowpoke.tgz -C ~ && mkdir -p ~/results ~/kit && echo $COMMIT > ~/results/COMMIT.txt"
for d in control tests; do scp_to "$KIT/$d" control '~/kit/' >/dev/null; done
ssh_run control "chmod +x ~/kit/control/*.sh ~/slowpoke/slowpoke ~/slowpoke/src/run.sh 2>/dev/null; ls ~/slowpoke | head -20; test -f ~/slowpoke/src/main.py && echo SYNC_OK"
