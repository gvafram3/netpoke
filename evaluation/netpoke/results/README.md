# Results reported in the paper

All measurements behind the paper's tables and figures. Logs are named `<arm>_rep<N>.log`, one per repetition; `arm` names the condition and the system (`freeze` = Slowpoke as published, `hold` = NetPoke).

Throughput values printed inside the logs are the raw values from Slowpoke's driver. For network-bound runs some of them are inflated by the capped request counter (see `INSTRUCTIONS.md`, Measurement notes). Always read the logs through `control/summarize_runs.py` or `plot_figures.py`, which apply the correction.

| Folder | Content | Paper |
|---|---|---|
| `reproduction/` | `phase1_nolock`: Slowpoke's image and YAMLs, no lock contention, no network cap (20,000 requests per measurement) | §5.2, Table 4 |
| `cpu_quota/` | per-process and per-request CPU use of the target's node, used to derive the effective quota of 1.84 cores | §5.2 |
| `calibration/` | ground-truth throughput with and without the 175 Mbit/s cap (`quick_tput/` holds every point's deployment log) | §2.3, Table 1 |
| `netbound_deep/` | `phase2_freeze` (Slowpoke) and `deepq_hold` (NetPoke) under the cap with the default `fq_codel` queue | §5.3, §5.5, Tables 5 and 8, Figs. 3a and 7a |
| `netbound_shallow/` | `phase5_freeze` and `phase5_hold`, interleaved, under the cap with a 20-packet `pfifo` queue; `phase5_conditions.txt` records the queue | §5.5, Tables 7 and 8, Figs. 3b, 6 and 7b |
| `no_bottleneck/` | `cpu_*` (small responses) and `nocap_*` (8 KB responses), interleaved, no cap | §5.6, Table 9, Fig. 8 |
| `leak_kernel/` | single paused TCP sender, with and without the hold, pauses of 50 to 1,000 ms | §2.2, §5.4 |
| `leak_inapp/` | in-application leak at the paused pod (A) and at the bottleneck (B) for three queues and both systems: `result_*` analyses, `markers_*` pause markers, `leak_matrix*.txt` run logs | §5.4, Table 6, Fig. 5 |
| `harness_checks/` | probes behind the harness corrections (stale DNS after redeploys, first-request stalls, neighbour caches) | §5.1 |
| `env.txt`, `image.txt`, `COMMIT.txt`, `build_*.log` | instance types and kernels, container image digest, code commit, image build log | §5.1, Table 2 |

All prediction experiments except the reproduction use 60,000 requests per measurement.
