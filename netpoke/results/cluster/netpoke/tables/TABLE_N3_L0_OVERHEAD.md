# Table N3 — L0 RMSE overhead, SIGSTOP-only vs NetPoke-on (no injection)

**Design:** Same standard SlowPoke 10-point accuracy benchmark as Table N2, but at **L0** — no
`netem` I/O-gap injection at all — run with `SLOWPOKE_NETPOKE=1`
(`slowpoke/evaluation/run_netpoke_l0_overhead.sh`). Directly motivated by Table N2's finding that
NetPoke regresses boutique's L2 RMSE: is that cost specific to the injected/stressed condition,
or does the mechanism cost accuracy even at baseline, with nothing to fix?

**Status:** Complete for all 4 apps, single run each (2026-07-20).

## Results

| App | SIGSTOP-only L0 RMSE | NetPoke-on L0 RMSE | Change (NetPoke vs SIGSTOP-only) |
|-----|----------------------|---------------------|-----------------------------------|
| Boutique | 2.57% | **9.13%** | **+6.56pp — worse** |
| Hotel | 20.65% | **14.13%** | **−6.52pp — better** |
| Social | 14.01% | **17.35%** | **+3.34pp — worse, mild** |
| Movie | 12.21% | **12.13%** | **−0.08pp — flat** |

## Interpretation

- **Boutique's regression is not L2-specific — it's baseline.** +6.56pp at L0 is essentially the
  same magnitude as Table N2's +6.73pp at L2. This directly corroborates
  [`BOUTIQUE_FANOUT_FINDING.md`](BOUTIQUE_FANOUT_FINDING.md): boutique's cart target has zero
  synchronous I/O in its live code path, so NetPoke's egress-hold overhead (netlink toggling, `tc`
  state changes on every `SIGSTOP`/`SIGCONT`) has nothing to offset it *at any injection level*.
  This is now a two-measurement-consistent finding, not a single noisy result.
- **Movie is the cleanest "no harm, real benefit only when needed" case.** Flat at L0 (−0.08pp,
  within noise), and the largest recoverer at L2 in Table N2 (13.84% → 10.23%). The mechanism's
  cost is negligible when there's no real gap, and its benefit shows up exactly when there is one.
- **Social shows a small L0 cost (+3.34pp) alongside its large L2 benefit (−14.92pp in Table N2).**
  Consistent with the same story as movie, just noisier at baseline — a small, roughly constant
  overhead that's overwhelmed by a much larger benefit once there's a real gap to close.
- **Hotel improving at L0 (−6.52pp) should be read with the standing volatility caveat**, not as
  a clean mechanism effect: hotel's SIGSTOP-only L0 RMSE alone has already moved 10.23% → 20.65%
  between two "identical" runs with nothing else changed (`TABLE_L0_SUMMARY.md`). A shift of
  similar size here is as consistent with cluster noise as with a real NetPoke effect — this
  result doesn't resolve that ambiguity, and shouldn't be cited as if it does.

## Overall picture (Tables N1 + N2 + N3 together)

NetPoke's egress hold has a small, roughly constant timing cost per pause window. For apps with
a genuine synchronous-I/O gap on their causal target's request path (hotel, social, movie — see
`BOUTIQUE_FANOUT_FINDING.md` for what "genuine" means here, concretely), that cost is outweighed
by the accuracy recovered at L2. For boutique, whose target has no such gap, there is only the
cost and no benefit, at both L0 and L2 — a consistent, now twice-measured limitation rather than
an unexplained anomaly.

## Data quality notes

- Single-run measurements, same caveat as every other table in this project — not averaged over
  repetitions.
- Baseline throughput again differs somewhat from the SIGSTOP-only runs for the same app (e.g.
  hotel: 723.9 → 440.2 req/s) — consistent with this cluster's known run-to-run variance.

## Regenerate

```bash
cd ~/slowpoke/evaluation
screen -S slowpoke-l0-overhead
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
WATCH_INTERVAL=10 ./run_netpoke_l0_overhead.sh
# Ctrl+A D; SSH 2: ./watch_progress.sh --append results/

for b in boutique hotel social movie; do
  python3 summarize_results.py results/${b}_netpoke_medium.log
done
```
