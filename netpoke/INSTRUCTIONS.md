# NetPoke thesis artifact — reproduction instructions

This repository extends **SlowPoke** (Xie et al., NSDI 2026) with **NetPoke**:
I/O-aware causal profiling for microservice throughput prediction.

For evaluation, follow the same discipline as the SlowPoke artifact
([`slowpoke/INSTRUCTIONS.md`](../slowpoke/INSTRUCTIONS.md)): functional smoke test,
then reproducible benchmarks, then plots.

## Reproducibility branch (submit for defense)

| Branch | Purpose |
|--------|---------|
| **`netpoke26-thesis`** | Frozen thesis artifact — scripts, docs, sample outputs (like SlowPoke `nsdi26-ae`) |
| `main` | Integration branch |

```bash
git clone https://github.com/gvafram3/netpoke.git
cd netpoke
git checkout netpoke26-thesis
```

**Naming rule:** branches use `netpoke/…` or `netpoke26-…` only — no tool-generated names.

## Cluster

- **Control:** `netpoke-control` (GCP, `us-central1-a`)
- **Workers:** `worker1`, `worker2`, `worker3`
- **SlowPoke tree on control:** `~/slowpoke` (this repo’s `slowpoke/` directory)

Full runbook: [`netpoke/docs/gcp-run-with-progress.md`](docs/gcp-run-with-progress.md)  
Master roadmap: [`netpoke/docs/thesis-evaluation-roadmap.md`](docs/thesis-evaluation-roadmap.md)

---

# 1. Artifact functional (~5 minutes)

On **netpoke-control**:

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation
bash install_netpoke_fixes.sh
./run_functional.sh
```

**Pass:** `results/boutique_tiny.log` exists (accuracy not required for tiny run).

---

# 2. SlowPoke baseline — §5.1 / Fig. 8 ( ~2.5 h per full suite )

Reproduces SlowPoke prediction accuracy on **four real-world applications**
(boutique, hotel, social, movie). This establishes **baseline RMSE** before
I/O-gap and NetPoke experiments.

```bash
cd ~/slowpoke/evaluation
screen -S slowpoke-repro
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
WATCH_INTERVAL=10 ./run_with_monitor.sh ./run_reproducible.sh
```

Or run individually (recommended after partial completion):

```bash
WATCH_INTERVAL=10 ./run_with_monitor.sh bash movie/run-movie-medium.sh results/movie_medium.log
```

**Second SSH — live progress:**

```bash
SLOWPOKE_ACTIVE_LOG=~/slowpoke/evaluation/results/movie_medium.log \
  WATCH_INTERVAL=10 ./watch_progress.sh --loop-tty
```

**Pass (each app):**

- `results/<app>_medium.log` ends with `Error Perc:`
- 21 `[exp] Throughput:` lines
- `python3 summarize_results.py results/<app>_medium.log` prints RMSE

**Plots (Fig. 8 panels + macro PDF):**

```bash
bash plot_fig8_png.sh results/
# → boutique_medium.png … movie_medium.png, plot_macro.pdf
```

Reference appearance: [`slowpoke/evaluation/sample_output/`](../slowpoke/evaluation/sample_output/)

---

# 3. Synthetic microbenchmarks — Fig. 9 (optional, 2–3 days full suite)

SlowPoke validates the performance model on **108 synthetic service graphs**
under [`slowpoke/evaluation/synthetic/`](../slowpoke/evaluation/synthetic/).
Paper **Figure 9** uses these; the artifact marks them **optional**.

## Relevance for NetPoke

| Use | Priority |
|-----|----------|
| Show you reproduced the **full SlowPoke artifact scope** | High for defense Q&A |
| Isolate topology effects (chain/DAG, sync/async, gRPC/HTTP) separate from DeathStarBench noise | Medium |
| Test NetPoke on **controlled I/O** without modifying boutique/hotel/social/movie | Medium (Phase 3 supplement) |

**Thesis minimum:** four real-world apps (Fig. 8) + your I/O-gap matrix (all four apps).  
**Thesis plus:** 1–3 representative synthetic configs (e.g. `chain-d2-grpc-async`) in an appendix.

## Run one synthetic benchmark

```bash
cd ~/slowpoke
./evaluation/synthetic/chain-d2-grpc-async/run.sh
python3 evaluation/draw.py evaluation/results
```

**Pass (artifact):** three output logs per config; errors mostly 0–6%, within ~15%.

---

# 4. NetPoke thesis experiments (after baseline completes)

See [`docs/thesis-evaluation-roadmap.md`](docs/thesis-evaluation-roadmap.md):

| Phase | Content |
|-------|---------|
| 3 | I/O gap — all four benchmarks × I/O levels L0/L1/L2 |
| 4 | eBPF residual I/O during SIGSTOP |
| 5 | NetPoke (`sch_plug` in POKER) — [`design/poker-io-pause.md`](design/poker-io-pause.md) |
| 6 | Re-run I/O configs with NetPoke; compare RMSE to Phase 2 baseline |

---

# 5. Figures and tables to produce

Aligned with SlowPoke paper + thesis chapters:

| ID | SlowPoke paper | NetPoke output | Script |
|----|----------------|----------------|--------|
| Fig. 8 panels | Per-app Predicted vs Groundtruth | `results/*_medium.png` | `draw.py` |
| Fig. 8 macro | Combined RMSE figure | `results/plot_macro.pdf` | `plot_macro.py` |
| Table | RMSE / per-point errors | `summarize_results.py` | stdout → thesis table |
| Fig. 9 | Synthetic accuracy | optional `synthetic/*/run.sh` | `draw.py` |
| Thesis I/O | — | RMSE vs I/O level (4 apps) | Phase 3 analysis |
| Thesis NetPoke | — | RMSE before/after NetPoke | Phase 6 analysis |

Sample I/O-gap boutique logs (reference only):  
[`slowpoke/evaluation/sample_output/io_gap/`](../slowpoke/evaluation/sample_output/io_gap/)

---

# 6. Download results

Logs are **not** committed (see `slowpoke/evaluation/results/.gitignore`).
Archive on the control node, then `gcloud compute scp` from Cloud Shell.

```bash
cd ~/slowpoke/evaluation
tar czf ~/netpoke_results_$(date +%Y%m%d).tar.gz results/saved results/*.png results/plot_macro.pdf results/*_medium.log
```

---

# 7. Key scripts

| Script | Purpose |
|--------|---------|
| `install_netpoke_fixes.sh` | Preflight cluster + script fixes |
| `run_reproducible.sh` | All four medium benchmarks |
| `run_social_movie.sh` | Social → movie chain with auto-save |
| `verify_benchmark_results.sh` | Check all four logs complete |
| `summarize_results.py` | RMSE tables |
| `plot_fig8_png.sh` | All plots |
