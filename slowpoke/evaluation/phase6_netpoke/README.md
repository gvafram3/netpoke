# Phase 6 — corrected NetPoke validation

Replaces the ad hoc `SLOWPOKE_NETPOKE=1` wiring that lived inside
`phase4_ebpf/run_ebpf_one_L2.sh`. Read
[`netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md`](../../../netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md)
first — everything here exists to fix or verify a specific finding in that doc.

## What changed before you got here

`slowpoke/src/poker/net_hold.c` was rewritten (finding F1): `net_hold()`/`net_release()`
now try the fast netlink toggle first (the design always intended this) and
only fall back to shelling out to `tc` if netlink fails at runtime — and every
toggle is timed and logged to stderr (`netpoke: hold via=netlink took_ns=...`),
so we can *see* which path is active instead of assuming.

## Status / what to run, in order

| Step | Script | Purpose | Status |
|---|---|---|---|
| 1 | `phase5_netpoke/build_netpoke_images.sh <bench>` | rebuild image with fixed `net_hold.c` | rebuild required before anything below |
| 2 | `run_toggle_smoke.sh <bench>` + `check_toggle_latency.sh <bench>` | confirm the netlink toggle actually works on this kernel, measure real per-toggle cost | **ready to run** |
| 3 | in-pod residual sampler (replaces the deprecated kubectl-exec-loop one) | fine-grained residual I/O evidence for RQ2 | **not yet built — build after Step 2 tells us the toggle path is confirmed working** |
| 4 | L0 overhead-only regression check | confirm NetPoke doesn't regress the compute-bound baseline | not yet built |
| 5 | full L2 RMSE matrix, NetPoke on, all 4 apps | Table N1 / Fig N1 | not yet built |
| 6 | fan-out instrumentation for the boutique outlier | explain, not just report, the L2 anomaly | not yet built |

Steps 3-6 are deliberately not built yet: there is no point building the
fine-grained residual sampler (which is real engineering effort) until Step 2
confirms the netlink fix actually works on your cluster's kernel. If Step 2
comes back "STILL BROKEN", the next move is diagnosing that specific netlink
error (reported by `check_toggle_latency.sh`), not building more on top of a
broken toggle.

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

This does not need the two-screen `screen` + `watch_progress.sh` monitoring
setup — it's a single small run, done in a couple of minutes. That monitoring
pattern is for Step 5 (the full 40-50-minute-per-app matrix), once we get there.
