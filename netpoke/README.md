# NetPoke

[Overview](#overview) | [Current status](#current-status) | [Replicating the experiments](#replicating-the-experiments) | [Repository structure](#repository-structure) | [Key documents](#key-documents)

NetPoke extends **SlowPoke** (Xie et al., NSDI 2026) so that its throughput
predictions stay accurate for **I/O-bound** microservices, not only
compute-bound ones.

- **Student:** Afram Visca Gyebi
- **Supervisor:** Dr. (Mrs.) Rose-Mary Mensah Gyening
- **Programme:** MPhil Computer Science, Kwame Nkrumah University of Science
  and Technology (KNUST), Kumasi, Ghana
- **Base paper:** [`../slowpoke_nsdi_2026.pdf`](../slowpoke_nsdi_2026.pdf)

## Overview

SlowPoke predicts end-to-end throughput of a microservice graph by pausing
non-target services with `SIGSTOP`/`SIGCONT` (via its `poker` controller) and
extrapolating from how the target's throughput changes. `SIGSTOP` freezes a
process's CPU scheduling, but the Linux kernel keeps servicing that process's
network sockets while it is stopped — buffered reads/writes and TCP ACKs
continue. For CPU-bound services this residual I/O is negligible and the
model holds; for **I/O-bound** services it is not, and predictions degrade.

NetPoke closes that gap by holding a paused service's **network egress** for
exactly the same window its process is stopped, so the pause is complete
end-to-end. The mechanism is a Linux `sch_plug` queueing discipline (`tc`
qdisc), driven directly from inside `poker` over an `AF_NETLINK` socket —
**not** a sidecar container and **not** a fixed configured delay: the hold is
armed and released in lock-step with each real `SIGSTOP`/`SIGCONT` pair.

## Current status

| Phase | What it does | Status |
|-------|---------------|--------|
| 1 — SlowPoke baseline (§5.1/Fig. 8) | Reproduce paper's RMSE, all 4 apps | **Complete** (re-run 2026-07) |
| 3 — I/O-gap injection | Static `netem` delay as an indirect I/O-sensitivity probe | **Complete**, 8/8 runs — noisy proxy, see caveat below |
| 6 — Residual I/O (Table N1) | Direct in-pod measurement of bytes leaking through real pause windows, SIGSTOP-only vs NetPoke-on | **Complete**, all 4 apps at L2 + boutique L0 overhead check |
| 5/6 — RMSE restoration (Table N2) | Same L2 accuracy benchmark as Phase 3, SIGSTOP-only vs NetPoke-on | **Complete**, all 4 apps |
| L0 RMSE overhead (Table N3) | Same accuracy benchmark, no injection, SIGSTOP-only vs NetPoke-on | **Complete**, all 4 apps |

**Headline result (Table N1):** with NetPoke on, residual network I/O during
pause windows drops in 3 of 4 apps — hotel ~2.9x, social ~2.2x, movie ~4.3x —
measured directly from POKER's own pause-window timestamps, not inferred from
an RMSE proxy. Boutique's residual-*bytes* stay flat at L0 (no regression at
the byte level) — but see Table N3 below, which found a real cost at the
*RMSE* level that the byte-level check didn't catch. Full numbers, coverage,
and caveats:
[`results/cluster/netpoke/tables/TABLE_RESIDUAL_MATRIX.md`](results/cluster/netpoke/tables/TABLE_RESIDUAL_MATRIX.md).

**Headline result (Table N2):** that residual-I/O reduction translates into
restored prediction accuracy. Social — the cleanest I/O-gap case, where
SIGSTOP-only L2 RMSE spiked to 33.61% from a 14.01% baseline — drops to
18.69% with NetPoke on, recovering 76% of the gap. Hotel and movie also
improve, landing at or below their own baselines. Boutique, which never had
a real I/O gap to close, gets worse (3.53% → 10.26%) — a genuine regression,
not smoothed over. Full numbers and caveats:
[`results/cluster/netpoke/tables/TABLE_N2_RMSE_COMPARISON.md`](results/cluster/netpoke/tables/TABLE_N2_RMSE_COMPARISON.md).

**Important methodological note:** Phase 3's `netem`-based I/O-gap RMSE is an
indirect, noisy proxy — hotel's Phase 3 result even reversed direction between
runs, while hotel's *direct* residual-I/O measurement (Table N1) is a normal,
consistent result matching social and movie. The direct residual-I/O
measurement is the more trustworthy signal; see the "Live status log" in
[`docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`](docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md)
for the full investigation.

**Why boutique is different (resolved):** traced directly in source — boutique's
`cart` target handles requests entirely from an in-process `sync.Map`, with
zero synchronous network calls in its live code path (a Redis client and
state-store call exist in the file but are dead code). Hotel/movie/social's
targets all make at least one real network round-trip (a Dapr state-store
call, and for movie/social an explicit HTTP call to another service). There
was never an I/O gap for boutique to have.
Full trace: [`results/cluster/netpoke/tables/BOUTIQUE_FANOUT_FINDING.md`](results/cluster/netpoke/tables/BOUTIQUE_FANOUT_FINDING.md).

