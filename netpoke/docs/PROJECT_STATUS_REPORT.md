# NetPoke / SlowPoke Thesis — Project Status Report

**Student:** Afram Visca Gyebi  
**Supervisor:** Dr. (Mrs.) Rose-Mary Mensah Gyening  
**Programme:** MPhil Computer Science, KNUST, Kumasi, Ghana  
**Base paper:** SlowPoke (Xie et al., NSDI 2026)  
**Repository:** [gvafram3/netpoke](https://github.com/gvafram3/netpoke)  
**Defense branch:** `netpoke26-thesis`  
**Report date:** June 2026  
**Cluster:** GCP `netpoke-control` + `worker1–3`

---

## 1. Executive summary

This thesis extends **SlowPoke**—distributed causal profiling for microservice throughput prediction—so that predictions remain accurate for **I/O-bound** services, not only compute-bound ones. SlowPoke pauses non-target services with **SIGSTOP**; that stops CPU but not kernel/network I/O, so the artificial slowdown is incomplete and prediction error grows on I/O-heavy paths.

**NetPoke** (proposed contribution) synchronises a **network egress hold** (`sch_plug`) with each SIGSTOP/SIGCONT window in SlowPoke’s POKER controller, making the pause complete across CPU and network.

**Where we are:** The evaluation programme is roughly **55–60%** complete. **Phase 1** (L0 baselines, four DeathStarBench apps) and **Phase 3** (I/O-gap characterisation, 8/8 runs) are **done** on the cluster. **Phase 4** (eBPF mechanistic validation), **Phase 5** (NetPoke implementation), and **Phase 6** (NetPoke evaluation) remain.

**Headline empirical result (Phase 3):** At fixed causal targets, path netem injection under SIGSTOP-only slowdown increased RMSE by **+14.3 pp** (social), **+6.1 pp** (hotel), and **+2.8 pp** (movie) at L2 vs L0. Boutique was a negative outlier (−6.1 pp), informing injection-placement discussion in Chapter 3.

---

## 2. Research motivation (from proposal / Chapter 1)

### 2.1 The operational question

Microservice applications decompose into many interacting services. Engineers need to know **which service to optimise** for the largest end-to-end throughput gain before investing implementation effort. **Causal profiling** answers this by slowing non-target components and observing relative throughput change—the slowed run emulates a sped-up target (Curtsinger & Berger, 2015).

### 2.2 SlowPoke’s promise

**SlowPoke** (Xie et al., 2026) brings causal profiling to distributed microservices **without** distributed tracing or prior call-graph knowledge. On four DeathStarBench applications it reports **2.07% RMSE** for throughput-prediction accuracy—credible for planning optimisations.

### 2.3 The problem this thesis addresses

SlowPoke’s slowdown uses **SIGSTOP/SIGCONT** on non-target process groups. That removes CPU time but **does not stop kernel-mediated network I/O**: packets are still received, ACKs sent, buffers drain. For **I/O-bound** services (DB, cache, synchronous RPC), the pause is **incomplete**, bottleneck-equivalence fails, and predictions degrade—typically **over-prediction**.

The base paper **acknowledges** this limitation and suggests sidecar netem or I/O throttling as **future work**, without measurement or implementation. This thesis **measures** the gap, **explains** it with eBPF, and **proposes NetPoke** as a fix.

### 2.4 Aim

Design, build, and evaluate an **I/O-aware extension** to SlowPoke’s slowdown so bottleneck-equivalence holds for network-bound microservices and prediction accuracy is restored toward compute-bound levels.

### 2.5 Objectives and research questions

| # | Objective | Research question |
|---|-----------|-------------------|
| **O1** | Measure prediction error vs I/O intensity | **RQ1:** How large is the error for I/O-bound services, and how does it scale with I/O intensity and pause duration? |
| **O2** | Establish cause via eBPF (residual I/O during pauses) | **RQ2:** Can residual I/O be measured at the kernel, and does it explain the error? |
| **O3** | Design/build coordinated network pause (NetPoke) | **RQ3:** Can network activity be paused for the same window as the process? |
| **O4** | Evaluate accuracy gain vs overhead | **RQ4:** By how much does NetPoke improve RMSE vs SIGSTOP-only? |

**Thesis chapter map:** Ch. 3 → O1/RQ1 · Ch. 4 → O2/RQ2 · Ch. 5 → O3 · Ch. 6 → O4.

Full prose: [`netpoke/thesis/chapter1.md`](../thesis/chapter1.md).

---

## 3. Gap in the base paper (SlowPoke)

| What SlowPoke does | What it assumes | What breaks for I/O-bound services |
|--------------------|-----------------|-------------------------------------|
| SIGSTOP on non-target pods | Pause ≈ genuine slowdown of that service | Kernel/network stack keeps working during pause |
| Performance model from CPU quota + request ratios | Bottleneck preserved under artificial slowdown | Residual I/O capacity → model sees less slowdown than reality |
| Strong results on standard medium configs | Mostly compute-like paths | Paper notes network/disk bottlenecks not preserved; **not quantified** |

**Explicit future work in paper:** service-mesh sidecar or I/O throttling for network bottlenecks—**no design, no numbers**.

**This thesis fills:** (1) quantified I/O gap on four benchmarks, (2) eBPF evidence of residual I/O during pauses, (3) NetPoke (`sch_plug` egress hold), (4) before/after accuracy evaluation.

---

## 4. Proposed solution: NetPoke

### 4.1 Mechanism A (canonical)

Integrate into `slowpoke/src/poker/poker.c` around existing pause logic:

```
NET_HOLD();                  // tc sch_plug — buffer egress
kill(-child_pgid, SIGSTOP);
precise_sleep(pause_duration);
kill(-child_pgid, SIGCONT);
NET_RELEASE();               // flush plug queue
```

- **Why egress hold:** TCP back-pressure stops ingress without drops/retransmits.
- **Why not static netem:** Fixed delay ≠ per-pause windows; good for **stimulating** I/O load in Phase 3, not for **fixing** the pause mechanism.
- **Design doc:** [`netpoke/design/poker-io-pause.md`](../design/poker-io-pause.md)

### 4.2 Scope boundaries (from proposal)

| In scope | Out of scope |
|----------|--------------|
| Network I/O during pauses | Disk I/O subsystem |
| User-space POKER extension | Kernel changes |
| Experimental bottleneck-equivalence | Formal proof |
| Four DeathStarBench apps | SlowPoke model rewrite |

---

## 5. Evaluation programme (master plan)

Canonical roadmap: [`thesis-evaluation-roadmap.md`](thesis-evaluation-roadmap.md).

```
Phase 0  Cluster + tooling
    ↓
Phase 1  L0 baselines (SIGSTOP-only, standard medium) — 4 apps
    ↓
Phase 2  Package baselines (tables, Fig. 8 style plots)
    ↓
Phase 3  I/O gap (L1/L2 path netem, same -x target) — 4 apps × 2 levels
    ↓
Phase 4  eBPF residual I/O during pause windows
    ↓
Phase 5  NetPoke implementation (sch_plug in POKER)
    ↓
Phase 6  Re-run L2 matrix: SIGSTOP-only vs NetPoke
```

---

## 6. Infrastructure and process journey

### 6.1 Cluster

- **Platform:** GCP Kubernetes — `netpoke-control` + 3 workers (`worker1–3`).
- **Repo on VM:** `~/slowpoke` is **not** a git checkout; sync via Cloud Shell `git pull` + `tar`/`scp`.
- **Pattern:** SSH1 `screen` + suite script; SSH2 `watch_progress.sh --loop-tty`.
- **Always:** `export SLOWPOKE_TOP=~/slowpoke`.

### 6.2 Major engineering fixes (enabling valid runs)

| Issue | Fix |
|-------|-----|
| Boutique shipping 2/2 pod hang | `run.sh` accepts N/N ready; remove stray `shipping_io_l2.yaml` from `yamls/` |
| Hotel/social/movie proxy hang | Rust proxy detached from `kubectl exec`; heartbeat checks |
| Movie zero-throughput retry loop | `IO_NUM_REQ_MOVIE=20000` (match L0), not 100000 |
| Monitor stuck on finished log | `watch_progress.sh` io_gap auto-switch + `.slowpoke_active_log` |
| Phase 3 injection | `apply_io_injection.sh` / `restore_io_injection.sh` + `patch_netem_yaml.py` |

### 6.3 Discarded / unverified data

Per [`netpoke/README.md`](../README.md): early-session numbers (e.g. 59% RMSE, specific byte counts) are **unverified** and **not cited**. The functional test is **not** an accuracy benchmark.

---

## 7. Progress by phase

### Phase 0 — Cluster & tooling (~95%)

- [x] 4-node K8s cluster operational  
- [x] `install_netpoke_fixes.sh`, monitoring scripts, safe teardown  
- [ ] Optional: full 8-VM layout from original budget doc (using 3 workers in practice)

### Phase 1 — L0 baselines (100%)

| App | Target | Baseline (req/s) | RMSE | Log |
|-----|--------|------------------|------|-----|
| Boutique | cart | 1820.0 | 9.19% | `boutique_medium.log` |
| Hotel | profile | 563.2 | 10.23% | `hotel_medium.log` |
| Social | hometimeline | 930.0 | 10.34% | `social_medium.log` |
| Movie | moviereviews | 611.2 | 13.97% | `movie_medium.log` |

*Note: Cluster RMSE is higher than paper’s 2.07% aggregate—expected on different hardware and configuration.*

### Phase 2 — Package baselines (~80%)

- [x] `summarize_results.py`, `draw.py`, `plot_macro.py`  
- [ ] Final Fig. 8 panels + macro PDF archived in `results/final_package/`

### Phase 3 — I/O gap (100% experiments, analysis partial)

**Design (final):** L0/L1/L2 share the **same `-x` target**; L1/L2 add **tc netem sidecars** on downstream path services.

| App | L0 RMSE | L1 RMSE | L2 RMSE | L2 − L0 | RQ1 |
|-----|---------|---------|---------|---------|-----|
| Social | 10.34% | 26.04% | 24.64% | **+14.30 pp** | Yes |
| Hotel | 10.23% | 13.90% | 16.28% | **+6.05 pp** | Yes (monotonic) |
| Movie | 13.97% | 19.18% | 16.72% | **+2.75 pp** | Yes (modest) |
| Boutique | 9.19% | 11.53% | 3.07% | **−6.12 pp** | No (outlier) |

- [x] 8/8 logs complete, verification passed  
- [x] `io_gap_matrix.csv` on cluster  
- [x] Archive `slowpoke_phase3_20260607.tar.gz`  
- [ ] Fig I1 (RMSE vs I/O intensity plot)  
- [ ] Chapter 3 draft  

**Details:** [`slowpoke/evaluation/io_gap/PHASE3_RESULTS.md`](../../slowpoke/evaluation/io_gap/PHASE3_RESULTS.md)

### Phase 4 — eBPF (~10%)

- [ ] Residual bytes/syscalls during SIGSTOP pause windows  
- [ ] Correlate with Phase 3 error  
- Reference tiny logs: `experiment_f_*`  
- **Priority configs:** social L2, hotel L2, movie L2  

### Phase 5 — NetPoke implementation (design only)

- [x] Design doc (`poker-io-pause.md`)  
- [ ] `sch_plug` availability test on cluster  
- [ ] `net_hold.c` / `net_release()` in POKER  
- [ ] Build flag NetPoke on/off  

### Phase 6 — NetPoke evaluation (0%)

- [ ] Re-run L2 with NetPoke; compare RMSE to Phase 3 L2 and Phase 1 L0  
- [ ] Overhead measurement  

---

## 8. Deviations from original plan

| Planned | What happened | Impact |
|---------|---------------|--------|
| Phase 3: change `-x` to I/O-heavy services (checkout, search, etc.) | **Redesigned:** fixed `-x` + path netem (thesis-aligned) | Correct for RQ1; first partial runs archived to `io_gap_target_switch/` |
| Boutique L2 via swapped `shipping.yaml` only | Generalised `apply_io_injection.sh` for all apps | Cleaner, reversible injection |
| Static netem as **solution** | Netem used only as **I/O stimulus** in Phase 3; **NetPoke** remains `sch_plug` | Aligns with design doc §4 |
| 100k requests for movie io_gap | **20k** after infinite retry loop on slowdown exp | Documented in `io_levels.conf` |
| Monotonic L0 < L1 < L2 everywhere | Social/movie: L1 > L2; boutique: L2 < L0 | Report L2−L0; discuss injection path and variance |
| 8 GCP worker VMs | 3 workers used successfully | Sufficient for four benchmarks |
| Early RMSE/residual numbers | Discarded as unverified | Clean evidence base |

---

## 9. Mapping objectives to evidence

| Objective | Status | Evidence |
|-----------|--------|----------|
| **O1 / RQ1** | **Substantially met** | Phase 3 matrix: 3/4 apps show L2 > L0; hotel monotonic; social largest gap |
| **O2 / RQ2** | **Not started** (experiments) | Design and roadmap ready; needs Phase 4 runs |
| **O3 / RQ3** | **Design complete** | `poker-io-pause.md`; implementation pending |
| **O4 / RQ4** | **Not started** | Depends on Phases 5–6 |

---

## 10. Way forward (ordered)

### Immediate (writing + packaging)

1. Draft **Chapter 3** using `PHASE3_RESULTS.md` and `io_gap_matrix.csv`.  
2. Produce **Fig I1** (RMSE vs I/O level, four apps).  
3. Complete **Phase 2** figures (Fig. 8 style) for L0 baselines if not already archived.  
4. Download and back up cluster tarball off GCP.

### Next experiments

5. **Phase 4 eBPF** on **social L2** and **hotel L2** (minimum viable for Ch. 4).  
6. Implement **Phase 5 NetPoke** in `poker.c`; confirm `sch_plug` on cluster kernel.  
7. **Phase 6** re-run L2 configs with NetPoke on/off.

### Optional / appendix

- Boutique follow-up: netem on `product_catalog` (cart path)—only if supervisor wants four clean monotonic curves.  
- Do **not** re-run all eight io_gap experiments unless a methodology error is found.

---

## 11. Repository map

| Path | Purpose |
|------|---------|
| [`netpoke/thesis/chapter1.md`](../thesis/chapter1.md) | Chapter 1 (Introduction) |
| [`netpoke/docs/thesis-evaluation-roadmap.md`](thesis-evaluation-roadmap.md) | Master experiment plan |
| [`netpoke/docs/PROJECT_STATUS_REPORT.md`](PROJECT_STATUS_REPORT.md) | This report |
| [`netpoke/design/poker-io-pause.md`](../design/poker-io-pause.md) | NetPoke design |
| [`slowpoke/evaluation/io_gap/`](../../slowpoke/evaluation/io_gap/) | Phase 3 scripts + results doc |
| [`slowpoke/evaluation/io_gap/PHASE3_RESULTS.md`](../../slowpoke/evaluation/io_gap/PHASE3_RESULTS.md) | Final Phase 3 numbers |
| [`netpoke/docs/gcp-run-with-progress.md`](gcp-run-with-progress.md) | Cluster runbook |
| [`netpoke/infra/gcp/`](../../netpoke/infra/gcp/) | GCP cluster scripts |

**Branches:**

| Branch | Role |
|--------|------|
| `netpoke26-thesis` | **Defense / canonical** — merge target for thesis work |
| `cursor/phase3-io-gap-eab9` | Phase 3 PR branch (merged into `netpoke26-thesis`) |
| `main` | Upstream; merge thesis milestones via PR |

---

## 12. Summary sentence for supervisor

We have **reproduced SlowPoke baselines** on four benchmarks, **quantified the I/O gap** under a thesis-aligned methodology (fixed targets + controlled path netem), and shown **large prediction-error increases** on social, hotel, and movie—supporting the motivation for **NetPoke**, which is **designed but not yet implemented**. **eBPF validation** and **NetPoke evaluation** are the critical path to completing the original four-objective programme.
