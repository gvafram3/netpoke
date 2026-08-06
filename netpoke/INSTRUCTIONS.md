# NetPoke artifact — reproduction instructions

Extends **SlowPoke** (Xie et al., NSDI 2026) with I/O-gap measurement and
**NetPoke** (network-synchronised pause).

## Where to start

**To run experiments:** follow [`docs/EXPERIMENT_RUNBOOK.md`](docs/EXPERIMENT_RUNBOOK.md).
That document is the single authoritative guide — it covers cluster bring-up,
the 6 paired runs (L0 + L1 + L2, SIGSTOP-only and NetPoke-on), result
extraction, and teardown.

**To understand the project state, findings, and fixes:** read
[`docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`](docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md).

**For a handoff summary:** [`docs/HANDOFF_2026_08_04.md`](docs/HANDOFF_2026_08_04.md).

---

## Cluster (GCP)

| Node | VM | vCPU | Role |
|------|----|------|------|
| control-plane | `netpoke-control` | 2 | Runs `kubectl`, `main.py`, all scripts |
| worker1–3 | `netpoke-worker1/2/3` | 2 each | Service pods + `wrk` client |
| loadgen | `netpoke-loadgen` | 4 | Disabled (`ENABLE_LOADGEN=0`) |

Managed from **Google Cloud Shell**. Scripts in `netpoke/infra/gcp/`.

---

## The 6 runs at a glance

| Run | Condition | Level | Core question |
|-----|-----------|-------|---------------|
| 1 | SIGSTOP-only | L0 | What is SlowPoke's baseline accuracy? |
| 2 | NetPoke-on | L0 | Does NetPoke cost accuracy when there's no I/O problem? |
| 3 | SIGSTOP-only | L1 | How much does moderate I/O stress hurt accuracy? |
| 4 | NetPoke-on | L1 | Does NetPoke recover that accuracy? |
| 5 | SIGSTOP-only | L2 | How much does heavy I/O stress hurt accuracy? |
| 6 | NetPoke-on | L2 | Does NetPoke recover that accuracy? (**core thesis result**) |

---

## Key scripts

| Script | Purpose |
|--------|---------|
| `netpoke/infra/gcp/start_cluster_vms.sh` | Start stopped VMs |
| `netpoke/infra/gcp/01_create_cluster.sh` | Create VMs from scratch |
| `netpoke/infra/gcp/02_initialize_cluster.sh` | Install Kubernetes on all nodes |
| `netpoke/infra/gcp/sync_to_control.sh` | Push `slowpoke/` to control node |
| `netpoke/infra/gcp/03_teardown.sh` | Delete all VMs |
| `slowpoke/evaluation/phase5_netpoke/patch_all_netpoke_yamls.sh` | Generate `netpoke/` and `netpoke-sigstop/` yaml dirs |
| `slowpoke/evaluation/io_gap/apply_io_injection.sh` | Inject netem delay (bug fixed) |
| `slowpoke/evaluation/run_with_monitor.sh` | Run experiment with live progress |
| `slowpoke/evaluation/run_netpoke_l0_overhead.sh` | Run 2 (NetPoke-on L0) |
| `slowpoke/evaluation/io_gap/run_io_medium.sh` | Runs 3–6 (L1/L2 per app) |
| `slowpoke/evaluation/io_gap/run_io_gap_netpoke_L2.sh` | Run 6 (NetPoke-on L2, all apps) |
| `slowpoke/evaluation/summarize_results.py` | Extract RMSE from a log file |
| `slowpoke/evaluation/watch_progress.sh` | Live progress dashboard (SSH 2) |

---

## Results layout

| Path | Content |
|------|---------|
| `netpoke/results/cluster/baseline/` | Table B1 — SIGSTOP-only L0 RMSE |
| `netpoke/results/cluster/io_gap/` | Tables I1 — I/O-gap RMSE matrix |
| `netpoke/results/cluster/netpoke/` | Tables N1–N3 — NetPoke results |
| `netpoke/results/reference/` | Paper-format reference figures |