**Headline result (Table N3):** boutique's regression isn't specific to L2 — it
costs almost exactly the same at baseline with no injection at all (+6.56pp
at L0 vs +6.73pp at L2 in Table N2), a second, independent measurement
consistent with the fan-out finding: nothing to fix, so the mechanism's
per-pause overhead shows up as pure cost. Movie is the cleanest opposite
case — flat at L0 (−0.08pp), largest recoverer at L2 — a small, roughly
constant cost that's negligible without a real gap and outweighed by a large
benefit when there is one. Full numbers and caveats:
[`results/cluster/netpoke/tables/TABLE_N3_L0_OVERHEAD.md`](results/cluster/netpoke/tables/TABLE_N3_L0_OVERHEAD.md).

**Still open:** all figures above are single-run measurements; repeating key
runs to separate signal from this cluster's known run-to-run noise
(especially hotel — its L0 RMSE alone has already moved 10.23%→20.65%
between two runs with nothing else changed) is the natural next step before
treating exact magnitudes as final.

## Replicating the experiments

Everything runs on a GCP Kubernetes cluster built from SlowPoke's own setup
scripts. Full step-by-step commands (functional smoke test → SlowPoke
baseline → I/O-gap matrix → residual-I/O matrix) live in
[`INSTRUCTIONS.md`](INSTRUCTIONS.md) — start there.

**Two-window monitoring pattern**, used for every run no matter how short:

```bash
# SSH window 1 — runs the experiment inside a detached screen session
screen -S <name>
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./run_with_monitor.sh <script>.sh
# Ctrl+A D to detach — leave it detached; screen keeps running and draining

# SSH window 2 — live, accumulating dashboard (does not clear the screen)
cd ~/slowpoke/evaluation
./watch_progress.sh --append results/
```

Residual-I/O checks specifically (Table N1):

```bash
cd ~/slowpoke/evaluation
bash phase6_netpoke/run_residual_check.sh <bench> L2 full 0   # SIGSTOP-only
bash phase6_netpoke/run_residual_check.sh <bench> L2 full 1   # NetPoke-on
python3 phase6_netpoke/correlate_residual.py results/residual/<outdir> [--netpoke]
```

Pack and download results:

```bash
bash scripts/pack_results_for_repo.sh
gcloud compute scp --zone=us-central1-a \
  aframviscagyebi@netpoke-control:~/netpoke_results_pack_*.tar.gz .
```

**Repeated trials from a cold cluster:** full step-by-step commands for every run, every time,
including a verification step for an injection-yaml bug found and fixed while writing this:
[`docs/EXPERIMENT_RUNBOOK.md`](docs/EXPERIMENT_RUNBOOK.md).

## Repository structure

* [`thesis/`](thesis/) — thesis chapters and drafts (writing happens on branch
  `netpoke/thesis-material`; results referenced from `netpoke/results/`).
* [`design/poker-io-pause.md`](design/poker-io-pause.md) — design for the
  synchronised network hold inside POKER (the core contribution).
* [`infra/gcp/`](infra/gcp/) — scripts/runbook for the GCP measurement
  cluster, reusing SlowPoke's own setup scripts.
* [`results/`](results/) — reference (paper-format) and cluster (this
  project's own) logs, figures, and tables. See
  [`results/README.md`](results/README.md) for the layout.
* [`docs/`](docs/) — see [Key documents](#key-documents) below.
* `../slowpoke/` — the SlowPoke artifact itself (application code, `poker`
  controller, evaluation scripts), with NetPoke's changes on top. See
  [`../slowpoke/README.md`](../slowpoke/README.md).

## Key documents

| Document | What it's for |
|----------|----------------|
| [`INSTRUCTIONS.md`](INSTRUCTIONS.md) | Step-by-step reproduction commands |
| [`docs/EXPERIMENT_RUNBOOK.md`](docs/EXPERIMENT_RUNBOOK.md) | Exact commands for a fresh, repeatable run from a cold cluster |
| [`docs/ARCHITECTURE_AND_COST_COMPARISON.md`](docs/ARCHITECTURE_AND_COST_COMPARISON.md) | SlowPoke's reference cluster vs. this project's, and why the sizing difference matters |
| [`docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`](docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md) | **Canonical reference**: findings, fix plan, dated Live status log |
| [`docs/slowpoke-paper-deep-dive.md`](docs/slowpoke-paper-deep-dive.md) | Self-contained study guide to the SlowPoke paper/artifact |
| [`results/cluster/netpoke/tables/TABLE_RESIDUAL_MATRIX.md`](results/cluster/netpoke/tables/TABLE_RESIDUAL_MATRIX.md) | Table N1: residual-I/O reduction |
| [`results/cluster/netpoke/tables/TABLE_N2_RMSE_COMPARISON.md`](results/cluster/netpoke/tables/TABLE_N2_RMSE_COMPARISON.md) | Table N2: end-to-end RMSE restoration |
| [`docs/deprecated/`](docs/deprecated/README.md) | Superseded planning docs, kept for history |

## Current decisions (canonical)

- Mechanism: perfect pause via egress hold (`sch_plug`), integrated into
  POKER and synchronised with each `SIGSTOP`/`SIGCONT`. Throttle and
  static-delay variants exist only as comparison baselines.
- Cluster: 8 GCP VMs (1 control + 1 load-generator + 6 service workers), torn
  down between experiment batches to stay within budget.
- Referencing: APA 7th. Spelling: British.
