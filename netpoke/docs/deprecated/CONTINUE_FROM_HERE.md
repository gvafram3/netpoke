# NetPoke thesis — continue from here

**Purpose:** Single handoff document for resuming work in **Cursor Desktop** (or any environment) with full project context.  
**Student:** Afram Visca Gyebi · KNUST MPhil · Supervisor: Dr. (Mrs.) Rose-Mary Mensah Gyening  
**Repo:** https://github.com/gvafram3/netpoke  
**Active branch:** `netpoke/experiments`  
**Last updated:** June 2026 (after Phase 3 complete; Phase 4 smoke in progress)

---

## 1. What this project is

### 1.1 Base paper

**SlowPoke** (Xie et al., NSDI 2026) predicts how much **end-to-end throughput** (req/s at the frontend) would increase if you optimized one microservice—**without** implementing the optimization first.

- **Mechanism:** Pause non-target services with **SIGSTOP/SIGCONT** (POKER controller).
- **Method:** Causal profiling—slow others to emulate speeding the target.
- **Limitation (acknowledged in paper):** SIGSTOP stops **CPU** but not **kernel/network I/O** during pauses → predictions degrade on **I/O-bound** services.

### 1.2 Your thesis (NetPoke)

1. **Measure** the prediction error under I/O-heavy workloads (Phase 3).
2. **Explain** with kernel evidence—residual I/O during pauses (Phase 4 eBPF / `/proc` sampler).
3. **Fix** with **NetPoke:** synchronised **network egress hold** (`sch_plug`) around each SIGSTOP window (Phase 5–6).

**Design doc:** `netpoke/design/poker-io-pause.md`

### 1.3 Deep reading

| Resource | Path |
|----------|------|
| SlowPoke paper study guide (Word) | `netpoke/docs/slowpoke-paper-deep-dive.docx` |
| Markdown source | `netpoke/docs/slowpoke-paper-deep-dive.md` |
| Artifact manual (SlowPoke) | `slowpoke/INSTRUCTIONS.md` |
| Artifact manual (NetPoke) | `netpoke/INSTRUCTIONS.md` |
| Evaluation flow | `netpoke/docs/slowpoke-evaluation-process.md` |
| Monitor + screen | `netpoke/docs/gcp-run-with-progress.md` |

---

## 2. Infrastructure

| Component | Detail |
|-----------|--------|
| **GCP project** | netpoke cluster (control + workers) |
| **Control VM** | `netpoke-control` (zone `us-central1-a`) |
| **Workers** | `worker1`, `worker2`, `worker3` (hostnames required in boutique YAMLs) |
| **SlowPoke tree on VM** | `~/slowpoke` — **not** a git repo; sync via `scp`/`tar` from Cloud Shell |
| **Env var** | `export SLOWPOKE_TOP=~/slowpoke` (always) |
| **Cloud Shell** | `git pull`, `gcloud compute scp` only — **no** `~/slowpoke` |
| **Load** | `wrk` in `ubuntu-client` pod (often on worker1) |

### 2.1 Common mistakes

| Mistake | Correct |
|---------|---------|
| Run `draw.py` / benchmarks in Cloud Shell | Run on **netpoke-control** |
| Look for logs in `~/results/` | `~/slowpoke/evaluation/results/` |
| `git pull` inside `~/slowpoke` | Pull **netpoke** repo in Cloud Shell; **scp** scripts to VM |
| Re-use old `netpoke-phase4.tgz` | Pull latest `netpoke/experiments` or scp `phase4_ebpf/` |
| `curl raw.githubusercontent.com` | Repo is **private** → use `git pull` + `gcloud compute scp` |
| Start Phase 4 full suite before smoke PASS | Smoke must show `with_state_T > 0` |

---

## 3. Git branches

| Branch | Use |
|--------|-----|
| **`netpoke/experiments`** | **You are here.** Scripts, results layout, all experiment work |
| **`netpoke/thesis-material`** | Chapter drafts only (`netpoke/thesis/`) — writing paused |
| `netpoke26-thesis` | Older integration snapshot |
| `main` | Upstream / general |

