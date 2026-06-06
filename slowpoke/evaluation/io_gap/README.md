# Phase 3 — I/O gap characterization

Show that prediction RMSE **rises** when the slowed service sits on an I/O-heavy path
(SIGSTOP-only), relative to Phase 1 L0 baselines.

**Thesis-aligned design:** L0, L1, and L2 use the **same `-x` target** as Phase 1.
L1/L2 add controlled synchronous I/O on downstream path services via **tc netem sidecars**
(patched into service yamls before deploy, restored after each run).

## I/O levels

| Level | Script | `-x` target | Path I/O injection |
|-------|--------|-------------|-------------------|
| **L0** | `run-*-medium.sh` | cart / profile / hometimeline / moviereviews | none |
| **L1** | `run-*-medium-io-L1.sh` | same as L0 | moderate netem (30 ms) |
| **L2** | `run-*-medium-io-L2.sh` | same as L0 | heavier netem (50 ms + extra services) |

Per-benchmark injection matrix is in [`io_levels.conf`](io_levels.conf).

## Sync to netpoke-control

`~/slowpoke` on the VM is not a git checkout. From Cloud Shell (after `git pull`):

```bash
cd ~/netpoke && git pull origin cursor/phase3-io-gap-eab9
tar czf ~/io_gap_phase3.tgz \
  -C ~/netpoke slowpoke/evaluation/io_gap \
  $(find slowpoke/evaluation -name 'run-*-medium-io-*.sh')
gcloud compute scp --zone=us-central1-a ~/io_gap_phase3.tgz \
  aframviscagyebi@netpoke-control:~/
```

On **netpoke-control**:

```bash
cd ~ && tar xzf ~/io_gap_phase3.tgz
chmod +x ~/slowpoke/evaluation/io_gap/*.sh ~/slowpoke/evaluation/*/run-*-medium-io-*.sh
rm -f ~/slowpoke/evaluation/boutique/yamls/shipping_io_l2.yaml
bash ~/slowpoke/evaluation/io_gap/restore_io_injection.sh
```

## Stop old run and archive target-switch logs

If a prior (wrong-design) suite is running or partial logs exist:

```bash
pkill -f 'python3.*main.py' || true
screen -S slowpoke-io-gap -X quit 2>/dev/null || true
export SLOWPOKE_TOP=~/slowpoke
bash ~/slowpoke/evaluation/io_gap/restore_io_injection.sh
bash ~/slowpoke/evaluation/safe_delete_workloads.sh
mkdir -p ~/slowpoke/evaluation/results/saved/io_gap_target_switch
mv ~/slowpoke/evaluation/results/*_io_L*_medium.log \
   ~/slowpoke/evaluation/results/saved/io_gap_target_switch/ 2>/dev/null || true
```

`run_io_gap_all.sh` also archives any remaining `*_io_L*_medium.log` files on start.

## Run all 8 automatically (recommended)

Chained script: boutique L1 → L2 → hotel → social → movie (8 runs). Monitor on
SSH 1; SSH 2 auto-follows the active log.

### SSH 1 — screen + full suite

```bash
screen -S slowpoke-io-gap
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./io_gap/run_io_gap_all.sh
```

Detach: `Ctrl+A`, `D`

### SSH 2 — live monitor (auto log switch)

```bash
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 ./watch_progress.sh --loop-tty
```

Shows `I/O-gap: X/8 runs complete` and switches log each run automatically.

Completed logs are saved to `results/saved/` after each run.

## Analysis

```bash
python3 io_gap/summarize_io_gap_matrix.py results/ \
  -o results/final_package/io_gap_matrix.csv
bash io_gap/verify_io_gap_results.sh results/
```

## I/O injection mechanics

- `apply_io_injection.sh` backs up each service yaml, inserts a netem sidecar via
  `patch_netem_yaml.py`, and records backups in `.io_injection_active`.
- `restore_io_injection.sh` restores all patched yamls (also handles legacy boutique L2 stamp).
- `run_io_medium.sh` applies injection before deploy and restores on exit (including on failure).

**Important:** Do not place standalone `shipping_io_l2.yaml` under `boutique/yamls/`.
`run.sh` applies every `*.yaml` there; a stray copy deploys a 2/2 shipping pod and
older `run.sh` waited forever for `1/1` only.

## Gate checks before starting

```bash
export SLOWPOKE_TOP=~/slowpoke
ls ~/slowpoke/evaluation/io_gap/run_io_gap_all.sh
grep io_gap_summary_line ~/slowpoke/evaluation/watch_progress.sh
grep 'Waiting for all pod containers to be ready' ~/slowpoke/src/run.sh
bash ~/slowpoke/evaluation/io_gap/preflight_io_gap.sh results/
```
