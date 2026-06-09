# Phase 4 — eBPF residual I/O during SIGSTOP pauses

**Objective (O2 / RQ2):** Measure bytes and syscalls that continue during POKER pause windows; correlate with Phase 3 prediction error.

## When to run

After Phase 3 I/O-gap matrix is complete. Run during **L2 (heavy I/O)** configurations — same targets and injections as `io_gap/io_levels.conf`.

## Priority order

1. Social L2 (`hometimeline` + poststorage 50ms + socialgraph 30ms) — largest gap  
2. Hotel L2 (`profile` + rate 50ms + user 30ms) — monotonic gap  
3. Movie L2 (`moviereviews` + reviewstorage 50ms + movieinfo 30ms)  
4. Boutique L2 (after product_catalog re-run)

## Measurements (per thesis roadmap)

- Bytes received/sent on service interface during pause windows  
- Syscall counts (`read`, `write`, `recvfrom`, …) while process is SIGSTOP'd  
- Later: compare SIGSTOP-only vs NetPoke (Phase 6)

## Deliverables

| ID | Output |
|----|--------|
| T3 | Residual I/O (bytes) vs pause duration |
| T4 | Correlation: residual I/O vs Error % |
| F8 | CDF or bar chart (4 apps or representative subset) |
| D3 | `results/cluster/ebpf/*_ebpf_*.log` |

## Implementation status

- [ ] eBPF probe scripts (scale from reference `experiment_f_*` logs when available on cluster)  
- [ ] Wrapper: run medium benchmark with eBPF attached to paused non-target pods  
- [ ] `summarize_ebpf_residual.py` → tables under `netpoke/results/cluster/ebpf/tables/`

## Cluster placeholder

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation
# TBD: bash phase4_ebpf/run_ebpf_during_io_L2.sh social
```

Results pack into repo via `scripts/pack_results_for_repo.sh` (extend for ebpf/).
