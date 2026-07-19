# Deprecated planning docs

These describe the Phase 5-6 plan as understood before the methodology audit
in `netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`. That audit found the
NetPoke network-hold mechanism, the Phase 4 "eBPF" sampler, and parts of this
plan's sequencing didn't hold up under inspection. Kept for history; treat
`METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md` as canonical going forward.

## Also kept here (superseded, not deleted)

- `CONTINUE_FROM_HERE.md` — old handoff doc; its role is now the root
  [`README.md`](../../../README.md) plus the Live status log in
  `METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`.
- `PROJECT_STATUS_REPORT.md` — old progress narrative, last updated after
  Phase 3; superseded by the Live status log.
- `thesis-evaluation-roadmap.md` — the original Phase 0-6 plan, written before
  the mechanism rewrite (sidecar `netem` → in-POKER `sch_plug` egress hold).
  Sequencing and some phase names no longer match what was actually built.
- `gcp-run-with-progress.md` — early two-window monitoring notes; superseded
  by the two-window pattern documented in
  `slowpoke/evaluation/phase6_netpoke/README.md` and `netpoke/README.md`.
- `slowpoke-evaluation-process.md` — general SlowPoke-artifact-process notes;
  superseded by `docs/slowpoke-paper-deep-dive.md`.
- `fetch-boutique-l2-results.md` — one-off instructions for a single already-
  completed download task, not a general procedure.
