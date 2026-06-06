# Phase 3 — I/O gap characterization

Show that prediction RMSE **rises** when the slowed service sits on an I/O-heavy path
(SIGSTOP-only), relative to Phase 1 L0 baselines.

## I/O levels

| Level | Script | Target service(s) |
|-------|--------|-------------------|
| **L0** | `run-*-medium.sh` | cart, profile, hometimeline, moviereviews |
| **L1** | `run-*-medium-io-L1.sh` | checkout, search, poststorage, reviewstorage |
| **L2** | `run-*-medium-io-L2.sh` | checkout+shipping netem, reservation, socialgraph, movieinfo |

Matrix is defined in [`io_levels.conf`](io_levels.conf).

## Sync to netpoke-control

`~/slowpoke` on the VM is not a git checkout. From Cloud Shell:

```bash
cd ~/netpoke && git fetch origin cursor/phase3-io-gap-eab9
gcloud compute scp --recurse --zone=us-central1-a \
  slowpoke/evaluation/io_gap slowpoke/evaluation/boutique/yamls/shipping_io_l2.yaml \
  slowpoke/evaluation/*/run-*-medium-io-*.sh \
  aframviscagyebi@netpoke-control:~/slowpoke/evaluation/
# Fix paths if scp flattened directories — prefer rsync or tar:
tar czf /tmp/io_gap.tgz -C ~/netpoke slowpoke/evaluation/io_gap \
  $(find slowpoke/evaluation -name 'run-*-medium-io-*.sh')
gcloud compute scp --zone=us-central1-a /tmp/io_gap.tgz \
  aframviscagyebi@netpoke-control:~/
# On netpoke-control: tar xzf ~/io_gap.tgz -C ~/slowpoke --strip-components=1
```

Or copy the whole `evaluation/` tree after `git pull` on `netpoke26-thesis`.

## Run order (recommended)

One benchmark at a time in **screen**; second SSH for `watch_progress.sh`.

```bash
cd ~/slowpoke/evaluation
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
bash io_gap/preflight_io_gap.sh results/
```

| Step | screen name | Command | Watch log |
|------|-------------|---------|-----------|
| 1 | `slowpoke-boutique-io-L1` | `WATCH_INTERVAL=10 ./run_with_monitor.sh bash boutique/run-boutique-medium-io-L1.sh results/boutique_io_L1_medium.log` | `boutique_io_L1_medium.log` |
| 2 | `slowpoke-boutique-io-L2` | `… run-boutique-medium-io-L2.sh results/boutique_io_L2_medium.log` | `boutique_io_L2_medium.log` |
| 3 | hotel L1 | `hotel/run-hotel-medium-io-L1.sh` | `hotel_io_L1_medium.log` |
| 4 | hotel L2 | `hotel/run-hotel-medium-io-L2.sh` | `hotel_io_L2_medium.log` |
| 5 | social L1 | `social/run-social-medium-io-L1.sh` | `social_io_L1_medium.log` |
| 6 | social L2 | `social/run-social-medium-io-L2.sh` | `social_io_L2_medium.log` |
| 7 | movie L1 | `movie/run-movie-medium-io-L1.sh` | `movie_io_L1_medium.log` |
| 8 | movie L2 | `movie/run-movie-medium-io-L2.sh` | `movie_io_L2_medium.log` |

Second SSH (each run):

```bash
cd ~/slowpoke/evaluation
SLOWPOKE_ACTIVE_LOG=~/slowpoke/evaluation/results/<app>_io_L<n>_medium.log \
  WATCH_INTERVAL=10 ./watch_progress.sh --loop-tty
```

After each complete log: `cp -a results/<log> results/saved/`.

## Analysis

```bash
python3 io_gap/summarize_io_gap_matrix.py results/ \
  -o results/final_package/io_gap_matrix.csv
bash io_gap/verify_io_gap_results.sh results/
```

## Boutique L2 note

L2 enables a **50 ms netem sidecar** on the shipping pod (`enable_boutique_l2_io.sh`
swaps `yamls/shipping.yaml` from `io_gap/shipping_io_l2.yaml`). The script restores
the standard yaml on exit. If a run is killed abruptly, run
`bash io_gap/disable_boutique_l2_io.sh` manually.

**Important:** `shipping_io_l2.yaml` must **not** live under `boutique/yamls/`.
`run.sh` applies every `*.yaml` there; a stray copy deploys a 2/2 shipping pod and
older `run.sh` waited forever for `1/1` only.

## Sync extract (correct)

```bash
cd ~ && tar xzf ~/io_gap_phase3.tgz
chmod +x ~/slowpoke/evaluation/io_gap/*.sh ~/slowpoke/evaluation/*/run-*-medium-io-*.sh
# Remove stray copy if present:
rm -f ~/slowpoke/evaluation/boutique/yamls/shipping_io_l2.yaml
```
