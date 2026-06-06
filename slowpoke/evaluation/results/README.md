# Evaluation results (runtime directory)

This directory holds **logs and plots produced on your cluster** (`netpoke-control`).
It is intentionally **empty in git** — same pattern as SlowPoke's artifact (outputs are
generated locally, reference outputs are under `sample_output/`).

## After a run

| File | Meaning |
|------|---------|
| `*_medium.log` | Full medium benchmark (needs `Error Perc:`) |
| `saved/` | Timestamped backups (use `run_social_movie.sh` or manual `cp`) |
| `*.png`, `plot_macro.pdf` | From `plot_fig8_png.sh` |

## Verify

```bash
bash verify_benchmark_results.sh .
python3 ../summarize_results.py *_medium.log
```

See [`netpoke/docs/thesis-evaluation-roadmap.md`](../../../netpoke/docs/thesis-evaluation-roadmap.md).
