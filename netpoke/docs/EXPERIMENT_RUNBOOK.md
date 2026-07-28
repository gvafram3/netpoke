# Experiment runbook: from a cold cluster to genuine numbers

This is the procedure to follow, in order, every time you want a fresh, trustworthy set of
results, whether that's the first run or the twentieth repetition. It assumes the cluster has
just been torn down (`03_teardown.sh`) or never existed for this session.

## Read this first: a bug this runbook exists partly to route around

While building this runbook, a real bug was found in
[`slowpoke/evaluation/io_gap/apply_io_injection.sh`](../../slowpoke/evaluation/io_gap/apply_io_injection.sh)
and has now been fixed, but it affects how much you should trust some *existing* numbers.

The script that inserts the `netem` delay for L1/L2 injection always patched the plain
`<bench>/yamls/*.yaml` files. `src/run.sh`, separately, deploys from `<bench>/yamls/netpoke/` or
`<bench>/yamls/netpoke-sigstop/` whenever `SLOWPOKE_NETPOKE=1` or `SLOWPOKE_YAML_SUBDIR` is set.
Those are different files. Any run that used the netpoke-tagged deployment path *and* asked for
L1/L2 injection would have deployed from a yaml snapshot that never received the injected delay,
silently running under effectively no-injection conditions while being labelled L1/L2.

This affects, at minimum:

- **Table N1**'s L2 residual-I/O rows (hotel, social, movie): both the SIGSTOP-only side
  (`netpoke-sigstop` subdir) and the NetPoke-on side (`netpoke` subdir) may have run without real
  injected stress.
- **Table N2**'s NetPoke-on L2 RMSE numbers specifically: the SIGSTOP-only side of that table
  came from the original Phase 3 runs (plain yaml directory, unaffected), but the NetPoke-on side
  used `SLOWPOKE_NETPOKE=1` and is subject to the same bug.

It does **not** affect: Table B1/I1 (original Phase 3, plain directory throughout), Table N3
(L0, no injection involved at all), or the boutique fan-out finding (source-code analysis, no
deployment involved).

**The fix** (already applied) makes `apply_io_injection.sh` resolve the same directory `run.sh`
will actually deploy from, mirroring `run.sh`'s own `SLOWPOKE_YAML_SUBDIR` /
`SLOWPOKE_NETPOKE` precedence, so the injected delay lands in the files that get deployed.

**What this means for you:** the L2 NetPoke-on numbers in Table N2 need to be re-measured with
the fix in place before they can be fully trusted. This runbook's Step 5 does that as part of the
normal sequence, so simply following it from here resolves this rather than requiring a separate
investigation.

## Step 0: Sync this fix (and anything else pending) to the cluster

```bash
# Cloud Shell
cd ~/netpoke && git pull origin netpoke/experiments
```

## Step 1: Bring the cluster up

```bash
# Cloud Shell
gcloud compute instances list --filter="tags.items=netpoke-cluster"
```

- **Nothing listed (fully torn down):**
  ```bash
  cd ~/netpoke/netpoke/infra/gcp
  cp -n config.env.example config.env    # if config.env doesn't already exist
  grep -q ENABLE_LOADGEN config.env || echo 'ENABLE_LOADGEN=0' >> config.env
  ./01_create_cluster.sh
  # wait ~60s for VMs to finish booting
  ./02_initialize_cluster.sh
  ```
  Wait for the printed `kubectl get nodes` to show all nodes `Ready`.

- **Listed but `TERMINATED` (just stopped):**
  ```bash
  cd ~/netpoke/netpoke/infra/gcp
  grep -q ENABLE_LOADGEN config.env || echo 'ENABLE_LOADGEN=0' >> config.env
  ./start_cluster_vms.sh
  ```

`netpoke-loadgen` failing or staying `TERMINATED` is expected and fine with `ENABLE_LOADGEN=0`,
since it is never used by any experiment script (confirmed: no yaml or shell script in this repo
references the `loadgen` node).

## Step 2: Get `~/slowpoke` onto the (possibly brand new) control node

One command, run from Cloud Shell, packs `slowpoke/`, sends it, extracts it, and marks every
script executable on `netpoke-control` in one shot:

```bash
# Cloud Shell
cd ~/netpoke/netpoke/infra/gcp
./sync_to_control.sh
```

Safe to re-run any time you want to push local changes to the control node, not just on a fresh
cluster. It ends with `SYNC_OK` printed from the remote side; if you don't see that, something
failed partway and should be investigated before continuing.

Docker images do **not** need rebuilding. They are already pushed to Docker Hub
(`gvafram3/mucache:<bench>-pokerpp-netpoke`) and Kubernetes pulls them by tag; rebuilding is only
needed if `poker.c` / `net_hold.c` change, which they have not for this phase.

## Step 3: One-time per-cluster yaml setup

Generates both the `netpoke/` and `netpoke-sigstop/` yaml variants (all four apps). Do this once
per fresh cluster, not once per repetition.

- `netpoke/` — same `gvafram3` image, `NET_ADMIN`, `SLOWPOKE_NETPOKE=1` (egress hold on)
- `netpoke-sigstop/` — same `gvafram3` image, `NET_ADMIN`, `SLOWPOKE_NETPOKE=0` (egress hold off)

Both are required. Without `netpoke-sigstop/`, runs 1 and 3 silently fall back to the plain
`yizhengx` images, which lack the `poker: pause_start`/`pause_end` markers.

