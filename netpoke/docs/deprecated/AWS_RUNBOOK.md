# AWS Experiment Runbook

End-to-end procedure for running SlowPoke and NetPoke experiments on AWS EC2,
from a cold account to final numbers. Mirrors `EXPERIMENT_RUNBOOK.md` but for
AWS instead of GCP.

## Prerequisites (one-time)

- AWS CLI configured in WSL (`aws sts get-caller-identity` returns your account)
- vCPU quota for "Running On-Demand Standard instances" in us-east-2 set to **48**
- Repo cloned to `~/netpoke` on branch `netpoke/experiments`
- AMI patched to `ami-0d1b5a8c13042c939` (already committed)

---

## Cost reference

| Phase | Duration | Cost |
|---|---|---|
| Cluster creation + init | ~30 min | ~$1 |
| SlowPoke reproducible run (`run_reproducible.sh`) | ~2.5 hr | ~$5–6 |
| Full NetPoke experiment set (4 runs × 4 apps) | ~4–5 hr | ~$8–10 |
| Cluster idle (stopped, not terminated) | per day | ~$0.10 (EBS only) |

Terminate (not just stop) when done to avoid ongoing EBS charges.

---

## Part A: Cluster setup

### A1. Create the cluster

```bash
# WSL
cd ~/netpoke/slowpoke/scripts/setup
mkdir -p ~/cluster_info
python3 setup_ec2_cluster.py -d ~/cluster_info -n 12
```

Expected: script prints 14 instance IDs, waits for all to reach `running` then
`ok` status. Takes ~5 minutes.

### A2. Initialize the cluster

```bash
# WSL
cd ~/netpoke/slowpoke/scripts/setup
bash initialize-aws.sh ~/cluster_info
```

Expected: installs Docker, Kubernetes 1.29, Istio 1.18 on all nodes, joins
workers, ends with `kubectl get nodes` showing all 12 workers + control `Ready`.
Takes ~15–20 minutes.

### A3. Get the control node IP

```bash
# WSL
head -1 ~/cluster_info/ec2_ips
```

This is `CONTROL_IP` used in all SSH commands below.

### A4. Sync the repo to the control node

```bash
# WSL
CONTROL_IP=$(head -1 ~/cluster_info/ec2_ips)
KEY=~/cluster_info/slowpoke-expr.pem

# Copy slowpoke/ to the control node
tar -czf /tmp/slowpoke.tar.gz -C ~/netpoke slowpoke
scp -i $KEY -o StrictHostKeyChecking=no /tmp/slowpoke.tar.gz ubuntu@$CONTROL_IP:~
ssh -i $KEY -o StrictHostKeyChecking=no ubuntu@$CONTROL_IP \
  "tar -xzf ~/slowpoke.tar.gz && find ~/slowpoke -name '*.sh' | xargs chmod +x && echo SYNC_OK"
```

Must print `SYNC_OK`. Re-run any time you push changes.

---

## Part B: One-time per-cluster setup (SSH into control node)

```bash
# WSL — open SSH session
CONTROL_IP=$(head -1 ~/cluster_info/ec2_ips)
KEY=~/cluster_info/slowpoke-expr.pem
ssh -i $KEY -o StrictHostKeyChecking=no ubuntu@$CONTROL_IP
```

All commands from here run **on the control node** unless noted.

