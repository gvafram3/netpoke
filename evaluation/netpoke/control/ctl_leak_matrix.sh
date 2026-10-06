#!/bin/bash
# Queue-depth experiment: for each bottleneck queue, measure ground-truth throughput (800, 400 us) and the in-pod leak
# with the hold ON and OFF. Runs entirely on the control node. Start it detached:
#   screen -dmS matrix bash -lc "~/kit/control/ctl_leak_matrix.sh > ~/results/leak_matrix.txt 2>&1"
source ~/kit/control/ctl_lib.sh; ensure_hostshell || exit 1
echo "===== queue-depth leak matrix $(date '+%Y-%m-%d %H:%M')"
for leaf in "fq_codel" "pfifo limit 20" "pfifo limit 5"; do
  tag=$(echo "$leaf" | sed 's/ limit //; s/ //g')
  echo; echo "########## bottleneck queue: $leaf"
  ~/kit/control/ctl_netcap.sh 175 $leaf || { echo "cap failed - skipping $leaf"; continue; }
  [ -n "${SKIP_TPUT:-}" ] || SECS=20 ~/kit/control/quick_tput.sh yamls-freeze 800 400 2>&1 | grep -E "^(800|400) "
  for arm in yamls-hold yamls-freeze; do ~/kit/control/ctl_leak.sh $arm 400 20 $tag; done
done
~/kit/control/ctl_netcap.sh 175 fq_codel >/dev/null; echo; echo "(cap restored to 175 Mbit/s fq_codel)"
echo; echo "===== SUMMARY"; grep -h "^SUMMARY" ~/results/inpod_leak/result_*_pt400_*.txt | sort
echo "===== matrix finished $(date '+%H:%M')"
