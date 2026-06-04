#!/usr/bin/env bash
# Systematic preflight for hotel/social/movie (proxy + cluster). Run on netpoke-control.
set -u

BENCH="${1:-hotel}"
export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
RESULTS="${RESULTS_DIR:-$SLOWPOKE_TOP/evaluation/results}"

echo "=== SlowPoke diagnose: $BENCH ==="
echo "SLOWPOKE_TOP=$SLOWPOKE_TOP"
echo ""

echo "--- 1. Boutique results (if full run already passed boutique) ---"
BF="$RESULTS/boutique_medium.log"
if [[ -f "$BF" ]]; then
  if grep -q 'Error Perc:' "$BF"; then
    echo "OK: boutique_medium.log complete"
    grep 'Error Perc:' "$BF" | tail -1
    ls -lh "$BF"
  else
    echo "INCOMPLETE: boutique_medium.log (no Error Perc yet)"
    tail -5 "$BF"
  fi
else
  echo "SKIP: no $BF"
fi
echo ""

echo "--- 2. Cluster pods ---"
kubectl get pods -o wide 2>/dev/null || { echo "kubectl failed"; exit 1; }
bad=$(kubectl get pods --no-headers 2>/dev/null | grep -vE 'Running|Completed' | wc -l)
if (( bad > 0 )); then
  echo "WARN: pods not all Running/Completed"
fi
echo ""

echo "--- 3. Client pod + analysis.txt path ---"
CLIENT=$(kubectl get pod --no-headers 2>/dev/null | awk '/ubuntu-client/{print $1; exit}')
if [[ -z "$CLIENT" ]]; then
  echo "WARN: no ubuntu-client pod (deploy via run.sh or client/client.yaml)"
else
  echo "Client: $CLIENT"
  AF="$SLOWPOKE_TOP/evaluation/$BENCH/data/analysis.txt"
  if [[ -f "$AF" ]]; then
    echo "OK: $AF exists ($(wc -c <"$AF") bytes)"
  else
    echo "FAIL: missing $AF"
  fi
  kubectl exec "$CLIENT" -- test -f /analysis.txt 2>/dev/null \
    && echo "OK: /analysis.txt on client" \
    || echo "WARN: /analysis.txt not on client yet (populate runs in run.sh)"
fi
echo ""

echo "--- 4. Rust proxy (hotel/social/movie) ---"
if [[ "$BENCH" == "boutique" || "$BENCH" == "synthetic" ]]; then
  echo "SKIP: boutique/synthetic do not use rust proxy on client"
else
  if [[ -z "${CLIENT:-}" ]]; then
    echo "SKIP: no client"
  else
    kubectl exec "$CLIENT" -- test -x /mucache/proxy/target/release/proxy \
      && echo "OK: proxy binary present" \
      || echo "FAIL: /mucache/proxy/target/release/proxy missing"
    kubectl exec "$CLIENT" -- bash -c \
      "pkill -f '/mucache/proxy/target/release/proxy' 2>/dev/null || true; \
       nohup /mucache/proxy/target/release/proxy $BENCH >/tmp/proxy-test.log 2>&1 </dev/null &"
    sleep 3
    if kubectl exec "$CLIENT" -- curl -sf --max-time 3 http://localhost:3000/heartbeat 2>/dev/null | grep -q Heartbeat; then
      echo "OK: proxy responds on localhost:3000/heartbeat"
    else
      echo "FAIL: no heartbeat on :3000"
      kubectl exec "$CLIENT" -- tail -20 /tmp/proxy-test.log 2>/dev/null || true
    fi
    kubectl exec "$CLIENT" -- pkill -f '/mucache/proxy/target/release/proxy' 2>/dev/null || true
  fi
fi
echo ""

echo "--- 5. Active / stuck log for $BENCH ---"
LF="$RESULTS/${BENCH}_medium.log"
if [[ -f "$LF" ]]; then
  ls -lh "$LF"
  echo "Last run.sh / test.py lines:"
  grep -E '\[run\.sh\]|\[test\.py\]|\[exp\] Throughput:|Error Perc:' "$LF" 2>/dev/null | tail -12
  if grep -q 'Starting the rust proxy' "$LF" && ! grep -q 'Running warmup test' "$LF"; then
  echo ""
  echo "LIKELY HANG: proxy started but warmup never ran."
  echo "  Fix: update ~/slowpoke/src/run.sh (nohup proxy) from latest repo, then re-run hotel only."
  fi
else
  echo "No $LF yet"
fi
echo ""
echo "=== Done. Hotel-only run: ==="
echo "  cd ~/slowpoke/evaluation && mv -f results/hotel_medium.log results/hotel_medium.log.bak 2>/dev/null; \\"
echo "  WATCH_INTERVAL=10 ./run_with_monitor.sh bash hotel/run-hotel-medium.sh results/hotel_medium.log"
