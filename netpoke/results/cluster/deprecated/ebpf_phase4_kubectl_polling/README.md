# Phase 4 eBPF / residual I/O results — DEPRECATED, do not cite as RQ2 evidence

Moved here from `netpoke/results/cluster/ebpf/`. The sampler that produced these
numbers (`slowpoke/evaluation/phase4_ebpf/deprecated/residual_io_sampler.py`)
polls too slowly to resolve individual SIGSTOP pause windows — see
`netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md` (finding F2). The RMSE
figures inherited here (Phase 1/3 baselines) remain valid; the residual I/O
byte/syscall counts do not support a "kernel evidence of pause-time leakage"
claim as measured. Corrected results will land in
`netpoke/results/cluster/phase6_netpoke/` once produced.

```text
ebpf/
├── logs/          ← *_ebpf_L2_medium.log, *_ebpf_L2_residual.jsonl
├── tables/        ← ebpf_residual_summary.csv (from summarize_ebpf_residual.py)
└── figures/       ← F8 plots (after analysis)
```

Generate on **netpoke-control**, pack with `scripts/pack_results_for_repo.sh`.

See [`netpoke/evaluation/phase4_ebpf/README.md`](../../../evaluation/phase4_ebpf/README.md).
