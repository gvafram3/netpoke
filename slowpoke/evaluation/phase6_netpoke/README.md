# Phase 6 — corrected NetPoke validation

Replaces the ad hoc `SLOWPOKE_NETPOKE=1` wiring that lived inside
`phase4_ebpf/run_ebpf_one_L2.sh`. Read
[`netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`](../../../netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md)
first — everything here exists to fix or verify a specific finding in that doc.

## What changed before you got here

`slowpoke/src/poker/net_hold.c` was rewritten (finding F1): `net_hold()`/`net_release()`
now try the fast netlink toggle first (the design always intended this) and
only fall back to shelling out to `tc` if netlink fails at runtime, with a
receive timeout so a stuck netlink call fails visibly instead of hanging the
pause-monitoring thread forever. Every toggle is timed **and now timestamped**
and logged to stderr (`netpoke: hold via=netlink took_ns=... uptime_s=...`),
so we can *see* which path is active and line pause windows up against
independent evidence — which is exactly what Step 3 uses `uptime_s` for.

## Status / what to run, in order

| Step | Script | Purpose | Status |
|---|---|---|---|
| 1 | `phase5_netpoke/build_netpoke_images.sh <bench>` | rebuild image with fixed `net_hold.c` | **done** for boutique, confirmed with the `SO_RCVTIMEO` fix included (2026-07-16) |
| 2 | `run_toggle_smoke.sh <bench>` + `check_toggle_latency.sh <bench>` | confirm the netlink toggle actually works on this kernel, measure real per-toggle cost | **PASS (2026-07-16)** — boutique: `n=362 min_ns=7280 avg_ns=481359 max_ns=25724998`, zero CLI fallbacks. Net hit two sync gotchas getting here (see live status log): `gcloud compute scp --recurse` nesting a directory into itself, and a skipped sync step producing a false "still broken" reading — both resolved. |
| 3 | `run_residual_check.sh <bench> [smoke\|full]` | fine-grained residual I/O evidence for RQ2, correctly correlated to real pause windows | **PASS (2026-07-16)** — boutique smoke: net RX during pause windows consistently lower than outside for every service with a real delay (e.g. `product_catalog` ~10% of outside-pause rate, `payment` ~2%); 69/197 windows had ≥1 overlapping sample. See live status log for the full result and its caveats (a few services had only 1-2 samples land inside 30+ windows — real signal, not yet solid statistics at smoke scale). |
| 4 | L0 overhead-only regression check | confirm NetPoke doesn't regress the compute-bound baseline | not yet built |
| 5 | full L2 RMSE matrix, NetPoke on, all 4 apps | Table N1 / Fig N1 | not yet built |
| 6 | fan-out instrumentation for the boutique outlier | explain, not just report, the L2 anomaly | not yet built |

Steps 4-6 are deliberately not built yet — see the live status log for the
current sequencing decision (validate the sampler first, then a fresh
SIGSTOP-only Phase 1+3 re-run on the fixed harness, then Phase 4 redone with
this sampler, then the NetPoke comparison).

## Step 3 in detail

Three new files, none baked into the Docker image (no rebuild needed for
this step):

- `residual_sampler_inpod.sh` — runs *inside* each non-target pod (no
  `kubectl exec` per sample, unlike the deprecated sampler — finding F2).
  Polls `/proc/[pid]/stat` + `/proc/pid/io` + `/proc/net/dev` every 10ms by
  default, writing JSONL to a local file in the container.
- `run_residual_check.sh <bench> [smoke|full]` — the orchestrator. Copies
  the sampler script into every non-target pod as soon as it's `Running`
  (via `kubectl cp` + a backgrounded `kubectl exec`), keeps re-attaching it
  across the baseline → groundtruth → slowdown redeploy cycles (`run.sh`
  fully redeploys between each — a pod that existed for baseline is not the
  same pod that exists for slowdown), runs the NetPoke experiment, then
  collects each pod's sample file and POKER's own `netpoke:` log lines.
