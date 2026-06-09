# NetPoke evaluation results (repository layout)

Mirrors the SlowPoke artifact pattern: **scripts in `slowpoke/evaluation/`**, **committed
reference outputs here**, **full raw logs** under `logs/` after cluster sync.

## Directory layout

```
netpoke/results/
├── README.md                 ← this file
├── reference/                ← authors' sample_output appearance (Fig. 8 format)
│   ├── figures/              ← PNG + plot_macro from SlowPoke paper artifact samples
│   └── tables/               ← table format examples
├── cluster/                  ← YOUR netpoke-control runs (sync from VM)
│   ├── baseline/
│   │   ├── logs/             ← raw *_medium.log (L0)
│   │   ├── figures/          ← draw.py + plot_macro.py output
│   │   └── tables/           ← summarize_results.py exports
│   └── io_gap/
│       ├── logs/             ← raw *_io_L*_medium.log
│       ├── figures/          ← plot_io_gap_rmse.py
│       └── tables/           ← io_gap_matrix.csv + markdown
└── archive/                  ← superseded runs (e.g. boutique shipping injection)
```

## Important: where to run plotting commands

Plots are generated **on netpoke-control** (where logs live), not Cloud Shell:

```bash
# SSH: netpoke-control
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation

python3 summarize_results.py results/boutique_medium.log results/hotel_medium.log \
  results/social_medium.log results/movie_medium.log

bash plot_fig8_png.sh results/

python3 io_gap/summarize_io_gap_matrix.py results/ \
  -o results/final_package/io_gap_matrix.csv
python3 io_gap/plot_io_gap_rmse.py results/
```

Then sync to your laptop / commit to repo:

```bash
# From Cloud Shell
gcloud compute scp --recurse --zone=us-central1-a \
  aframviscagyebi@netpoke-control:~/slowpoke/evaluation/results/ \
  ~/netpoke_results_sync/

# Copy into repo cluster/ tree
cp -a netpoke_results_sync/* netpoke/results/cluster/baseline/logs/
# … figures similarly
```

Or use the pack script on the control node:

```bash
bash ~/slowpoke/evaluation/scripts/pack_results_for_repo.sh
```

## Boutique re-run (product_catalog injection)

After syncing updated `io_gap/` from git:

```bash
cd ~/slowpoke/evaluation
bash io_gap/run_boutique_io_rerun.sh
```

Prior shipping-injection logs are archived under `results/saved/boutique_shipping_inject_20260607/`.

## Phase 4 (eBPF) — next

See [`evaluation/phase4_ebpf/README.md`](../evaluation/phase4_ebpf/README.md).
