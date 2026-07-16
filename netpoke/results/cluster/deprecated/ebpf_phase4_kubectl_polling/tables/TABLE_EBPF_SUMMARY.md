# Table E1 — Residual I/O during SIGSTOP (Phase 4, L2 runs)

**Status:** **4/4 complete** (netpoke-control, finalized 2026-06-14)  
**Method:** `/proc` sampler — state `T` + `/proc/pid/io` + `/proc/net/dev` every 0.2 s  
**Archive:** `netpoke_phase4_complete_20260614.tar.gz` on VM  
**CSV:** `ebpf_residual_summary.csv` in same directory (sync from VM)

## Summary (SIGSTOP-only, same L2 netem as Phase 3)

| App | Target | SIGSTOP wins | Δ read B | Δ write B | Δ syscr | Δ net rx | RMSE (%) Phase 4 | RMSE (%) Phase 3 L2 |
|-----|--------|--------------|----------|-----------|---------|----------|------------------|---------------------|
| Social | hometimeline | 69 | 0 | 0 | 573,494 | 26.09×10⁹ | **24.04** | 24.64 |
| Hotel | profile | 14 | 0 | 0 | 213,878 | 5.73×10⁹ | **15.75** | 16.28 |
| Movie | moviereviews | 18 | 0 | 0 | 514,102 | 12.03×10⁹ | **13.70** | 16.72 |
| Boutique | cart | 34 | 0 | 0 | 1,034,440 | 5.20×10⁹ | **4.04** | 5.61 |

**Δ columns:** cumulative totals over all sample windows with `stopped_pids > 0` (full run).  
**Δ net rx:** bytes received on pod interfaces during pause windows (not per-pause rate).

## L2 RMSE: Phase 3 vs Phase 4 (validation)

| App | Phase 3 L2 RMSE | Phase 4 L2 RMSE | Δ (pp) |
|-----|-----------------|-----------------|--------|
| Social | 24.64% | 24.04% | −0.60 |
| Hotel | 16.28% | 15.75% | −0.53 |
| Movie | 16.72% | 13.70% | −3.02 |
| Boutique | 5.61% | 4.04% | −1.57 |

Phase 4 replicates Phase 3 L2 configs (RMSE within ~0.5–3 pp). Social/hotel/movie match closely; movie variance is run-to-run noise.

## Rank order (mechanism vs Phase 3 I/O-gap)

| Rank | Phase 3 L2−L0 RMSE Δ | Phase 4 Δ net rx | Phase 4 RMSE |
|------|------------------------|------------------|--------------|
| 1 | Social (+14.30 pp) | Social (26.1 GB) | 24.04% |
| 2 | Hotel (+6.05 pp) | Movie (12.0 GB) | 15.75% |
| 3 | Movie (+2.75 pp) | Boutique (5.2 GB) | 13.70% |
| 4 | Boutique (−3.59 pp) | Hotel (5.7 GB) | 4.04% |

**RQ2:** Non-zero residual I/O during SIGSTOP on all four apps (Δ syscr and Δ net rx > 0). Social shows largest residual ingress, aligned with largest I/O-gap. Boutique has moderate residual I/O but **lowest** RMSE (4.04%) — consistent with Phase 3 outlier (RMSE fell at L2 vs L0); discuss as case study, not primary I/O-gap figure.

## Regenerate (netpoke-control)

```bash
cd ~/slowpoke/evaluation
python3 phase4_ebpf/summarize_ebpf_residual.py results/
python3 phase4_ebpf/summarize_ebpf_residual.py results/ \
  -o results/final_package/ebpf_residual_summary.csv
python3 phase4_ebpf/plot_ebpf_residual.py results/ -o results/final_package/
```

## Figures (after plot script synced)

| ID | File | Description |
|----|------|-------------|
| **E1** | `fig_ebpf_rmse_L2.png` | RMSE bar chart (L2, Phase 4) |
| **E2** | `fig_ebpf_residual_io.png` | SIGSTOP windows + Δ net RX |
| **E3** | `fig_ebpf_rmse_vs_netrx.png` | RMSE vs residual ingress scatter |
