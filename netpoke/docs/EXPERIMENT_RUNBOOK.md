# Experiment runbook: GCP cluster → clean results

Full procedure from a cold or stopped cluster to a complete set of results.
Covers all 6 paired runs (L0 + L1 + L2, SIGSTOP-only and NetPoke-on).

---

## Background: what the 6 runs measure

| Run | Condition | Level | Tables produced |
|-----|-----------|-------|-----------------|
| 1 | SIGSTOP-only | L0 — no injection | Table B1 (baseline RMSE) |
| 2 | NetPoke-on | L0 — no injection | Table N3 (overhead cost) |
| 3 | SIGSTOP-only | L1 — moderate I/O stress | Table I1 (L1 row), Table N2 (L1 SIGSTOP side) |
| 4 | NetPoke-on | L1 — moderate I/O stress | Table N2 (L1 NetPoke side) |
| 5 | SIGSTOP-only | L2 — heavy I/O stress | Table I1 (L2 row), Table N2 (L2 SIGSTOP side) |
| 6 | NetPoke-on | L2 — heavy I/O stress | Table N2 (L2 NetPoke side) — **core thesis result** |

Run 6 vs Run 5 is the headline comparison. Runs 3–4 add the L1 gradient that
shows the RMSE degradation and recovery scale with injection severity, not just
appear at one extreme level.

Run these **sequentially**, never in parallel — they redeploy the same pods.

---

## Step 0: Pull latest code (Cloud Shell)

```bash
cd ~/netpoke && git pull origin netpoke/experiments
```

---

## Step 1: Bring the cluster up (Cloud Shell)

Check current state:

```bash
gcloud compute instances list --filter="tags.items=netpoke-cluster"
```

**VMs listed as TERMINATED (stopped from a previous session):**

```bash
cd ~/netpoke/netpoke/infra/gcp
grep -q ENABLE_LOADGEN config.env || echo 'ENABLE_LOADGEN=0' >> config.env
./start_cluster_vms.sh
```

**Nothing listed (fully torn down):**

```bash
cd ~/netpoke/netpoke/infra/gcp
cp -n config.env.example config.env
grep -q ENABLE_LOADGEN config.env || echo 'ENABLE_LOADGEN=0' >> config.env
./01_create_cluster.sh
# wait ~60s for VMs to boot, then:
./02_initialize_cluster.sh
```

`netpoke-loadgen` staying TERMINATED is expected with `ENABLE_LOADGEN=0`.

---

## Step 2: Sync repo to control node (Cloud Shell)

```bash
cd ~/netpoke/netpoke/infra/gcp
./sync_to_control.sh
```

Must print `SYNC_OK`. Re-run any time you push local changes.

---

## Step 3: Verify Kubernetes health (SSH into control node)

```bash
gcloud compute ssh netpoke-control --zone us-central1-a
```

```bash
kubectl get nodes
```

All nodes must show `Ready` before continuing.

---

## Step 4: One-time yaml setup (control node, once per fresh cluster)

