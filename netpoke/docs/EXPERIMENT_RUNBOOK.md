# Experiment runbook: GCP cluster → clean results

Full procedure from a cold or stopped cluster to a complete set of results.
Covers the 4 L1/L2 paired runs that constitute the thesis evidence (rep2 onward).
L0 runs (Runs 1 and 2) are already recorded from the July 2026 session and do not
need to be repeated unless you want additional repetitions.

---

## Background: what the runs measure and their dependencies

| Run | Condition | Level | Script | Tables produced | Depends on |
|-----|-----------|-------|--------|-----------------|------------|
| 1 | SIGSTOP-only | L0 — no injection | `run_reproducible.sh` (per-app) | Table B1 (baseline RMSE) | — |
| 2 | NetPoke-on | L0 — no injection | `run_netpoke_l0_overhead.sh` | Table N3 (overhead cost) | — |
| **3** | **SIGSTOP-only** | **L1 — moderate I/O stress** | **`run_io_gap_sigstop_L1.sh`** | **Table I1 (L1 row), Table N2 (L1 SIGSTOP side)** | **none** |
| **4** | **NetPoke-on** | **L1 — moderate I/O stress** | **`run_io_gap_netpoke_L1.sh`** | **Table N2 (L1 NetPoke side)** | **Run 3 must exist first** |
| **5** | **SIGSTOP-only** | **L2 — heavy I/O stress** | **`run_io_gap_sigstop_L2.sh`** | **Table I1 (L2 row), Table N2 (L2 SIGSTOP side)** | **none** |
| **6** | **NetPoke-on** | **L2 — heavy I/O stress** | **`run_io_gap_netpoke_L2.sh`** | **Table N2 (L2 NetPoke side) — core thesis result** | **Run 5 must exist first** |

**Runs 1 and 2 are complete** (recorded in `netpoke/results/cluster/baseline/` and
`netpoke/results/cluster/netpoke/tables/TABLE_N3_L0_OVERHEAD.md`). Do not re-run
them unless starting a new repetition set.

**Runs 3–6 are the active work.** They must be run in the order shown — Run 4
compares against Run 3, and Run 6 compares against Run 5. Never run the NetPoke
variant before its SIGSTOP-only counterpart at the same level.

Run these **sequentially**, never in parallel — they redeploy the same pods.

**Why rep2 starts fresh at Run 3:** The injection-yaml bug (fixed 2026-07-21)
caused any L1/L2 run using `SLOWPOKE_NETPOKE=1` or `SLOWPOKE_YAML_SUBDIR` to
deploy from a yaml that never received the netem delay. All L1/L2 results
collected before that fix are invalid. rep2 is the first clean repetition.

---

## Current rep2 state (as of 2026-08-04)

| Run | Log files in rep2 | Status |
|-----|-------------------|--------|
| Run 3 — SIGSTOP L1 | `*_io_L1_sigstop_medium.log` | ❌ Not started |
| Run 4 — NetPoke L1 | `*_io_L1_netpoke_medium.log` | ❌ Premature attempt moved to `saved/premature_run4/` |
| Run 5 — SIGSTOP L2 | `*_io_L2_sigstop_medium.log` | ❌ Not started |
| Run 6 — NetPoke L2 | `*_io_L2_netpoke_medium.log` | ❌ Not started |

**Next action: Step 9 (Run 3 — SIGSTOP L1).**

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

## Step 2: Sync repo to control node

**On your Windows machine** (git commit + push):

```powershell
cd g:\projects\netpoke
git add -A
git commit -m "describe your changes"
git push
```

**Then in Cloud Shell** (pull + sync to control node):

```bash
cd ~/netpoke && git pull origin netpoke/experiments
cd netpoke/infra/gcp && ./sync_to_control.sh
```

Must print `SYNC_OK`. Repeat any time you push new changes from Windows.

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

## Step 6: Clean up any stuck or partial runs (control node)

Run this before starting any new run to ensure a clean state:

```bash
pkill -f 'run_io_gap' 2>/dev/null || true
pkill -f 'main.py' 2>/dev/null || true
pkill -f 'run.sh' 2>/dev/null || true
screen -ls | grep -oP '\d+\.[^\s]+' | xargs -I{} screen -S {} -X quit 2>/dev/null || true
bash ~/slowpoke/evaluation/safe_delete_workloads.sh
bash ~/slowpoke/evaluation/io_gap/restore_io_injection.sh || true
```

If a previous run left a partial log that was not completed, move it aside before
restarting so the skip-if-done check does not falsely treat it as complete:

```bash
cd ~/slowpoke/evaluation/results/rep2
mkdir -p saved/partial
# example: move a stuck hotel log
mv hotel_io_L1_netpoke_medium.log saved/partial/ 2>/dev/null || true
```

---

## Step 7: Open two SSH windows

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

## Step 8: Verify rep2 state before starting (SSH 1)

Check which logs are already complete so you don't redo finished work:

```bash
for f in ~/slowpoke/evaluation/results/rep2/*_medium.log; do
  echo -n "$(basename $f): "
  grep -q 'Error Perc:' "$f" && echo "DONE" || echo "incomplete"
done
```

The scripts skip any log that already contains `Error Perc:`, so it is safe to
restart a script mid-suite — it will resume from the first incomplete app.

---

## Step 9: Run 3 — SIGSTOP-only, L1 (SSH 1)

**Must run before Run 4.** Produces the SIGSTOP-only L1 baseline that Run 4's
NetPoke numbers are compared against.

**SSH 1:**
```bash
cd ~/slowpoke/evaluation
screen -S rep-l1-sigstop
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
WATCH_INTERVAL=10 ./io_gap/run_io_gap_sigstop_L1.sh
```

