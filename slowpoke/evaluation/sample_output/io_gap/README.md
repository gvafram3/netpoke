# Reference logs: boutique I/O-gap experiments

These logs are **examples** of SlowPoke runs with added I/O intensity on
Online Boutique (early exploration). They are **not** the GCP cluster baseline
runs — those live only on `netpoke-control` under `evaluation/results/`.

Use them as format references when building Phase 3 I/O-level scripts for
**all four** benchmarks (see `netpoke/docs/thesis-evaluation-roadmap.md`).

| File | Notes |
|------|-------|
| `boutique_io_medium.log` | I/O-augmented boutique medium |
| `boutique_io_sleep_medium.log` | Synthetic sleep injection |
| `boutique_io_cart_medium.log` | Cart-target variant |

Analyze with: `python3 ../../summarize_results.py <log>`
