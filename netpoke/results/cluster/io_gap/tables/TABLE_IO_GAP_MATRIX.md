# Table I1 — RMSE vs I/O level (netpoke-control, final)

**Design:** Fixed `-x` target (same as L0); L1/L2 add tc netem on downstream path services.  
**Status:** 8/8 complete + boutique **product_catalog** re-run (2026-06-09).  
**Superseded:** shipping-injection boutique logs → `results/saved/boutique_shipping_inject_20260607/`

| App | Level | Target / injection | Baseline (req/s) | RMSE (%) | Mean \|err\| (%) |
|-----|-------|-------------------|------------------|----------|----------------|
| Boutique | L0 | cart | 1820.0 | 9.19 | 7.44 |
| Boutique | L1 | cart + productcatalog 30ms | 1715.6 | 6.93 | 6.05 |
| Boutique | L2 | cart + productcatalog 50ms, currency 30ms | 1739.0 | 5.61 | 4.39 |
| Hotel | L0 | profile | 563.2 | 10.23 | 8.83 |
| Hotel | L1 | profile + rate 30ms | 593.2 | 13.90 | 11.16 |
| Hotel | L2 | profile + rate 50ms, user 30ms | 675.5 | 16.28 | 14.94 |
| Social | L0 | hometimeline | 930.0 | 10.34 | 6.94 |
| Social | L1 | hometimeline + poststorage 30ms | 820.9 | 26.04 | 20.19 |
| Social | L2 | hometimeline + poststorage 50ms, socialgraph 30ms | 839.5 | 24.64 | 22.88 |
| Movie | L0 | moviereviews | 611.2 | 13.97 | 12.08 |
| Movie | L1 | moviereviews + reviewstorage 30ms | 504.7 | 19.18 | 15.16 |
| Movie | L2 | moviereviews + reviewstorage 50ms, movieinfo 30ms | 696.7 | 16.72 | 14.23 |

## L2 − L0 RMSE delta (thesis headline)

| App | L0 → L2 RMSE | Δ (pp) | Monotonic L0→L1→L2? | Supports I/O-gap stimulus (RQ1)? |
|-----|--------------|--------|----------------------|----------------------------------|
| Social | 10.34% → 24.64% | **+14.30** | L1 peak (26.04) | **Yes** (strongest) |
| Hotel | 10.23% → 16.28% | **+6.05** | Yes | **Yes** |
| Movie | 13.97% → 16.72% | **+2.75** | L1 peak (19.18) | **Yes** (modest) |
| Boutique | 9.19% → 5.61% | **−3.59** | No (9.19 → 6.93 → 5.61) | **No** (outlier) |

## Interpretation

- **Hotel, social, movie:** Path netem under SIGSTOP-only slowdown **increases** prediction RMSE — consistent with the paper’s acknowledged I/O limitation when synchronous path I/O grows.
- **Boutique (cart):** After correcting injection to **product_catalog** (+ **currency** on L2), RMSE **falls** at L1 and L2 vs L0. This does **not** show the same monotonic error growth. Plausible readings: cart path remains relatively **CPU-bound** in this workload; added netem **reshapes** bottlenecks rather than only increasing I/O stress on the paused services; run-to-run variance. **Do not** use boutique as the primary Fig. for I/O-gap magnitude — use **social** and **hotel**.
- **Paper gap** is still supported at the programme level (**3/4** benchmarks). Boutique is a **case study** in when the netem stimulus does not track the theoretical I/O-bound failure mode.

Regenerate on cluster:

```bash
python3 io_gap/summarize_io_gap_matrix.py results/
python3 io_gap/plot_io_gap_rmse.py results/
```
