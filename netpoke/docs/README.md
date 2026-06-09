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
| [`../INSTRUCTIONS.md`](../INSTRUCTIONS.md) | Artifact manual (experiments branch) |
| [`slowpoke-evaluation-process.md`](slowpoke-evaluation-process.md) | What the NSDI artifact actually runs |
| [`gcp-run-with-progress.md`](gcp-run-with-progress.md) | Monitor + screen on netpoke-control |
| [`fetch-boutique-l2-results.md`](fetch-boutique-l2-results.md) | Pack and sync cluster results |

Thesis drafts: branch `netpoke/thesis-material`, folder `netpoke/thesis/`.
