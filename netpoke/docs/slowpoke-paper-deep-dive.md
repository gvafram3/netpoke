# SlowPoke Paper — Deep Study Guide

**Paper:** SlowPoke: End-to-end Throughput Optimization Modeling for Microservice Applications (Xie et al., NSDI 2026)

**Purpose of this document:** A self-contained, detailed explanation of the SlowPoke paper and artifact, from first principles through implementation details. Written for the NetPoke thesis evaluation programme. Every major technical term is explained.

**Repository:** gvafram3/netpoke (branch `netpoke/experiments`)

**Companion files:** `slowpoke/INSTRUCTIONS.md`, `netpoke/INSTRUCTIONS.md`, `netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`

---

## How to use this guide

Read in order. Early sections use plain language; later sections add math, code paths, and log semantics. Skim the **Glossary** first if you are unfamiliar with microservices or causal profiling.

**Suggested reading path:**

1. Part A (Levels 0–2) — intuition
2. Part B (Sections 1–5) — paper structure
3. Part C — artifact and your cluster
4. Part D — glossary and log field reference
5. Part E — connection to NetPoke thesis experiments

---

# Part A — Intuition before formalism

## Level 0 — One sentence

**SlowPoke predicts how much whole-application throughput (requests per second at the frontend) would increase if you optimized one microservice—without implementing that optimization first.**

## Level 1 — Restaurant analogy

Imagine a restaurant:

- **Stations** = microservices (grill, salad bar, cashier, delivery desk).
- **Customers** arrive at the door = HTTP requests hit the **frontend**.
- **Throughput** = how many customers per hour the restaurant can serve under load (not how long one customer waits in line).

**Question:** If we make the grill 30% faster, how many more customers per hour can we serve?

| Approach | Idea | Drawback |
|----------|------|----------|
| Build it and measure | Actually upgrade the grill, run for weeks | Expensive, slow |
| Distributed tracing | Record every order’s path through stations | Needs instrumentation; tells past latency paths, not always throughput what-if |
| **Causal profiling (SlowPoke)** | **Slow every other station** by a calculated amount; measure throughput; infer what speeding the grill would do | Needs a mechanism that preserves bottleneck structure |

**Causal profiling** (Curtsinger & Berger, 2015, single-machine) inverts the problem: instead of speeding code up before it exists, **slow everything else down** in a controlled way. The relative bottleneck relationships are preserved, so the slowed system behaves like the sped-up one—in principle.

SlowPoke extends this to **many machines**, **network calls**, and predicts **throughput**, not just CPU time in one process.

## Level 2 — Why microservices make this hard

1. **Shared resources** — CPU, network links, connection pools. Optimizing service A can move the bottleneck to service B.
2. **Call graph complexity** — fan-out (one request → many downstream calls), optional paths, retries. The “critical path” changes per request type.
3. **Metric choice** — operators often need **sustained req/s** under load (capacity), not only p99 latency of individual requests.
4. **No tracing assumption** — SlowPoke deliberately avoids requiring a pre-built service graph or full distributed trace at profiling time. It learns **request ratios** during a prerun instead.

---

# Part B — Paper section by section

The artifact maps paper contributions as follows (from `slowpoke/INSTRUCTIONS.md`):

| Paper section | Contribution |
|---------------|--------------|
| **§2** | Throughput predictor — the SlowPoke **system** |
| **§3** | Performance **model** (mathematics) |
| **§4** | **POKER** — distributed slowdown mechanism |
| **§5** | **Evaluation** — four real apps + synthetic benchmarks |

---

## Section 1 — Introduction and problem (motivation)

### The operational question

Engineers ask: **Given limited optimization budget, which service should we improve to raise end-to-end throughput the most?**

This is harder than it sounds because:

- Services are **coupled** through dependencies and shared resources.
- Improving a service **off the critical path** yields little benefit; the bottleneck moves.
- You want an answer **before** writing code.

### What SlowPoke contributes at a high level

1. A **performance model** relating per-service processing time to application throughput.
2. A **distributed slowdown mechanism** (POKER) that implements artificial slowdown on non-target services.
3. An **orchestrator** that runs ground-truth and slowdown experiments and applies the model to **predict** throughput.
4. **Evaluation** showing low prediction error (~2% RMSE reported) on four real-world benchmarks.

### Throughput vs latency

