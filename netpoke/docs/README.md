# NetPoke documentation

## Operations

| File | Description |
|------|-------------|
| [`EXPERIMENT_RUNBOOK.md`](EXPERIMENT_RUNBOOK.md) | **Start here for GCP runs** — cluster bring-up, all 6 paired runs, result extraction, teardown |
| [`METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`](METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md) | **Canonical reference** — findings, fix plan, and the dated live status log |
| [`HANDOFF_2026_08_04.md`](HANDOFF_2026_08_04.md) | Full project state as of 2026-08-04 — results so far, bugs fixed, next actions |
| [`ARCHITECTURE_AND_COST_COMPARISON.md`](ARCHITECTURE_AND_COST_COMPARISON.md) | GCP vs AWS cluster comparison, cost estimates, RMSE interpretation |

## Study guides

| File | Format | Description |
|------|--------|-------------|
| [`slowpoke-paper-deep-dive.md`](slowpoke-paper-deep-dive.md) | Markdown | SlowPoke paper deep study guide |
| [`slowpoke-paper-deep-dive.docx`](slowpoke-paper-deep-dive.docx) | Word | Same content for offline reading |

Regenerate Word after editing markdown:

```bash
cd netpoke/docs && python3 build_slowpoke_guide_docx.py
```

Requires: `pip install python-docx`

## Deprecated

Older docs that have been superseded are in [`deprecated/`](deprecated/README.md).