```bash
# SSH 1
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation
bash phase5_netpoke/patch_all_netpoke_yamls.sh all
```

Confirm both directories are non-empty for at least one app:

```bash
ls ~/slowpoke/evaluation/social/yamls/netpoke/*.yaml
ls ~/slowpoke/evaluation/social/yamls/netpoke-sigstop/*.yaml
```

**Verify the injection fix actually works before trusting any L2 number.** Pick one app and one
service, apply injection, and confirm the file that will actually be deployed received it:

```bash
export SLOWPOKE_TOP=~/slowpoke SLOWPOKE_NETPOKE=1
bash io_gap/apply_io_injection.sh social L2
grep -l tc-netem-sidecar ~/slowpoke/evaluation/social/yamls/netpoke/*.yaml
# should print at least post_storage.yaml and social_graph.yaml
bash io_gap/restore_io_injection.sh
```

Also verify the sigstop variant receives injection (run 3 deploys from there):

```bash
export SLOWPOKE_YAML_SUBDIR=netpoke-sigstop SLOWPOKE_NETPOKE=0
bash io_gap/apply_io_injection.sh social L2
grep -l tc-netem-sidecar ~/slowpoke/evaluation/social/yamls/netpoke-sigstop/*.yaml
# should print at least post_storage.yaml and social_graph.yaml
bash io_gap/restore_io_injection.sh
unset SLOWPOKE_YAML_SUBDIR
```

If either `grep` finds nothing, stop — do not trust any L2 result until this is fixed.

## Step 4: Start a fresh repetition directory

Every repetition gets its own subdirectory so nothing overwrites a prior run.

```bash
# SSH 1
export REP=rep1   # rep2, rep3, ... for later repetitions
export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
mkdir -p "$RESULTS_DIR"
```

## Step 5: Run the four paired experiments, in this order

Two windows for every run, no exceptions, even a "quick" one.

**SSH 2** (leave this running for the whole session):
```bash
export REP=rep1
export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
cd ~/slowpoke/evaluation
./watch_progress.sh --append "$RESULTS_DIR/"
```

**SSH 1, run 1: SIGSTOP-only, L0 (no injection):**
```bash
export REP=rep1
export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
screen -S rep-l0-sigstop
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export SLOWPOKE_YAML_SUBDIR=netpoke-sigstop SLOWPOKE_NETPOKE=0
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 RESULTS_DIR="$RESULTS_DIR" ./run_with_monitor.sh bash -c '
  bash boutique/run-boutique-medium.sh "$RESULTS_DIR/boutique_medium.log"
  bash hotel/run-hotel-medium.sh "$RESULTS_DIR/hotel_medium.log"
  bash social/run-social-medium.sh "$RESULTS_DIR/social_medium.log"
  bash movie/run-movie-medium.sh "$RESULTS_DIR/movie_medium.log"
'
# Ctrl+A D to detach
```

**SSH 1, run 2: NetPoke-on, L0:**
```bash
export REP=rep1
export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
screen -S rep-l0-netpoke
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1 SLOWPOKE_NETPOKE=1
unset SLOWPOKE_YAML_SUBDIR
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 RESULTS_DIR="$RESULTS_DIR" ./run_netpoke_l0_overhead.sh
# Ctrl+A D to detach
```

**SSH 1, run 3: SIGSTOP-only, L2 (same image as NetPoke-on, injection fix applies):**
```bash
export REP=rep1
export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
screen -S rep-l2-sigstop
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export SLOWPOKE_YAML_SUBDIR=netpoke-sigstop SLOWPOKE_NETPOKE=0
cd ~/slowpoke/evaluation
# NOTE: unquoted <<EOF so $RESULTS_DIR expands in the heredoc body.
# <<'EOF' would pass the literal string "$RESULTS_DIR" to bash, which only
# works by accident (run_with_monitor.sh re-exports it). Unquoted is explicit.
WATCH_INTERVAL=10 RESULTS_DIR="$RESULTS_DIR" ./run_with_monitor.sh bash <<EOF
for b in boutique hotel social movie; do
  bash io_gap/run_io_medium.sh "\$b" L2 "$RESULTS_DIR/\${b}_io_L2_medium.log" || exit 1
done
EOF
# Ctrl+A D to detach
```

**SSH 1, run 4: NetPoke-on, L2:**
```bash
export REP=rep1
export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
screen -S rep-l2-netpoke
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1 SLOWPOKE_NETPOKE=1
unset SLOWPOKE_YAML_SUBDIR
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 RESULTS_DIR="$RESULTS_DIR" ./run_io_gap_netpoke_L2.sh
# Ctrl+A D to detach
```

Run these four sequentially, not in parallel: they redeploy the same pods and will interfere
with each other if overlapped.

## Step 6: Extract this repetition's numbers

```bash
# SSH 1
cd ~/slowpoke/evaluation
for f in "$RESULTS_DIR"/*.log; do
  echo "=== $(basename "$f") ==="
  python3 summarize_results.py "$f"
done
```

Copy this output somewhere durable (paste it to me, or append to a local file) before tearing
down. `results/` lives only on the VM and does not survive `03_teardown.sh` deleting the disk.

## Step 7: Tear down

```bash
# Cloud Shell
cd ~/netpoke/netpoke/infra/gcp
./03_teardown.sh
```

## Step 8: Repeat

Go back to Step 1 for the next repetition (`REP=rep2`, etc.). Once you have three or more
repetitions recorded, tell me and I'll compute mean/spread across them rather than you tracking
it by hand.
