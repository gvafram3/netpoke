# Run SlowPoke on GCP with live progress (netpoke-control)

One place to follow from a clean start. All experiment commands run on **netpoke-control**, not Cloud Shell.

---

## Before you start

| Item | Check |
|------|--------|
| VMs running | GCP Console → Compute Engine → `netpoke-control`, workers **Running** |
| SSH target | **SSH** button on **netpoke-control** (zone `us-central1-a`) |
| SlowPoke tree | `~/slowpoke` exists on control (`ls ~/slowpoke/src/main.py`) |

Cloud Shell is only for **copying files** and **downloading results** later.

---

## Step 1 — Stop anything old

On **netpoke-control**:

```bash
pkill -f 'slowpoke/src/main.py' 2>/dev/null || true
pkill -f run_reproducible 2>/dev/null || true
screen -ls
# If slowpoke screens exist: screen -S slowpoke-repro -X quit 2>/dev/null || true
```

---

## Step 2 — Fix shipping (required)

Broken shipping blocks every boutique run.

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation/boutique/yamls
cp -a shipping.yaml shipping.yaml.backup-$(date +%Y%m%d) 2>/dev/null || true

cat > shipping.yaml << 'ENDYAML'
kind: Service
apiVersion: v1
metadata:
  name: shipping
  labels:
    app: shipping
spec:
  selector:
    app: shipping
  ports:
    - protocol: TCP
      port: 80
      targetPort: 3000
      name: http
    - protocol: TCP
      port: 5550
      targetPort: 5550
      name: zmq1
    - protocol: TCP
      port: 5551
      targetPort: 5551
      name: zmq2
  type: LoadBalancer
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: shipping
  labels:
    app: shipping
spec:
  replicas: 1
  selector:
    matchLabels:
      app: shipping
  template:
    metadata:
      labels:
        app: shipping
    spec:
      containers:
        - name: shipping
          image: yizhengx/mucache:boutique-pokerpp
          imagePullPolicy: Always
          env:
            - name: APP_PORT
              value: "3000"
            - name: APP_NAME
              value: shipping
            - name: SLOWPOKE_SERV_NAME
              value: shipping
            - name: SLOWPOKE_DELAY_MICROS
              value: "${SLOWPOKE_DELAY_MICROS_SHIPPING}"
            - name: SLOWPOKE_PROCESSING_MICROS
              value: "${SLOWPOKE_PROCESSING_MICROS_SHIPPING}"
            - name: SLOWPOKE_PRERUN
              value: "${SLOWPOKE_PRERUN}"
            - name: SLOWPOKE_POKER_BATCH_THRESHOLD
              value: "${SLOWPOKE_POKER_BATCH_THRESHOLD_SHIPPING}"
            - name: SLOWPOKE_IS_TARGET_SERVICE
              value: "${SLOWPOKE_IS_TARGET_SERVICE_SHIPPING}"
          ports:
            - containerPort: 3000
            - containerPort: 5550
            - containerPort: 5551
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/hostname
                    operator: In
                    values:
                      - worker3
ENDYAML

grep -r 'slowpoke-shipping\|netem' . && echo "FIX YAMLS ABOVE" || echo "shipping yaml OK"
```

---

## Step 3 — Install progress scripts

Paste **once** on **netpoke-control**:

```bash
mkdir -p ~/slowpoke/evaluation

cat > ~/slowpoke/evaluation/run_with_monitor.sh << 'ENDMON'
#!/usr/bin/env bash
set -euo pipefail
EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export RESULTS_DIR="${RESULTS_DIR:-$EVAL_DIR/results}"
INTERVAL="${WATCH_INTERVAL:-20}"
export PYTHONUNBUFFERED=1
if (( $# == 0 )); then set -- ./run_reproducible.sh; fi
case " $* " in
  *run_functional*) export SLOWPOKE_ACTIVE_LOG="$RESULTS_DIR/boutique_tiny.log" ;;
  *boutique_medium*) export SLOWPOKE_ACTIVE_LOG="$RESULTS_DIR/boutique_medium.log" ;;
  *hotel_medium*) export SLOWPOKE_ACTIVE_LOG="$RESULTS_DIR/hotel_medium.log" ;;
  *) export SLOWPOKE_ACTIVE_LOG="" ;;
