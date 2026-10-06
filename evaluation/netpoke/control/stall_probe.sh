#!/bin/bash
# Direct probe of the intermittent stall: redeploy N times; after each deploy, BEFORE any load, record
#   - whether one request through service1:80 succeeds
#   - the state of every process in each service pod (S = sleeping/normal, R = running, T = STOPPED by a signal)
#   - which qdisc sits on each service pod's eth0 (a plug here would mean the network hold is installed)
#   - any net_hold / plug / netlink lines, and the last poker pause markers, in the service logs
#   usage: stall_probe.sh [N=10] [p_t=400] [yamls-dir=yamls-freeze]
N="${1:-10}"; PT="${2:-400}"; YD="${3:-yamls-freeze}"
for i in $(seq 1 "$N"); do
  MODE=truth ~/kit/control/manual_point.sh "$YD" "$PT" > /tmp/probe_deploy.log 2>&1 || { echo "===== run $i: DEPLOY FAILED"; tail -3 /tmp/probe_deploy.log; continue; }
  CL=$(kubectl get pod -o name | grep ubuntu-client | head -1)
  r=$(kubectl exec $CL -- curl -s -o /dev/null -m 3 -w "%{http_code} connect=%{time_connect}s total=%{time_total}s" http://service1:80/ 2>&1)
  echo "===== run $i   one request: $r"
  for S in $(kubectl get pod -o name | grep -E "service[12]-"); do
    echo "  $S processes: $(kubectl exec $S -- sh -c 'for p in /proc/[0-9]*; do read a b c rest < $p/stat 2>/dev/null && echo "$a$b=$c"; done' 2>&1 | tr '\n' ' ')"
    echo "  $S qdisc: $(kubectl exec $S -- tc -s qdisc show dev eth0 2>&1 | tr '\n' ' ' | tr -s ' ' | cut -c1-160)"
    echo "  $S log:   $(kubectl logs $S 2>&1 | grep -iE 'net_hold|plug|netlink|netpoke|pause_' | tail -3 | tr '\n' '|')"
  done
done
echo "===== probe finished"