Ctrl+A D to detach.

**SSH 2 — monitor:**
```bash
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
cd ~/slowpoke/evaluation
./watch_progress.sh --append
```

Wait for: `[sigstop_l1] All 4 SIGSTOP-only L1 runs complete.`
Logs produced: `boutique_io_L1_sigstop_medium.log`, `hotel_io_L1_sigstop_medium.log`,
`social_io_L1_sigstop_medium.log`, `movie_io_L1_sigstop_medium.log`

---

## Step 10: Run 4 — NetPoke-on, L1 (SSH 1)

**Run after Step 9 is complete.** Compared directly against Run 3 logs.

**SSH 1:**
```bash
cd ~/slowpoke/evaluation
screen -S rep-l1-netpoke
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
WATCH_INTERVAL=10 ./io_gap/run_io_gap_netpoke_L1.sh
```

Ctrl+A D to detach.

**SSH 2 — monitor** (if not already running):
```bash
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
cd ~/slowpoke/evaluation
./watch_progress.sh --append
```

Wait for: `[netpoke_l1] All 4 NetPoke-on L1 runs complete.`
Logs produced: `boutique_io_L1_netpoke_medium.log`, `hotel_io_L1_netpoke_medium.log`,
`social_io_L1_netpoke_medium.log`, `movie_io_L1_netpoke_medium.log`

---

## Step 11: Run 5 — SIGSTOP-only, L2 (SSH 1)

**Must run before Run 6.** Re-run of the old Table I1 L2 numbers with the
injection-yaml bug fixed. Produces the SIGSTOP-only L2 baseline for Run 6.

**SSH 1:**
```bash
cd ~/slowpoke/evaluation
screen -S rep-l2-sigstop
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
WATCH_INTERVAL=10 ./io_gap/run_io_gap_sigstop_L2.sh
```

Ctrl+A D to detach.

**SSH 2 — monitor** (if not already running):
```bash
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
cd ~/slowpoke/evaluation
./watch_progress.sh --append
```

Wait for: `[sigstop_l2] All 4 SIGSTOP-only L2 runs complete.`
Logs produced: `boutique_io_L2_sigstop_medium.log`, `hotel_io_L2_sigstop_medium.log`,
`social_io_L2_sigstop_medium.log`, `movie_io_L2_sigstop_medium.log`

---

## Step 12: Run 6 — NetPoke-on, L2 (SSH 1)

**Run after Step 11 is complete.** This is the core thesis result — NetPoke-on L2
RMSE compared against SIGSTOP-only L2 RMSE from Run 5. Re-run of the old Table N2
with the injection-yaml bug fixed.

**SSH 1:**
```bash
cd ~/slowpoke/evaluation
screen -S rep-l2-netpoke
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
WATCH_INTERVAL=10 ./io_gap/run_io_gap_netpoke_L2.sh
```

Ctrl+A D to detach.

**SSH 2 — monitor** (if not already running):
```bash
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
cd ~/slowpoke/evaluation
./watch_progress.sh --append
```

Wait for: `[netpoke_rmse] All 4 NetPoke-on L2 runs complete.`
Logs produced: `boutique_io_L2_netpoke_medium.log`, `hotel_io_L2_netpoke_medium.log`,
`social_io_L2_netpoke_medium.log`, `movie_io_L2_netpoke_medium.log`

---

## Step 13: Extract results (before tearing down)

Run on SSH 1 after all 4 runs complete:

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

- Each run (all 4 apps) takes roughly **30–60 minutes** at L1/L2 due to reduced
  throughput under injection — hotel, social, and movie drop to ~2–10 req/s
- Hotel RMSE is volatile — large swings between runs are expected and documented
- Boutique shows little change between SIGSTOP-only and NetPoke-on at any level
  (its cart handler uses in-memory storage, not real network I/O — see
  `netpoke/results/cluster/netpoke/tables/BOUTIQUE_FANOUT_FINDING.md`)
- If a run stalls with no progress for >15 minutes, reattach and check for errors

## Reattaching to a detached screen session

```bash
screen -ls                    # list all sessions
screen -r rep-l1-sigstop      # reattach by name
```

## If a run gets stuck mid-suite

The scripts skip any app whose log already contains `Error Perc:`, so you can
kill and restart safely — completed apps will be skipped automatically.

```bash
# kill the stuck run
pkill -f 'run_io_gap' 2>/dev/null || true
pkill -f 'main.py' 2>/dev/null || true
bash ~/slowpoke/evaluation/safe_delete_workloads.sh
bash ~/slowpoke/evaluation/io_gap/restore_io_injection.sh || true

# restart the same script — it resumes from the first incomplete app
screen -S rep-l1-sigstop   # or whichever run was stuck
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./io_gap/run_io_gap_sigstop_L1.sh   # replace with the stuck script
```

## Known issues

| Symptom | Fix |
|---------|-----|
| `start_cluster_vms.sh` 404 errors | Check `GCP_ZONE` in `config.env` matches where VMs actually are (`gcloud compute instances list`) |
| `kubectl get nodes` shows `NotReady` after VM restart | Wait 2 minutes; if persists, `kubectl describe node <name>` |
| `grep` finds no `tc-netem-sidecar` in Step 4 | `git pull` on control node, re-run `sync_to_control.sh`, retry |
| `main.py already running` error at run start | `pkill -f 'python3.*main\.py'` then `bash safe_delete_workloads.sh` |
| Run stuck at heartbeat check for >10 min | Kill all processes (Step 6 cleanup), restart the script |
| `0/21 workloads` stuck indefinitely | `fix_req_n.lua` counter issue — check `io_levels.conf` `IO_NUM_REQ_*` values are 800, not 100000 |