esac
mkdir -p "$RESULTS_DIR"
export WATCH_INTERVAL="$INTERVAL"
"${EVAL_DIR}/watch_progress.sh" --loop-tty "$RESULTS_DIR" &
wpid=$!
trap 'kill "$wpid" 2>/dev/null || true' EXIT INT TERM
cd "$EVAL_DIR"
echo "Starting: $*"
echo "Monitor log: ${SLOWPOKE_ACTIVE_LOG:-auto}"
echo ""
"$@"
echo ""
"${EVAL_DIR}/watch_progress.sh" --once "${SLOWPOKE_ACTIVE_LOG:-$RESULTS_DIR}"
ENDMON

cat > ~/slowpoke/evaluation/watch_progress.sh << 'ENDWATCH'
#!/usr/bin/env bash
set -u
EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$EVAL_DIR/results}"
LOG_FILE=""
INTERVAL="${WATCH_INTERVAL:-15}"
MODE="fullscreen"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) MODE=once; shift ;;
    --loop-tty) MODE=loop-tty; shift ;;
    *) [[ -f "$1" ]] && LOG_FILE="$1"; [[ -d "$1" ]] && RESULTS_DIR="$1"; shift ;;
  esac
done
REPRO=(boutique hotel social movie)
is_slowpoke_log() { [[ -s "$1" ]] && grep -qE '^benchmark|\[test\.py\]' "$1" 2>/dev/null; }
pick_active_log() {
  local dir="$1" f
  [[ -n "${SLOWPOKE_ACTIVE_LOG:-}" ]] && { echo "$SLOWPOKE_ACTIVE_LOG"; return; }
  for f in "$dir/boutique_medium.log" "$dir/hotel_medium.log" "$dir/social_medium.log" \
           "$dir/movie_medium.log" "$dir/boutique_tiny.log"; do
    [[ -f "$f" ]] && ! grep -q 'Error Perc:' "$f" 2>/dev/null && { echo "$f"; return; }
  done
  for f in "$dir"/*.log; do
    [[ -f "$f" ]] && is_slowpoke_log "$f" && ! grep -q 'Error Perc:' "$f" && { echo "$f"; return; }
  done
  ls -t "$dir"/*.log 2>/dev/null | head -1
}
parse_log() {
  local log="$1"
  P_LOG="$log"; P_NUM_EXP=10; P_FINISHED_OPT=0; P_THROUGHPUTS=0
  P_TOTAL_WORKLOADS=21; P_PCT_WORKLOADS=0; P_PCT_OPT=0; P_LOG_DONE=0
  P_BENCHMARK=""; P_TARGET=""; P_PHASE=""; P_LAST_TP=""
  [[ -f "$log" ]] || return 1
  P_NUM_EXP=$(grep -m1 '^target_num_exp' "$log" 2>/dev/null | sed -E 's/.*: *//'); P_NUM_EXP=${P_NUM_EXP:-10}
  P_FINISHED_OPT=$(grep -c 'Finished running .*th optmization experiment' "$log" 2>/dev/null || true)
  P_THROUGHPUTS=$(grep -c '\[exp\] Throughput:' "$log" 2>/dev/null || true)
  P_TOTAL_WORKLOADS=$((1 + P_NUM_EXP * 2))
  (( P_TOTAL_WORKLOADS > 0 )) && P_PCT_WORKLOADS=$((P_THROUGHPUTS * 100 / P_TOTAL_WORKLOADS))
  (( P_NUM_EXP > 0 )) && P_PCT_OPT=$((P_FINISHED_OPT * 100 / P_NUM_EXP))
  P_PHASE=$(grep -E '\[test\.py\]|\[run\.sh\]|\[exp\] Throughput:' "$log" 2>/dev/null | tail -1 | sed 's/^[[:space:]]*//')
  P_BENCHMARK=$(grep -m1 '^benchmark' "$log" 2>/dev/null | sed -E 's/.*: *//')
  P_TARGET=$(grep -m1 '^target_service' "$log" 2>/dev/null | sed -E 's/.*: *//')
  P_LAST_TP=$(grep '\[exp\] Throughput:' "$log" 2>/dev/null | tail -1 | sed 's/.*Throughput: //')
  grep -q 'Error Perc:' "$log" 2>/dev/null && P_LOG_DONE=1
}
render_bar() {
  local pct="${1:-0}" w=20 f i; (( pct < 0 )) && pct=0; (( pct > 100 )) && pct=100
  f=$((pct * w / 100)); printf '['
  for ((i=0;i<w;i++)); do (( i < f )) && printf '#' || printf '.'; done
  printf '] %3d%%' "$pct"
}
print_compact() {
  local out="${1:-}"
  [[ -n "${SLOWPOKE_ACTIVE_LOG:-}" ]] && LOG_FILE="$SLOWPOKE_ACTIVE_LOG"
  [[ -z "${LOG_FILE:-}" ]] && LOG_FILE=$(pick_active_log "$RESULTS_DIR")
  _emit() {
    echo "── SlowPoke $(date '+%H:%M:%S') ──"
    local n d=0 f
    for n in "${REPRO[@]}"; do
      f="$RESULTS_DIR/${n}_medium.log"
      [[ -f "$f" ]] && grep -q 'Error Perc:' "$f" && d=$((d+1))
    done
    echo "Suite: ${d}/4 done (boutique -> hotel -> social -> movie)"
    [[ -z "${LOG_FILE:-}" || ! -f "$LOG_FILE" ]] && { echo "Log: (not started)"; return; }
    parse_log "$LOG_FILE" || true
    echo "Now: $(basename "$P_LOG") (${P_BENCHMARK:-?} / ${P_TARGET:-?})"
    if (( P_LOG_DONE )); then echo "      FINISHED"; else
      printf "      workloads %s/%s " "$P_THROUGHPUTS" "$P_TOTAL_WORKLOADS"; render_bar "$P_PCT_WORKLOADS"; echo
      printf "      opt points %s/%s " "$P_FINISHED_OPT" "$P_NUM_EXP"; render_bar "$P_PCT_OPT"; echo
      echo "      phase: ${P_PHASE:-...}"
    fi
  }
  [[ -n "$out" ]] && _emit >"$out" || _emit
}
[[ "$MODE" == "once" ]] && { print_compact; exit 0; }
if [[ "$MODE" == "loop-tty" ]]; then
  T=/dev/tty; [[ -w "$T" ]] || T=/dev/stdout
  while true; do print_compact "$T"; echo "" >"$T"; sleep "$INTERVAL"; done
