# Phase 4 — eBPF / residual I/O during SIGSTOP (L2)

Measure bytes and syscalls that continue while non-target processes are **SIGSTOP'd** (state `T`), during **L2** I/O-gap configurations.

**Scripts live in:** `slowpoke/evaluation/phase4_ebpf/` (sync to `~/slowpoke` on netpoke-control).

## Quick start

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation

# 1) Verify environment
bash phase4_ebpf/preflight_ebpf.sh

# 2) Smoke test (~5–10 min)
bash phase4_ebpf/run_ebpf_smoke.sh

# 3) Full suite (~3–4 h) — SSH 1
screen -S phase4-ebpf
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
WATCH_INTERVAL=10 ./phase4_ebpf/run_ebpf_all_L2.sh
# Ctrl+A D

# 4) SSH 2 — scrollable monitor
export WATCH_INTERVAL=10 SLOWPOKE_PHASE4_EBPF=1
cd ~/slowpoke/evaluation
./watch_progress.sh --append results/
```

## Outputs

| File | Content |
|------|---------|
| `<app>_ebpf_L2_medium.log` | Full SlowPoke L2 benchmark log |
| `<app>_ebpf_L2_residual.jsonl` | Residual I/O samples during state `T` |
| `final_package/ebpf_residual_summary.csv` | Table T3/T4 input |

## Order

social → hotel → movie → boutique (largest Phase 3 gap first).

## Pack for repo

```bash
bash scripts/pack_results_for_repo.sh
```

Copy into `netpoke/results/cluster/ebpf/`.
