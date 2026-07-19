# NetPoke artifact — reproduction instructions

Extends **SlowPoke** (Xie et al., NSDI 2026) with I/O-gap measurement and **NetPoke**
(network-synchronised pause). Follow the same workflow as
[`slowpoke/INSTRUCTIONS.md`](../slowpoke/INSTRUCTIONS.md): functional smoke test →
reproducible benchmarks → plots → thesis extensions.

## Branches

| Branch | Purpose |
|--------|---------|
| **`netpoke/experiments`** | Active evaluation work, results layout, scripts |
| **`netpoke/thesis-material`** | Chapter drafts and writeups (separate from experiment branch) |
| `netpoke26-thesis` | Integration / defense snapshot |

```bash
git clone https://github.com/gvafram3/netpoke.git
cd netpoke
git checkout netpoke/experiments
```

**Project overview and current status:** [`README.md`](README.md)

## Where experiments run

| Location | Role |
|----------|------|
| **netpoke-control** (GCP VM) | All benchmarks, logs, plots |
| **Cloud Shell** | `git pull`, `gcloud compute scp`, download tarballs |
| **This repo** | Scripts, reference figures, synced results under `netpoke/results/` |

**Do not** run `draw.py` from Cloud Shell unless logs are copied there first.  
`~/slowpoke` exists only on **netpoke-control**, not Cloud Shell.

```bash
# Correct — on netpoke-control
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation
python3 summarize_results.py results/boutique_medium.log
bash plot_fig8_png.sh results/
```

---

# 1. Artifact functional (~5 min)

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation
bash install_netpoke_fixes.sh
./run_functional.sh
```

**Pass:** `results/boutique_tiny.log` exists (accuracy not required).

---

# 2. SlowPoke baseline — §5.1 / Fig. 8 (~2.5 h all four apps)

```bash
screen -S slowpoke-repro
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./run_with_monitor.sh ./run_reproducible.sh
```

**Pass per app:** `Error Perc:` in log; 21 `[exp] Throughput:` lines.

**Tables + figures (paper format):**

```bash
python3 summarize_results.py results/*_medium.log
bash plot_fig8_png.sh results/
```

**Pack for repo / download:**

```bash
bash scripts/pack_results_for_repo.sh
gcloud compute scp --zone=us-central1-a \
  aframviscagyebi@netpoke-control:~/netpoke_results_pack_*.tar.gz .
```

Reference appearance: [`netpoke/results/reference/figures/`](../netpoke/results/reference/figures/)

---

# 3. Phase 3 — I/O gap (8 runs, complete)

```bash
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./io_gap/run_io_gap_all.sh
python3 io_gap/summarize_io_gap_matrix.py results/ -o results/final_package/io_gap_matrix.csv
python3 io_gap/plot_io_gap_rmse.py results/
bash io_gap/verify_io_gap_results.sh results/
```

**Boutique re-run** (product_catalog path — replaces shipping injection):

```bash
bash io_gap/run_boutique_io_rerun.sh
```

---

# 4. Phase 4 — eBPF residual I/O (all benchmarks L2)

```bash
cd ~/slowpoke/evaluation
bash phase4_ebpf/preflight_ebpf.sh          # verify
bash phase4_ebpf/run_ebpf_smoke.sh          # ~5–10 min smoke

screen -S phase4-ebpf
WATCH_INTERVAL=10 ./phase4_ebpf/run_ebpf_all_L2.sh   # ~3–4 h full suite
```

**SSH 2 monitor:** `WATCH_INTERVAL=10 SLOWPOKE_PHASE4_EBPF=1 ./watch_progress.sh --append results/`

See [`slowpoke/evaluation/phase6_netpoke/README.md`](../slowpoke/evaluation/phase6_netpoke/README.md)
(the in-pod `/proc` sampler that replaced the original eBPF plan — see finding F2 in
[`docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`](docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md)).

---

# 5. Phase 5–6 — NetPoke

Design: [`design/poker-io-pause.md`](design/poker-io-pause.md)  
Re-run L2 matrix with NetPoke enabled; compare RMSE to Phase 3.

---

# 6. Results in this repository

| Path | Content |
|------|---------|
| [`netpoke/results/README.md`](../netpoke/results/README.md) | Layout |
| `netpoke/results/reference/` | Paper-format examples (authors' sample) |
| `netpoke/results/cluster/` | Your cluster logs, figures, tables |

---

# 7. Key scripts

| Script | Purpose |
|--------|---------|
| `slowpoke/evaluation/summarize_results.py` | Per-point table + RMSE (paper) |
| `slowpoke/evaluation/draw.py` | Fig. 8 panels |
| `slowpoke/evaluation/plot_macro.py` | Fig. 8 macro PDF |
| `slowpoke/evaluation/io_gap/summarize_io_gap_matrix.py` | Table I1 |
| `slowpoke/evaluation/io_gap/plot_io_gap_rmse.py` | I/O-gap RMSE figure |
| `slowpoke/evaluation/scripts/pack_results_for_repo.sh` | Tarball for scp |
| `slowpoke/evaluation/io_gap/run_boutique_io_rerun.sh` | Boutique L1/L2 only |

Canonical reference (findings, fix plan, dated status log): [`docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`](docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md)  
**SlowPoke paper study guide (Word):** [`docs/slowpoke-paper-deep-dive.docx`](docs/slowpoke-paper-deep-dive.docx)