fi
while true; do clear; print_compact; sleep "$INTERVAL"; done
ENDWATCH

chmod +x ~/slowpoke/evaluation/watch_progress.sh ~/slowpoke/evaluation/run_with_monitor.sh
~/slowpoke/evaluation/watch_progress.sh --once ~/slowpoke/evaluation/results
```

No errors = scripts OK.

---

## Step 4 — Clean the cluster

```bash
kubectl delete deployment --all -n default --wait=false 2>/dev/null || true
kubectl delete pod --all -n default --force --grace-period=0 2>/dev/null || true
sleep 5
kubectl get pods -n default
```

Wait until **no pods** (empty list). If a pod sticks:

```bash
kubectl get rs -n default
kubectl delete rs -l app=shipping --force --grace-period=0 2>/dev/null || true
```

---

## Step 5 — Smoke test (~5 min)

```bash
export SLOWPOKE_TOP=~/slowpoke
export PYTHONUNBUFFERED=1
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./run_with_monitor.sh ./run_functional.sh
```

**Pass:** monitor shows `boutique_tiny.log`, `workloads` reaches **3/3**, ends without hanging.

```bash
grep 'Error Perc' ~/slowpoke/evaluation/results/boutique_tiny.log
```

---

## Step 6 — Full run (~2.5 h) in screen

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation
screen -S slowpoke-repro
```

Inside screen:

```bash
export SLOWPOKE_TOP=~/slowpoke
export PYTHONUNBUFFERED=1
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./run_with_monitor.sh
```

Detach: **Ctrl+A**, then **D**.

Reattach: `screen -r slowpoke-repro`

---

## Step 7 — What good progress looks like

Every ~10s:

```text
Suite: 0/4 done
Now: boutique_medium.log (boutique / cart)
      workloads 5/21 [#####...............]  23%
      opt points 2/10 [####................]  20%
      phase: [test.py] Running 2th slowdown exp
```

