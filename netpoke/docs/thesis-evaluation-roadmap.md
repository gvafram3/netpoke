# NetPoke Thesis — Full Evaluation Roadmap

**Project:** I/O-Aware Causal Profiling for Throughput Prediction (NetPoke)  
**Base system:** SlowPoke (NSDI 2026)  
**Cluster:** GCP `netpoke-control` + `worker1–3`  
**Last updated:** June 2026  

This document is the **master plan** for experiments, deliverables, and thesis chapters. It extends the SlowPoke artifact evaluation (paper §5.1) with the NetPoke research program (I/O gap → eBPF → network-aware pause → accuracy restoration) across **all four** DeathStarBench applications.

---

## Table of contents

1. [Thesis aim, objectives, and research questions](#1-thesis-aim-objectives-and-research-questions)
2. [Repository map (what to read first)](#2-repository-map-what-to-read-first)
3. [SlowPoke paper & artifact: figures, tables, and pass criteria](#3-slowpoke-paper--artifact-figures-tables-and-pass-criteria)
4. [Current status (GCP cluster)](#4-current-status-gcp-cluster)
5. [Phase overview & progress tracker](#5-phase-overview--progress-tracker)
6. [Phase 0 — Cluster & tooling (prerequisite)](#phase-0--cluster--tooling-prerequisite)
7. [Phase 1 — SlowPoke baseline: all four benchmarks](#phase-1--slowpoke-baseline-all-four-benchmarks)
8. [Phase 1b — Finish movie (step-by-step, two-SSH method)](#phase-1b--finish-movie-step-by-step-two-ssh-method)
9. [Phase 2 — Package baseline results (paper-style)](#phase-2--package-baseline-results-paper-style)
10. [Phase 3 — I/O gap characterization (all four benchmarks)](#phase-3--io-gap-characterization-all-four-benchmarks)
11. [Phase 4 — eBPF mechanistic validation](#phase-4--ebpf-mechanistic-validation)
12. [Phase 5 — NetPoke implementation](#phase-5--netpoke-implementation)
13. [Phase 6 — NetPoke evaluation (all four benchmarks)](#phase-6--netpoke-evaluation-all-four-benchmarks)
14. [Figures & tables checklist (thesis + paper alignment)](#figures--tables-checklist-thesis--paper-alignment)
15. [Download & archive results](#download--archive-results)
16. [Rules of thumb (avoid lost runs)](#rules-of-thumb-avoid-lost-runs)

---

## 1. Thesis aim, objectives, and research questions

**Source documents in this repo:**

| Document | Path |
|----------|------|
| Chapter 1 (aim, objectives, RQs, chapter outline) | [`netpoke/thesis/chapter1.md`](../thesis/chapter1.md) |
| MPhil proposal (docx) | `Chapter 1 [2].docx`, `MPhil_Thesis_Proposal_IOAware_Causal_Profiling.docx` (repo root) |
| NetPoke design (sch_plug in POKER) | [`netpoke/design/poker-io-pause.md`](../design/poker-io-pause.md) |

### Aim

Design, build, and evaluate **NetPoke**: an I/O-aware extension to SlowPoke’s slowdown so bottleneck-equivalence holds for **network/I/O-bound** microservices, restoring prediction accuracy.

### Objectives → experiments

| Obj | Objective | Experiment track |
|-----|-----------|------------------|
| **O1** | Measure prediction error for I/O-bound services vs I/O intensity | Phase 3: I/O sweep on **boutique, hotel, social, movie** |
| **O2** | Establish cause via eBPF (residual I/O during SIGSTOP) | Phase 4: eBPF during pause windows on I/O-heavy configs |
| **O3** | Design/build coordinated network + process pause | Phase 5: NetPoke in `src/poker/poker.c` |
| **O4** | Evaluate vs baseline; report accuracy gain & overhead | Phase 6: Re-run Phases 3 configs with NetPoke on |

### Research questions

1. **RQ1:** How large is the I/O gap, and how does error scale with I/O intensity and pause duration? → Phase 3  
2. **RQ2:** Can residual I/O during pauses be measured at the kernel, and does it explain error? → Phase 4  
3. **RQ3:** Can network activity be paused with the process for the same window? → Phase 5  
4. **RQ4:** By how much does NetPoke improve RMSE vs SIGSTOP-only, and at what cost? → Phase 6  

### Experimental logic (your thesis narrative)

```
Baseline RMSE (SIGSTOP-only, standard medium)     ← Phase 1–2  [reference numbers]
        ↓
+I/O intensity (controlled per benchmark)           ← Phase 3  [RMSE rises]
        ↓
+eBPF: quantify residual I/O during pause           ← Phase 4  [mechanism]
        ↓
+NetPoke (network hold + SIGSTOP)                   ← Phase 5–6  [RMSE → toward baseline]
```

**Success criterion:** On I/O-heavy configs, RMSE moves back **toward your Phase 1 baseline** (~9–11% on this cluster), not necessarily the paper’s ~2% headline (smaller cluster, single repetition).

---

## 2. Repository map (what to read first)

### SlowPoke artifact (runs on `netpoke-control`)

| Purpose | Path |
|---------|------|
| Artifact instructions (§5.1, Fig. 8) | [`slowpoke/INSTRUCTIONS.md`](../../slowpoke/INSTRUCTIONS.md) |
| Orchestrator | [`slowpoke/src/main.py`](../../slowpoke/src/main.py) |
| Deploy + wrk | [`slowpoke/src/run.sh`](../../slowpoke/src/run.sh) |
| POKER / SIGSTOP | [`slowpoke/src/poker/poker.c`](../../slowpoke/src/poker/poker.c) |
| Full reproducible (4 apps) | [`slowpoke/evaluation/run_reproducible.sh`](../../slowpoke/evaluation/run_reproducible.sh) |
| Social → movie chain | [`slowpoke/evaluation/run_social_movie.sh`](../../slowpoke/evaluation/run_social_movie.sh) |
| Preflight / verify | [`slowpoke/evaluation/preflight_social_movie.sh`](../../slowpoke/evaluation/preflight_social_movie.sh), [`verify_benchmark_results.sh`](../../slowpoke/evaluation/verify_benchmark_results.sh) |
| Live progress | [`slowpoke/evaluation/watch_progress.sh`](../../slowpoke/evaluation/watch_progress.sh), [`run_with_monitor.sh`](../../slowpoke/evaluation/run_with_monitor.sh) |
| Safe cluster cleanup | [`slowpoke/evaluation/safe_delete_workloads.sh`](../../slowpoke/evaluation/safe_delete_workloads.sh) |
| Fix checker | [`slowpoke/evaluation/install_netpoke_fixes.sh`](../../slowpoke/evaluation/install_netpoke_fixes.sh) |
| Summary tables + RMSE | [`slowpoke/evaluation/summarize_results.py`](../../slowpoke/evaluation/summarize_results.py) |
| Per-app plots (Fig. 8 panels) | [`slowpoke/evaluation/draw.py`](../../slowpoke/evaluation/draw.py) |
| Macro figure PDF | [`slowpoke/evaluation/plot_macro.py`](../../slowpoke/evaluation/plot_macro.py), [`plot_fig8_png.sh`](../../slowpoke/evaluation/plot_fig8_png.sh) |
| Authors’ sample outputs | [`slowpoke/evaluation/sample_output/`](../../slowpoke/evaluation/sample_output/) |

### Per-benchmark medium scripts (standard baseline)

| Benchmark | Script | Target service (`-x`) | Log file |
|-----------|--------|----------------------|----------|
| Boutique | [`boutique/run-boutique-medium.sh`](../../slowpoke/evaluation/boutique/run-boutique-medium.sh) | `cart` | `results/boutique_medium.log` |
| Hotel | [`hotel/run-hotel-medium.sh`](../../slowpoke/evaluation/hotel/run-hotel-medium.sh) | `profile` | `results/hotel_medium.log` |
| Social | [`social/run-social-medium.sh`](../../slowpoke/evaluation/social/run-social-medium.sh) | `hometimeline` | `results/social_medium.log` |
| Movie | [`movie/run-movie-medium.sh`](../../slowpoke/evaluation/movie/run-movie-medium.sh) | `moviereviews` | `results/movie_medium.log` |

### NetPoke / thesis docs

| Purpose | Path |
|---------|------|
| GCP runbook with progress | [`gcp-run-with-progress.md`](gcp-run-with-progress.md) |
| SlowPoke process explained | [`slowpoke-evaluation-process.md`](slowpoke-evaluation-process.md) |
| **This roadmap** | `thesis-evaluation-roadmap.md` |

---

## 3. SlowPoke paper & artifact: figures, tables, and pass criteria

### Paper §5.1 — real-world applications (your Phase 1–2)

| Paper element | Artifact equivalent | Your output |
|---------------|---------------------|-------------|
| **Fig. 8** (4 panels: Predicted vs Groundtruth) | `draw.py` per `*_medium.log` | `results/boutique_medium.png`, … `movie_medium.png` |
| **Fig. 8 macro** (combined) | `plot_macro.py -r results/` | `results/plot_macro.pdf` |
| Per-point error | `Error Perc:` in log | Table in thesis / `summarize_results.py` |
| RMSE headline (~2.07% paper) | `summarize_results.py` | Per-app RMSE table (your cluster ~9–11%) |
| Pass guide (artifact) | INSTRUCTIONS.md | Mostly within **~10%** per point; often **0–4%**; outliers to ~35% |

### Log format (every complete run must end with)

```
Baseline throughput: <float>
Groundtruth: [...]
Slowdown:    [...]
Predicted:   [...]
Error Perc:  [...]
```

**Complete medium run:** 21 `[exp] Throughput:` lines (1 baseline + 10 × (groundtruth + slowdown)), 10 optimization points, final `Error Perc:`.

### Optional (not required for thesis core)

| Paper | Artifact | Time |
|-------|----------|------|
| Fig. 9 synthetic microbenchmarks | `evaluation/synthetic/*/run.sh` | 2–3 days |

### Authors’ presentation style (replicate in thesis)

- **Per-app figure:** X-axis = optimization point (0%–90% processing time reduction); Y-axis = throughput; two curves (Groundtruth, Predicted). See `sample_output/*_medium.png`.
- **Summary table:** 10 rows × columns Groundtruth, Slowdown, Predicted, Error %; footer Mean \|error\|, RMSE.
- **Macro figure:** All four apps on one axes with RMSE annotation (see `sample_output/plot_macro.png`).

---

## 4. Current status (GCP cluster)

*Update this section after each major milestone.*

| Benchmark | Status | Baseline req/s | RMSE | Saved copy |
|-----------|--------|----------------|------|------------|
| Boutique | **Complete** | 1820.0 | 9.19% | `results/boutique_medium.log` |
| Hotel | **Complete** | 563.2 | 10.23% | `results/hotel_medium.log` |
| Social | **Complete** | 930.0 | 10.34% | `results/saved/social_medium.log` |
| Movie | **Incomplete** | — | — | partial log ~161 KB, no `Error Perc:` |

**Infrastructure:** cluster Ready; proxy fix; monitoring scripts installed.

---

## 5. Phase overview & progress tracker

| Phase | Description | Est. weight (thesis experiments) | Status |
|-------|-------------|----------------------------------|--------|
| **0** | Cluster + tooling | 10% | ~95% |
| **1** | SlowPoke baseline (4 apps, standard medium) | 15% | ~75% (movie pending) |
| **2** | Package baseline tables/plots | 5% | ~60% (3/4 apps) |
| **3** | I/O gap — all 4 benchmarks × I/O levels | 25% | Not started |
| **4** | eBPF residual I/O | 15% | ~10% (tiny logs only) |
| **5** | NetPoke implementation | 15% | Design doc |
| **6** | NetPoke eval — all 4 benchmarks | 15% | Not started |

**Overall thesis research program:** ~**35–45%** complete (writing chapters separate).

---

## Phase 0 — Cluster & tooling (prerequisite)

**Where:** `netpoke-control` only (not Cloud Shell).

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation
bash install_netpoke_fixes.sh
```

**Pass criteria:**

- [ ] `kubectl get nodes` → 4 Ready  
- [ ] `install_netpoke_fixes.sh` → All checks passed  
- [ ] `grep -q start_rust_proxy ~/slowpoke/src/run.sh`  
- [ ] `watch_progress.sh`, `run_with_monitor.sh`, `safe_delete_workloads.sh` executable  

**Docs:** [`gcp-run-with-progress.md`](gcp-run-with-progress.md)

---

## Phase 1 — SlowPoke baseline: all four benchmarks

**Purpose:** Establish **reference RMSE** under standard artifact configs (SIGSTOP-only). These numbers are the comparison point for Phases 3 and 6.

**Method (same for every app):**

1. `screen` session on control node  
2. `export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1`  
3. `WATCH_INTERVAL=10 ./run_with_monitor.sh bash <app>/run-<app>-medium.sh results/<app>_medium.log`  
4. Second SSH: `SLOWPOKE_ACTIVE_LOG=.../<app>_medium.log ./watch_progress.sh --loop-tty`  
5. Done when log contains `Error Perc:` and 21 throughput lines  

**Never** re-run a complete log without backup — scripts use `>log` which **truncates** on start.

---

## Phase 1b — Finish movie (step-by-step, two-SSH method)

Movie failed mid-teardown last time. Use the **same pattern** as boutique/hotel/social.

### Step 1 — Preflight (SSH 1: netpoke-control)

```bash
cd ~/slowpoke/evaluation
export SLOWPOKE_TOP=~/slowpoke

# Archive incomplete movie log
if [[ -f results/movie_medium.log ]] && ! grep -q 'Error Perc:' results/movie_medium.log; then
  mv results/movie_medium.log results/movie_medium.log.bak-$(date +%Y%m%d-%H%M%S)
fi

# Confirm other three complete
for b in boutique hotel social; do
  grep -q 'Error Perc:' results/${b}_medium.log && echo "$b OK" || echo "$b FAIL"
done

bash safe_delete_workloads.sh
kubectl get pods -n default   # prefer empty
pgrep -f 'python3.*main.py' && echo "STOP: main.py still running" || echo "OK: idle"
```

### Step 2 — Start movie in screen (SSH 1)

```bash
screen -S slowpoke-movie
cd ~/slowpoke/evaluation
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
WATCH_INTERVAL=10 ./run_with_monitor.sh bash movie/run-movie-medium.sh results/movie_medium.log
```

**Detach:** `Ctrl+A`, then `D` (safe to close SSH 1).

### Step 3 — Live progress (SSH 2: from Cloud Shell)

```bash
gcloud compute ssh aframviscagyebi@netpoke-control --zone=us-central1-a
```

On netpoke-control:

```bash
cd ~/slowpoke/evaluation
SLOWPOKE_ACTIVE_LOG=~/slowpoke/evaluation/results/movie_medium.log \
  WATCH_INTERVAL=10 ./watch_progress.sh --loop-tty
```

**Healthy signs:**

- `workloads X/21` increasing  
- `phase: [run.sh] Running the actual test` during wrk  
- `movie_medium.log` growing (`ls -lh results/movie_medium.log`)  
- Movie pods in `kubectl get pods` (frontend, moviereviews, etc.)  

**Done when:** monitor shows `FINISHED — Error Perc:` and Suite **4/4**.

### Step 4 — Verify movie

```bash
cd ~/slowpoke/evaluation
grep -q 'Error Perc:' results/movie_medium.log && echo "MOVIE COMPLETE"
grep -c '\[exp\] Throughput:' results/movie_medium.log   # expect 21
python3 summarize_results.py results/movie_medium.log
```

### Step 5 — Backup immediately

```bash
mkdir -p results/saved
cp -a results/movie_medium.log results/saved/movie_medium.log
cp -a results/movie_medium.log results/saved/movie_medium-$(date +%Y%m%d-%H%M%S).log
```

---

## Phase 2 — Package baseline results (paper-style)

Run after all four `*_medium.log` files are complete.

```bash
cd ~/slowpoke/evaluation
export SLOWPOKE_TOP=~/slowpoke

bash verify_benchmark_results.sh results/
python3 summarize_results.py results/boutique_medium.log \
  results/hotel_medium.log results/social_medium.log results/movie_medium.log \
  | tee results/final_package/baseline_summary.txt

bash plot_fig8_png.sh results/
```

### Deliverables (Phase 2)

| ID | Deliverable | File | Thesis use |
|----|-------------|------|------------|
| T1 | Baseline RMSE table (4 apps) | `baseline_summary.txt` | Ch. 2–3, comparison table |
| F1–F4 | Per-app Fig. 8 panels | `*_medium.png` | Ch. 2 / baseline section |
| F5 | Macro Fig. 8 | `plot_macro.pdf` | Ch. 2 |
| D1 | Raw logs | `*_medium.log`, `saved/*` | Appendix / reproducibility |

### Baseline reference table (fill after movie)

| App | Target (`-x`) | Baseline (req/s) | RMSE (%) | Mean \|error\| (%) |
|-----|---------------|------------------|----------|-------------------|
| Boutique | cart | 1820.0 | 9.19 | 7.44 |
| Hotel | profile | 563.2 | 10.23 | 8.83 |
| Social | hometimeline | 930.0 | 10.34 | 6.94 |
| Movie | moviereviews | *TBD* | *TBD* | *TBD* |

---

## Phase 3 — I/O gap characterization (all four benchmarks)

**Purpose (O1 / RQ1 / thesis Ch. 3):** Show RMSE **increases** when services perform **heavy synchronous I/O** under SIGSTOP-only slowdown.

**Scope:** All four DeathStarBench apps — not boutique only.

### I/O intensity levels (use consistently)

| Level | Name | Description |
|-------|------|-------------|
| **L0** | Baseline | Standard `run-*-medium.sh` (Phase 1) — already done for 3/4 |
| **L1** | Moderate I/O | Add controlled sync delay / extra downstream RPC in target path |
| **L2** | Heavy I/O | Stronger sync I/O (paper boutique example: checkout + DB → ~25–58% error) |

### Per-benchmark plan

Create one log per (app, level), e.g. `results/<app>_io_L1_medium.log`.

| App | L0 target (done) | I/O injection strategy (L1 / L2) | Notes |
|-----|-----------------|----------------------------------|-------|
| **Boutique** | `cart` (L0 complete) | L1: `checkout` or cart+DB sleep; L2: heavy `checkout` / `SLOWPOKE_PROCESSING` + blocking downstream | Paper: frontend ~8–9%, checkout ~25–58% RMSE |
| **Hotel** | `profile` | L1/L2: add sync delay on `search` / `reservation` / Mongo paths | Hotel is naturally DB-heavy |
| **Social** | `hometimeline` | L1/L2: amplify sync calls to `post-storage` / `social-graph` / Redis | DeathStarBench social network I/O |
| **Movie** | `moviereviews` | L1/L2: amplify `review-storage` / `movie-info` sync RPC | Media microservices DB/RPC |

### Implementation tasks (before running)

- [ ] For each app, add `run-<app>-medium-io-L1.sh` and `run-<app>-medium-io-L2.sh` (or env flag `SLOWPOKE_IO_LEVEL=1|2`)  
- [ ] Document exact code/YAML change per level in `evaluation/<app>/README-io-levels.md`  
- [ ] Reuse same wrk parameters as medium scripts for comparability  
- [ ] Run in `screen` + second SSH watch (same as Phase 1)  

### Run template (each app × level)

```bash
screen -S slowpoke-<app>-io-L1
cd ~/slowpoke/evaluation
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
WATCH_INTERVAL=10 ./run_with_monitor.sh bash <app>/run-<app>-medium-io-L1.sh results/<app>_io_L1_medium.log
```

Second SSH:

```bash
SLOWPOKE_ACTIVE_LOG=~/slowpoke/evaluation/results/<app>_io_L1_medium.log \
  WATCH_INTERVAL=10 ./watch_progress.sh --loop-tty
```

### Phase 3 deliverables

| ID | Deliverable | Description |
|----|-------------|-------------|
| T2 | RMSE vs I/O level table | 4 apps × 3 levels (L0–L2) |
| F6 | RMSE vs I/O intensity plot | 4 lines or 4-panel figure |
| F7 | Error% curves under heavy I/O | Optional per-app, like Fig. 8 but L2 only |
| D2 | Logs | `results/<app>_io_L*_medium.log` |

### Analysis

```bash
python3 summarize_results.py results/boutique_io_L1_medium.log  # etc.
# Build combined CSV for thesis tables
```

---

## Phase 4 — eBPF mechanistic validation

**Purpose (O2 / RQ2 / thesis Ch. 4):** Measure **residual I/O** during SIGSTOP pause windows; correlate with prediction error from Phase 3.

**When:** During representative **L2 (heavy I/O)** runs for each benchmark (subset of workloads acceptable for thesis).

### Measurements

- Bytes received / sent on service interface during pause  
- Syscall counts (`read`, `write`, `recvfrom`, …) while process is stopped  
- Compare **pause-only** vs later **NetPoke on**  

### Deliverables

| ID | Deliverable |
|----|-------------|
| T3 | Residual I/O (bytes) vs pause duration |
| T4 | Correlation: residual I/O vs Error % |
| F8 | CDF or bar chart of residual I/O (4 apps or representative) |
| D3 | `results/*_ebpf_*.log` |

**Reference:** tiny eBPF logs in [`slowpoke/evaluation/results/`](../../slowpoke/evaluation/results/) (`experiment_f_*`); scale to full benchmark windows.

---

## Phase 5 — NetPoke implementation

**Purpose (O3 / RQ3 / thesis Ch. 5):**

**Design doc:** [`netpoke/design/poker-io-pause.md`](../design/poker-io-pause.md)

| Task | Detail |
|------|--------|
| Confirm `sch_plug` on cluster kernel | `tc qdisc add dev eth0 root plug` test in pod |
| Implement `net_hold.c` / `net_release()` | Wrap SIGSTOP/SIGCONT in `poker.c` |
| Build flag | NetPoke on/off for A/B |
| Container caps | `NET_ADMIN` for POKER pod |
| Unit smoke | Hold/release without benchmark |

**Pass criteria:** eBPF shows residual I/O → near zero with NetPoke on (design doc §6).

---

## Phase 6 — NetPoke evaluation (all four benchmarks)

**Purpose (O4 / RQ4 / thesis Ch. 6):** Re-run **same matrix as Phase 3** with NetPoke enabled.

### Comparison table (thesis headline)

| App | I/O level | RMSE SIGSTOP-only | RMSE NetPoke | Δ RMSE | Overhead |
|-----|-----------|-------------------|--------------|--------|----------|
| Boutique | L0 | 9.19% | *TBD* | *TBD* | *TBD* |
| Boutique | L2 | *TBD* | *TBD* | ↓ toward L0 | *TBD* |
| Hotel | L0 / L2 | … | … | … | … |
| Social | L0 / L2 | … | … | … | … |
| Movie | L0 / L2 | … | … | … | … |

**Success:** On L2, NetPoke RMSE moves **toward** Phase 1 L0 baseline; L0 RMSE unchanged (no regression on compute-bound path).

### Run template

```bash
export SLOWPOKE_NETPOKE=1   # or build flag — define during Phase 5
WATCH_INTERVAL=10 ./run_with_monitor.sh bash <app>/run-<app>-medium-io-L2.sh \
  results/<app>_io_L2_netpoke_medium.log
```

### Phase 6 deliverables

| ID | Deliverable |
|----|-------------|
| T5 | Full comparison table (4 apps × conditions) |
| F9 | Before/after RMSE bar chart (SIGSTOP vs NetPoke) |
| F10 | Overhead CDF or table |
| D4 | All NetPoke logs under `results/saved/netpoke/` |

---

## Figures & tables checklist (thesis + paper alignment)

Use this as a **completion checklist**. Mark when files exist on disk.

### SlowPoke baseline (paper §5.1 style)

- [ ] **Table B1:** Baseline throughput + RMSE — 4 apps (`summarize_results.py`)
- [ ] **Fig B1–B4:** Per-app Predicted vs Groundtruth (`draw.py` → `*_medium.png`)
- [ ] **Fig B5:** Macro Fig. 8 (`plot_macro.pdf`)
- [ ] **Appendix:** Raw `Error Perc:` arrays in logs

### I/O gap (thesis Ch. 3)

- [ ] **Table I1:** RMSE vs I/O level — 4 apps × L0/L1/L2
- [ ] **Fig I1:** RMSE vs I/O intensity (all benchmarks)
- [ ] **Fig I2:** Example error% curve under L2 (optional per app)

### eBPF (thesis Ch. 4)

- [ ] **Table E1:** Residual bytes during pause (SIGSTOP-only)
- [ ] **Fig E1:** Residual I/O vs prediction error

### NetPoke evaluation (thesis Ch. 6)

- [ ] **Table N1:** RMSE SIGSTOP vs NetPoke — 4 apps
- [ ] **Fig N1:** RMSE restoration bar chart
- [ ] **Table N2:** Overhead (latency per pause, CPU)

### Paper cross-reference

| Paper | Your figure/table |
|-------|-------------------|
| Fig. 8 (4 real-world apps) | Figs B1–B5 (Phase 2) |
| Table: RMSE 2.07% | Table B1 (your cluster values) |
| Functional CPU vs I/O boutique | Table I1 rows for boutique; extend to 4 apps |
| Future work: sidecar / throttling | Phase 5–6 NetPoke evaluation |

---

## Download & archive results

### On netpoke-control — create package

```bash
cd ~/slowpoke/evaluation
mkdir -p results/final_package/{baseline,io_gap,ebpf,netpoke,plots}

# After Phase 2
cp results/*_medium.log results/saved/*_medium.log results/*.png results/plot_macro.pdf \
   results/final_package/baseline/ 2>/dev/null || true
cp results/final_package/baseline_summary.txt results/final_package/baseline/ 2>/dev/null || true

tar czf ~/slowpoke_full_results_$(date +%Y%m%d).tar.gz -C ~/slowpoke/evaluation results/final_package results/saved
ls -lh ~/slowpoke_full_results_*.tar.gz
```

### From Cloud Shell — download

```bash
gcloud compute scp --zone=us-central1-a \
  aframviscagyebi@netpoke-control:~/slowpoke/evaluation/slowpoke_full_results_*.tar.gz \
  ~/

cloudshell download ~/slowpoke_full_results_YYYYMMDD.tar.gz
```

### Download this roadmap

```bash
# From Cloud Shell (after git pull)
cloudshell download ~/netpoke/netpoke/docs/thesis-evaluation-roadmap.md
```

Or clone/pull repo branch `cursor/social-movie-chain-eab9` (or `main` after merge).

---

## Rules of thumb (avoid lost runs)

1. **Always** `export SLOWPOKE_TOP=~/slowpoke` before benchmark scripts.  
2. **Always** use `screen` for runs >30 min; detach with `Ctrl+A` `D`.  
3. **Never** re-run `run-*-medium.sh` on a complete log — `>file` truncates. Backup first:  
   `cp results/foo_medium.log results/saved/foo_medium-$(date +%Y%m%d).log`  
4. **Second SSH** for watch: set `SLOWPOKE_ACTIVE_LOG` to the **active** log.  
5. After each complete benchmark: copy to `results/saved/` immediately.  
6. Stuck >15 min with no log growth: `kubectl get pods`, `bash safe_delete_workloads.sh`, check `diagnose_benchmark.sh <app>`.  

---

## Quick command reference

| Task | Command |
|------|---------|
| Preflight | `bash preflight_social_movie.sh` |
| Verify all 4 | `bash verify_benchmark_results.sh results/` |
| Summary tables | `python3 summarize_results.py results/*_medium.log` |
| Plots | `bash plot_fig8_png.sh results/` |
| Watch (2nd SSH) | `SLOWPOKE_ACTIVE_LOG=results/<app>_medium.log ./watch_progress.sh --loop-tty` |
| Movie run | `WATCH_INTERVAL=10 ./run_with_monitor.sh bash movie/run-movie-medium.sh results/movie_medium.log` |

---

*End of roadmap. Update §4 status table after each benchmark completes.*