| Term | Meaning |
|------|---------|
| **Throughput** | Number of completed requests per unit time (e.g. req/s) at a boundary (usually frontend) under sustained load. |
| **Latency** | Time for one request to complete (e.g. milliseconds). |

SlowPoke targets **throughput optimization modeling**: “If cart were faster, how many more req/s can boutique sustain?” Latency-focused tools (critical path analysis, LatenSeer) answer different questions.

### What “optimization” means in experiments

Not “buy bigger VMs.” In SlowPoke experiments, **optimization** means **reducing simulated per-request processing time** on the **target service** via environment variable `SLOWPOKE_PROCESSING_MICROS_<SERVICE>`. The sweep runs from 0% to 90% of baseline processing time in steps (10 points in medium runs).

**Ground truth experiment:** actually apply that reduced processing time on the target.

**Slowdown experiment:** restore target to baseline; pause non-target services so the system should behave similarly to the optimized case—if the mechanism is correct.

---

## Section 2 — The throughput predictor (system architecture)

### Simple view

SlowPoke is three cooperating layers:

1. **Orchestrator** (`slowpoke/src/main.py`, `config.py`) — plans experiments, computes delays, applies prediction formula.
2. **Cluster runtime** (`slowpoke/src/run.sh`, Kubernetes YAMLs, `wrk` client) — deploys apps, generates load, collects timings.
3. **POKER** (`slowpoke/src/poker/poker.c`, Go wrappers) — executes pauses inside each service pod.

### End-to-end experiment flow

```
Prerun (optional) → learn request_ratio per service
For each optimization level i = 0..90%:
    1. Ground truth run  → throughput G_i
    2. Slowdown run      → throughput S_i  (POKER pauses on non-targets)
    3. Predict           → P_i = f(S_i, delay_i)  from §3 model
    4. Error_i = (P_i - G_i) / G_i × 100%
Aggregate → RMSE over 10 points; plot Fig. 8
```

### Key artifact command

```bash
python3 main.py -b boutique -x cart -r mix -t 8 -c 1024 \
  --num_exp 10 --num_req 100000 --poker_batch_req 100
```

| Flag | Meaning |
|------|---------|
| `-b boutique` | Benchmark application (hotel, social, movie, …) |
| `-x cart` | **Target service** — the one whose optimization you hypothesize |
| `-r mix` | Request mix (workload script for wrk) |
| `-t`, `-c` | wrk threads and connections |
| `--num_exp 10` | Ten optimization points (0%, 10%, …, 90%) |
| `--num_req 100000` | Requests per wrk measurement |
| `--poker_batch_req 100` | Batch pauses per N requests (POKER tuning) |

### Prerun and request_ratio

During **prerun**, SlowPoke collects how often each service participates in serving requests. Stored as **request_ratio** in logs:

```text
request_ratio : {'frontend': 1.0, 'cart': 0.45, 'product_catalog': 0.61, ...}
```

| Field | Interpretation |
|-------|----------------|
| `frontend: 1.0` | Every request hits the frontend. |
| `cart: 0.45` | Fraction of “service work units” involving cart on the path. |
| `product_catalog: 0.61` | Heavier involvement on catalog path (boutique cart target). |

The model uses these ratios to **scale pause delays** across non-target services so that slowing them emulates removing time from the target.

**Technical term — fan-out:** One incoming request triggers multiple downstream internal requests. Request ratios encode this aggregate involvement.

### Three curves per benchmark (Fig. 8)

| Curve | Source experiment | Role |
|-------|-------------------|------|
| **Ground truth** | Target processing time reduced | “True” optimized throughput |
| **Slowdown** | Target at baseline; others paused | Physical emulation via POKER |
| **Predicted** | Formula from slowdown + delay | Model output; should track ground truth |

### Workload count (why 21?)

Per medium benchmark log:

- 1 baseline wrk run
- 10 optimization points × (1 ground truth + 1 slowdown) = 20 runs
- **Total = 21** `[exp] Throughput:` lines

Your monitor’s `workloads 21/21` refers to this.

### Services supported

Artifact uses **Go microservices** wrapped with SlowPoke runtime (`app/pkg/slowpoke`, `app/pkg/wrapper`). Images named `*-pokerpp` run the app as child of `poker` binary.

---

## Section 3 — The performance model (mathematics)

### Core assumption (bottleneck equivalence)

