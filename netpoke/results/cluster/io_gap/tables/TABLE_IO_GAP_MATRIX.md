# Table I1 — RMSE vs I/O level (netpoke-control, 2026-06-07)

**Design:** Fixed `-x` target (same as L0); L1/L2 add tc netem on downstream path services.  
**Status:** 8/8 complete. **Boutique rows below used shipping injection — superseded by product_catalog re-run.**

| App | Level | Target / injection | Baseline (req/s) | RMSE (%) | Mean \|err\| (%) |
|-----|-------|-------------------|------------------|----------|----------------|
| Boutique | L0 | cart | 1820.0 | 9.19 | 7.44 |
| Boutique | L1 | cart + shipping 30ms | 2067.0 | 11.53 | 6.75 |
| Boutique | L2 | cart + shipping 50ms | 2096.9 | 3.07 | 2.37 |
| Hotel | L0 | profile | 563.2 | 10.23 | 8.83 |
| Hotel | L1 | profile + rate 30ms | 593.2 | 13.90 | 11.16 |
| Hotel | L2 | profile + rate 50ms, user 30ms | 675.5 | 16.28 | 14.94 |
| Social | L0 | hometimeline | 930.0 | 10.34 | 6.94 |
| Social | L1 | hometimeline + poststorage 30ms | 820.9 | 26.04 | 20.19 |
| Social | L2 | hometimeline + poststorage 50ms, socialgraph 30ms | 839.5 | 24.64 | 22.88 |
| Movie | L0 | moviereviews | 611.2 | 13.97 | 12.08 |
| Movie | L1 | moviereviews + reviewstorage 30ms | 504.7 | 19.18 | 15.16 |
| Movie | L2 | moviereviews + reviewstorage 50ms, movieinfo 30ms | 696.7 | 16.72 | 14.23 |

## L2 − L0 RMSE delta

| App | Δ (pp) | Supports I/O gap? |
|-----|--------|-------------------|
| Social | +14.30 | Yes |
| Hotel | +6.05 | Yes |
| Movie | +2.75 | Yes |
| Boutique (shipping) | −6.12 | No — re-run with product_catalog |

**Interpretation:** SIGSTOP-only error rises when path I/O increases on the causal chain (hotel, social, movie). Boutique shipping injection was off the cart path; replaced in `io_levels.conf`.

Regenerate after boutique re-run:

```bash
python3 io_gap/summarize_io_gap_matrix.py results/
```
