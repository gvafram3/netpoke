#!/bin/bash
# GATE 0. If 'qdisc plug' says FAIL anywhere, STOP: NetPoke cannot run on this kernel.
set -uo pipefail
source "$(dirname "$0")/lib.sh"
mkdir -p "$KIT/logs"
for n in $NODES; do
  scp_to "$KIT/node/day0_check.sh" "$n" '~/day0_check.sh' >/dev/null
  ssh_run "$n" "bash ~/day0_check.sh" 2>&1 | tee "$KIT/logs/day0_$n.log"; echo
done
if grep -q "plug (THE key one) *FAIL" "$KIT"/logs/day0_*.log 2>/dev/null; then
  echo "[04] *** GATE 0 FAILED: sch_plug not available on this kernel. Try on the failing node:
        sudo apt-get install -y linux-modules-extra-\$(uname -r) && sudo modprobe sch_plug
        If that does not exist for the running kernel, NetPoke cannot run here."
  exit 2
fi
if grep -q "  plug .* FAIL" "$KIT"/logs/day0_*.log 2>/dev/null; then
  echo "[04] WARNING: a plug control verb FAILED (see '  plug ...' lines above). The qdisc exists but a verb net_hold needs may not work: run README section 9a before trusting the hold."
fi
echo "[04] GATE 0 PASSED. Next: ./cluster/05_sync_repo.sh"