When non-target services are paused correctly, the **bottleneck structure** of the slowed system matches the system where the target was truly optimized. Then one measurement (slowdown throughput) plus algebra predicts the optimized throughput.

If pauses are **incomplete** (e.g. network I/O continues during SIGSTOP), this assumption fails—your thesis Phase 3 measures that.

### Per-request processing time

Each service has **baseline processing time** (microseconds of simulated work per request), from `analysis.txt` / config:

```text
baseline_service_processing_time : {'cart': 1000, 'product_catalog': 0, ...}
```

For ground truth at optimization level with target time `p_t`:

- Target service uses `p_t` (lower = faster).
- Others stay at baseline.

### Delay on non-target services (slowdown experiment)

From `main.py` (conceptual):

```
delay[service] = (T_baseline - T_opt) × request_ratio[target] × cpu_quota[service]
                 ─────────────────────────────────────────────────────────────────
                 request_ratio[service] × cpu_quota[target]
```

Where:

- `T_baseline - T_opt` = amount of per-request time “removed” in the hypothetical optimization on the target.
- **cpu_quota** = Kubernetes CPU limit factor per service (from YAML); scales delays when services have different CPU caps.

Services with `request_ratio[service] == 0` get **zero delay** (not on path).

**Technical term — cgroup / CPU quota:** Linux control groups limit CPU; `cpu_quota: 2` in logs means relative share used in delay normalization.

### Prediction formula (implemented)

After slowdown throughput `S` is measured:

```
delay_target = (T_baseline - T_opt) × request_ratio[target] / cpu_quota[target]

predicted_throughput = 1 / ( 1/S - delay_target )
```

(in consistent time units; code uses microseconds in delay path.)

**Intuition:** Work at the application boundary has an effective “seconds per unit progress” of `1/S`. The optimization removes `delay_target` from the target’s contribution per unit progress. Subtract and invert to get predicted throughput.

**Technical term — harmonic / inverse-rate form:** Throughput composes like parallel bottlenecks; the implementation uses inverse throughput (time per completed app-level work) for a simple scalar model.

### Error metric

Per point:

```
error% = (predicted - groundtruth) / groundtruth × 100
```

**RMSE (root mean square error):** `sqrt(mean(error%²))` over the 10 points—single summary number for a benchmark run. Paper reports ~2.07% aggregate; your cluster L0 values are ~9–14% (fewer repetitions, smaller cluster—expected).

### What the model does NOT do

- Does not model disk I/O explicitly.
- Does not change network topology.
- Does not require explicit call graph—only ratios and per-service CPU quotas.
- Does not guarantee accuracy when POKER pauses do not match real resource removal (I/O gap).

---

## Section 4 — POKER: distributed slowdown mechanism

### Role

POKER is the **actuator** for §3: it turns computed delays into **real time removed** from non-target services during requests.

### Process architecture

Each service pod:

```
poker (parent, C)  →  SIGSTOP/SIGCONT  →  Go microservice (child)
         ↑
    FIFO pause commands
    ZMQ coordination with neighbors
```

**Files:**

- `slowpoke/src/poker/poker.c` — pause loop
- `app/pkg/slowpoke/pause.go` — Go integration
- Yamls — `SLOWPOKE_DELAY_MICROS_*`, ports 5550/5551 for ZMQ

### What happens on each pause

1. Model/runtime decides this service should accumulate pause time.
2. POKER receives batched pause duration.
3. `kill(-child_pgid, SIGSTOP)` — freeze **user-space** execution of service process group.
4. `precise_sleep(duration)` — hold.
5. `kill(-child_pgid, SIGCONT)` — resume.

**Technical term — SIGSTOP / SIGCONT:** POSIX signals that stop and continue a process. SIGSTOP cannot be caught by the application; the scheduler does not run user code on that process while stopped.

**Technical term — process group:** `kill(-child_pgid, …)` stops the service and its child threads together.

### Batching

Per-request SIGSTOP would dominate overhead. Environment variables:

- `SLOWPOKE_POKER_BATCH_THRESHOLD` — pause batch size
- `SLOWPOKE_POKER_BATCH_REQ` — requests per batch window

### What SIGSTOP does and does NOT stop

| Stopped | NOT stopped |
|---------|-------------|
| User-space code in the service | Kernel network stack processing for open sockets |
| CPU time attributed to the process | Incoming packets accepted into socket buffers |
| | TCP acknowledgements from kernel |
| | Completion of some in-flight I/O |