Generates `netpoke/` and `netpoke-sigstop/` yaml variants for all 4 apps.
Only needed once per cluster, not once per repetition.

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation
bash phase5_netpoke/patch_all_netpoke_yamls.sh all
```

**Verify the injection fix before trusting any L1/L2 result:**

```bash
# netpoke/ variant
export SLOWPOKE_TOP=~/slowpoke SLOWPOKE_NETPOKE=1
bash io_gap/apply_io_injection.sh social L2
grep -l tc-netem-sidecar ~/slowpoke/evaluation/social/yamls/netpoke/*.yaml
# must print post_storage.yaml and social_graph.yaml — if empty, STOP
bash io_gap/restore_io_injection.sh

# netpoke-sigstop/ variant
export SLOWPOKE_YAML_SUBDIR=netpoke-sigstop SLOWPOKE_NETPOKE=0
bash io_gap/apply_io_injection.sh social L2
grep -l tc-netem-sidecar ~/slowpoke/evaluation/social/yamls/netpoke-sigstop/*.yaml
# must print post_storage.yaml and social_graph.yaml — if empty, STOP
bash io_gap/restore_io_injection.sh
unset SLOWPOKE_YAML_SUBDIR
```

---

## Step 5: Create a results directory (control node)

Each repetition gets its own directory. Use `rep2`, `rep3`, ... for subsequent runs.

```bash
export REP=rep2   # increment for each new repetition
export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
mkdir -p "$RESULTS_DIR"
echo "RESULTS_DIR=$RESULTS_DIR"
```

---

## Step 6: Open two SSH windows

Open a **second browser tab** → GCP Console → Compute Engine → VM instances →
SSH on `netpoke-control`. This gives two independent terminals to the same machine.

**SSH 2 — progress monitor (leave running for the entire session):**

```bash
export REP=rep2
export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
cd ~/slowpoke/evaluation
./watch_progress.sh --append
```

SSH 2 updates every 15s. Normal to see the same line repeat many times.
Come back to SSH 1 for all experiment commands.

---

## Step 7: Run 1 — SIGSTOP-only, L0 (SSH 1)

```bash
cd ~/slowpoke/evaluation
screen -S rep-l0-sigstop
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export SLOWPOKE_YAML_SUBDIR=netpoke-sigstop SLOWPOKE_NETPOKE=0
WATCH_INTERVAL=10 RESULTS_DIR="$RESULTS_DIR" ./run_with_monitor.sh bash -c '
  bash boutique/run-boutique-medium.sh "$RESULTS_DIR/boutique_medium.log"
  bash hotel/run-hotel-medium.sh "$RESULTS_DIR/hotel_medium.log"
  bash social/run-social-medium.sh "$RESULTS_DIR/social_medium.log"
  bash movie/run-movie-medium.sh "$RESULTS_DIR/movie_medium.log"
'
```

Ctrl+A D to detach. Wait for SSH 2 to show `Suite: 4/4 benchmarks finished`.

---

## Step 8: Run 2 — NetPoke-on, L0 (SSH 1)

```bash
screen -S rep-l0-netpoke
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
unset SLOWPOKE_YAML_SUBDIR
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./run_netpoke_l0_overhead.sh
```

Ctrl+A D to detach. Wait for `NetPoke-on L0 overhead check: 4/4 runs complete`.

---

## Step 9: Run 3 — SIGSTOP-only, L1 (SSH 1)

```bash
screen -S rep-l1-sigstop
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./io_gap/run_io_gap_sigstop_L1.sh
```

Ctrl+A D to detach. Logs: `*_io_L1_sigstop_medium.log`.

---

## Step 10: Run 4 — NetPoke-on, L1 (SSH 1)

```bash
screen -S rep-l1-netpoke
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./io_gap/run_io_gap_netpoke_L1.sh
```

Ctrl+A D to detach. Logs: `*_io_L1_netpoke_medium.log`.

---

## Step 11: Run 5 — SIGSTOP-only, L2 (SSH 1)

```bash
screen -S rep-l2-sigstop
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./io_gap/run_io_gap_sigstop_L2.sh
```

Ctrl+A D to detach. Logs: `*_io_L2_sigstop_medium.log`.

---

## Step 12: Run 6 — NetPoke-on, L2 (SSH 1)

```bash
screen -S rep-l2-netpoke
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./io_gap/run_io_gap_netpoke_L2.sh
```

Ctrl+A D to detach. Logs: `*_io_L2_netpoke_medium.log`.

---

## Step 13: Extract results (before tearing down)

```bash
cd ~/slowpoke/evaluation
for f in "$RESULTS_DIR"/*.log; do
  echo "=== $(basename "$f") ==="
  python3 summarize_results.py "$f"
done
```

**Copy this output somewhere durable before tearing down.** Results live only
on the VM disk and are deleted by `03_teardown.sh`.

---

## Step 14: Tear down (Cloud Shell)

```bash
cd ~/netpoke/netpoke/infra/gcp
./03_teardown.sh
```

---

## Step 15: Repeat for more repetitions

Go back to Step 1 with `REP=rep3`, `rep4`, etc. Aim for 3+ repetitions to
compute mean and spread across runs. Paste `summarize_results.py` output after
each repetition before tearing down.

---

## What to expect during runs

- Each run takes roughly **30–45 minutes** for all 4 apps
- Hotel RMSE is volatile — large swings between runs are expected and documented
- Boutique shows little change between SIGSTOP-only and NetPoke-on at any level
  (its cart handler uses in-memory storage, not real network I/O — see
  `netpoke/results/cluster/netpoke/tables/BOUTIQUE_FANOUT_FINDING.md`)
- If a run stalls with no progress for >10 minutes, check `screen -r <name>`
  for error output

## Reattaching to a detached screen session

```bash
screen -ls                    # list sessions
screen -r rep-l0-sigstop      # reattach by name
```

## Known issues

| Symptom | Fix |
|---------|-----|
| `start_cluster_vms.sh` 404 errors | Check `GCP_ZONE` in `config.env` matches where VMs actually are (`gcloud compute instances list`) |
| `kubectl get nodes` shows `NotReady` after VM restart | Wait 2 minutes; if persists, `kubectl describe node <name>` |
| `grep` finds no `tc-netem-sidecar` in Step 4 | `git pull` on control node, re-run `sync_to_control.sh`, retry |
| `main.py already running` error at run start | `pkill -f 'python3.*main\.py'` then `bash safe_delete_workloads.sh` |
