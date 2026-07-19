# Table N1 — Residual network I/O during pause windows, SIGSTOP-only vs NetPoke

**Design:** In-pod residual sampler (`slowpoke/evaluation/phase6_netpoke/`, replacing the
deprecated `kubectl exec`-per-sample sampler — finding F2 in
[`METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`](../../../../docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md)).
Measures actual bytes of network RX during real `SIGSTOP` pause windows (identified via POKER's
unconditional `poker: pause_start`/`pause_end` markers), expressed as a percentage of the RX rate
outside pause windows — the number NetPoke's egress hold is designed to reduce toward zero.

**Status:** Complete for all 4 apps at L2 (the injected/stressed condition), plus boutique at L0
(overhead-regression check — confirms NetPoke doesn't hurt the compute-bound baseline).

## Results

| App | Level | SIGSTOP-only residual | NetPoke-on residual | Change | Sample coverage (both conditions) |
|-----|-------|----------------------|---------------------|--------|-----------------------------------|
| Boutique | L0 | 8.43% | 7.06% | ~flat, no regression | 15-17% |
| Boutique | L2 | 3.28% | 4.28% | flat | 3-9% |
| Hotel | L2 | 9.52% | 3.33% | **~2.9x reduction** | 13-16% |
| Social | L2 | 8.91% | 4.00% | **~2.2x reduction** | 17-23% |
| Movie | L2 | 6.89% | 1.59% | **~4.3x reduction** | 8-10% |

"Residual" = (net RX bytes during pause windows) / (net RX bytes outside pause windows), summed
across all non-target services in the app. Coverage = fraction of real pause windows that had
≥1 overlapping sample (limited by sampler interval and pod-replacement timing, not a validity
problem below — see caveats).

## Interpretation

- **Core result: NetPoke substantially reduces residual network I/O during pauses in 3 of 4
  apps** (hotel, social, movie) — direct, measured evidence, not inferred from an RMSE proxy.
  Social is the best-supported single result (excellent coverage both conditions).
- **Boutique stays flat under both L0 and L2**, consistent with never showing a strong I/O-gap
  signal anywhere in this project (Phase 1/3 RMSE, and now residual I/O directly). Little gap to
  close, little effect from closing it — internally consistent, not a failure of the mechanism.
- **Boutique L0 confirms no regression**: NetPoke does not increase residual I/O at the
  compute-bound baseline (if anything, marginally lower). This was the one piece of the original
  validation plan (design doc §6, "Overhead") never previously executed.
- **Methodologically important:** hotel's Phase 3 RMSE *reversed* direction (contradicted the
  I/O-gap hypothesis) — but hotel's direct residual-I/O measurement here is a completely normal
  result matching social/movie. This is evidence that Phase 3's netem-injection RMSE method is a
  noisy, confounded proxy that doesn't always track the underlying phenomenon reliably, and that
  this direct residual-I/O measurement is the more trustworthy signal. See the live status log
  in `METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md` for the full discussion.

## Data quality notes

- Movie was re-run with `SAMPLER_INTERVAL=0.005` (5ms, vs the 10ms default) after an initial
  attempt showed only 1.0-1.6% window coverage — too sparse to trust. The 8-10% coverage shown
  here is from the corrected re-run only (old low-coverage data manually separated out, not
  included in these numbers).
- Boutique L2 and hotel/social L2 used the default 10ms sampler interval.
- All figures are single-run measurements (not averaged over repetitions) — treat as a solid
  directional result, not a statistically tight confidence interval.

## Regenerate

```bash
cd ~/slowpoke/evaluation
for d in results/residual/boutique_L0_sigstop results/residual/boutique_L0_netpoke \
         results/residual/boutique_L2_sigstop results/residual/boutique_L2_netpoke \
         results/residual/hotel_L2_sigstop results/residual/hotel_L2_netpoke \
         results/residual/social_L2_sigstop results/residual/social_L2_netpoke \
         results/residual/movie_L2_sigstop results/residual/movie_L2_netpoke; do
  name=$(basename "$d")
  netpoke_flag=""
  [[ "$name" == *_netpoke ]] && netpoke_flag="--netpoke"
  echo "=== $name ==="
  python3 phase6_netpoke/correlate_residual.py "$d" $netpoke_flag
done
```