**Paper’s acknowledged limitation:** Mechanism preserves **CPU-time bottlenecks** well; **network/disk bottlenecks** involve buffering in the kernel—pause is incomplete. Suggests sidecar netem or I/O throttling as future work.

**Your thesis:** Measure this gap (Phase 3 netem stress, Phase 4 eBPF), fix with NetPoke `sch_plug` (Phase 5–6).

### NetPoke extension (preview)

Hold **egress** with Linux `sch_plug` qdisc for the same window as SIGSTOP so network activity is also frozen—restores bottleneck equivalence for I/O-bound services. Design: `netpoke/design/poker-io-pause.md`.

---

## Section 5 — Evaluation

### Real-world benchmarks (Fig. 8)

| Application | Source | Typical target (`-x`) |
|-------------|--------|------------------------|
| Boutique | Google microservices demo | cart |
| Hotel | DeathStarBench hotel | profile |
| Social | DeathStarBench social | hometimeline |
| Movie | DeathStarBench media | moviereviews |

**Medium run** (~40–50 min per app): one repetition, 10 optimization points, 100k requests (movie may use 20k in your io_gap config).

**Artifact pass criterion:** `Error Perc:` in log; errors mostly within ~10%, often 0–4% per point (paper/artifact); outliers possible on noisy clusters.

### Synthetic benchmarks (Fig. 9, optional)

108 configurations under `evaluation/synthetic/` — chains, DAGs, sync/async, gRPC/HTTP. Emulator changes behavior from config files. Tests model across **topologies**, not only four real apps. Runtime: 2–3 days full suite.

### Fig. 8 how to read

- **X-axis:** % reduction in target service processing time (0% → 90%).
- **Y-axis:** Throughput (req/s).
- **Ground truth** should generally rise if target is on critical path.
- **Predicted** should overlay **ground truth** if model + POKER accurate.
- **Slowdown** curve shape should track ground truth if mechanism works.

`plot_macro.pdf` — macro comparison across all four apps (RMSE summary).

### Plotting on your cluster

```bash
cd ~/slowpoke/evaluation
python3 summarize_results.py results/*_medium.log
bash plot_fig8_png.sh results/
python3 plot_macro.py -r results/
```

### Your evaluation extensions (thesis phases)

| Phase | What | Relation to paper |
|-------|------|-------------------|
| **1 — L0** | Standard medium runs | Reproduce §5 baseline on GCP |
| **3 — I/O gap** | Same target; add netem on path services L1/L2 | Stress §4 assumption |
| **4 — eBPF** | Measure residual I/O during pauses at L2 | Explain §3–§4 mismatch |
| **5–6 — NetPoke** | sch_plug + re-run L2 | Proposed fix to §4 |

---

# Part C — Artifact and your GCP cluster

## Cluster layout

| Node | Role |
|------|------|
| netpoke-control | Kubernetes control plane, `main.py`, `kubectl` |
| worker1–3 | Service pods (boutique YAMLs pin services to nodes) |
| wrk client | `ubuntu-client` pod (often on worker1) |

`SLOWPOKE_TOP=~/slowpoke` on control node.

## run.sh lifecycle

1. Delete old deployments.
2. `envsubst` + `kubectl apply` benchmark yamls.
3. Deploy client if missing.
4. Wait pods Ready; heartbeat between services.
5. Run `wrk` from client pod against frontend.
6. Tear down (timing tied to pod lifetime).

**Known fix:** Rust proxy must use `nohup` (not blocking `kubectl exec`)—`install_netpoke_fixes.sh` checks this.

## Log file anatomy

Top of log — experiment metadata:

```text
benchmark                        : boutique
target_service                   : cart
request_ratio                    : {...}
baseline_service_processing_time : {...}
cpu_quota                        : {...}
target_num_exp                   : 10
```

During run — `[run.sh]`, `[test.py]`, `[exp] Throughput:` lines.

End — Summary:

```text
Groundtruth:  [...]
Slowdown:     [...]
Predicted:    [...]
Error Perc:   [...]
```

## I/O-gap logs

Phase 3 logs named `boutique_io_L1_medium.log`, etc. Header includes:

```text
# io_gap run: benchmark=boutique level=L1 target=cart inject=productcatalog:30
```

L1/L2 apply **tc netem sidecars** on path services—**stimulus** to increase synchronous I/O, not the NetPoke fix.

---

