#!/bin/bash
# Are the 4 machines reachable, the right size, and able to talk to each other?
source "$(dirname "$0")/lib.sh"
declare -A PRIV; bad=0
printf '%-9s %-18s %-5s %-22s %s\n' NODE HOSTNAME vCPU OS KERNEL
for n in $NODES; do
  out=$(ssh_run "$n" 'echo "$(hostname)|$(nproc)|$(. /etc/os-release; echo $PRETTY_NAME)|$(uname -r)|$(hostname -I | cut -d" " -f1)"') || { echo "$n: CANNOT SSH"; bad=1; continue; }
  IFS='|' read -r h c o k p <<<"$out"; PRIV[$n]="$p"
  printf '%-9s %-18s %-5s %-22s %s\n' "$n" "$h" "$c" "$o" "$k"
  [ "$c" = 2 ] || echo "   WARNING: $n has $c vCPU (the paper's service nodes have 2)"
done
[ $bad -eq 0 ] || { echo "Fix SSH first (README section 4d)."; exit 1; }
echo; echo "Private-network test (needs the 'all traffic from the same security group' rule):"
for a in $NODES; do for b in $NODES; do [ "$a" = "$b" ] && continue
  if ssh_run "$a" "ping -c1 -W3 ${PRIV[$b]} >/dev/null 2>&1"; then :; else echo "  FAIL: $a cannot reach $b (${PRIV[$b]})"; bad=1; fi
done; done
[ $bad -eq 0 ] && echo "  all 12 directions OK" || { echo "Fix the security group (README section 3, step 4)."; exit 1; }
echo "[01] OK. Next: ./cluster/02_bootstrap_nodes.sh"
