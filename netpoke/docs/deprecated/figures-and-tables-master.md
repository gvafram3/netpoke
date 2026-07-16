# Figures and tables — master guide (SlowPoke paper → NetPoke thesis)

**Purpose:** Map every diagram/table/graph to the base paper presentation style, your thesis phases, generation commands, and download paths.  
**Use for:** defense slides, chapter drafts, supervisor meetings.  
**Last updated:** June 2026 (Phase 4: 3/4 apps; boutique pending)

---

## 1. How the SlowPoke paper presents results (§5)

The NSDI 2026 paper structures evaluation as:

| Paper element | What it shows | How it is built |
|---------------|---------------|-----------------|
| **System overview** (early figures) | SlowPoke architecture: predictor, model, POKER | Conceptual — cite paper; your thesis adds NetPoke box in Ch. 5 |
| **§5.1 Fig. 8 — four panels** | Per app: **Groundtruth** vs **Predicted** throughput vs optimisation point (0%–90% target speedup) | One medium log per app → `draw.py` |
| **§5.1 Fig. 8 — macro** | All four apps + **RMSE** annotation | `plot_macro.py` |
| **RMSE headline (~2.07%)** | Single table number aggregating four apps | `summarize_results.py` over 10 `Error Perc` values per log |
| **§5.2 Fig. 9 (optional)** | Synthetic topologies — model accuracy across graphs | 108 configs → `synthetic/*/run.sh` → `draw.py` |
| **Limitation paragraph** | SIGSTOP incomplete for network I/O; future work sidecar/throttle | **Your thesis Phases 3–6** |

**Paper plot conventions (match in thesis):**

- X-axis: optimisation point index or % processing-time reduction on target  
- Y-axis: throughput (req/s)  
- Two curves: **Groundtruth** (actual speedup), **Predicted** (model)  
- Optional third curve in logs: **Slowdown** (POKER emulation)  
- Error: per-point `(predicted − groundtruth) / groundtruth × 100`; summary **RMSE** over 10 points  

Reference appearance: `slowpoke/evaluation/sample_output/*_medium.png`, `plot_macro.pdf`  
Interpretation: [`netpoke/results/reference/FIGURE_INTERPRETATION.md`](../results/reference/FIGURE_INTERPRETATION.md)

---

## 2. Complete inventory — paper vs thesis

### Chapter 2 / baseline (reproduce SlowPoke §5.1)

| ID | SlowPoke paper | NetPoke output | Status | Generate on cluster | Repo path after sync |
|----|----------------|---------------|--------|---------------------|----------------------|
| **B1** | Table RMSE | `TABLE_L0_SUMMARY.md` | Done | `python3 summarize_results.py results/*_medium.log` | `results/cluster/baseline/tables/` |
| **Fig B1–B4** | Fig. 8 panels | `boutique_medium.png` … `movie_medium.png` | Run on VM if missing | `bash plot_fig8_png.sh results/` | `results/cluster/baseline/figures/` |
| **Fig B5** | Fig. 8 macro | `plot_macro.pdf` | Run on VM if missing | `python3 plot_macro.py -r results/` | `results/cluster/baseline/figures/` |

### Chapter 3 / I/O gap (thesis extension — not in paper)

| ID | Thesis figure | Output | Status | Generate | Repo path |
|----|---------------|--------|--------|----------|-----------|
| **I1** | RMSE vs I/O level (4 lines) | `fig_io_gap_rmse.png` + `.pdf` | Done | `python3 io_gap/plot_io_gap_rmse.py results/` | `results/cluster/io_gap/figures/` |
| **T I1** | RMSE matrix L0/L1/L2 | `TABLE_IO_GAP_MATRIX.md`, `io_gap_matrix.csv` | Done | `python3 io_gap/summarize_io_gap_matrix.py results/` | `results/cluster/io_gap/tables/` |
| **Fig I2** (optional) | L2 error curves like Fig. 8 | `draw.py` on `*_io_L2_medium.log` | Optional | `python3 draw.py results/social_io_L2_medium.log` | per-app in `io_gap/figures/` |

### Chapter 4 / eBPF & residual I/O (thesis — not in paper)

| ID | Thesis figure | Output | Status | Generate | Repo path |
|----|---------------|--------|--------|----------|-----------|
| **T E1** | Residual I/O + RMSE table | `TABLE_EBPF_SUMMARY.md`, `ebpf_residual_summary.csv` | **3/4** (boutique TBD) | `python3 phase4_ebpf/summarize_ebpf_residual.py results/` | `results/cluster/ebpf/tables/` |
| **Fig E1** | RMSE at L2 (Phase 4) | `fig_ebpf_rmse_L2.png` | After boutique | `python3 phase4_ebpf/plot_ebpf_residual.py results/` | `results/cluster/ebpf/figures/` |
| **Fig E2** | SIGSTOP windows + Δ net RX | `fig_ebpf_residual_io.png` | After boutique | same | same |
| **Fig E3** | RMSE vs Δ net RX scatter | `fig_ebpf_rmse_vs_netrx.png` | After boutique | same | same |
| **D3** | Raw JSONL + logs | `*_ebpf_L2_*` | 3/4 on VM | — | `results/cluster/ebpf/logs/` |

