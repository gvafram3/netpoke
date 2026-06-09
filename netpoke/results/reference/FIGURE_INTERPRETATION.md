# Figure interpretation (SlowPoke paper §5.1 / Fig. 8 format)

## Per-application panel (`*_medium.png`)

**What it shows:** Throughput (req/s) vs **optimised processing time on the target** (0%–90%).

| Curve | Meaning |
|-------|---------|
| **Groundtruth** | Measured throughput when the target service is actually sped up |
| **Predicted** | SlowPoke model prediction for the same optimisation |

**Good prediction:** Curves track each other; points stay close.  
**Poor prediction:** Large vertical gap; high `Error Perc` in the log.

**RMSE:** Root mean square of the 10 per-point error percentages (artifact `summarize_results.py`).

Files in `reference/figures/` are from **authors' sample_output** (shows correct plot style).  
Files in `cluster/baseline/figures/` should be your **netpoke-control** runs after `plot_fig8_png.sh`.

## Macro figure (`plot_macro.pdf`)

Combines all four applications with RMSE annotation — same role as **Fig. 8** in the SlowPoke paper.

## I/O-gap figure (`fig_io_gap_rmse.png`)

**Not in the base paper** — NetPoke thesis extension.  
Y-axis: RMSE (%). X-axis: L0 (baseline), L1 (moderate path netem), L2 (heavy path netem).  
**Upward slope** on an app supports the I/O-gap hypothesis (SIGSTOP-only error grows with path I/O).