- `correlate_residual.py` — pairs POKER's `hold`/`release` timestamps
  (`uptime_s`, now logged — see above) into pause windows, buckets every
  sampled I/O delta as "during a pause window" vs "outside," and reports
  totals. This is the actual mechanistic answer: if net RX during pause
  windows comes back at or near zero, that's the evidence NetPoke's egress
  hold is doing its job.

```bash
bash phase6_netpoke/run_residual_check.sh boutique smoke
```

`smoke` mode reuses the same 1-point/5000-request scale as Step 2's smoke
test — cheap, fast, meant to validate the sampler itself (we already know
this scenario produces real pauses, since Step 2 confirmed 362 of them).
Once that's confirmed working, the real target per the plan is `social`
(largest I/O gap in Phase 3) with `full` instead of `smoke`.

## Step 2 in detail

```bash
# 1. Rebuild + push the image with the fixed net_hold.c
cd ~/slowpoke/evaluation
bash phase5_netpoke/build_netpoke_images.sh boutique
PUSH=1 bash phase5_netpoke/build_netpoke_images.sh boutique

# 2. Deploy + tiny run + report
bash phase6_netpoke/run_toggle_smoke.sh boutique
```

Read the verdict at the end of the output:

- **PASS** — every toggle used netlink; note the reported `avg_ns` (this is
  the actual per-pause overhead NetPoke now adds; compare it against
  `poker_batch_req`/pause frequency to judge whether it's negligible).
- **STILL BROKEN** — every toggle fell back to the CLI; the script prints the
  specific netlink failure reason (`strerror(errno)`) from the pod logs. Bring
  that back before doing anything else — it tells us exactly what to fix next
  in `net_hold.c`, rather than guessing again.
- **MIXED** — inconsistent; worth investigating before trusting any RMSE
  numbers gathered under NetPoke.

## Always run with two windows, no matter how short

Standing rule: never run an experiment script in a single window "because it's
quick" — a stale/incomplete yaml folder (see the live status log) cost real
time precisely because nothing was watched live. Every run, including this
smoke test, uses two terminals on `netpoke-control`:

**Window 1 — runs the experiment:**
```bash
bash phase6_netpoke/run_toggle_smoke.sh boutique
```

**Window 2 — the live dashboard**, same tool as Phase 3/4, pinned directly at
this smoke test's log file (its auto-detection doesn't recognize the
`_netpoke_` suffix, and env-var-based detection doesn't carry across a
separate SSH session anyway):
```bash
WATCH_INTERVAL=5 bash ~/slowpoke/evaluation/watch_progress.sh \
  ~/slowpoke/evaluation/results/boutique_ebpf_L2_netpoke_medium.log
```
Shows the familiar `workloads X/3` / `opt points X/1` bars (3, not 21 --
smoke mode is baseline + 1 groundtruth + 1 slowdown), current phase, and last
throughput, refreshed every 5s.

Once that dashboard shows `FINISHED`, get the actual netlink-vs-CLI answer
(works in either window, the pods are still alive after the run finishes):
```bash
bash phase6_netpoke/check_toggle_latency.sh boutique
```

If you want to catch `netpoke:` toggle lines live rather than waiting for
the run to finish, use this instead of/alongside the dashboard in a spare
pane -- but note it's tied to one specific pod, and `run.sh` fully
redeploys between the groundtruth and slowdown phases, so it may need
re-running once the pod it's watching gets replaced:
```bash
while true; do
  POD=$(kubectl get pods -n default --field-selector=status.phase=Running \
    -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}' \
    | grep -Ev '^cart-|^ubuntu-client-' | head -1)
  [[ -n "$POD" ]] && break
  echo "waiting for a non-target service pod to be Running..."
  sleep 5
done
CTR=$(kubectl get pod -n default "$POD" -o jsonpath='{.spec.containers[0].name}')
echo "watching $POD ($CTR)"
kubectl logs -f -n default "$POD" -c "$CTR" | grep --line-buffered 'netpoke:'
```

For the full L2 matrix later (Step 5, ~40-50 min/app), Window 1 becomes a
`screen` session running the suite and Window 2 becomes
`watch_progress.sh --append results/`, same as Phase 3/4.