### Chapter 5–6 / NetPoke (planned)

| ID | Content | Output | Status |
|----|---------|--------|--------|
| **Fig N0** | POKER pause timeline (SIGSTOP vs NetPoke) | Draw from `design/poker-io-pause.md` | Design doc |
| **Fig N1** | RMSE before/after NetPoke (L2) | Bar chart Phase 3 L2 vs Phase 6 | Phase 6 |
| **T N1** | Full comparison table | 4 apps × {L0, L2 SIGSTOP, L2 NetPoke} | Phase 6 |
| **Fig N2** | Residual I/O with NetPoke on | Re-run Phase 4 sampler with `SLOWPOKE_NETPOKE=1` | Phase 5–6 |
| **T N2** | Overhead per pause | Timers in POKER / eBPF | Phase 6 |

---

## 3. One-command downloads (presentation pack)

### On netpoke-control (after boutique completes)

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation
bash phase4_ebpf/finalize_phase4_results.sh
# → figures in results/final_package/
# → ~/netpoke_presentation_pack_YYYYMMDD.tar.gz
```

Or pack only (without Phase 4 verify):

```bash
bash scripts/build_presentation_pack.sh
```

### Download to laptop (Cloud Shell)

```bash
gcloud compute scp --zone=us-central1-a \
  aframviscagyebi@netpoke-control:~/netpoke_presentation_pack_*.tar.gz \
  ~/
cloudshell download ~/netpoke_presentation_pack_YYYYMMDD.tar.gz
```

### Windows (local)

```powershell
gcloud compute scp --zone=us-central1-a `
  aframviscagyebi@netpoke-control:~/netpoke_presentation_pack_YYYYMMDD.tar.gz `
  G:\projects\netpoke\
```

Unpack → copy into `netpoke/results/cluster/` tree for git commit.

---

## 4. Slide deck structure (mirrors paper + thesis arc)

| Slide block | Content | Assets |
|-------------|---------|--------|
| 1. Problem | SlowPoke + SIGSTOP limitation (quote paper) | Paper figure or architecture sketch |
| 2. Baseline | Fig. 8 style — your cluster RMSE ~9–14% | `baseline/*.png`, `TABLE_L0_SUMMARY.md` |
| 3. I/O gap | RMSE rises L0→L2 (social +14 pp) | `fig_io_gap_rmse.png`, `TABLE_IO_GAP_MATRIX.md` |
| 4. Mechanism | Residual Δ net RX during pause | `fig_ebpf_residual_io.png`, `TABLE_EBPF_SUMMARY.md` |
| 5. NetPoke fix | sch_plug timeline | `design/poker-io-pause.md` diagram |
| 6. Evaluation | RMSE restoration | Phase 6 Fig N1 (future) |
| Appendix | Logs, JSONL, reproducibility | `ebpf/logs/`, pack tarball |

---

## 5. The moment boutique finishes — checklist

Run on **netpoke-control** (boutique screen still finishing is OK to wait):

```bash
cd ~/slowpoke/evaluation

# Verify all four
for app in social hotel movie boutique; do
  grep -q 'Error Perc:' results/${app}_ebpf_L2_medium.log && \
  echo "$app OK ($(grep -c '\[exp\] Throughput:' results/${app}_ebpf_L2_medium.log)/21)"
done

# Finalize Phase 4
bash phase4_ebpf/finalize_phase4_results.sh
```

**Update repo tables** (local, after scp pack):

1. Copy `ebpf_residual_summary.csv` → `netpoke/results/cluster/ebpf/tables/`  
2. Update `TABLE_EBPF_SUMMARY.md` boutique row from CSV  
3. Copy figures → `netpoke/results/cluster/ebpf/figures/`  
4. Copy logs/jsonl → `netpoke/results/cluster/ebpf/logs/`  

**Then Phase 5** — see [`PHASE5_6_READINESS.md`](PHASE5_6_READINESS.md).

---

## 6. Partial download (already done — 3/4 apps)

You already have `~/netpoke_phase4_partial_3of4_20260613.tar.gz` with social/hotel/movie.  
After boutique: run full `finalize_phase4_results.sh` and replace partial with complete pack.

---

## 7. Reference files in repo

| Document | Path |
|----------|------|
| SlowPoke paper study | `netpoke/docs/slowpoke-paper-deep-dive.md` |
| Evaluation process | `netpoke/docs/slowpoke-evaluation-process.md` |
| Master roadmap | `netpoke/docs/thesis-evaluation-roadmap.md` |
| Results layout | `netpoke/results/README.md` |
| NetPoke design | `netpoke/design/poker-io-pause.md` |
| Handoff | `netpoke/CONTINUE_FROM_HERE.md` |

---

*Sync new scripts to VM before finalize: `phase4_ebpf/plot_ebpf_residual.py`, `finalize_phase4_results.sh`, `scripts/build_presentation_pack.sh`, patched `watch_progress.sh`.*
