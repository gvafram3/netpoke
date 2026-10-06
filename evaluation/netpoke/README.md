# NetPoke experiments

Harness for the experiments in the NetPoke paper. See [`INSTRUCTIONS.md`](../../INSTRUCTIONS.md) at the repository root for the full procedure.

* `cluster/`: run from your machine. Cluster setup (`01_` to `05_`), SSH helpers, network cap (`netcap.sh`), kernel leak test (`leak_suite.sh`), run control (`start_run.sh`, `watch.sh`, `stop_run.sh`) and `pull_results.sh`. Configure with `cluster/config.env` (copy `config.env.example`; never commit it).
* `node/`: run on each node by the cluster scripts. Installs Docker, cri-dockerd and Kubernetes, and checks kernel support for `sch_plug`, `htb` and `netem`.
* `control/`: run on the control node (copied to `~/kit/control` by `05_sync_repo.sh`).
  * `run_series.sh`, `start_series.sh`, `run_arm.sh`: interleaved prediction experiments.
  * `make_mutex_yamls.py`, `make_mutex_yamls_nopayload.sh`: Slowpoke and NetPoke YAML variants.
  * `ctl_netcap.sh`: the 175 Mbit/s bottleneck and its leaf queue.
  * `ctl_leak.sh`, `ctl_leak_matrix.sh`, `ctl_lib.sh`: in-application leak measurement.
  * `quick_tput.sh`, `manual_point.sh`: single ground-truth points.
  * `slowlog.py`, `summarize_runs.py`: log parsing with the capped-counter correction.
* `tests/`: egress-leak tools. `kernel_leak_test.py` and `leak_suite.sh` (single sender), `leak_by_uptime.py` (leak during real pauses from packet captures and pause markers).
* `results/`: the paper's data ([index](results/README.md)).
* `plot_figures.py`, `figures/`: regenerate the paper's figures from the logs.

New runs write to `evaluation/results/netpoke/`, never into `results/`.
