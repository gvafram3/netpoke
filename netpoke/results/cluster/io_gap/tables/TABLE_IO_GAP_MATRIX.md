# Table I1 — RMSE vs I/O level (netpoke-control, final)

**Design:** Fixed `-x` target (same as L0); L1/L2 add tc netem on downstream path services.

## Current (2026-07-17) — fresh re-run on the bug-fixed harness

Collected immediately after the fresh Phase 1 baseline re-run (see
[`TABLE_L0_SUMMARY.md`](../../baseline/tables/TABLE_L0_SUMMARY.md)), same corrected injection
targets as the previous (superseded) run below. This is the matrix of record going forward.

| App | Level | Target / injection | Baseline (req/s) | RMSE (%) | Mean \|err\| (%) |
|-----|-------|-------------------|------------------|----------|----------------|
| Boutique | L0 | cart | 1937.3 | 2.57 | 2.13 |
| Boutique | L1 | cart + productcatalog 30ms | 2002.1 | 4.85 | 3.89 |
| Boutique | L2 | cart + productcatalog 50ms, currency 30ms | 1995.7 | 3.53 | 2.63 |
| Hotel | L0 | profile | 723.9 | 20.65 | 16.99 |
| Hotel | L1 | profile + rate 30ms | 729.5 | 20.03 | 16.27 |
| Hotel | L2 | profile + rate 50ms, user 30ms | 768.7 | 17.51 | 14.88 |
| Social | L0 | hometimeline | 959.9 | 14.01 | 10.85 |
| Social | L1 | hometimeline + poststorage 30ms | 943.3 | 30.33 | 22.13 |
| Social | L2 | hometimeline + poststorage 50ms, socialgraph 30ms | 788.1 | 33.61 | 28.29 |
| Movie | L0 | moviereviews | 550.8 | 12.21 | 10.01 |
| Movie | L1 | moviereviews + reviewstorage 30ms | 626.8 | 28.48 | 18.46 |
| Movie | L2 | moviereviews + reviewstorage 50ms, movieinfo 30ms | 651.9 | 13.84 | 12.40 |

### L2 − L0 RMSE delta (fresh)

| App | L0 → L2 RMSE | Δ (pp) | Monotonic L0→L1→L2? | Supports I/O-gap stimulus (RQ1)? |
|-----|--------------|--------|----------------------|----------------------------------|
| Social | 14.01% → 33.61% | **+19.60** | **Yes** (14.01 → 30.33 → 33.61) | **Yes** (strongest, cleanest of all four) |
| Movie | 12.21% → 13.84% | **+1.63** | No — L1 spikes to 28.48, then drops back | Ambiguous — net positive but not a clean trend |
| Boutique | 2.57% → 3.53% | **+0.96** | No — L1 (4.85) is the peak, L2 dips below it | Weakly yes — net positive now, no longer a contradicting outlier, but not clean |
| Hotel | 20.65% → 17.51% | **−3.14** | Yes, but **decreasing** (20.65 → 20.03 → 17.51) | **No** — reversed from the previous run's clean supporting result |

### Honest read of the fresh data — this is more mixed than the old result, not cleaner

Worth stating plainly rather than picking the flattering parts: **social is now the strongest,
cleanest evidence for the I/O-gap hypothesis this project has produced** — a genuinely monotonic
+19.6pp increase, stronger and cleaner than before. But **hotel has flipped**: it used to be the
second-cleanest supporting result (+6.05pp, monotonic); now it *decreases* with more I/O
intensity, directly contradicting the hypothesis. Movie and boutique both land net-positive but
neither shows a clean monotonic trend (movie's L1 in particular is a large, unexplained spike
that partially resolves by L2).

**A pattern worth noting, not yet explained:** hotel's numbers have been unusually volatile
across this session's re-runs specifically — its Phase 1 (L0) RMSE alone nearly doubled between
the old and fresh runs (10.23% → 20.65%, see `TABLE_L0_SUMMARY.md`) before any I/O-gap injection
is even involved. That's consistent with hotel being more sensitive to whatever varies run-to-run
on this cluster (load, timing, scheduling) than the other three apps, rather than the I/O-gap
mechanism itself behaving differently for hotel. Not investigated further here — flagged as a
real open question, not glossed over. Any thesis claim built on hotel's L0→L2 trend specifically
should note this volatility rather than treat either the old or new hotel numbers as more
"correct" without further repetitions to separate signal from noise.

**Bottom line for now:** the aggregate evidence for RQ1 (does I/O-gap injection increase
prediction error) still holds at the programme level — 3 of 4 apps show a net increase — but the
per-app story is noisier and less individually clean than the earlier dataset suggested. Lead
with social; treat boutique, movie, and now hotel's specific trend as open case studies rather
than settled supporting or contradicting evidence.

## Previous (pre-this-session, superseded)

**Status:** 8/8 complete + boutique **product_catalog** re-run (2026-06-09).
**Superseded logs:** shipping-injection boutique logs → `results/saved/boutique_shipping_inject_20260607/`

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

### L2 − L0 RMSE delta (previous)

| App | L0 → L2 RMSE | Δ (pp) | Monotonic L0→L1→L2? | Supports I/O-gap stimulus (RQ1)? |
|-----|--------------|--------|----------------------|----------------------------------|
| Social | 10.34% → 24.64% | **+14.30** | L1 peak (26.04) | **Yes** (strongest) |
| Hotel | 10.23% → 16.28% | **+6.05** | Yes | **Yes** |
| Movie | 13.97% → 16.72% | **+2.75** | L1 peak (19.18) | **Yes** (modest) |
| Boutique | 9.19% → 5.61% | **−3.59** | No (9.19 → 6.93 → 5.61) | **No** (outlier) |

## Interpretation (original, kept for context)

- **Hotel, social, movie:** Path netem under SIGSTOP-only slowdown **increases** prediction RMSE — consistent with the paper’s acknowledged I/O limitation when synchronous path I/O grows.
- **Boutique (cart):** After correcting injection to **product_catalog** (+ **currency** on L2), RMSE **falls** at L1 and L2 vs L0. This does **not** show the same monotonic error growth. Plausible readings: cart path remains relatively **CPU-bound** in this workload; added netem **reshapes** bottlenecks rather than only increasing I/O stress on the paused services; run-to-run variance. **Do not** use boutique as the primary Fig. for I/O-gap magnitude — use **social** and **hotel**.
- **Paper gap** is still supported at the programme level (**3/4** benchmarks). Boutique is a **case study** in when the netem stimulus does not track the theoretical I/O-bound failure mode.

Regenerate on cluster:

```bash
python3 io_gap/summarize_io_gap_matrix.py results/
python3 io_gap/plot_io_gap_rmse.py results/
```
