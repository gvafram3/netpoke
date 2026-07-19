# NetPoke documentation

## Study guides (downloadable)

| File | Format | Description |
|------|--------|-------------|
| [`slowpoke-paper-deep-dive.md`](slowpoke-paper-deep-dive.md) | Markdown | Source — SlowPoke paper deep study guide |
| [`slowpoke-paper-deep-dive.docx`](slowpoke-paper-deep-dive.docx) | **Word** | Same content for offline reading |

Regenerate Word after editing markdown:

```bash
cd netpoke/docs && python3 build_slowpoke_guide_docx.py
```

Requires: `pip install python-docx`

## Operations

| File | Description |
|------|-------------|
| [`../README.md`](../README.md) | Project overview, current status, how to replicate |
| [`../INSTRUCTIONS.md`](../INSTRUCTIONS.md) | Artifact manual (experiments branch) |
| [`METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`](METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md) | **Canonical reference** — findings, fix plan, and the dated Live status log (the up-to-date "where are we" record) |

Thesis drafts: branch `netpoke/thesis-material`, folder `netpoke/thesis/`.

Older planning/status docs (superseded by the two files above) have moved to
[`deprecated/`](deprecated/README.md) rather than being deleted, since they
still have historical value.
