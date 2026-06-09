# Phase 3 I/O-gap results (thesis-aligned design)

**Design:** L0/L1/L2 share the same `-x` target; L1/L2 add path netem on downstream services.  
**Cluster:** netpoke-control · **Suite:** **8/8** + boutique product_catalog re-run (2026-06-09)

Regenerate on cluster:

```bash
cd ~/slowpoke/evaluation
python3 io_gap/summarize_io_gap_matrix.py results/ -o results/final_package/io_gap_matrix.csv
bash io_gap/verify_io_gap_results.sh results/
python3 io_gap/plot_io_gap_rmse.py results/
```

## RMSE vs I/O level (GCP cluster — final)

| App | Level | Target / injection | Baseline (req/s) | RMSE % | Mean \|err\| % |
|-----|-------|-------------------|------------------|--------|---------------|
| Boutique | L0 | cart | 1820.0 | 9.19 | 7.44 |
| Boutique | L1 | cart (+netem productcatalog:30ms) | 1715.6 | 6.93 | 6.05 |
| Boutique | L2 | cart (+netem productcatalog:50ms,currency:30ms) | 1739.0 | 5.61 | 4.39 |
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
| **Social** | 10.34% | 24.64% | **+14.30** | L1 peak (26.04) | **Yes** |
| **Hotel** | 10.23% | 16.28% | **+6.05** | Yes | **Yes** |
| **Movie** | 13.97% | 16.72% | **+2.75** | L1 peak (19.18) | **Yes** |
| **Boutique** | 9.19% | 5.61% | **−3.59** | No (decreasing) | **No** |

## Chapter 3 conclusion (draft)

SIGSTOP-only prediction error **rises with path netem injection** for **three of four** benchmarks (**hotel**, **social**, **movie**). **Boutique** (`cart` target) remains an outlier after moving injection from shipping to **product_catalog** (+ currency on L2): RMSE **decreases** at L1/L2 vs L0.

**Strongest evidence:** social (+14.3 pp), hotel (+6.1 pp, monotonic).

**Boutique:** Case study — correct path placement does not guarantee monotonic RMSE growth; cart workload may remain CPU-limited relative to storage-heavy apps.

## Next: Phase 4 (eBPF)

Priority L2: **social**, **hotel**, **movie**, then **boutique** (optional — check residual I/O even if RMSE flat).
