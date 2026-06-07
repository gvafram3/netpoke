# Phase 3 I/O-gap results (thesis-aligned design)

**Design:** L0/L1/L2 share the same `-x` target; L1/L2 add path netem on downstream services.  
**Cluster:** netpoke-control · **Last updated:** 2026-06-07  
**Suite progress:** **5 / 8** io_gap runs complete in `results/` (social L2 in progress; movie pending)

Regenerate the table on the cluster:

```bash
cd ~/slowpoke/evaluation
python3 io_gap/summarize_io_gap_matrix.py results/ -o results/final_package/io_gap_matrix.csv
```

## RMSE vs I/O level (GCP cluster)

| App | Level | Target / injection | Baseline (req/s) | RMSE % | Mean \|err\| % | Status |
|-----|-------|-------------------|------------------|--------|---------------|--------|
| Boutique | L0 | cart | 1820.0 | 9.19 | 7.44 | complete |
| Boutique | L1 | cart (+netem shipping:30ms) | 2067.0 | 11.53 | 6.75 | complete |
| Boutique | L2 | cart (+netem shipping:50ms) | 2096.9 | 3.07 | 2.37 | complete |
| Hotel | L0 | profile | 563.2 | 10.23 | 8.83 | complete |
| Hotel | L1 | profile (+netem rate:30ms) | 593.2 | 13.90 | 11.16 | complete |
| Hotel | L2 | profile (+netem rate:50ms,user:30ms) | 675.5 | 16.28 | 14.94 | complete |
| Social | L0 | hometimeline | 930.0 | 10.34 | 6.94 | complete |
| Social | L1 | hometimeline (+netem poststorage:30ms) | 820.9 | 26.04 | 20.19 | complete |
| Social | L2 | hometimeline (+netem poststorage:50ms,socialgraph:30ms) | — | — | — | **in progress** |
| Movie | L0 | moviereviews | 611.2 | 13.97 | 12.08 | complete (L0) |
| Movie | L1 | moviereviews (+netem reviewstorage:30ms) | — | — | — | pending |
| Movie | L2 | moviereviews (+netem reviewstorage:50ms,movieinfo:30ms) | — | — | — | pending |

## L2 vs L0 RMSE delta (headline, complete rows only)

| App | L0 RMSE | L2 RMSE | Δ (pp) | Supports RQ1? |
|-----|---------|---------|--------|---------------|
| Boutique | 9.19% | 3.07% | **−6.12** | No (non-monotonic; L1 +2.34 pp) |
| Hotel | 10.23% | 16.28% | **+6.05** | Yes (L0 < L1 < L2) |
| Social | 10.34% | *TBD* | *TBD* | L1 **+15.70 pp** (strong) |
| Movie | 13.97% | *TBD* | *TBD* | pending |

## Run completion (`results/`)

| Run | Log | Complete |
|-----|-----|----------|
| boutique L1 | `boutique_io_L1_medium.log` | yes |
| boutique L2 | `boutique_io_L2_medium.log` | yes |
| hotel L1 | `hotel_io_L1_medium.log` | yes |
| hotel L2 | `hotel_io_L2_medium.log` | yes |
| social L1 | `social_io_L1_medium.log` | yes |
| social L2 | `social_io_L2_medium.log` | **no** (in progress) |
| movie L1 | `movie_io_L1_medium.log` | no |
| movie L2 | `movie_io_L2_medium.log` | no |

Saved copies after each finished run: `results/saved/<app>_io_L*_medium.log`.

**Note:** `results/saved/social_io_L2_medium.log` dated 2026-06-07 06:08 is from an **earlier incomplete / target-switch** attempt — use only logs with `Error Perc:` in `results/`.

## Operational notes

- **Movie `num_req`:** `IO_NUM_REQ_MOVIE=20000` (matches `run-movie-medium.sh`). Using 100000 caused zero-throughput retry loops on the first slowdown experiment.
- **Boutique:** shipping netem on the `cart` path does not show a monotonic I/O gap; discuss injection placement in Ch. 3.