# Part D — Glossary of technical terms

| Term | Definition |
|------|------------|
| **Microservice** | Independently deployable service owning a bounded capability; communicates over network. |
| **Frontend** | Edge service receiving external HTTP requests (boutique: `frontend`). |
| **Throughput** | Completed requests per second under load. |
| **Latency** | Time to complete one request. |
| **Bottleneck** | Resource or stage limiting system throughput or latency. |
| **Critical path** | Sequence of stages determining end-to-end time for a request. |
| **Causal profiling** | Infer effect of speeding region X by slowing everything else. |
| **Ground truth** | Measured outcome with real optimization applied. |
| **Slowdown experiment** | Measured outcome with POKER pauses instead of real optimization. |
| **request_ratio** | Estimated fraction of work involving each service. |
| **Processing time** | Simulated per-request compute time (microseconds) in SlowPoke wrapper. |
| **POKER** | Pause controller process (C) wrapping each service. |
| **SIGSTOP / SIGCONT** | Unix stop/continue signals for processes. |
| **wrk** | HTTP load generator used in client pod. |
| **Kubernetes (K8s)** | Container orchestration platform deploying pods/services. |
| **Pod** | One or more containers scheduled together on a node. |
| **Sidecar** | Auxiliary container in same pod (e.g. tc-netem for delay injection). |
| **netem** | Linux traffic control module emulating network delay/loss. |
| **tc** | Linux traffic control (`tc qdisc`, `tc-netem`). |
| **RMSE** | Root mean square error of prediction error percentages. |
| **DeathStarBench** | Open microservice benchmark suite (hotel, social, movie). |
| **Online Boutique** | Google microservices demo (boutique). |
| **Prerun** | Phase collecting request ratios before main sweep. |
| **Optimization point** | One step in 0%..90% processing time reduction sweep. |
| **I/O-bound service** | Throughput limited by network/disk waits, not CPU. |
| **Compute-bound service** | Throughput limited primarily by CPU. |
| **eBPF** | Kernel instrumentation for measuring syscalls/bytes without kernel modules. |
| **sch_plug** | Linux qdisc buffering egress until release (NetPoke). |
| **Phase 3 L0/L1/L2** | Baseline / moderate path I/O / heavy path I/O experiment levels. |

---

# Part E — NetPoke thesis connection

## Research problem

SlowPoke’s pause is incomplete for I/O-bound services → prediction error grows when services do heavy synchronous network/DB work.

## Your objectives mapped to paper

| Objective | Paper anchor |
|-----------|--------------|
| Measure error vs I/O intensity | §5 extension — Phase 3 matrix |
| Kernel evidence during pause | §4 limitation — Phase 4 eBPF |
| NetPoke coordinated network hold | §4 future work — Phase 5–6 |
| Re-evaluate accuracy | New §5-style curves with NetPoke |

## Boutique re-run rationale

Original Phase 3 boutique L1/L2 used **shipping** netem (~10% cart path traffic). Re-run uses **product_catalog** (~61%) + **currency** on L2—aligned with cart target causal path.

## Interpreting boutique vs other apps

If boutique RMSE does not rise at L1/L2 while hotel/social/movie do, discuss: workload mix, how much cart path is I/O vs CPU bound, whether netem changes bottleneck identity—not only “wrong injection site.”

---

# Appendix A — Commands reference

## Verify complete benchmark log

```bash
grep -c '\[exp\] Throughput:' results/boutique_medium.log   # expect 21
grep 'Error Perc:' results/boutique_medium.log
```

## I/O-gap matrix

```bash
python3 io_gap/summarize_io_gap_matrix.py results/
```

## Pack for repo download

```bash
bash scripts/pack_results_for_repo.sh
```

## Cloud Shell download

```bash
gcloud compute scp --zone=us-central1-a \
  aframviscagyebi@netpoke-control:~/netpoke_results_pack_*.tar.gz .
```

---

# Appendix B — Document revision

| Version | Date | Notes |
|---------|------|-------|
| 1.0 | June 2026 | Initial deep-dive for NetPoke thesis programme |

---

# Appendix C — Extended deep dives

## C.1 Two-service chain example (toy model)

Consider the simplest non-trivial app: **Frontend → Service B → response**.

Suppose:

- Baseline processing time: Frontend 0 µs (negligible), Service B 1000 µs per request.
- Target service: **B**.
- Optimization: reduce B from 1000 µs to 700 µs (30% reduction).
- request_ratio: frontend 1.0, B 1.0 (every request hits B once).

