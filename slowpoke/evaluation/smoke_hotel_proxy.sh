#!/usr/bin/env bash
# One-shot hotel proxy + wrk smoke test on netpoke-control (after hotel pods are up).
set -euo pipefail
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"

echo "=== Hotel proxy smoke test ==="
bash "$SLOWPOKE_TOP/evaluation/safe_delete_workloads.sh"
sleep 5

YAML="$SLOWPOKE_TOP/evaluation/hotel/yamls"
for f in "$YAML"/*.yaml; do
  envsubst < "$f" | kubectl apply -f -
done
envsubst < "$SLOWPOKE_TOP/client/client.yaml" | kubectl apply -f -
echo "Waiting for pods..."
kubectl wait --for=condition=ready pod --all --timeout=300s

CLIENT=$(kubectl get pod -l app=ubuntu-client -o jsonpath='{.items[0].metadata.name}')
echo "Client: $CLIENT"

kubectl cp "$SLOWPOKE_TOP/evaluation/hotel/data/analysis.txt" "$CLIENT:/analysis.txt"
kubectl exec "$CLIENT" -- bash -c \
  "pkill -f '/mucache/proxy/target/release/proxy' 2>/dev/null || true; \
   nohup /mucache/proxy/target/release/proxy hotel >/tmp/proxy-hotel.log 2>&1 </dev/null &"

for i in $(seq 1 30); do
  if kubectl exec "$CLIENT" -- curl -sf --max-time 2 http://localhost:3000/heartbeat 2>/dev/null | grep -q Heartbeat; then
    echo "OK: proxy heartbeat (${i}s)"
    break
  fi
  sleep 1
done

echo "--- proxy log ---"
kubectl exec "$CLIENT" -- tail -15 /tmp/proxy-hotel.log 2>/dev/null || true

echo "--- wrk warmup ---"
kubectl exec "$CLIENT" -- /wrk/wrk -t2 -c64 --timeout 5s -d3s -L http://localhost:3000

echo "=== Smoke test done (look for Requests/sec above) ==="
