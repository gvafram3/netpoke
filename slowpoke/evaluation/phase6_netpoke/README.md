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
| 3 | `run_residual_check.sh <bench> [smoke\|full]` | validate the sampler itself | **PASS (2026-07-16)** — boutique smoke (NetPoke on): net RX during pause windows consistently lower than outside for every service with a real delay; 69/197 windows had ≥1 overlapping sample. See live status log. |
| 3.5 | `run_residual_check.sh <bench> <L1\|L2> [smoke\|full] [netpoke:0\|1]` | **the actual RQ2 question**: how much I/O leaks through during a SIGSTOP-only pause, under Phase 3's real netem conditions — not yet measured before this | **built (2026-07-17), not yet run** — see below |
| 4 | L0 overhead-only regression check | confirm NetPoke doesn't regress the compute-bound baseline | not yet built |
| 5 | full L2 RMSE matrix, NetPoke on, all 4 apps | Table N1 / Fig N1 | not yet built |
| 6 | fan-out instrumentation for the boutique outlier | explain, not just report, the L2 anomaly | not yet built |

## Step 3.5 — the SIGSTOP-only residual-I/O question, directly

Phase 3's RMSE numbers are an *indirect* stimulus test (add netem, see if accuracy gets worse)
— they never actually watch whether residual I/O during a pause increased as a result. This
step measures that directly, on the SIGSTOP-only baseline (no NetPoke), under the exact netem
conditions Phase 3 used, so it can be compared against Phase 3's RMSE pattern (and later against
the same scenario with NetPoke on).

**This required two real additions, not just a script change:**

- `poker.c` now prints an unconditional `poker: pause_start uptime_s=...` /
  `poker: pause_end uptime_s=...` around every SIGSTOP/SIGCONT, regardless of NetPoke. Previously
  *only* `net_hold()`/`net_release()` logged timestamps, and those are no-ops when NetPoke is
  off — meaning there was literally no way to know when a SIGSTOP-only pause happened. This
  needs a rebuild (`build_netpoke_images.sh`) before it takes effect.
- `run_residual_check.sh` now takes a `netpoke:0|1` argument (default `0`, SIGSTOP-only). When
  `0`, it generates a `yamls/netpoke-sigstop/` variant on the fly — same `*-netpoke` image (has
  the `poker.c` fix above) but with `SLOWPOKE_NETPOKE` forced to `"0"`, so the egress-hold
  mechanism itself stays inert while pause-window logging still works. This means the
  SIGSTOP-only and NetPoke-on runs are otherwise identical (same image, same caps) except for
  that one variable.
- `correlate_residual.py` now reads the unconditional `poker: pause_*` markers as the primary
  pause-window signal (falls back to the old `netpoke: hold/release` format for logs captured
  before this fix). Prints a different summary line depending on `--netpoke`.

```bash
# Rebuild first (poker.c changed) -- sync + rebuild same as always:
bash phase5_netpoke/build_netpoke_images.sh <bench>
PUSH=1 bash phase5_netpoke/build_netpoke_images.sh <bench>

# Then, SIGSTOP-only, matching Phase 3's actual L2 conditions:
bash phase6_netpoke/run_residual_check.sh social L2 smoke 0
```

Recommended: validate on `social` (smoke first — it's the strongest, cleanest RMSE signal, worth
confirming residual I/O actually tracks it) and `hotel` (smoke first — it reversed direction in
the fresh Phase 3 re-run, worth checking whether residual I/O explains that or points elsewhere).
Once smoke confirms the mechanism works under real injection, move to `full` for a trustworthy
number.

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
