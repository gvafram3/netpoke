#!/bin/bash
# cpu_split.sh - worker1 CPU per request at ground-truth points (nothing frozen), mutex benchmark.
# Deploys p_t = 800, 400, 800 with MODE=truth (spin p_t, no delay), runs wrk 30 s, samples worker1's
# /proc/stat between seconds ~8 and ~23 of the run. Run from your local machine: ./cpu_split.sh
cd "$(dirname "$0")" && source ./lib.sh
mkdir -p ../../results/netpoke; OUT=../../results/netpoke/cpu_split_$(date +%Y%m%d_%H%M).txt
snap(){ ssh_run worker1 'echo $(date +%s.%N) $(head -1 /proc/stat)'; }
for pt in 800 400 800; do
  ssh_run control "MODE=truth ~/kit/control/manual_point.sh yamls-orig $pt > /tmp/mp.log 2>&1" || { echo "deploy failed at p_t=$pt"; exit 1; }
  ssh_run control 'CL=$(kubectl get pod | awk "/ubuntu-client-/{print \$1}"); kubectl exec $CL -- /wrk/wrk -t8 -c512 --timeout 20s -d30s -L http://service1:80/' > /tmp/wrk_cpu.txt 2>&1 &
  WP=$!
  sleep 8; A=$(snap); sleep 15; B=$(snap); wait $WP
  RPS=$(awk '/Requests\/sec:/{print $2}' /tmp/wrk_cpu.txt)
  echo "$A $B" | awk -v pt=$pt -v r="$RPS" '{dt=$13-$1; u=($15+$16)-($3+$4); sy=$17-$5; id=($18+$19)-($6+$7); irq=$20-$8; si=$21-$9; st=$22-$10; tot=u+sy+id+irq+si+st; k=10000/(r*dt);
    printf "p_t=%s req/s=%.1f busy%%=%.1f steal%%=%.1f | per-request us: user=%.1f system=%.1f irq+softirq=%.1f steal=%.1f total=%.1f\n", pt, r, 100*(u+sy+irq+si)/tot, 100*st/tot, u*k, sy*k, (irq+si)*k, st*k, (u+sy+irq+si+st)*k}'
  echo "   raw: $A | $B"
done | tee "$OUT"
ssh_run control 'kubectl delete -f ~/slowpoke/evaluation/mutex/yamls-orig --ignore-not-found >/dev/null'
echo "saved: $OUT"
