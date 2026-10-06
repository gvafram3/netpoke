#!/bin/bash
# DNS probe (fast, like the one that failed): after each redeploy, make one request FIRST, then check whether the name 'service1'
# (as the client sees it) and 'service2' (as the service1 pod sees it) still resolve to an OLD, deleted Service address.
# A failed request is retried against the CURRENT service1 address directly (no DNS), and service1's pending connection attempts
# (SYN_SENT) are listed, to see where service1 itself is trying to connect.
#   usage: dns_probe.sh [N=10] [p_t=400] [yamls-dir=yamls-freeze]
N="${1:-10}"; PT="${2:-400}"; YD="${3:-yamls-freeze}"
echo "CoreDNS cache setting: $(kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}' | grep -o 'cache [0-9]*' | head -1)"
echo "Services at start: service1=$(kubectl get svc service1 -o jsonpath={.spec.clusterIP} 2>/dev/null) service2=$(kubectl get svc service2 -o jsonpath={.spec.clusterIP} 2>/dev/null)"
for i in $(seq 1 "$N"); do
  MODE=truth ~/kit/control/manual_point.sh "$YD" "$PT" > /tmp/probe_deploy.log 2>&1 || { echo "===== run $i: DEPLOY FAILED"; continue; }
  CL=$(kubectl get pod -o name | grep ubuntu-client | head -1); S1=$(kubectl get pod -o name | grep '^pod/service1-')
  r=$(kubectl exec $CL -- curl -s -o /dev/null -m 3 -w "%{http_code} connect=%{time_connect}s" http://service1:80/ 2>/dev/null)
  c1=$(kubectl get svc service1 -o jsonpath={.spec.clusterIP}); c2=$(kubectl get svc service2 -o jsonpath={.spec.clusterIP})
  d1=$(kubectl exec $CL -- getent hosts service1 2>/dev/null | awk '{print $1}' | head -1)
  d2=$(kubectl exec $S1 -- nslookup service2 2>/dev/null | awk '/^Address/{a=$NF} END{print a}')
  v1="ok"; [ "$d1" = "$c1" ] || v1="OLD ADDRESS"; v2="ok"; [ -z "$d2" ] && v2="n/a (no nslookup)"; [ -n "$d2" ] && [ "$d2" != "$c2" ] && v2="OLD ADDRESS"
  echo "===== run $i  request: $r"
  echo "   service1 is now $c1 | client resolves 'service1' -> ${d1:-?}  [$v1]"
  echo "   service2 is now $c2 | service1 pod resolves 'service2' -> ${d2:-?}  [$v2]"
  if [[ "$r" != 200* ]]; then
    echo "   retry straight to $c1 (no DNS): $(kubectl exec $CL -- curl -s -o /dev/null -m 3 -w "%{http_code} connect=%{time_connect}s" http://$c1:80/ 2>/dev/null)"
    echo "   service1's pending connection attempts: $(kubectl exec $S1 -- cat /proc/net/tcp 2>/dev/null | python3 ~/kit/control/syn_sent.py)   (service2 is now $c2)"
  fi
done
echo "===== dns probe finished"
