#!/bin/bash
# Control-node version of the in-pod leak measurement (survives PC disconnects when run in screen).
#   ctl_leak.sh <yamls-hold|yamls-freeze> [p_t=400] [seconds=20] [extra tag]
source ~/kit/control/ctl_lib.sh; ensure_hostshell || exit 1
ARM="${1:?}"; PT="${2:-400}"; SECS="${3:-20}"; EXTRA="${4:-}"; TAG="${ARM#yamls-}_pt${PT}${EXTRA:+_$EXTRA}"
OUT=~/results/inpod_leak; mkdir -p $OUT; R=$OUT/result_$TAG.txt; : > $R
say(){ echo "$*" | tee -a $R; }
say "===== in-pod leak: $ARM p_t=$PT ${SECS}s ${EXTRA:+[$EXTRA]} $(date '+%H:%M:%S')"
H "mkdir -p /root/netpoke_leak"   # own folder: files left in /tmp by other users cannot be overwritten, even by root (protected_regular)
HPUT /root/netpoke_leak/leak_by_uptime.py < ~/kit/tests/leak_by_uptime.py
~/kit/control/manual_point.sh $ARM $PT 2>&1 | grep -E "gate:|ERROR" | tee -a $R
P=$(kubectl get pod -o name | grep "^pod/service2-"); POD_IP=$(kubectl get $P -o jsonpath={.status.podIP}); NP=$(kubectl exec $P -- sh -c 'echo $SLOWPOKE_NETPOKE')
[ -n "$POD_IP" ] || { say "no service2 pod IP"; exit 1; }
say "  service2 ${P#pod/} ip $POD_IP SLOWPOKE_NETPOKE=$NP"
H "CID=\$(docker ps -q --filter name=k8s_service2_service2 | head -1); PID=\$(docker inspect -f '{{.State.Pid}}' \$CID)
IF=\$(ip -o -4 route show to default | awk '{print \$5}'); HIP=\$(hostname -I | cut -d' ' -f1)
rm -f /root/netpoke_leak/cap_pod.txt /root/netpoke_leak/cap_host.txt
python3 -c 'import time; print(repr(time.time()-time.clock_gettime(time.CLOCK_BOOTTIME)), repr(time.time()-time.clock_gettime(time.CLOCK_MONOTONIC)))' > /root/netpoke_leak/off.txt
setsid nohup timeout $((SECS+90)) nsenter -t \$PID -n tcpdump -n -tt -l -s 96 -i eth0 'src host $POD_IP and tcp' > /root/netpoke_leak/cap_pod.txt 2>/root/netpoke_leak/cap_pod.err < /dev/null &
setsid nohup timeout $((SECS+90)) tcpdump -q -n -tt -l -s 96 -i \$IF \"udp and (dst port 6784 or dst port 6783) and src host \$HIP\" > /root/netpoke_leak/cap_host.txt 2>/root/netpoke_leak/cap_host.err < /dev/null &
sleep 2; echo \"  captures running (pid \$PID, \$IF, \$HIP)\"" | tee -a $R
CL=$(kubectl get pod -o name | grep ubuntu-client | head -1)
kubectl exec $CL -- /wrk/wrk -t8 -c512 --timeout 20s -d${SECS}s http://service1:80/ 2>&1 | grep -E "requests in|Requests/sec" | sed 's/^/  /' | tee -a $R
kubectl logs $P | grep pause_ > $OUT/markers_$TAG.txt; HPUT /root/netpoke_leak/markers.txt < $OUT/markers_$TAG.txt
say "  markers: $(grep -c pause_start $OUT/markers_$TAG.txt) pauses; pod qdisc: $(kubectl exec $P -- tc -s qdisc show dev eth0 | head -2 | tr '\n' ' ' | tr -s ' ' | cut -c1-110)"
H "pkill -f 'tcpdump .*-tt -l -s 96' ; sleep 1; echo \"  captured: pod \$(wc -l < /root/netpoke_leak/cap_pod.txt), host \$(wc -l < /root/netpoke_leak/cap_host.txt) packets\"" | tee -a $R
H 'read OB OM < /root/netpoke_leak/off.txt
for w in "A pod eth0|/root/netpoke_leak/cap_pod.txt" "B host NIC (bottleneck)|/root/netpoke_leak/cap_host.txt"; do
  python3 /root/netpoke_leak/leak_by_uptime.py ${w##*|} /root/netpoke_leak/markers.txt $OB 2 "${w%%|*}" 2>&1 || python3 /root/netpoke_leak/leak_by_uptime.py ${w##*|} /root/netpoke_leak/markers.txt $OM 2 "${w%%|*}" 2>&1
done' | tee -a $R
a=$(grep -A2 "^A pod" $R | grep -o "LEAK = [0-9.na]*% of packets, [0-9.na]*% of bytes" | head -1); b=$(grep -A2 "^B host" $R | grep -o "LEAK = [0-9.na]*% of packets, [0-9.na]*% of bytes" | head -1)
say "SUMMARY $TAG | A pod: ${a#LEAK = } | B bottleneck: ${b#LEAK = }"
