#!/bin/bash
# Direct test of the post-redeploy stall (run on the PC). After each redeploy it compares every service pod's REAL MAC with the MAC
# that the forwarding node has cached for that pod IP (neighbour table), makes one request, and - if the request fails - flushes the
# cached entries and retries immediately. A retry that then succeeds proves stale neighbour entries cause the stall.
#   usage: ./cluster/neigh_probe.sh [runs=6] [p_t=400]
source "$(dirname "$0")/lib.sh"
N="${1:-6}"; PT="${2:-400}"
req(){ ssh_run control 'kubectl exec $(kubectl get pod -o name | grep ubuntu-client) -- curl -s -o /dev/null -m 3 -w "%{http_code} connect=%{time_connect}s" http://service1:80/' 2>/dev/null | tr -d '\r' | tail -n1; }
for i in $(seq 1 "$N"); do
  ssh_run control "MODE=truth ~/kit/control/manual_point.sh yamls-freeze $PT >/dev/null 2>&1" || { echo "===== run $i: deploy failed"; continue; }
  info=$(ssh_run control 'for s in service1 service2; do P=$(kubectl get pod -o name | grep "^pod/$s-"); echo "$s $(kubectl get $P -o jsonpath={.status.podIP}) $(kubectl exec $P -- cat /sys/class/net/eth0/address)"; done' | tr -d '\r')
  ip1=$(echo "$info" | awk '$1=="service1"{print $2}'); mac1=$(echo "$info" | awk '$1=="service1"{print $3}')
  ip2=$(echo "$info" | awk '$1=="service2"{print $2}'); mac2=$(echo "$info" | awk '$1=="service2"{print $3}')
  n0=$(ssh_run worker0 "ip neigh show $ip1" | tr -d '\r' | tr '\n' ';'); n1=$(ssh_run worker1 "ip neigh show $ip2" | tr -d '\r' | tr '\n' ';')
  r=$(req)
  s0="MATCH"; echo "$n0" | grep -qi "$mac1" || s0="STALE/ABSENT"; s1="MATCH"; echo "$n1" | grep -qi "$mac2" || s1="STALE/ABSENT"
  echo "===== run $i   request: $r"
  echo "   service1 $ip1  real MAC $mac1   worker0 cache: ${n0:-none}   -> $s0"
  echo "   service2 $ip2  real MAC $mac2   worker1 cache: ${n1:-none}   -> $s1"
  if [[ "$r" != 200* ]]; then
    ssh_run worker0 "sudo ip neigh flush $ip1" >/dev/null 2>&1; ssh_run worker1 "sudo ip neigh flush $ip2" >/dev/null 2>&1
    echo "   after flushing both cached entries, retry: $(req)"
  fi
done
echo "===== neigh probe finished"