**Ground truth experiment:** Set `SLOWPOKE_PROCESSING_MICROS_B=700`, measure throughput G. Higher than baseline because B is faster.

**Slowdown experiment:** Restore B to 1000 µs. Pause Frontend (non-target) during requests so that the **effective** time removed from the pipeline matches what optimizing B would have done. POKER pauses the frontend process while B still runs at baseline speed—but the **intent** is that the queueing interaction produces the same end-to-end rate as if B were faster.

**Prediction:** Measure slowdown throughput S. Compute delay term from the 300 µs optimization equivalent. Apply `P = 1/(1/S - delay)`. Compare P to G.

If pauses only remove CPU from Frontend but Frontend was waiting on network I/O to B, the emulation fails—this is the I/O-gap story in miniature.

## C.2 One optimization point timeline (what the cluster does)

For boutique, optimization point 30% (example):

1. **main.py** sets processing times and delays for this point.
2. **run.sh** deletes prior K8s objects, applies yamls with new env vars.
3. Pods start; **heartbeat** checks services respond.
4. **Warmup wrk** runs (short duration)—may show `Socket errors: connect N` while settling.
5. **Measured wrk** runs for `num_req` requests; times collected.
6. Throughput = `num_req / mean(latency list)`.
7. Tear down; repeat for ground truth then slowdown.

Each point is **two full deploy cycles** (ground + slow)—why one benchmark takes ~40–50 minutes.

## C.3 Why three measurements instead of one?

| If you only had… | Problem |
|------------------|---------|
| Ground truth only | You must implement every optimization level—defeats prediction purpose. |
| Slowdown only | You do not know if slowdown matched optimization without a model. |
| Model without slowdown | No physical measurement to anchor prediction. |

The **triplet** (G, S, P) lets you validate both **model** (P vs G) and **mechanism** (S curve shape vs G).

## C.4 Related work positioning (paper context)

| System / paper | Question answered |
|----------------|-------------------|
| **Coz** (Curtsinger & Berger) | Which **code regions** matter on one machine? |
| **SlowPoke** | Which **services** matter for **throughput** in distributed apps? |
| **CRISP** | Where is latency critical path in microservices? |
| **LatenSeer** | End-to-end **latency distribution** from traces? |
| **Autothrottle** | How to allocate resources for SLOs? |

SlowPoke is unique in **throughput what-if without prior call graph**.

## C.5 Each benchmark in one paragraph

**Boutique (Online Boutique):** E-commerce microservices demo—frontend, cart, product catalog, checkout, payment, shipping, etc. Target **cart** for Fig. 8. Mixed read-heavy workload (`mix.lua`). Good for realistic fan-out to catalog and currency.

**Hotel (DeathStarBench):** Hotel reservation app—search, profile, rate, geo, etc. Target **profile**. Represents tourism/booking style DAG.

**Social (DeathStarBench):** Social network timelines—compose post, home timeline, social graph, post storage. Target **hometimeline**. Heavy fan-out and storage services.

**Movie (DeathStarBench):** Movie review pipeline—reviews, storage, movie info, compose. Target **moviereviews**. Storage and metadata services on path.

## C.6 Environment variables (complete list for experiments)

| Variable | Set by | Purpose |
|----------|--------|---------|
| `SLOWPOKE_DELAY_MICROS_<SVC>` | main.py | Pause budget communicated to POKER |
| `SLOWPOKE_PROCESSING_MICROS_<SVC>` | main.py | Simulated service work per request |
| `SLOWPOKE_IS_TARGET_SERVICE_<SVC>` | main.py | 1 if target, 0 otherwise |
| `SLOWPOKE_POKER_BATCH_THRESHOLD_<SVC>` | main.py / yaml | Batch size for pauses |
| `SLOWPOKE_PRERUN` | main.py | Enable ratio collection phase |
| `SLOWPOKE_SERV_NAME` | yaml | Service identity in pod |
| `SLOWPOKE_TOP` | you | Root path to slowpoke tree |

## C.7 ZMQ ports in boutique yamls

Services expose ports **5550** and **5551** for POKER neighbor coordination—pause propagation across dependent services in the same request chain. **Technical term — ZeroMQ (ZMQ):** messaging library for inter-process coordination without heavy RPC.

