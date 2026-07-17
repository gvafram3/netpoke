# Table B1 — SlowPoke baseline (L0 / §5.1 style, netpoke-control)

Standard `run-*-medium.sh`, SIGSTOP-only, one repetition (artifact style).

## Current (2026-07-16/17) — fresh re-run on the bug-fixed harness

Collected after this session's fixes to `main.py` (empty-`times` guard), `run.sh` (wrk duration
cap), and `fix_req_n.lua` (nil-guard) — see
[`netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`](../../../docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md).
This is the baseline of record for I/O-gap and NetPoke comparisons going forward.

| App | Target | Baseline throughput (req/s) | RMSE (%) | Log file |
|-----|--------|----------------------------|----------|----------|
| Boutique | cart | 1937.3 | **2.57** | `boutique_medium.log` |
| Hotel | profile | 723.9 | **20.65** | `hotel_medium.log` |
| Social | hometimeline | 959.9 | **14.01** | `social_medium.log` |
| Movie | moviereviews | 550.8 | **12.21** | `movie_medium.log` |

Boutique's 2.57% RMSE is close to the paper's own reported ~2.07% — the best agreement this
project has produced, and evidence the harness fixes were eliminating real measurement
corruption rather than cosmetic bugs. Hotel and social came out higher than the previous run
(below); not yet explained — plausible single-repetition run-to-run variance rather than a
regression, since none of this session's fixes touch hotel/social-specific code paths. See the
live status log in the methodology doc for the full discussion.

## Previous (pre-this-session, superseded)

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
