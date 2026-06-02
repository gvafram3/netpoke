# SlowPoke evaluation process (from the artifact, not assumptions)

This document tracks **what the NSDI 2026 artifact actually does**, as stated in
`slowpoke/INSTRUCTIONS.md` and the code under `slowpoke/`. Your NetPoke thesis
extends step 4 (the slowdown mechanism).

## Paper vs artifact vs your GCP cluster

| Aspect | Paper / AWS artifact | Your `netpoke-*` GCP cluster |
|--------|----------------------|------------------------------|
| Control node | 1× (kubeadm, runs `kubectl`, `main.py`) | `netpoke-control` |
| Load generator | 2nd EC2 runs `wrk` client | `netpoke-loadgen` exists; **artifact still pins client to `worker1`** in `client/client.yaml` |
| Service workers | 12× `m5.large` (many nodes) | 3× `worker1..3` (boutique YAMLs spread 9 services across 3 nodes) |
| Slowdown | POKER sends `SIGSTOP`/`SIGCONT` to non-target pods | Same (`src/poker/poker.c`) |
| Accuracy target | Fig. 8; RMSE ~2.07% boutique (paper) | Re-measure on your cluster; expect higher noise than paper |

## End-to-end flow (what `run_functional.sh` / `run_reproducible.sh` do)

All experiments run **on the Kubernetes control node** (your `netpoke-control`),
with `kubectl` talking to the API server on that node.

### Phase 0 — Cluster prerequisites

1. Nodes joined with hostnames **`worker1`, `worker2`, `worker3`** (boutique
   affinity in `evaluation/boutique/yamls/*.yaml`).
2. Optional fourth node name **`loadgen`** (your init script labels it; not used
   by default client YAML yet).
3. Docker images pulled on workers (e.g. `yizhengx/mucache:boutique-pokerpp`,
   `yizhengx/mucache:client`).
4. `SLOWPOKE_TOP` points at the `slowpoke/` tree on the control node.

### Phase 1 — Orchestrator (`src/main.py`)

For each benchmark run, Python:

1. Sets env vars: per-service `SLOWPOKE_DELAY_MICROS_*`, `SLOWPOKE_PROCESSING_MICROS_*`,
   `SLOWPOKE_IS_TARGET_SERVICE_*`, `SLOWPOKE_POKER_BATCH_THRESHOLD_*`.
2. Shells out to **`src/run.sh`**, which deploys K8s resources and runs load.

### Phase 2 — Deploy + load (`src/run.sh`)

1. `kubectl delete` existing deployments/services.
2. `envsubst` + `kubectl apply` every YAML in `evaluation/<benchmark>/yamls/`.
3. Deploy **`client/client.yaml`** (`ubuntu-client` / `wrk`) if missing — default
   **`nodeName: worker1`**.
4. Wait for pods Ready; heartbeat checks between services.
5. Run **`wrk`** inside the client pod against `http://frontend:80` (boutique).
6. Tear down deployments (experiment timing uses pod lifetime).

### Phase 3 — Per optimization point (medium/reproducible runs)

For each target processing time in the sweep (`main.py` `run()`):

1. **Baseline** — no artificial delays on non-target services.
2. **Ground truth** — actually reduce target service processing time (`SLOWPOKE_PROCESSING_MICROS_<TARGET>`).
3. **Slowdown** — restore target processing time; set delays on **non-target** services so POKER pauses them (SIGSTOP windows).
4. **Predict** — use formula from paper model: combine slowdown throughput with delay math → `predicted`.
5. **Error %** — `(predicted - groundtruth) / groundtruth * 100`.

Logs end with `Groundtruth`, `Slowdown`, `Predicted`, `Error Perc` lists.

### Phase 4 — POKER / SIGSTOP (inside each service pod)

- Container image `*-pokerpp` runs the Go app **under** `poker` (`poker.c`).
- `poker` reads pause timing from a FIFO; on each pause:
  - `kill(-child_pgid, SIGSTOP)` → sleep → `SIGCONT`.
- Go runtime registers neighbors over ZMQ (`app/pkg/slowpoke/pause.go`).

**NetPoke thesis** adds network hold around that window (`netpoke/design/poker-io-pause.md`).

## Artifact tests (official)

| Script | Time | Purpose | Pass criterion |
|--------|------|---------|----------------|
| `evaluation/run_functional.sh` | ~5 min | Smoke test | Completes; writes `results/boutique_tiny.log` with summary lines (error can be huge; **not** accuracy) |
| `evaluation/run_reproducible.sh` | ~2.5 h | Fig. 8 reproduction | `boutique_medium.log`, `hotel_medium.log`, etc.; errors mostly 0–10% per artifact |

`run-boutique-tiny.sh` uses **target `frontend`**, 10k requests, 1 experiment — check log yourself; INSTRUCTIONS text mentions cart but the shipped tiny script targets frontend.

## Your position in this pipeline

```
[Done]    GCP VMs + IP quota layout (control public, others internal)
[Next]    02_initialize_cluster.sh  → kubeadm + weave + istio on all nodes
[Next]    Clone slowpoke on control, run_functional.sh
[Later]   run_reproducible.sh → baseline RMSE on this cluster
[Thesis]  eBPF residual I/O → NetPoke sch_plug → re-run accuracy
```

Use `./preflight_cluster.sh` before step 2 and `./preflight_cluster.sh --after-k8s` after.

## Monitoring progress (counter dashboard)

`tail -f` on a multi-hour log is hard to read. Experiment scripts redirect output to
`results/*.log`, so the SSH window stays **silent** unless you add a monitor.

### One SSH session (recommended)

```bash
cd ~/slowpoke/evaluation
screen -S slowpoke
./run_with_monitor.sh
# or simply (auto-wraps the monitor):
./run_reproducible.sh
```

Every ~20s you get counters on **your terminal** (even while output goes to the log file):

- `workloads 7/21` — completed `wrk` runs for the current benchmark
- `opt points 3/10` — finished optimization sweep points
- `Suite: 1/4 benchmarks finished` — boutique → hotel → social → movie

Faster updates: `WATCH_INTERVAL=10 ./run_with_monitor.sh`

**Inside one `screen` session**, split panes (still one SSH): `Ctrl+A` then `|` or `S`,
open a second pane, run `./watch_progress.sh` in the lower pane.

**Optional tmux** (if installed): `SLOWPOKE_TMUX=1 ./run_with_monitor.sh`

### Second SSH session (if you have one)

```bash
cd ~/slowpoke/evaluation
./watch_progress.sh
```

You should see:

| Counter | Meaning |
|---------|---------|
| **Workload runs X / 21** | Each medium benchmark does 1 baseline + 10×(groundtruth + slowdown) = **21** `wrk` runs (`num_exp=10`). Increments when `[exp] Throughput:` appears. |
| **Opt points done Y / 10** | Increments when `Finished running Nth optmization experiment` appears. |
| **Full reproducible** | `boutique` → `hotel` → `social` → `movie`; each `*_medium.log` shows `DONE` when `Error Perc:` is written. |

If workload count is stuck for **>15 minutes** with no new log bytes, check `kubectl get pods -A`
(deploy/wrk may be hung). Short pauses (1–3 min) during a single `wrk` run are normal.