## C.8 Reading Error Perc signs

| Error sign | Typical reading |
|------------|-----------------|
| Near 0% | Good prediction at that optimization point. |
| Positive | Predicted **higher** than ground truth (over-prediction). |
| Negative | Predicted **lower** than ground truth (under-prediction). |
| I/O-gap hypothesis | Systematic **positive** error when I/O-bound—slowdown leaves more capacity than model assumes. |

RMSE aggregates magnitude across points; sign can cancel in mean but RMSE penalizes large misses.

## C.9 Paper RMSE ~2% vs your cluster ~9–14%

Reasons your L0 numbers may be higher (not necessarily “wrong”):

1. **Single repetition** vs paper’s multiple repetitions and central points.
2. **Smaller cluster** (3 workers vs 12)—more resource contention noise.
3. **Different absolute throughputs**—sensitivity to wrk and kube scheduling.
4. **Shipping/yaml fixes** and proxy fixes applied on your tree.

Compare **relative** trends (L2 vs L0) on the **same cluster** for thesis claims.

## C.10 Phase 3 netem injection (not NetPoke)

**Purpose:** Deliberately add synchronous network delay on **downstream path services** while keeping the same `-x` target. If SIGSTOP-only slowdown is incomplete under I/O, **RMSE should rise** from L0 to L1/L2.

**Not** the proposed fix—only a **stimulus** to expose §4 weakness. NetPoke `sch_plug` is the synchronized fix (Phase 5).

## C.11 Phase 4 eBPF (planned)

Measure during POKER pause windows:

- Bytes still received/sent on pod interface
- Syscall counts (`read`, `write`, `recvfrom`, …) while process is SIGSTOP’d

Correlate residual I/O with Error % from Phase 3. Runs at **L2** configs (heaviest I/O).

## C.12 Frequently asked questions

**Q: Why SIGSTOP instead of sleep in Go code?**  
A: Precise, uniform pause of entire process group without modifying every code path; works across unmodified service logic inside wrapper.

**Q: Does SlowPoke need a service mesh?**  
A: No—Istio may be on cluster but core mechanism is POKER + env vars, not mesh rules.

**Q: Can it predict latency?**  
A: Not primary output—throughput under load is the modeled metric.

**Q: What if target is wrong?**  
A: Optimizing off critical path yields flat ground truth curve—prediction errors may still be low but optimization irrelevant.

**Q: Why 0–90% sweep?**  
A: Shows model accuracy across small and large hypothetical optimizations—not only one point.

## C.13 Checklist: is my run valid?

- [ ] Log has 21 `[exp] Throughput:` lines (medium)
- [ ] `Error Perc:` with 10 values
- [ ] `request_ratio` present at log head
- [ ] File size roughly 100–200 KB (not a few KB truncated)
- [ ] For io_gap: header shows correct `inject=...`
- [ ] `install_netpoke_fixes.sh` passed before multi-benchmark runs

## C.14 After boutique L2 completes — sync workflow

On **netpoke-control**:

```bash
cd ~/slowpoke/evaluation
grep 'Error Perc:' results/boutique_io_L2_medium.log
python3 io_gap/summarize_io_gap_matrix.py results/
python3 io_gap/plot_io_gap_rmse.py results/
bash scripts/pack_results_for_repo.sh
```

On **Cloud Shell** (download):

```bash
gcloud compute scp --zone=us-central1-a \
  aframviscagyebi@netpoke-control:~/netpoke_results_pack_*.tar.gz .
```

Unpack into repo:

```text
netpoke/results/cluster/io_gap/logs/     ← boutique_io_L1/L2_medium.log
netpoke/results/cluster/io_gap/figures/  ← fig_io_gap_rmse.png
netpoke/results/cluster/io_gap/tables/   ← update TABLE_IO_GAP_MATRIX.md
```

Commit on `netpoke/experiments` and push.

## C.15 Way forward after Phase 3 matrix is final

1. **Commit** boutique L1/L2 + full matrix to repo.
2. **Phase 4 eBPF** — all four apps at L2 (social first—largest gap).
3. **Phase 5** — implement NetPoke `sch_plug` in `poker.c`.
4. **Phase 6** — re-run L2 matrix with NetPoke; compare RMSE to Phase 3 L2.
5. **Thesis writing** — from `netpoke/results/cluster/` on `netpoke/thesis-material` branch.

---

*End of study guide.*