```bash
git clone https://github.com/gvafram3/netpoke.git
cd netpoke
git checkout netpoke/experiments
```

**Do not** use `cursor/*` branch names for new work (user preference).

---

## 4. Repository layout

```
netpoke/
  CONTINUE_FROM_HERE.md          ← this file
  INSTRUCTIONS.md                ← experiment runbook
  design/poker-io-pause.md       ← NetPoke mechanism design
  docs/                          ← guides, Word deep-dive
  results/
    reference/                   ← SlowPoke sample figures (paper format)
    cluster/                     ← YOUR cluster outputs (sync from VM)
      baseline/logs|figures|tables/
      io_gap/logs|figures|tables/
      ebpf/logs|tables/          ← Phase 4 outputs go here
  evaluation/phase4_ebpf/README.md  ← Phase 4 quick start (pointer)

slowpoke/                        ← NSDI 2026 artifact (fork/vendor)
  src/main.py                    ← orchestrator
  src/poker/poker.c              ← SIGSTOP pause
  evaluation/
    io_gap/                      ← Phase 3 framework
    phase4_ebpf/                 ← Phase 4 scripts
    watch_progress.sh            ← monitor (append mode: --append)
    run_with_monitor.sh
    scripts/pack_results_for_repo.sh
```

---

## 5. Evaluation phases — status

| Phase | Description | Status |
|-------|-------------|--------|
| **0** | Cluster + K8s + fixes | Done |
| **1** | L0 baselines (4 apps, standard medium) | **Done** |
| **3** | I/O gap L0/L1/L2 (8 runs + boutique re-run) | **Done** |
| **4** | Residual I/O during SIGSTOP at L2 | **In progress** — smoke must pass, then full suite |
| **5** | NetPoke `sch_plug` implementation | Not started |
| **6** | Re-run L2 with NetPoke vs Phase 3 | Not started |
| **Thesis writing** | Chapters | **Paused** — use `netpoke/thesis-material` later |

---

## 6. Results — Phase 1 (L0 baselines)

Standard `run-*-medium.sh`, SIGSTOP only, target per paper:

| App | Target (`-x`) | Baseline (req/s) | RMSE % |
|-----|---------------|------------------|--------|
| Boutique | cart | 1820.0 | 9.19 |
| Hotel | profile | 563.2 | 10.23 |
| Social | hometimeline | 930.0 | 10.34 |
| Movie | moviereviews | 611.2 | 13.97 |

**Logs on VM:** `~/slowpoke/evaluation/results/{boutique,hotel,social,movie}_medium.log`  
**Repo table:** `netpoke/results/cluster/baseline/tables/TABLE_L0_SUMMARY.md`

Paper reports ~2% RMSE on AWS; your cluster ~9–14% is expected (fewer repetitions, 3 workers).

---

## 7. Results — Phase 3 (I/O gap matrix, final)

**Design:** L0/L1/L2 share the **same `-x` target**; L1/L2 add **tc netem sidecars** on downstream path services (stimulus, not NetPoke fix).

### 7.1 Full table

| App | Level | Target / injection | Baseline (req/s) | RMSE % |
|-----|-------|-------------------|------------------|--------|
| Boutique | L0 | cart | 1820.0 | 9.19 |
| Boutique | L1 | cart + productcatalog 30ms | 1715.6 | 6.93 |
| Boutique | L2 | cart + productcatalog 50ms, currency 30ms | 1739.0 | 5.61 |
| Hotel | L0 | profile | 563.2 | 10.23 |
| Hotel | L1 | profile + rate 30ms | 593.2 | 13.90 |
| Hotel | L2 | profile + rate 50ms, user 30ms | 675.5 | 16.28 |
| Social | L0 | hometimeline | 930.0 | 10.34 |
| Social | L1 | hometimeline + poststorage 30ms | 820.9 | 26.04 |
| Social | L2 | hometimeline + poststorage 50ms, socialgraph 30ms | 839.5 | 24.64 |
| Movie | L0 | moviereviews | 611.2 | 13.97 |
| Movie | L1 | moviereviews + reviewstorage 30ms | 504.7 | 19.18 |
| Movie | L2 | moviereviews + reviewstorage 50ms, movieinfo 30ms | 696.7 | 16.72 |

