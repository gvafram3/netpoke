# Table B1 — SlowPoke baseline (L0 / §5.1 style, netpoke-control)

Standard `run-*-medium.sh`, SIGSTOP-only, one repetition (artifact style).

| App | Target | Baseline throughput (req/s) | RMSE (%) | Log file |
|-----|--------|----------------------------|----------|----------|
| Boutique | cart | 1820.0 | 9.19 | `boutique_medium.log` |
| Hotel | profile | 563.2 | 10.23 | `hotel_medium.log` |
| Social | hometimeline | 930.0 | 10.34 | `social_medium.log` |
| Movie | moviereviews | 611.2 | 13.97 | `movie_medium.log` |

**Interpretation (paper format):** Each log contains 10 optimisation points (0%–90% processing-time reduction on the target). RMSE is computed over the 10 `Error Perc` values (same as SlowPoke artifact `summarize_results.py`). Cluster RMSE is higher than the paper’s 2.07% headline — expected on a smaller cluster; use these numbers for **before/after** comparisons in NetPoke experiments.

**Per-point table:** run on netpoke-control:

```bash
python3 summarize_results.py results/boutique_medium.log
```

**Figure:** `draw.py` → `boutique_medium.png` (Predicted vs Groundtruth). Macro: `plot_macro.py` → `plot_macro.pdf`.
