#!/bin/bash
# cpu_procs.sh - per-process CPU on worker1 during ground-truth points p_t=800 and 400 (nothing frozen).
cd "$(dirname "$0")" && source ./lib.sh
mkdir -p ../../results/netpoke; OUT=../../results/netpoke/cpu_procs_$(date +%Y%m%d_%H%M).txt
for pt in 800 400; do
  ssh_run control "MODE=truth ~/kit/control/manual_point.sh yamls-orig $pt > /tmp/mp.log 2>&1" || { echo "deploy failed at p_t=$pt"; exit 1; }
  ssh_run control 'CL=$(kubectl get pod | awk "/ubuntu-client-/{print \$1}"); kubectl exec $CL -- /wrk/wrk -t8 -c512 --timeout 20s -d30s -L http://service1:80/' > /tmp/wrk_procs.txt 2>&1 &
  WP=$!
  sleep 8
  echo "===== p_t=$pt  (worker1, 15 s average) ====="
  ssh_run worker1 'top -b -n 2 -d 15 -w 250 -o %CPU | awk "/^top -/{n++} n==2" | head -25'
  wait $WP
  echo "wrk: $(awk '/Requests\/sec:/{print $2}' /tmp/wrk_procs.txt) req/s"
done | tee "$OUT"
ssh_run control 'kubectl delete -f ~/slowpoke/evaluation/mutex/yamls-orig --ignore-not-found >/dev/null'
echo "saved: $OUT"
