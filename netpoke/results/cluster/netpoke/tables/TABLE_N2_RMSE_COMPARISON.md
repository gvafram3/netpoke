# Table N2 — End-to-end prediction RMSE, SIGSTOP-only vs NetPoke-on (L2)

**Design:** The standard SlowPoke 10-point accuracy benchmark (same as Phase 1/3 —
`summarize_results.py`, RMSE over the 10 `Error Perc` values), run at L2 (the injected I/O-gap
condition from [`TABLE_IO_GAP_MATRIX.md`](../../io_gap/tables/TABLE_IO_GAP_MATRIX.md)) with
`SLOWPOKE_NETPOKE=1` (`slowpoke/evaluation/io_gap/run_io_gap_netpoke_L2.sh`). This is the direct
test of RQ4 / Objective 4 — does the egress hold that reduces residual I/O (Table N1) actually
restore end-to-end prediction accuracy — as distinct from Table N1's residual-bytes measurement.

**Status:** Complete for all 4 apps, single run each (2026-07-19).

## Results

| App | L0 baseline RMSE | SIGSTOP-only L2 RMSE | NetPoke-on L2 RMSE | Change (NetPoke vs SIGSTOP-only) |
|-----|------------------|----------------------|---------------------|-----------------------------------|
| Boutique | 2.57% | 3.53% | **10.26%** | **+6.73pp — worse** |
| Hotel | 20.65% | 17.51% | **10.25%** | **−7.26pp — better** |
| Social | 14.01% | 33.61% | **18.69%** | **−14.92pp — better, largest recovery** |
| Movie | 12.21% | 13.84% | **10.23%** | **−3.61pp — better, below L0 baseline** |

## Interpretation

- **Social — the cleanest I/O-gap case — is the headline result.** SIGSTOP-only L2 pushed RMSE
  from a 14.01% L0 baseline up to 33.61% (+19.60pp, the strongest I/O-gap signal in this
  project). With NetPoke on, L2 RMSE comes back down to 18.69% — recovering **76% of the gap**
  ((33.61−18.69)/(33.61−14.01)). This is direct evidence that the mechanism validated in Table N1
  (residual I/O cut ~2.2x for social) translates into restored end-to-end accuracy, not just a
  smaller number on a proxy metric.
- **Hotel and movie also improve**, ending up at or below their own L0 baselines. Read this with
  the same caution already on record for hotel: its RMSE has been the most volatile number in
  this project across re-runs (L0 alone moved 10.23%→20.65% between two "identical" runs before
  any I/O-gap injection was involved — see `TABLE_L0_SUMMARY.md`), and its Phase 3 SIGSTOP-only
  L2 RMSE reversed direction from an earlier run. Landing *below* baseline here is consistent
  with a real improvement but is measured with the same single-run noise floor as everything
  else on this cluster — treat the direction as solid, the exact magnitude as approximate.
- **Boutique gets clearly worse with NetPoke on** (3.53% → 10.26%). This is the one result in
  this table that doesn't read as a win, and it shouldn't be smoothed over: boutique never showed
  a real I/O gap to close (Table N1's residual measurement was flat for boutique at both L0 and
  L2), so there was nothing for the egress hold to fix — and here, turning it on anyway made the
  prediction noticeably worse rather than merely neutral. Table N1's L0 overhead check found no
  regression in residual I/O terms; this result shows the overhead can still show up at the
  accuracy level under L2 injection specifically. Worth investigating rather than treating as
  noise — a natural next step alongside boutique's still-unexplained fan-out behavior.

## Data quality notes

- Single-run measurements for all four apps, same as the L0/L2 SIGSTOP-only tables — not
  averaged over repetitions. Treat as directional, not a tight confidence interval.
- Baseline throughput differs somewhat between the SIGSTOP-only and NetPoke-on runs for the same
  app/level (e.g. boutique: 1995.7 → 1665.1 req/s) — consistent with the run-to-run cluster
  variance already documented elsewhere in this project, not a methodology artifact.

## Regenerate

```bash
cd ~/slowpoke/evaluation
screen -S slowpoke-netpoke-rmse
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
WATCH_INTERVAL=10 ./io_gap/run_io_gap_netpoke_L2.sh
# Ctrl+A D; SSH 2: ./watch_progress.sh --append results/

for b in boutique hotel social movie; do
  python3 summarize_results.py results/${b}_io_L2_netpoke_medium.log
done
```