### B1. Generate NetPoke yaml variants

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation
bash phase5_netpoke/patch_all_netpoke_yamls.sh all
```

Confirm both variants exist:

```bash
ls ~/slowpoke/evaluation/social/yamls/netpoke/*.yaml
ls ~/slowpoke/evaluation/social/yamls/netpoke-sigstop/*.yaml
```

### B2. Verify the injection fix

```bash
export SLOWPOKE_TOP=~/slowpoke SLOWPOKE_NETPOKE=1
cd ~/slowpoke/evaluation
bash io_gap/apply_io_injection.sh social L2
grep -l tc-netem-sidecar ~/slowpoke/evaluation/social/yamls/netpoke/*.yaml
# must print at least post_storage.yaml and social_graph.yaml
bash io_gap/restore_io_injection.sh

export SLOWPOKE_YAML_SUBDIR=netpoke-sigstop SLOWPOKE_NETPOKE=0
bash io_gap/apply_io_injection.sh social L2
grep -l tc-netem-sidecar ~/slowpoke/evaluation/social/yamls/netpoke-sigstop/*.yaml
# must print at least post_storage.yaml and social_graph.yaml
bash io_gap/restore_io_injection.sh
unset SLOWPOKE_YAML_SUBDIR
```

If either `grep` finds nothing, stop — do not run any L2 experiment until fixed.

---

## Part C: Experiments

Two SSH windows for every run. Open a second terminal:

```bash
# WSL terminal 2
CONTROL_IP=$(head -1 ~/cluster_info/ec2_ips)
KEY=~/cluster_info/slowpoke-expr.pem
ssh -i $KEY -o StrictHostKeyChecking=no ubuntu@$CONTROL_IP
```

### C0. SlowPoke reproducible run (Part A of paper)

**Terminal 2 (watch):**
```bash
export REP=rep1
export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
mkdir -p "$RESULTS_DIR"
cd ~/slowpoke/evaluation
./watch_progress.sh --append "$RESULTS_DIR/"
```

**Terminal 1 (run):**
```bash
export REP=rep1
export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
mkdir -p "$RESULTS_DIR"
screen -S reproducible
cd ~/slowpoke/evaluation
RESULTS_DIR="$RESULTS_DIR" bash run_reproducible.sh
# Ctrl+A D to detach
```

Duration: ~2.5 hours. Produces Table 3 from the SlowPoke paper.

### C1–C4. NetPoke experiment set

Run these four sequentially (they redeploy the same pods).

**Terminal 2 (watch — keep running for all four):**
```bash
export REP=rep1
export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
cd ~/slowpoke/evaluation
./watch_progress.sh --append "$RESULTS_DIR/"
```

**Terminal 1, run 1 — SIGSTOP-only, L0:**
```bash
export REP=rep1
export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
mkdir -p "$RESULTS_DIR"
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
# Ctrl+A D to detach; wait for completion before starting run 2
```

**Terminal 1, run 2 — NetPoke-on, L0:**
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

**Terminal 1, run 3 — SIGSTOP-only, L2:**
```bash
export REP=rep1
export RESULTS_DIR=~/slowpoke/evaluation/results/$REP
screen -S rep-l2-sigstop
export SLOWPOKE_TOP=~/slowpoke PYTHONUNBUFFERED=1
export SLOWPOKE_YAML_SUBDIR=netpoke-sigstop SLOWPOKE_NETPOKE=0
cd ~/slowpoke/evaluation
WATCH_INTERVAL=10 RESULTS_DIR="$RESULTS_DIR" ./run_with_monitor.sh bash <<EOF
for b in boutique hotel social movie; do
  bash io_gap/run_io_medium.sh "\$b" L2 "$RESULTS_DIR/\${b}_io_L2_medium.log" || exit 1
done
EOF
# Ctrl+A D to detach
```

**Terminal 1, run 4 — NetPoke-on, L2:**
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

---

## Part D: Extract results

```bash
cd ~/slowpoke/evaluation
for f in "$RESULTS_DIR"/*.log; do
  echo "=== $(basename "$f") ==="
  python3 summarize_results.py "$f"
done
```

Copy this output before tearing down — it does not survive termination.

---

## Part E: Cluster lifecycle

### Stop (pause, keep data, small EBS charge)
```bash
# WSL
cd ~/netpoke/slowpoke/scripts/setup
python3 - <<'EOF'
import sys; sys.argv = ['', '-d', '/root/cluster_info']
exec(open('ec2_cluster.py').read())
stop_ec2()
EOF
```

### Restart stopped cluster
```bash
python3 - <<'EOF'
import sys; sys.argv = ['', '-d', '/root/cluster_info']
exec(open('ec2_cluster.py').read())
start_ec2()
EOF
```

Then re-sync: repeat step A4.

### Terminate (permanent, no further charges)
```bash
cd ~/netpoke/slowpoke/scripts/setup
python3 - <<'EOF'
import sys; sys.argv = ['', '-d', '/root/cluster_info']
exec(open('ec2_cluster.py').read())
remove_ec2()
remove_sg()
remove_key()
EOF
rm -rf ~/cluster_info
```

---

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `setup_ec2_cluster.py` creates 0 instances | vCPU quota not yet approved | Wait for quota approval email |
| `initialize-aws.sh` SSH timeout | Instances not fully booted | Wait 2 min and retry |
| `kubectl get nodes` shows `NotReady` | Weave CNI still initializing | Wait 2 min and re-check |
| `grep` finds no `tc-netem-sidecar` in B2 | Injection fix not applied | `git pull` on control node and re-sync |
| Hotel RMSE varies wildly between runs | Known volatility | Treat as directional; need 3+ reps |
| Boutique NetPoke shows regression | Known — zero sync I/O in cart handler | See `BOUTIQUE_FANOUT_FINDING.md` |
