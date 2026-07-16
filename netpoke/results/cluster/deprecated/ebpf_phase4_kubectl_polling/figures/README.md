# Phase 4 figures

Generate on **netpoke-control** after all four `*_ebpf_L2_*` files exist:

```bash
cd ~/slowpoke/evaluation
python3 phase4_ebpf/plot_ebpf_residual.py results/ -o results/final_package/
# or full finalize:
bash phase4_ebpf/finalize_phase4_results.sh
```

| File | Thesis ID | Description |
|------|-----------|-------------|
| `fig_ebpf_rmse_L2.png` (+ `.pdf`) | Fig E1 | RMSE bar chart at L2 |
| `fig_ebpf_residual_io.png` | Fig E2 | SIGSTOP windows + cumulative Δ net RX |
| `fig_ebpf_rmse_vs_netrx.png` | Fig E3 | RMSE vs residual ingress scatter |

Copy PNG/PDF here after cluster sync. See [`netpoke/docs/figures-and-tables-master.md`](../../../docs/figures-and-tables-master.md).
