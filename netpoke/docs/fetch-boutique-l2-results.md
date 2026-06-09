# Fetch boutique L2 results and update the repo

**Status (2026-06-09):** Boutique L1+L2 complete on netpoke-control. Final matrix in `netpoke/results/cluster/io_gap/tables/TABLE_IO_GAP_MATRIX.md`.

Run on **netpoke-control** to pack logs for git sync.

## 1. Verify L2 complete

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation/results

ls -lh boutique_io_L1_medium.log boutique_io_L2_medium.log
grep -c '\[exp\] Throughput:' boutique_io_L1_medium.log boutique_io_L2_medium.log
grep 'Error Perc:' boutique_io_L1_medium.log boutique_io_L2_medium.log
```

**Pass:** each file ~150–200 KB, **21** throughput lines, one `Error Perc:` each.

## 2. Full matrix + plots

```bash
cd ~/slowpoke/evaluation
python3 io_gap/summarize_io_gap_matrix.py results/
python3 summarize_results.py results/boutique_io_L1_medium.log results/boutique_io_L2_medium.log
python3 io_gap/plot_io_gap_rmse.py results/
bash scripts/pack_results_for_repo.sh
ls -lh ~/netpoke_results_pack_*.tar.gz
```

Save the matrix output (especially **L2 − L0** for boutique).

## 3. Download (Cloud Shell)

```bash
gcloud compute scp --zone=us-central1-a \
  aframviscagyebi@netpoke-control:~/netpoke_results_pack_*.tar.gz .
tar tzf netpoke_results_pack_*.tar.gz | head -30
```

## 4. Install into git repo

After `git pull origin netpoke/experiments`:

```bash
mkdir -p netpoke/results/cluster/io_gap/{logs,figures,tables}
tar xzf netpoke_results_pack_*.tar.gz -C /tmp/netpoke_unpack
cp /tmp/netpoke_unpack/results/boutique_io_L1_medium.log \
   netpoke/results/cluster/io_gap/logs/
cp /tmp/netpoke_unpack/results/boutique_io_L2_medium.log \
   netpoke/results/cluster/io_gap/logs/
cp /tmp/netpoke_unpack/results/fig_io_gap_rmse.png \
   netpoke/results/cluster/io_gap/figures/ 2>/dev/null || true
```

Update `netpoke/results/cluster/io_gap/tables/TABLE_IO_GAP_MATRIX.md` with new boutique L1/L2 rows.

## 5. Way forward

| Step | Action |
|------|--------|
| Done | Phase 3 matrix complete (all 4 apps × L0/L1/L2) |
| Next | Phase 4 eBPF at L2 — social → hotel → movie → boutique |
| Later | NetPoke implementation + L2 re-run with sch_plug |

See `netpoke/evaluation/phase4_ebpf/README.md`.