### 7.2 L2 − L0 RMSE delta (thesis headline)

| App | Δ (pp) | Supports I/O-gap? |
|-----|--------|-------------------|
| **Social** | **+14.30** | Yes (strongest) |
| **Hotel** | **+6.05** | Yes (monotonic) |
| **Movie** | **+2.75** | Yes (modest) |
| **Boutique** | **−3.59** | No (outlier) |

### 7.3 Boutique story

1. **First Phase 3:** shipping netem (~10% cart path) → L2 RMSE **fell** vs L0.
2. **Re-run (2026-06-09):** injection moved to **product_catalog** (~61% path) + **currency** on L2.
3. **Outcome:** RMSE still **fell** (9.19 → 6.93 → 5.61)—boutique does not show monotonic gap growth.
4. **Thesis use:** Lead with **social + hotel**; boutique = case study / limitation.

**Superseded logs:** `results/saved/boutique_shipping_inject_20260607/`  
**Config:** `slowpoke/evaluation/io_gap/io_levels.conf`  
**Repo:** `netpoke/results/cluster/io_gap/tables/TABLE_IO_GAP_MATRIX.md`, `BOUTIQUE_RERUN_NOTES.md`

### 7.4 Phase 3 logs (on netpoke-control)

```
results/boutique_io_L1_medium.log
results/boutique_io_L2_medium.log
results/hotel_io_L{1,2}_medium.log
results/social_io_L{1,2}_medium.log
results/movie_io_L{1,2}_medium.log
```

Regenerate matrix:

```bash
cd ~/slowpoke/evaluation
python3 io_gap/summarize_io_gap_matrix.py results/
python3 io_gap/plot_io_gap_rmse.py results/
```

---

## 8. Phase 4 — where you stopped (exactly)

### 8.1 Goal

Measure **residual I/O** (bytes, syscalls, network counters) while processes are in **SIGSTOP** state (`T` in `/proc/pid/stat`) during **L2** benchmark runs.

### 8.2 Scripts (`slowpoke/evaluation/phase4_ebpf/`)

| Script | Role |
|--------|------|
| `preflight_ebpf.sh` | Verify scripts, kubectl, Phase 3 L2 logs |
| `run_ebpf_smoke.sh` | ~5–10 min boutique L2 + sampler (**gate for full suite**) |
| `run_ebpf_all_L2.sh` | All 4 apps: social → hotel → movie → boutique (~3–4 h) |
| `run_ebpf_one_L2.sh` | Single app (internal) |
| `residual_io_sampler.py` | Polls pods via `kubectl exec`, state `T` + `/proc/pid/io` |
| `summarize_ebpf_residual.py` | Summary table + CSV |
| `sync_phase4_fix.sh` | Fetch scripts from GitHub (404 if repo private—use scp) |

### 8.3 What happened on the cluster

1. Preflight **passed** (Phase 3 L2 logs OK, cluster ready).
2. First smoke **failed:** sampler bug `out, _ = sh_quiet` (fixed in repo as `rc, out, err = sh_quiet`).
3. User re-applied scripts; **grep confirms fix** on line 71 of `residual_io_sampler.py`.
4. **Smoke re-run after fix:** not confirmed PASS in chat—must verify before full suite.
5. Failed smoke left `boutique_ebpf_L2_residual.jsonl` with **1 line** (meta only), `with_state_T=0`.

### 8.4 Outputs (when complete)

| File | Content |
|------|---------|
| `<app>_ebpf_L2_medium.log` | Full SlowPoke L2 run (21 workloads) |
| `<app>_ebpf_L2_residual.jsonl` | JSONL samples during pauses |
| `final_package/ebpf_residual_summary.csv` | T3/T4 table |

