#!/bin/bash
# FIRST-CONTACT SCRIPT (read before running): deploy ONE slowdown point of the mutex benchmark and LEAVE IT
# RUNNING, so the pod keeps a stable IP while you capture packets (Phase 3 / Phase 5 leak check).
#   manual_point.sh <yamls-dir> <target_processing_us>      e.g.  manual_point.sh yamls-freeze 400
# It sets the same variables src/main.py sets for one slowdown experiment (formula copied from main.py):
#   delay(service2) = (800 - p_t) * quota2 / quota1 = 800 - p_t ;  SLOWPOKE_DELAY_MICROS_SERVICE2 = delay / quota2
set -uo pipefail
YDIR="${1:?yamls-freeze|yamls-hold|yamls-orig}"; PT="${2:-400}"
TOP="$HOME/slowpoke"; EVAL="$TOP/evaluation/mutex"; [ -d "$EVAL/$YDIR" ] || { echo "no $EVAL/$YDIR"; exit 1; }
export SLOWPOKE_TOP="$TOP"
export SPIN_TIME_SERVICE1="$PT" SPIN_TIME_SERVICE2=350
export SLOWPOKE_DELAY_MICROS_SERVICE1=0
if [ "${MODE:-slowdown}" = truth ]; then export SLOWPOKE_DELAY_MICROS_SERVICE2=0; else export SPIN_TIME_SERVICE1=800; export SLOWPOKE_DELAY_MICROS_SERVICE2=$(( (800 - PT) / 2 )); fi   # MODE=truth: really optimised, nothing frozen
export SLOWPOKE_POKER_BATCH_THRESHOLD=20000000 SLOWPOKE_POKER_BATCH_THRESHOLD_SERVICE1=100 SLOWPOKE_POKER_BATCH_THRESHOLD_SERVICE2=100
export SLOWPOKE_PRERUN="" SLOWPOKE_PROCESSING_MICROS_SERVICE1="" SLOWPOKE_PROCESSING_MICROS_SERVICE2="" SLOWPOKE_MUTEX_IS_LOCKED=""
export CLIENT_CPU_QUOTA=2
# Delete only the Deployments. Deleting the Services too gives them NEW ClusterIPs on every redeploy, and CoreDNS (cache 30) then
# briefly hands out the OLD address: requests hang (measured: 6/10 fast redeploys failed). Keeping the Services keeps the address fixed.
kubectl delete deployment service1 service2 --ignore-not-found >/dev/null 2>&1
while [ "$(kubectl get pods --no-headers 2>/dev/null | grep -vc ubuntu-client)" -ne 0 ]; do sleep 1; done
for f in "$EVAL/$YDIR"/*.yaml; do envsubst < "$f" | kubectl apply -f -; done
kubectl get pod | grep -q ubuntu-client- || envsubst < "$TOP/client/client.yaml" | kubectl apply -f -
echo "waiting for pods..."; while [ "$(kubectl get pods --no-headers | grep -vc ' 1/1 .*Running')" -ne 0 ]; do sleep 2; done
for s in service1 service2; do kubectl get pods --no-headers | grep -q "^$s-.* 1/1 .*Running" || { echo "ERROR: $s pod is not running (see the 'kubectl apply' errors above)"; exit 1; }; done
# Gate: wait until one request through service1:80 succeeds before declaring READY. Right after a fresh deploy the very first
# connection occasionally fails for a few seconds (measured 1/10 even with fixed Service addresses). Logs how many tries it took.
CLG=$(kubectl get pod -o name | grep ubuntu-client | head -1)
if [ -n "$CLG" ]; then
  for t in $(seq 1 30); do
    code=$(kubectl exec $CLG -- curl -s -o /dev/null -m 2 -w "%{http_code}" http://service1:80/ 2>/dev/null); rc=$?
    if [ "$code" = 200 ]; then echo "gate: first successful request after $t attempt(s)"; break; fi
    echo "gate: attempt $t failed (http=${code:-none}, curl exit $rc)"; sleep 1
  done
  [ "$code" = 200 ] || { echo "ERROR: service1 never answered within 30 attempts"; exit 1; }
fi
kubectl get pods -o wide
CL=$(kubectl get pod | awk '/ubuntu-client-/{print $1}')
echo; echo "READY.  delay per request on service2 = ${SLOWPOKE_DELAY_MICROS_SERVICE2} us  -> ~$(( SLOWPOKE_DELAY_MICROS_SERVICE2 * 100 / 1000 )) ms pause per 100-request batch"
echo "Start your capture, then generate load (client pod: $CL):"
echo "   kubectl exec $CL -- /wrk/wrk -t8 -c512 --timeout 20s -d40s -L http://service1:80/"