| Stuck sign | Action |
|------------|--------|
| `Waiting for all pods` >5 min | `kubectl get pods`; fix `ErrImageNeverPull` on shipping |
| `workloads 0/21` >20 min | Same; kill run, Step 2+4, restart |
| `shipping` 1/2 | Re-do Step 2 |

Quick check:

```bash
kubectl get pods | grep -E 'shipping|NAME'
ls -lh ~/slowpoke/evaluation/results/*_medium.log
```

---

## Step 8 — Download results (Cloud Shell)

```bash
gcloud compute ssh netpoke-control --zone=us-central1-a -- \
  'tar czf /tmp/slowpoke-results.tgz -C ~/slowpoke/evaluation results && ls -lh /tmp/slowpoke-results.tgz'

gcloud compute scp --zone=us-central1-a \
  netpoke-control:/tmp/slowpoke-results.tgz ~/slowpoke-results.tgz

grep 'Error Perc' ~/slowpoke-results/results/*_medium.log
```

Four lines = full run succeeded. Each `*_medium.log` should be ~100KB+, not 5KB.

---

## Check boutique results only (without re-running)

On **netpoke-control** after boutique finished in a full run:

```bash
LOG=~/slowpoke/evaluation/results/boutique_medium.log
ls -lh "$LOG"
grep -E 'Error Perc:|Baseline throughput:|Test finished' "$LOG"
```

**Complete** boutique medium log: file ~100KB+, one `Error Perc:` line with 10 numbers, and `[run.sh] Test finished with status 0` many times inside the log.

Optional plot (on control, if matplotlib installed):

```bash
python3 ~/slowpoke/evaluation/draw.py ~/slowpoke/evaluation/results/boutique_medium.log
```

---

## Hotel / social / movie stuck after boutique

**Symptom:** `boutique_medium.log` has `Error Perc:` but `hotel_medium.log` stops right after `Reading analysis data from /analysis.txt` with no `Running warmup test`. Monitor shows boutique FINISHED for hours.

**Cause:** `run.sh` started the Rust proxy with `kubectl exec ... proxy &`. The exec session stayed open on the proxy’s stdout, so `run_test` never reached warmup (same failure mode on single-VM and multi-node).

**Fix on netpoke-control** — update `~/slowpoke/src/run.sh` from this repo (proxy uses `nohup` + log redirect + `pkill` before start). Quick check:

```bash
grep -A2 'start_rust_proxy' ~/slowpoke/src/run.sh
```

You should see `nohup` and `/tmp/proxy-`.

**Systematic preflight** (before hotel-only run):

```bash
chmod +x ~/slowpoke/evaluation/diagnose_benchmark.sh
export SLOWPOKE_TOP=~/slowpoke
~/slowpoke/evaluation/diagnose_benchmark.sh hotel
```

**Hotel-only medium run** (~40 min; do not restart boutique if it already passed):

```bash
export SLOWPOKE_TOP=~/slowpoke
export PYTHONUNBUFFERED=1
cd ~/slowpoke/evaluation
pkill -f 'slowpoke/src/main.py' 2>/dev/null || true
bash safe_delete_workloads.sh
mv -f results/hotel_medium.log results/hotel_medium.log.bak-$(date +%Y%m%d-%H%M) 2>/dev/null || true

screen -S slowpoke-hotel
# inside screen:
WATCH_INTERVAL=10 ./run_with_monitor.sh bash hotel/run-hotel-medium.sh results/hotel_medium.log
```

**Pass:** log grows past proxy line, shows `Running warmup test`, reaches `Error Perc:` at the end; monitor shows `Suite: 1/4` then hotel workloads advancing.

After hotel passes, run social and movie the same way, or resume full `run_reproducible.sh` from hotel (boutique will run again unless you edit the script).

---

## Quick reference

| Goal | Command |
|------|---------|
| SSH | GCP → **netpoke-control** → SSH |
| Run with monitor | `WATCH_INTERVAL=10 ./run_with_monitor.sh` |
| Detach screen | Ctrl+A, D |
| One-shot status | `~/slowpoke/evaluation/watch_progress.sh --once ~/slowpoke/evaluation/results` |