**Path:** `~/slowpoke/evaluation/results/` (not `~/results/`)

---

## 9. Next actions (copy-paste)

### Step A — Sync latest Phase 4 scripts to VM

**Cloud Shell:**

```bash
cd ~/netpoke
git pull origin netpoke/experiments

gcloud compute scp --recurse --zone=us-central1-a \
  ~/netpoke/slowpoke/evaluation/phase4_ebpf/ \
  netpoke-control:~/slowpoke/evaluation/phase4_ebpf/

gcloud compute scp --zone=us-central1-a \
  ~/netpoke/slowpoke/evaluation/watch_progress.sh \
  netpoke-control:~/slowpoke/evaluation/watch_progress.sh
```

**netpoke-control:**

```bash
chmod +x ~/slowpoke/evaluation/phase4_ebpf/*.sh ~/slowpoke/evaluation/phase4_ebpf/*.py
grep -n 'rc, out, err = sh_quiet' ~/slowpoke/evaluation/phase4_ebpf/residual_io_sampler.py
# Must show line ~71
```

### Step B — Smoke test (required gate)

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation

rm -f results/boutique_ebpf_L2_residual.jsonl results/boutique_ebpf_L2_medium.log

bash phase4_ebpf/preflight_ebpf.sh
bash phase4_ebpf/run_ebpf_smoke.sh
```

**PASS criteria:**

- `PASS: sampler saw paused processes`
- `samples > 0` and `with_state_T > 0`
- `wc -l results/boutique_ebpf_L2_residual.jsonl` → many lines, not 1

### Step C — Full Phase 4 suite (only after smoke PASS)

**SSH 1:**

```bash
screen -S phase4-ebpf
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./phase4_ebpf/run_ebpf_all_L2.sh
# Ctrl+A D
```

**SSH 2 (scrollable monitor):**

```bash
export WATCH_INTERVAL=10 SLOWPOKE_PHASE4_EBPF=1
cd ~/slowpoke/evaluation
./watch_progress.sh --append ~/slowpoke/evaluation/results/
```

### Step D — Summarize and pack

```bash
cd ~/slowpoke/evaluation
python3 phase4_ebpf/summarize_ebpf_residual.py results/ \
  -o results/final_package/ebpf_residual_summary.csv
bash scripts/pack_results_for_repo.sh
```

**Cloud Shell download:**

```bash
gcloud compute scp --zone=us-central1-a \
  aframviscagyebi@netpoke-control:~/netpoke_results_pack_*.tar.gz .
```

### Step E — Commit to repo

Unpack into:

- `netpoke/results/cluster/ebpf/logs/` — `*_ebpf_L2_medium.log`, `*_ebpf_L2_residual.jsonl`
- `netpoke/results/cluster/ebpf/tables/` — CSV summary

```bash
git checkout netpoke/experiments
git add netpoke/results/cluster/ebpf/
git commit -m "Add Phase 4 eBPF residual I/O cluster results"
git push origin netpoke/experiments
```

---

## 10. Monitoring cheatsheet

| Goal | Command |
|------|---------|
| Built-in monitor (SSH 1) | `WATCH_INTERVAL=10 ./run_with_monitor.sh <script>` |
| Second SSH, scroll history | `./watch_progress.sh --append results/` |
| One-shot status | `./watch_progress.sh --once results/` |
| Phase 4 suite line | `Phase-4 eBPF: X/4 L2 runs complete` |
| Pin active log | `export SLOWPOKE_ACTIVE_LOG=~/slowpoke/evaluation/results/social_ebpf_L2_medium.log` |
| Reattach screen | `screen -r phase4-ebpf` |

**Complete medium log:** 21 `[exp] Throughput:` lines + `Error Perc:` with 10 values (~150–200 KB).

---

## 11. Key scripts reference (all phases)

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation

# Phase 1 — L0 (done)
./run_reproducible.sh

# Phase 3 — I/O gap (done)
WATCH_INTERVAL=10 ./io_gap/run_io_gap_all.sh
python3 io_gap/summarize_io_gap_matrix.py results/

# Boutique re-run only (done)
bash io_gap/run_boutique_io_rerun.sh

# Phase 4 — eBPF (current)
bash phase4_ebpf/run_ebpf_smoke.sh
WATCH_INTERVAL=10 ./phase4_ebpf/run_ebpf_all_L2.sh

# Plots
bash plot_fig8_png.sh results/
python3 io_gap/plot_io_gap_rmse.py results/
bash scripts/pack_results_for_repo.sh
```

