# Phase 3 I/O-gap results (thesis-aligned design)

**Design:** L0/L1/L2 share the same `-x` target; L1/L2 add path netem on downstream services.  
**Cluster:** netpoke-control · **Completed:** 2026-06-07  
**Suite progress:** **8 / 8** complete · verification **PASSED**

Regenerate on cluster:

```bash
cd ~/slowpoke/evaluation
python3 io_gap/summarize_io_gap_matrix.py results/ -o results/final_package/io_gap_matrix.csv
bash io_gap/verify_io_gap_results.sh results/
```

**Archive:** `slowpoke_phase3_20260607.tar.gz` (logs + CSV on netpoke-control).

## RMSE vs I/O level (GCP cluster — final)

| App | Level | Target / injection | Baseline (req/s) | RMSE % | Mean \|err\| % |
|-----|-------|-------------------|------------------|--------|---------------|
| Boutique | L0 | cart | 1820.0 | 9.19 | 7.44 |
| Boutique | L1 | cart (+netem shipping:30ms) | 2067.0 | 11.53 | 6.75 |
| Boutique | L2 | cart (+netem shipping:50ms) | 2096.9 | 3.07 | 2.37 |
| Hotel | L0 | profile | 563.2 | 10.23 | 8.83 |
| Hotel | L1 | profile (+netem rate:30ms) | 593.2 | 13.90 | 11.16 |
| Hotel | L2 | profile (+netem rate:50ms,user:30ms) | 675.5 | 16.28 | 14.94 |
| Social | L0 | hometimeline | 930.0 | 10.34 | 6.94 |
| Social | L1 | hometimeline (+netem poststorage:30ms) | 820.9 | 26.04 | 20.19 |
| Social | L2 | hometimeline (+netem poststorage:50ms,socialgraph:30ms) | 839.5 | 24.64 | 22.88 |
| Movie | L0 | moviereviews | 611.2 | 13.97 | 12.08 |
| Movie | L1 | moviereviews (+netem reviewstorage:30ms) | 504.7 | 19.18 | 15.16 |
| Movie | L2 | moviereviews (+netem reviewstorage:50ms,movieinfo:30ms) | 696.7 | 16.72 | 14.23 |

## L2 vs L0 RMSE delta (thesis headline)

| App | L0 RMSE | L2 RMSE | Δ (pp) | Monotonic L0→L1→L2? | Supports RQ1? |
|-----|---------|---------|--------|---------------------|---------------|
| **Social** | 10.34% | 24.64% | **+14.30** | L1 peak (26.04); L2 slight dip | **Yes** (large gap) |
| **Hotel** | 10.23% | 16.28% | **+6.05** | Yes | **Yes** |
| **Movie** | 13.97% | 16.72% | **+2.75** | L1 peak (19.18) | **Yes** (modest) |
| **Boutique** | 9.19% | 3.07% | **−6.12** | No | **No** (outlier) |

## Chapter 3 conclusion (draft)

SIGSTOP-only prediction error **rises with path I/O intensity** for **three of four** benchmarks when netem is placed on services on the causal dependency chain (**hotel**, **social**, **movie**). **Boutique** (`cart` + shipping netem) is a negative result: RMSE falls at L2, consistent with shipping being weakly on the `cart` path.

**Strongest evidence:** social (+14.3 pp L2 vs L0), hotel (+6.1 pp, monotonic).

## Run completion

All eight logs in `results/` contain `Error Perc:` and 21 throughput lines each.

| Run | Log |
|-----|-----|
| boutique L1/L2 | `boutique_io_L1_medium.log`, `boutique_io_L2_medium.log` |
| hotel L1/L2 | `hotel_io_L1_medium.log`, `hotel_io_L2_medium.log` |
| social L1/L2 | `social_io_L1_medium.log`, `social_io_L2_medium.log` |
| movie L1/L2 | `movie_io_L1_medium.log`, `movie_io_L2_medium.log` |

## Operational notes

- **Movie `num_req`:** `IO_NUM_REQ_MOVIE=20000` (matches `run-movie-medium.sh`).
- **Boutique:** discuss injection placement in Ch. 3; do not use as primary I/O-gap figure.

## Next: Phase 4 (eBPF)

Priority L2 configs for residual-I/O measurement: **social L2**, **hotel L2**, **movie L2**. Boutique L2 optional (weak/negative gap).
