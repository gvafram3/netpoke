# Overview

The paper makes the following claims:

1. **Slowpoke's `SIGSTOP`-based slowdown does not pause network egress.** A paused service keeps transmitting the data it has already queued (§2.2, §5.4).
2. **Under a network bottleneck, Slowpoke's predictions become optimistic**, with an error that grows with the size of the optimisation (§5.3).
3. **NetPoke's egress hold always silences the paused service, but it silences the shared bottleneck only when the bottleneck queue is shallow** (§5.4).
4. **NetPoke restores prediction accuracy under a shallow bottleneck queue and brings no improvement under a deep one** (§5.5).
5. **Without a network bottleneck, NetPoke matches Slowpoke's accuracy** (§5.6).

This document is structured as follows:
* [Artifact Available](#artifact-available): the code and the data behind every number in the paper.
* [Cluster Setup](#cluster-setup): the four-node AWS cluster used in the paper (about 30 minutes).
* [Artifact Functional](#artifact-functional): a short check that NetPoke works on your cluster (about 15 minutes).
* [Results Reproducible](#results-reproducible): one section per experiment, with the command, the run time, and the expected output.
* [Changes relative to Slowpoke](#changes-relative-to-slowpoke) and [Measurement notes](#measurement-notes).

**Quick check without a cluster.** Every table and figure in the paper can be recomputed from the logs in this repository:

```sh
pip install matplotlib numpy
python3 evaluation/netpoke/plot_figures.py -o /tmp/netpoke-figures
```

The script prints RMSE, bias and worst error for all nine prediction experiments (Tables 4, 5, 7, 8 and 9) and writes the data figures (Figs. 3 and 5 to 9).

# Artifact Available

NetPoke is available at <https://github.com/gvafram3/netpoke>. It is a fork of [Slowpoke](https://github.com/atlas-brown/slowpoke) (branch `nsdi26-ae`, commit `ca69e8f`), with the `mutex` benchmark ported from Slowpoke's `main` branch.

The paper's raw data is in [`evaluation/netpoke/results`](evaluation/netpoke/results); its [README](evaluation/netpoke/results/README.md) maps every file to the table or figure it supports.
The container image used for all NetPoke experiments, `gvafram3/slowpoke:mutex-netpoke-9c993ce`, was built from this code with [`scripts/build/PrebuiltDockerfile`](scripts/build/PrebuiltDockerfile); its build log is [`results/build_mutex_netpoke_9c993ce.log`](evaluation/netpoke/results/build_mutex_netpoke_9c993ce.log).

# Cluster Setup

The paper uses four AWS EC2 `m7i-flex.large` instances (2 vCPU, 8 GB) in region `us-east-2`, running Ubuntu 24.04 (kernel 6.17.0-1017-aws), Kubernetes v1.29 and the Weave Net overlay. At the time of our experiments the four machines cost about US$0.40 to 0.50 per hour. Stop them when they are not in use.

The roles are fixed, because the benchmark YAMLs pin each service to a node name:

| Node | Role |
|---|---|
| `control` | Kubernetes control plane; runs Slowpoke's `src/main.py` and the NetPoke harness |
| `worker0` | load generator (`wrk`) |
| `worker1` | `service1`, the optimisation target (never paused) |
| `worker2` | `service2`, the paused service; the network bottleneck is configured on its interface |

**1. Launch the machines.** In the EC2 console, launch four Ubuntu 24.04 instances of type `m7i-flex.large` with one key pair and one security group, and name them `control`, `worker0`, `worker1` and `worker2`. In the security group, allow SSH from your address and *all traffic* whose source is the same security group.

**2. Configure.** All commands below run from `evaluation/netpoke/` on your machine (Linux, macOS, or WSL), unless marked otherwise.

```sh
cd evaluation/netpoke
cp cluster/config.env.example cluster/config.env
# edit cluster/config.env: SSH_KEY (path to your .pem file) and the four public IPs (IP_control, IP_worker0, ...)
```

**3. Build the cluster.** Each script is safe to re-run.

```sh
./cluster/01_check_machines.sh    # SSH, vCPU count and private network on all four machines        (~1 min)
./cluster/02_bootstrap_nodes.sh   # Docker, cri-dockerd and Kubernetes 1.29 on every node (detached)  (~10 min)
./cluster/03_init_cluster.sh      # kubeadm init/join, Weave Net, metrics-server                     (~5 min)
./cluster/04_day0_checks.sh       # kernel support for sch_plug, htb and netem on every node          (~1 min)
./cluster/05_sync_repo.sh         # copies this repository to control:~/slowpoke and the harness to ~/kit
```

`04_day0_checks.sh` must report `PASS` for `sch_plug` on every node; NetPoke cannot run otherwise. `05_sync_repo.sh` must end with `SYNC_OK`.
Public IPs change whenever the instances are stopped and started: update `cluster/config.env` when you resume. The cluster itself survives a restart.

**Useful helpers.** `./cluster/ssh.sh <node> ['command']` opens a shell or runs a command on a node. `./cluster/watch.sh` shows the live progress of a running experiment, and `./cluster/stop_run.sh` stops it. `./cluster/pull_results.sh` copies the control node's `~/results` to `evaluation/results/netpoke/` on your machine.

# Artifact Functional

**Kernel-level egress leak (~5 min, claim 1).** The following pauses a single TCP sender on `worker2` with and without the hold:

```sh
./cluster/leak_suite.sh
```

Expected output (compare [`results/leak_kernel/leak_table.md`](evaluation/netpoke/results/leak_kernel/leak_table.md)): with `HOLD off` the paused sender keeps transmitting at about 100% of its running rate; with `HOLD ON` the leak is 0.0% for pauses of 50, 200 and 1,000 ms, and the plug drops no packets.

**Prediction harness (~10 min).** Deploy the benchmark once at the largest optimisation without any pause, and measure its throughput:

```sh
./cluster/ssh.sh control 'python3 ~/kit/control/make_mutex_yamls.py --image gvafram3/slowpoke:mutex-netpoke-9c993ce --payload 8192'
./cluster/ssh.sh control '~/kit/control/quick_tput.sh yamls-freeze 400'
```

Expected output: a single line `400   <throughput> req/s`, about 3,000 req/s without a network cap.

# Results Reproducible

Each prediction experiment consists of three repetitions of a ten-level sweep (target processing time 760 µs down to 400 µs). One repetition of one system takes about 80 minutes. Long experiments run detached on the control node, so they continue if your connection drops; follow them with `./cluster/watch.sh`.

When an experiment finishes, summarise it on the control node (the summary applies the capped-counter correction, see [Measurement notes](#measurement-notes)):

```sh
./cluster/ssh.sh control 'python3 ~/kit/control/summarize_runs.py ~/results/<arm>_rep*.log'
```

### Prepare the images and YAMLs (once)

Use the published image, or build your own from this repository:

```sh
./cluster/ssh.sh control
# [control]
cd ~/slowpoke && bash src/poker/sync_to_app.sh && cd app
sudo docker build --build-arg BENCHMARK=mutex --build-arg POKER_CACHEBUST=$(date +%s) \
     -f ../scripts/build/PrebuiltDockerfile . -t <your-registry>/slowpoke:mutex-netpoke
sudo docker push <your-registry>/slowpoke:mutex-netpoke
```

Then create the YAML sets. Each set exists in two variants that differ only in `SLOWPOKE_NETPOKE` (`0` for Slowpoke, `1` for NetPoke):

```sh
# [control]   replace the image if you built your own
python3 ~/kit/control/make_mutex_yamls.py --image gvafram3/slowpoke:mutex-netpoke-9c993ce --payload 8192   # yamls-freeze, yamls-hold (8 KB responses)
~/kit/control/make_mutex_yamls_nopayload.sh --image gvafram3/slowpoke:mutex-netpoke-9c993ce               # yamls-freeze_cpu, yamls-hold_cpu (small responses)
```

The network bottleneck is a 175 Mbit/s `htb` class on `worker2` that matches only Weave's data plane; its leaf queue sets the bottleneck queue depth:

```sh
./cluster/ssh.sh control '~/kit/control/ctl_netcap.sh 175'                   # deep queue (fq_codel, the Linux default)
./cluster/ssh.sh control '~/kit/control/ctl_netcap.sh 175 pfifo limit 20'    # shallow queue (20 packets)
./cluster/ssh.sh control '~/kit/control/ctl_netcap.sh off'                   # no bottleneck
```

### Reproduction of Slowpoke (§5.2, Table 4)

Slowpoke's own image and YAMLs, without lock contention and without a network cap. About 4 hours.

```sh
./cluster/ssh.sh control '~/kit/control/ctl_netcap.sh off'
./cluster/start_run.sh 3 phase1_nolock:yamls-orig
```

Expected: RMSE about 3.7% with a negative bias of about −2.4% (paper: 3.68 ± 0.40%, −2.44 ± 0.43%).
The effective CPU quota of the target (§5.2) is measured with `./cluster/cpu_procs.sh` and `./cluster/cpu_split.sh`, which deploy ground-truth points and sample `worker1`'s CPU use; compare [`results/cpu_quota`](evaluation/netpoke/results/cpu_quota).

### Network-bottleneck calibration (§2.3, Table 1)

```sh
./cluster/ssh.sh control '~/kit/control/ctl_netcap.sh off; ~/kit/control/quick_tput.sh yamls-freeze 800 600 400'
./cluster/ssh.sh control '~/kit/control/ctl_netcap.sh 175; ~/kit/control/quick_tput.sh yamls-freeze 800 600 400'
```

Expected: the cap changes throughput by less than 2% at 800 µs and by about −27% at 400 µs (paper: 3,007 → 2,202 req/s).

### Slowpoke under a network bottleneck, deep queue (§5.3, Table 5, Fig. 3a)

About 4 hours per system. The NetPoke run completes the two-by-two design of §5.5.

```sh
./cluster/ssh.sh control '~/kit/control/ctl_netcap.sh 175'
./cluster/ssh.sh control '~/kit/control/start_series.sh 3 phase2_freeze:yamls-freeze'
# after it finishes:
./cluster/ssh.sh control '~/kit/control/start_series.sh 3 deepq_hold:yamls-hold'
```

Expected: Slowpoke RMSE about 9.3% with a positive bias of about +7.2% that grows with the optimisation (+20% at 50%); NetPoke gives no improvement (paper: 10.26 ± 0.32%).

### Egress leak during real pauses (§5.4, Table 6, Fig. 5)

Captures packets at the paused pod (point A) and at `worker2`'s interface (point B) for three bottleneck queues, with and without the hold. About 35 minutes. Runs entirely on the control node through a privileged helper pod on `worker2`.

```sh
./cluster/ssh.sh control 'screen -dmS matrix bash -lc "~/kit/control/ctl_leak_matrix.sh > ~/results/leak_matrix.txt 2>&1"'
# when it prints "matrix finished":
./cluster/ssh.sh control 'grep -E "#####|SUMMARY|^(800|400) " ~/results/leak_matrix.txt'
```

Expected: point A is 0.0% with the hold in every case; point B with the hold stays high with `fq_codel` (paper: 70.9% of bytes) and drops to about 0% with `pfifo` 20 and `pfifo` 5 (paper: 0.1% and 0.0%).

### NetPoke under a shallow bottleneck queue (§5.5, Tables 7 and 8, Figs. 3b, 6 and 7)

The two systems are interleaved within one series. About 8 hours.

```sh
./cluster/ssh.sh control '~/kit/control/ctl_netcap.sh 175 pfifo limit 20'
./cluster/ssh.sh control '~/kit/control/start_series.sh 3 phase5_hold:yamls-hold phase5_freeze:yamls-freeze'
```

Expected: Slowpoke RMSE about 11% with +7% bias; NetPoke RMSE about 4% with a small negative bias (paper: 11.32 ± 0.72% → 3.84 ± 0.54%).

### Accuracy without a network bottleneck (§5.6, Table 9, Fig. 8)

Two interleaved series, about 8 hours each.

```sh
./cluster/ssh.sh control '~/kit/control/ctl_netcap.sh off'
./cluster/ssh.sh control '~/kit/control/start_series.sh 3 cpu_hold:yamls-hold_cpu cpu_freeze:yamls-freeze_cpu'
# after it finishes:
./cluster/ssh.sh control '~/kit/control/start_series.sh 3 nocap_hold:yamls-hold nocap_freeze:yamls-freeze'
```

Expected: the difference between the two systems is smaller than the spread between repetitions in both series (paper: 3.35 vs 3.84% and 2.81 vs 2.48% RMSE).

### Figures (Figs. 3 and 5 to 9)

Copy your results to your machine and plot them:

```sh
./cluster/pull_results.sh                                              # -> evaluation/results/netpoke/
python3 plot_figures.py -r ../results/netpoke -o ../results/netpoke/figures
```

`plot_figures.py` finds `<arm>_rep<N>.log` files either directly in the given folder (as pulled from the control node) or in the sub-folders used for the paper's data. Figures for experiments you have not run are skipped.

Figs. 1, 2 and 4 are diagrams; they are in [`evaluation/netpoke/figures`](evaluation/netpoke/figures).

# Changes relative to Slowpoke

NetPoke changes the following files of Slowpoke (`nsdi26-ae`). All other benchmark code, YAMLs and scripts are Slowpoke's, unchanged.

| File | Change |
|---|---|
| [`src/poker/net_hold.c`](src/poker/net_hold.c), [`net_hold.h`](src/poker/net_hold.h) | New. Installs `sch_plug` on the pod interface and toggles it over netlink, with a `tc` fallback. |
| [`src/poker/poker.c`](src/poker/poker.c) | Closes the hold before `SIGSTOP`, opens it after `SIGCONT`, and logs `pause_start`/`pause_end` markers for every pause. |
| [`src/poker/build_poker.sh`](src/poker/build_poker.sh), [`sync_to_app.sh`](src/poker/sync_to_app.sh), [`app/slowpoke/poker`](app/slowpoke/poker) | Build helpers; `app/slowpoke/poker` is the Docker build copy of `src/poker`. |
| [`scripts/build/PrebuiltDockerfile`](scripts/build/PrebuiltDockerfile), [`src/deploy/PrebuiltDockerfile`](src/deploy/PrebuiltDockerfile) | Compile `net_hold.c` into `poker` and install `iproute2`. |
| [`app/cmd/mutex`](app/cmd/mutex), [`app/internal/trivial`](app/internal/trivial), [`evaluation/mutex`](evaluation/mutex), [`evaluation/run_mutex.sh`](evaluation/run_mutex.sh), [`evaluation/draw-mutex.py`](evaluation/draw-mutex.py), `CPUSpinTime` in [`app/pkg/slowpoke/utils.go`](app/pkg/slowpoke/utils.go), `mutex` entries in [`src/config.py`](src/config.py) and [`src/main.py`](src/main.py) | The `mutex` benchmark, ported from Slowpoke's `main` branch. `service2` additionally returns a response of `RESPONSE_PAYLOAD_BYTES` bytes. |
| [`src/main.py`](src/main.py), [`src/run.sh`](src/run.sh), [`client/fix_req_n.lua`](client/fix_req_n.lua) | Harness fixes: a guard against runs with no completed requests, Kubernetes Services kept between measurements with a first-request gate (stale DNS), and a robust request-count cap. |
| [`client/client.yaml`](client/client.yaml), [`client/proxy`](client/proxy) | Client image location, and a longer proxy timeout so requests buffered during a hold are not dropped. |

# Measurement notes

Three problems in the experiment harness affect any study of this kind; §5.1 of the paper describes them.

* **Forced redeploys.** Per-level settings reach the containers only at deployment, so `run_arm.sh` redeploys every measurement and stops if a log shows a skipped redeploy.
* **Stale service addresses.** Recreating Kubernetes Services between measurements changes their cluster IPs while cluster DNS still caches the old ones. The harness keeps the Services and waits for one successful request before each measurement ([`results/harness_checks`](evaluation/netpoke/results/harness_checks)).
* **Capped request counters.** The load generator's wrapper caps the per-thread request count after a slow warm-up, but `main.py` computes throughput from the planned count. [`control/slowlog.py`](evaluation/netpoke/control/slowlog.py) recovers the true values from each log (paper Algorithm 3); `summarize_runs.py` and `plot_figures.py` always apply it. Uncorrected throughputs in the raw logs are therefore inflated for some network-bound measurements.