---

## 12. Phase 5–6 (after Phase 4)

### Phase 5 — Implement NetPoke

- Integrate `sch_plug` egress hold in `slowpoke/src/poker/poker.c` around SIGSTOP/SIGCONT.
- Read `netpoke/design/poker-io-pause.md`.
- Build flag or env `SLOWPOKE_NETPOKE=1` for A/B.

### Phase 6 — Evaluate NetPoke

- Re-run **L2 matrix** with NetPoke on.
- Compare RMSE to Phase 3 L2; L0 should not regress.
- Success: L2 RMSE moves toward L0 on social/hotel/movie.

---

## 13. Thesis writing (paused)

- Drafts on branch **`netpoke/thesis-material`** → `netpoke/thesis/`
- **Do not** block experiments on writing.
- When ready: write fresh from `netpoke/results/cluster/` tables and figures.

---

## 14. Engineering fixes already applied (cluster)

| Issue | Fix |
|-------|-----|
| Hotel hung after boutique | `run.sh` proxy uses `nohup` (not blocking `kubectl exec`) |
| Movie L1 zero throughput | `IO_NUM_REQ_MOVIE=20000` in `io_levels.conf` |
| Boutique shipping image | `shipping.yaml` fix; shipping netem removed from path |
| Phase 3 wrong design | Abandoned changing `-x` per level; fixed target + path netem |
| Monitor stuck on boutique | `SLOWPOKE_ACTIVE_LOG` + `watch_progress.sh` phase detection |
| Phase 4 sampler crash | `rc, out, err = sh_quiet(...)` in `residual_io_sampler.py` |

Verify fixes: `bash install_netpoke_fixes.sh`

---

## 15. Injection map (Phase 3 config)

From `slowpoke/evaluation/io_gap/io_levels.conf`:

| App | Target | L1 inject | L2 inject |
|-----|--------|-----------|-----------|
| Boutique | cart | productcatalog:30 | productcatalog:50, currency:30 |
| Hotel | profile | rate:30 | rate:50, user:30 |
| Social | hometimeline | poststorage:30 | poststorage:50, socialgraph:30 |
| Movie | moviereviews | reviewstorage:30 | reviewstorage:50, movieinfo:30 |

---

## 16. Cursor Desktop workflow

1. Clone repo; checkout **`netpoke/experiments`**.
2. Read this file + `netpoke/INSTRUCTIONS.md`.
3. Edit scripts locally; push to GitHub.
4. Sync to netpoke-control via Cloud Shell `gcloud compute scp` (repo is private).
5. Run experiments on VM; pack results; pull tarball or commit synced files.
6. Ask Cursor agent to update tables in `netpoke/results/cluster/` from pasted matrix output.

**Open in Cursor:** workspace root = repo root; both `netpoke/` and `slowpoke/` are in one tree.

---

## 17. PRs and integration

- Experiment work: branch `netpoke/experiments`, PR #10 (draft) on GitHub.
- Merge target for integration: `netpoke26-thesis` when ready for defense snapshot.

---

## 18. One-line status

**Phase 3 done (3/4 apps prove I/O gap); boutique is outlier; Phase 4 scripts ready on VM with sampler fix—re-run smoke, then `run_ebpf_all_L2.sh`, then Phase 5 NetPoke.**

---

*End of handoff. Update this file when Phase 4 completes or major decisions change.*
