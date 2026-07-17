# Methodology critique and fix plan — why the numbers aren't proving the thesis yet

**Purpose:** A source-grounded audit of what SlowPoke's implementation actually does (vs the
paper), why the Phase 3/4/5/6 numbers gathered so far don't yet support the NetPoke claim, and
a concrete plan to get evidence that does. Every finding below is backed by a specific file/line
in this repo, not a general impression.

**Verdict up front:** The model and POKER's pause mechanics are implemented faithfully to the
paper (verified against `slowpoke/src/main.py` and `slowpoke/src/poker/poker.c`). The problem is
not the reproduction of SlowPoke — it's that **the three instruments built to prove the NetPoke
thesis (the network hold itself, the eBPF residual sampler, and the I/O-gap injection) each have
a concrete defect that stops them from measuring what they claim to measure.** That's why the
numbers look ambiguous (boutique outlier, Phase 4 "validating" Phase 3 by just re-running it,
NetPoke's effect unclear) — the instruments haven't been pointed correctly at the phenomenon yet.

---

## Live status log

**Read this section first — it's the current "where are we" answer.** Updated as we go;
newest entry on top. Everything below the log (findings, plan, figures) is the stable
background reference.

### 2026-07-17 (first real SIGSTOP-only residual result) — poststorage barely gets paused at all

`run_residual_check.sh social L2 smoke 0` (SIGSTOP-only, real L2 netem conditions, the
`SLOWPOKE_YAML_SUBDIR` fix applied) — the first genuine, direct measurement of residual I/O
during un-mitigated `SIGSTOP` pauses this project has produced. Good sample coverage: 171/276
pause windows (62%) had ≥1 overlapping sample, well up from the earlier NetPoke smoke test's 35%.

| Service | Δ net RX during pause | Δ net RX outside pause | Residual ratio |
|---|---|---|---|
| `poststorage` | 6.44MB | 7.05MB | **91%** — SIGSTOP barely reduces its traffic at all |
| `usertimeline` | 3.40MB | 4.77MB | 71% |
| `composepost` | 0.81MB | 2.10MB | 39% |
| `socialgraph` | 0.13MB | 1.54MB | 9% — SIGSTOP works reasonably well here |

Aggregate: 10.78MB during pause windows vs 15.45MB outside them (~70% residual rate).

**This directly explains, not just correlates with, Phase 3's strongest result.** `poststorage`
is exactly the service Phase 3's L2 injection targeted with the heaviest delay (50ms), and
social produced the cleanest, strongest RMSE increase of all four apps (+19.60pp, monotonic).
We now have direct mechanistic evidence — not an inferred proxy — that `poststorage` is
genuinely I/O-heavy enough that `SIGSTOP` fails to meaningfully pause its network activity,
which is precisely the paper's claimed failure mode. This is the first result in the project
that closes the causal chain (netem stimulus → genuinely more residual I/O during pause →
higher RMSE) rather than assuming the middle link.

**Next:** (1) same check on `hotel` (the app that reversed direction in fresh Phase 3 — does it
show low residual leakage, supporting "reversal is unrelated noise," or high leakage too,
which would be a more interesting puzzle) and (2) social with `netpoke=1` for the direct
before/after comparison (does NetPoke bring `poststorage`'s 91% down toward `socialgraph`'s 9%).

### 2026-07-17 (social smoke, take 1) — run.sh silently deployed the wrong image; fixed

First cluster attempt at the SIGSTOP-only residual measurement (social, L2, smoke): sampler
collected thousands of samples per pod correctly, but **zero** pause-window log lines anywhere,
and a direct check showed the pod had **no `SLOWPOKE_NETPOKE` env entry at all**. Root cause:
`run.sh` only switches to `yamls/netpoke` when the shell's `SLOWPOKE_NETPOKE` is exactly `"1"` —
for `netpoke=0` it silently fell through to the plain, original (non-`*-netpoke`) image, which
has none of this project's `poker.c` fixes. Fixed by adding `SLOWPOKE_YAML_SUBDIR` to `run.sh`
to select the yaml directory directly, independent of the on/off semantic flag, and updating
`run_residual_check.sh` to set it explicitly rather than relying on the `SLOWPOKE_NETPOKE=="1"`
check to also happen to pick the right image. Not yet re-tested on the cluster.

### 2026-07-17 (methodology pause) — questioned whether Phase 3 actually measures residual I/O

Before moving to Phase 4, stepped back to ask: does Phase 3's netem-injection RMSE method
actually measure "does I/O leak through during a SIGSTOP pause," or something more indirect?
Conclusion: it's an indirect stimulus test (add network delay somewhere, see if the final
accuracy number moves) that has never actually watched what happens *during* a pause window —
plausibly connected to the paper's claim (a slower downstream service could mean more in-flight
data at the instant of a pause), but never verified, and the fresh Phase 3 data's instability
(hotel reversing direction between runs) is more consistent with a noisy/confounded proxy than a
clean causal measurement.

**Found we couldn't actually check this even if we wanted to:** the residual sampler (Step 3)
only ever ran with NetPoke on. For the SIGSTOP-only case, POKER printed no pause-window
timestamps at all — `net_hold()`/`net_release()` are no-ops when NetPoke is off, and nothing
else logged when a SIGSTOP/SIGCONT pair actually happened. Fixed by adding an unconditional
`poker: pause_start`/`poker: pause_end` marker directly in `poker.c` (not gated on NetPoke), and
extended `run_residual_check.sh` to accept `<level>` and `netpoke:0|1`, generating a
`yamls/netpoke-sigstop` variant (same `*-netpoke` image, `SLOWPOKE_NETPOKE` forced to `"0"`) so
the SIGSTOP-only and NetPoke-on runs are identical except for that one variable — needed to make
the two conditions directly comparable.

**Not yet run.** Needs a rebuild (poker.c changed) and sync, then a smoke-scale validation on
`social` (confirm the strong RMSE signal is backed by real residual I/O) and `hotel` (check
whether residual I/O explains its reversal, or whether that reversal is unrelated noise) before
committing to full-scale runs or the Phase 4 sweep across all four apps.

### 2026-07-17 (Phase 3 done) — fresh I/O-gap matrix: social cleaner than ever, hotel reversed, mixed overall

Phase 3 completed fully overnight, unattended, with no further monitor intervention needed —
confirms both `watch_progress.sh` fixes held up across all 8 remaining transitions after the pty
stall was cleared. Full matrix in
[`TABLE_IO_GAP_MATRIX.md`](../results/cluster/io_gap/tables/TABLE_IO_GAP_MATRIX.md).

**Honest summary — more mixed than the old dataset, not cleaner:**

| App | Old Δ(L2−L0) | New Δ(L2−L0) | New trend |
|---|---|---|---|
| Social | +14.30pp | **+19.60pp** | Monotonic, cleanest result this project has produced |
| Movie | +2.75pp | +1.63pp | Net positive but L1 spikes to 28.48% then drops — not clean |
| Boutique | −3.59pp (outlier) | +0.96pp | No longer contradicts the hypothesis, but not a clean trend either |
| Hotel | +6.05pp (clean, monotonic) | **−3.14pp** | **Reversed** — now contradicts the hypothesis |

- **Social got stronger and cleaner** — the best single piece of evidence for RQ1 (I/O-gap
  increases prediction error) this project has produced.
- **Hotel flipped from supporting to contradicting.** Not investigated further, but worth
  connecting to an existing pattern: hotel's Phase 1 (L0) RMSE alone nearly doubled between the
  old and fresh runs (10.23% → 20.65%) before any I/O-gap injection is even involved — hotel
  appears to be unusually sensitive to run-to-run cluster variance specifically, more than the
  other three apps. This is a real open question, not something to gloss over or resolve by
  picking whichever run looks more convenient.
- **Aggregate RQ1 support still holds** (3/4 apps net positive) but the per-app story is noisier
  than the old dataset suggested. Lead with social; treat boutique/movie/hotel's specific trends
  as open case studies, not settled evidence either way.
- **Next: Phase 4** — residual I/O during SIGSTOP-only pauses, redone properly with the
  validated in-pod sampler from Step 3, on this fresh baseline.

### 2026-07-17 — Phase 3 stalled ~1h26m on a pty write block, not a script bug; diagnosed and cleared

- **Symptom:** after boutique L1 completed (23:41, real `Error Perc:` data), Phase 3 appeared
  stuck — no `boutique_io_L2_medium.log` ever appeared, dashboard showed "log file not created
  yet" indefinitely, and a `screen -X hardcopy` dump showed content frozen from hours earlier.
- **Root cause, confirmed via `/proc/<pid>/wchan` and `/proc/<pid>/fd`:** `restore_io_injection.sh`
  (invoked from `run_io_medium.sh`'s `EXIT` trap, itself a normal, correct part of the design) was
  blocked in the kernel's `iterate_tty_write`, mid-`write()` to `/dev/pts/2` — the `screen`
  session's terminal. The pty's output buffer was full and nothing was draining it, so the write
  blocked indefinitely. This also explains the "frozen hardcopy" — the screen genuinely stopped
  updating at that point because writes to it had been silently blocking ever since, not a display
  bug. Not a bug in any of the `io_gap` scripts themselves — a systems/infrastructure issue with a
  long-running `screen` session's pty filling up while nothing kept it drained (`run_with_monitor.sh`
  keeps writing periodic status to the same terminal for the life of a run, on top of an
  interactively-detached session not consuming it).
- **First fix attempt (partial):** `kill`ed the one stuck `restore_io_injection.sh` process,
  reasoning that `run_io_medium.sh`'s `restore_io_injection.sh || true` cleanup would swallow the
  resulting nonzero exit and let the script complete. This did clear that one process, but
  `run_io_medium.sh` itself remained stuck afterward — confirming the pty's output buffer was
  still full and undrained, so the *next* writer in the chain blocked the same way.
- **Actual root cause, confirmed:** `screen`'s own daemon process was healthy (`do_select`, the
  normal idle-wait state — not stuck), which narrowed it to **terminal flow control (XOFF/IXON)**:
  a `Ctrl-S` sent to that pty at some point (easy to trigger by accident across a long session
  with many attach/detach cycles) pauses all output to it at the kernel level until a `Ctrl-Q`
  releases it — exactly matching a healthy reader (screen) with writes still blocking.
- **Real fix:** attached (`screen -r slowpoke-fresh-run`) and immediately pressed `Ctrl-Q` before
  anything else. The entire backlog flushed at once and boutique L2 started running normally.
  No data lost, no restart needed either way.
- **Mitigation, corrected:** the true cause was flow control (likely an accidental keystroke),
  not a pty buffer simply filling up from lack of reading — `screen`'s own daemon continuously
  drains its pty regardless of client attachment, so being attached doesn't add protection and
  arguably adds *more* exposure to an accidental `Ctrl-S`. Better pattern: **leave the session
  detached** most of the time (SSH disconnecting entirely is fine — that's what `screen` is for),
  attach only briefly to check status, detach cleanly (`Ctrl+A` `D`) rather than lingering. If it
  freezes again, attach and immediately press `Ctrl-Q`. Worth remembering for Phase 4/5/6's own
  long-running sessions.

### 2026-07-16 (Phase 2 done) — fresh Phase 1 RMSE numbers: boutique now matches the paper; hotel/social higher

Ran `plot_fig8_png.sh` + `summarize_results.py` on the 4 fresh Phase 1 logs. Comparison against
the old (pre-this-session) numbers:

| App | Old baseline (req/s) | Old RMSE | New baseline (req/s) | New RMSE | Δ |
|---|---|---|---|---|---|
| Boutique | 1820.0 | 9.19% | 1937.3 | **2.57%** | −6.62 pp |
| Hotel | 563.2 | 10.23% | 723.9 | **20.65%** | +10.42 pp |
| Social | 930.0 | 10.34% | 959.9 | **14.01%** | +3.67 pp |
| Movie | 611.2 | 13.97% | 550.8 | **12.21%** | −1.76 pp |

- **Boutique now matches the paper's own reported ~2.07% RMSE almost exactly** — the best
  agreement this project has produced. Strong circumstantial evidence that this session's
  harness fixes (`main.py` empty-`times` guard, `run.sh` wrk duration cap, `fix_req_n.lua`
  nil-guard) were eliminating real silent measurement corruption, not just cosmetic bugs.
- **Hotel and social came out higher, not lower.** Treating this as real but not yet
  explained: these are single-repetition measurements (already flagged elsewhere in this
  project as noisy), and hotel's baseline throughput itself also shifted notably (563→724
  req/s, +28%), consistent with ordinary run-to-run cluster variance rather than a regression
  traceable to any specific fix (none of this session's fixes touched hotel-specific code
  paths). Not investigated further — not part of the current plan, and would need repeated
  runs to separate signal from noise.
- **This is now the baseline of record going forward**, superseding the old numbers for the
  I/O-gap and eventual NetPoke comparisons. Fresh figures: `results/{boutique,hotel,social,
  movie}_medium.png`, `results/plot_macro.pdf` (on netpoke-control, not yet synced to repo).
- Phase 3 (I/O-gap, all 4 apps × L1/L2) continues running in parallel, unaffected by this.

### 2026-07-16 (Phase 1 done) — fresh baseline complete for all 4 apps; Phase 3 running; both monitor fixes confirmed working

- **Fresh Phase 1 baseline complete**: boutique, hotel, social, movie all finished successfully
  in the current `screen` session. This is the clean "before" data the sequencing plan called
  for, collected on the current bug-fixed harness (not the numbers gathered before this
  session's `main.py`/`run.sh`/`fix_req_n.lua` fixes).
- **Both `watch_progress.sh` fixes confirmed working end-to-end, unattended**: the dashboard
  auto-transitioned hotel → social → movie, then correctly detected Phase 1's completion and
  Phase 3's start (`I/O-gap: 0/8 runs complete` → `boutique_io_L1_medium.log`, real throughput
  data flowing) with zero manual stamp-file edits or restarts. No further monitor intervention
  expected for the rest of this run (Phase 3's remaining 7 transitions).
- **Phase 3 (I/O-gap, all 4 apps × L1/L2) now running**, fresh, same bug-fixed harness.
- **Next, safe to do now in parallel** (reads log files only, no cluster interaction): Phase 2
  packaging — `plot_fig8_png.sh results/` + `summarize_results.py` on the 4 fresh baseline logs
  — to get updated Fig. 8 panels / macro PDF / RMSE table before Phase 3 finishes.
- **After Phase 3 finishes:** sync the 8 fresh logs down, update
  `netpoke/results/cluster/baseline/` and `.../io_gap/` tables to replace the old numbers, then
  move to Phase 4 (residual I/O, SIGSTOP-only, using the now-validated in-pod sampler from
  Step 3) before finally the NetPoke comparison (Phase 5/6).

### 2026-07-16 (second monitor bug fixed) — pick_active_log() checked a static guess before what's actually running

- After the stale-stamp fix (below), the dashboard jumped from `boutique_medium.log` straight to
  `boutique_io_L1_medium.log` while hotel's Phase 1 baseline was still genuinely running (`ps aux`
  confirmed `main.py -b hotel` active, `hotel_medium.log` growing, no `_io_` files existed
  anywhere yet). Root cause: `pick_active_log()`'s "Phase 3 I/O-gap suite: first incomplete log
  in fixed order" loop ran *before* the "match the benchmark main.py is actually running" check,
  so it matched `boutique_io_L1_medium.log` simply because that file doesn't exist yet — true in
  Phase 1 for every benchmark, not a sign Phase 3 had started.
- Fixed by reordering: check what's actually running first, and only probe that benchmark's
  `_io_L1`/`_io_L2` variants if I/O-gap output already exists somewhere on disk (evidence Phase
  3 has actually begun) — otherwise go straight to its plain `_medium.log`. The fixed-order
  guess is now only a last-resort fallback for when nothing can be determined about what's
  running at all.
- Same lesson as the stale-stamp bug: neither issue affected the actual experiment, only the
  live dashboard's display — but worth fixing properly since this run spans many hours and
  many phase transitions where it would keep recurring otherwise.

### 2026-07-16 (fresh baseline started) — watch_progress.sh stale-stamp bug fixed; Phase 1+3 re-run underway

- **Fresh Phase 1 + Phase 3 re-run started** (`run_reproducible.sh && io_gap/run_io_gap_all.sh`
  in a `screen` session), per the agreed sequencing — all 4 apps, SIGSTOP-only, no NetPoke, on
  the current bug-fixed harness.
- **False alarm, real bug found and fixed:** `watch_progress.sh` briefly reported the active log
  as `boutique_ebpf_L2_netpoke_medium.log` (a leftover from the Step 3 residual-sampler smoke
  test) while Phase 1's boutique run was genuinely healthy and in progress
  (`ps aux` confirmed `main.py -b boutique --num_exp 10 --num_req 100000`, correct full-scale
  params). Root cause: `pick_active_log()`'s `.slowpoke_active_log` stamp-file check trusted any
  stamped path as long as *some* `main.py` process was running, without checking whether the
  stamped log actually belonged to that process. Fixed by cross-checking the stamp's benchmark
  name against `main_py_benchmark()` before trusting it.
- Not a data-integrity issue — only affected the live dashboard's display, not the actual
  experiment.

### 2026-07-16 (Step 3 PASS) — first real mechanistic evidence: residual RX is reduced, not eliminated

- Re-ran `run_residual_check.sh boutique smoke` after the stream-in + parallel-attach fix — the
  sampler attached successfully across all three redeploy cycles (baseline/groundtruth/slowdown)
  and 8 pods returned samples + POKER logs.
- **`correlate_residual.py` result:** for every service with a real computed delay (checkout,
  currency, frontend, payment, product_catalog, shipping), net RX during pause windows is
  consistently *lower* than RX outside pause windows — e.g. `product_catalog` ~191KB during
  pause vs ~1.9MB outside (~10%); `payment` ~4.8KB vs ~214KB (~2%). Aggregate: 3.0MB RX during
  pause windows vs 13.2MB outside, across 69/197 windows that had ≥1 overlapping sample.
  `email`/`recommendations` show ~1 window each with no data, consistent with their known
  zero request-ratio for this target — expected, not a gap in the instrument.
- **This is genuinely new evidence, not just a working tool:** it's the first time this project
  has directly measured that NetPoke's egress hold reduces (not eliminates) residual ingress
  during a pause, rather than asserting it from design intent. Residual isn't exactly zero,
  which matches the design doc's own expectation (packets already in flight at the instant of
  the pause have to land somewhere) — the open question is whether this reduced level is
  *meaningfully* smaller than the un-mitigated SIGSTOP-only case, which requires the baseline
  comparison below to answer.
- **Caveat, not a flaw:** several services (currency, frontend, shipping) had 30+ real pause
  windows but the sampler only landed inside 1-2 of them — those specific during-pause numbers
  are single-sample estimates, not solid averages, at this smoke test's tiny 5000-request scale.
  Worth revisiting sampling resolution once we're doing this at full scale (Phase 4 redo), not
  now.
- **Step 3 is done.** Per the agreed sequencing, next is the fresh Phase 1 + Phase 3 re-run
  (all 4 apps, SIGSTOP-only, no NetPoke) on the current bug-fixed harness — independent of the
  sampler, so nothing here blocks it.

### 2026-07-16 (Step 3, first run failed silently) — fixed swallowed errors + a likely race

- First cluster run of `run_residual_check.sh boutique smoke`: the experiment itself completed
  fine (Error Perc -7.4%, consistent smoke noise), but **zero pods ever got the sampler
  attached** — `correlate_residual.py` found no `.jsonl` files at all.
- Root cause was in the orchestration script, not the sampler or the cluster: `kubectl
  cp`/`kubectl exec` stderr was being silently discarded, so there was no way to see why every
  attach attempt failed. Two real issues fixed:
  1. `kubectl cp` shells out to `tar` inside the target container -- not explicitly installed
     in these images, and unverifiable from here. Replaced with streaming the sampler script
     over `kubectl exec -i`'s stdin (`cat > file`), which only needs `sh`/`cat`.
  2. Likely timing race: attaching to each pod took ~2 kubectl round-trips done serially, one
     pod at a time, while `run.sh` fully redeploys all pods between baseline → groundtruth →
     slowdown -- in a fast 5000-request smoke run a phase may not last long enough for a
     serial sweep across ~8 pods to finish before they're replaced. Now fires all attach
     attempts in parallel per watch cycle instead of one at a time, and logs every failure
     reason to `results/residual/<bench>/.attach_debug.log` instead of discarding it.
- **Not yet re-tested.** Next: re-sync just this one file and re-run the same smoke command.

### 2026-07-16 (Step 3 built) — corrected residual-I/O sampler, sequencing decision

- **Agreed sequencing for the rest of the evaluation**, in order: (1) validate the new
  in-pod residual sampler on a cheap single-app smoke test, (2) a **fresh** Phase 1 + Phase 3
  re-run (all 4 apps, SIGSTOP-only, no NetPoke) on the current harness — worth doing properly
  since this session already fixed real bugs in `main.py`/`run.sh`/`fix_req_n.lua` that affect
  the ordinary path too, so old numbers may carry latent effects of bugs that no longer exist,
  (3) Phase 4 redone properly with the corrected sampler against that fresh baseline, (4) the
  actual NetPoke comparison (Phase 5/6) against steps 2-3's numbers. This keeps both sides of
  the eventual before/after comparison measured with the same trustworthy tooling.
- **Added a required piece of instrumentation that wasn't scoped until now:** POKER's
  `hold`/`release` log lines only carried a *duration* (`took_ns`), not an absolute
  timestamp — nothing to correlate residual-I/O samples against. Added `uptime_s` to both log
  lines in `net_hold.c` (seconds since node boot, same underlying clock as `/proc/uptime`,
  which the new sampler also reads — directly comparable without a separate clock-sync step).
- **Built Step 3** (`slowpoke/evaluation/phase6_netpoke/`):
  - `residual_sampler_inpod.sh` — runs inside each non-target pod, POSIX shell, ~10ms polling
    of `/proc/[pid]/stat`+`/proc/pid/io`+`/proc/net/dev`, no `kubectl exec` per sample (the
    core fix for finding F2).
  - `run_residual_check.sh <bench> [smoke|full]` — orchestrates: attaches the sampler to
    every non-target pod as it becomes `Running`, re-attaches across the baseline →
    groundtruth → slowdown redeploy cycles (pods are not the same pods across phases),
    collects samples + POKER logs at the end.
  - `correlate_residual.py` — pairs `hold`/`release` timestamps into pause windows, buckets
    every sampled I/O delta as during-pause vs outside-pause, reports totals. This is the
    actual O2/RQ2 evidence the deprecated sampler couldn't produce.
- **Not yet run on the cluster.** None of this required a rebuild (the sampler and
  orchestration are plain scripts, not baked into the image), so no sync/rebuild cycle needed
  before testing — just `bash phase6_netpoke/run_residual_check.sh boutique smoke`.
- **Next action:** run the smoke-scale validation on boutique (cheap, and we already know this
  exact scenario produces 362 real pauses from Step 2), confirm the correlation script produces
  a sane result, then move to the fresh Phase 1+3 re-run.

### 2026-07-16 (final) — Step 2 PASS: netlink toggle confirmed working on the cluster kernel

- After two failed sync attempts (`gcloud compute scp --recurse` nested the directory into
  itself both times — `~/slowpoke/src/poker/poker/net_hold.c` — rather than overwriting in
  place; fixed by scp'ing the individual files instead of the directory), the `SO_RCVTIMEO` fix
  finally landed correctly, image rebuilt, smoke test re-run.
- **Result: PASS.** `check_toggle_latency.sh boutique` →
  `netlink  n=362  min_ns=7280  avg_ns=481359  max_ns=25724998  (avg=0.481ms)`.
  **Zero** of 362 pause events fell back to the CLI path — finding F1 is fixed and confirmed on
  the real cluster kernel, not just in theory. The original EINVAL-causing bug (nested rtattr
  instead of the raw `struct tc_plug_qopt`) and the silent-hang risk (`recvmsg()` with no
  timeout) are both resolved.
- **First real NetPoke overhead data, ever:** min 7.3µs (matches the design's "microsecond
  toggle" intent exactly), avg 0.48ms, max 25.7ms. The max is a real tail-latency outlier, most
  likely `rtnl_lock` contention from many pods toggling `sch_plug` concurrently — worth
  watching as we scale up, not concerning at this stage (still far cheaper on average than the
  `system("tc ...")` fork/exec path it replaced, which the design doc estimated at several ms
  minimum per call).
- **Step 2 is done.** Next: Step 3 — build the corrected in-pod residual-I/O sampler (replacing
  the deprecated `kubectl exec`-polling one, finding F2) to get real evidence of whether
  NetPoke actually shrinks residual I/O during pauses, correlated against POKER's own
  hold/release timestamps.

### 2026-07-16 (later still) — SO_RCVTIMEO fix not actually tested yet: sync step was skipped

- Re-ran the smoke test after the `SO_RCVTIMEO` fix (previous entry) — still **zero**
  `hold`/`release` log lines, same as before.
- Before assuming the fix doesn't work, checked whether it was actually on the VM:
  `grep SO_RCVTIMEO ~/slowpoke/src/poker/net_hold.c` on `netpoke-control` came back **empty**.
  The Cloud Shell → VM sync step for this fix was skipped, so this test (and the one before
  it) ran the exact same pre-timeout code both times — fully consistent with the silent-hang
  theory, just not yet actually exercised against the fix.
- Also checked `imagePullPolicy` on the boutique netpoke yamls as a second possible
  explanation (stale cached image on a worker node despite pushing a new one under the same
  tag) — this came back clean, `Always` is already set everywhere, so that's **ruled out** as
  a contributing factor.
- **Not yet known:** whether the timeout fix actually resolves the hang. Next: sync
  `slowpoke/src/poker/` again, verify the grep finds `SO_RCVTIMEO` on the VM *before*
  rebuilding, rebuild + push, then re-run the smoke test.

### 2026-07-16 (later) — found and fixed a likely silent-hang bug in the netlink toggle

- **Deploy bug from the previous entry fixed correctly:** re-ran the smoke test with the
  corrected 9-service yaml set — all pods deployed and ran a full baseline → groundtruth →
  slowdown cycle successfully (boutique smoke summary: groundtruth 1718.4, slowdown 1731.6,
  predicted 2843.9 req/s — the 65.5% error is expected noise for a 1-point/5000-request smoke
  run, not meaningful on its own).
- **New finding, more fundamental than netlink-vs-CLI:** `check_toggle_latency.sh` found
  **zero** `hold`/`release` log lines for *any* of the 8 non-target services, for their entire
  lifetime (this is a full `kubectl logs` read, not a sampling gap — genuinely zero pauses
  fired). Confirmed via the log itself that this wasn't a model/ratio problem: `request_ratio`
  and the slowdown experiment's `SLOWPOKE_DELAY_MICROS_*` values were real and non-zero for
  `checkout` (4423.5µs), `currency` (869.5µs), `frontend` (225.5µs), `payment` (4423.5µs),
  `product_catalog` (370.5µs), `shipping` (2211.5µs) — `frontend` alone touches ~100% of
  requests (`request_ratio: 1.0`), so it should have fired dozens of pause batches over 5000
  requests. Getting *nothing at all*, not even a failure message, pointed at a hang rather than
  a clean failure.
- **Root cause hypothesis:** `netlink_send_ack()` in `net_hold.c` calls `recvmsg()` with no
  receive timeout on the socket. If the kernel doesn't ack the `NLM_F_REPLACE` toggle message
  the same way it acks the `NLM_F_CREATE` init message, `recvmsg()` blocks forever — and since
  `net_hold()` runs synchronously in POKER's single pause-monitoring thread, the very first
  pause attempt would freeze that thread permanently, silently, for the rest of the pod's life.
  This fully explains the observed symptom (init message present, zero toggle messages,
  everywhere).
- **Fix applied:** added `SO_RCVTIMEO` (100ms) to the netlink socket in
  `net_pause_init_from_env()`. The existing error handling (`if (len < 0) return -1`) already
  does the right thing once `recvmsg()` actually returns instead of blocking — so a timeout now
  surfaces as a normal, loggable "netlink hold failed" fallback to the CLI path instead of a
  silent freeze.
- **Not yet synced or tested.** Next: sync this change to `netpoke-control` (Cloud Shell
  `git pull` + `gcloud compute scp` for `slowpoke/src/poker/`), rebuild + push the image again
  (watch for a new `POKER_CACHEBUST` hash), and re-run the smoke test.

### 2026-07-16 — Step 2 mechanistic smoke test: fixing deploy issues, re-running now

- **`net_hold.c` fix (F1) committed and pushed** to `netpoke/experiments`
  ([PR #11](https://github.com/gvafram3/netpoke/pull/11), commit `2fdca10`). Repo reorganized:
  superseded sampler/docs/results moved into `deprecated/` folders; corrected work lives in
  `slowpoke/evaluation/phase6_netpoke/`.
- **Synced fix to `netpoke-control`** via Cloud Shell (`git pull` + `gcloud compute scp`).
  One `scp` attempt for `phase6_netpoke/` failed the first time on a path-truncation issue
  (likely pasted commands colliding) — resolved by re-running it standalone.
- **Images rebuilt with the fix and pushed** (`gvafram3/mucache:boutique-pokerpp-netpoke`).
  ⚠️ *Not yet double-confirmed* that the final pushed image's `POKER_CACHEBUST` hash actually
  differs from the pre-fix hash `3a4b17e5b14811aa4a4fe5d17777841a` — worth a quick rebuild
  right before the next run to remove all doubt (it's fast; everything but the poker compile
  step is cached).
- **Found and fixed a real deploy bug, unrelated to the netlink fix:**
  `slowpoke/evaluation/boutique/yamls/netpoke/` only contained `shipping.yaml` (a leftover from
  earlier manual `sch_plug` testing via `deploy_smoke_pod.sh`/`test_sch_plug.sh`), so `run.sh`
  was deploying a near-empty boutique app (only `shipping` + `ubuntu-client` ever came up,
  across two redeploy cycles). `run_ebpf_one_L2.sh` only checks "is the netpoke yaml folder
  non-empty," not "does it have all services," so this went undetected until we compared
  pod count against source yaml count. Fixed by deleting the stale folder and re-running
  `patch_all_netpoke_yamls.sh boutique` — now generates all 9 service yamls correctly.
- **Current state:** about to re-run `phase6_netpoke/run_toggle_smoke.sh boutique` with the
  corrected yaml set, using the two-window pattern (see below) for every run from now on,
  regardless of how short.
- **Not yet known:** whether the netlink toggle fix actually works on this cluster's kernel
  (`PASS` / `STILL BROKEN` / `MIXED` — see `phase6_netpoke/README.md`). This is the very next
  data point.

### Standing process note

Per explicit instruction: **always use the two-SSH-window pattern for every experiment run**,
no matter how short — one window runs the script, the other live-tails progress (pod status,
the active SlowPoke log, and/or `netpoke:` toggle lines). Don't run anything experiment-related
in a single window "because it's quick." See `phase6_netpoke/README.md` for the current
two-window commands.

---

## 1. What the paper/SlowPoke actually specifies (confirmed correct in this repo)

From `slowpoke/src/main.py:156-168`, the slowdown delay and prediction are:

```python
delay = int(((T1 - p_t) * request_ratio[target]) * cpu_quota[service] / (request_ratio[service] * cpu_quota[target]))
...
delay_target = (T1 - p_t) * request_ratio[target] / cpu_quota[target]
predicted = 1e6 / (1e6/slowdown - delay_target)
```

This matches the model described in the paper exactly (bottleneck-equivalence via
request-ratio/cpu-quota-scaled delays, inverse-throughput composition). `slowpoke/src/poker/poker.c`
implements the pause faithfully: `SIGSTOP` → `precise_sleep(accumulated_nano_sleep)` → `SIGCONT`,
batched over a FIFO, exactly as the paper's POKER is described. **This part is not the problem.**

---

## 2. Four concrete defects, each with file/line evidence

### F1 — NetPoke's `net_hold()`/`net_release()` don't use the mechanism the design doc requires

`netpoke/design/poker-io-pause.md` is explicit about *why* the hold must be a netlink message
over a socket opened once at startup:

> "POKER opens one AF_NETLINK/NETLINK_ROUTE socket at startup and reuses it for every toggle, so
> NET_HOLD()/NET_RELEASE() are just send() calls. This avoids forking `tc` on every pause, which
> would be far too slow and jittery."

The actual implementation in [`slowpoke/src/poker/net_hold.c`](../../slowpoke/src/poker/net_hold.c)
does the opposite:

```c
// line 208-212 — the fast path the design doc calls for, stubbed out and never called:
static int plug_change(int action)
{
    (void)action;
    return -1;
}

// lines 214-226 — what net_hold()/net_release() actually call instead:
static int tc_plug_action(const char *action)
{
    char cmd[256];
    snprintf(cmd, sizeof(cmd), "tc qdisc change dev %s root plug %s", net_iface, action);
    rc = system(cmd);   // <-- fork()+exec()+shell parse, on every single pause
    ...
}

// line 279-299:
void net_hold(void)    { ...; tc_plug_action("block"); ... }
void net_release(void) { ...; tc_plug_action("release_indefinite"); ... }
```

`plug_change()` — the function that should send `TCQ_PLUG_BUFFER`/`TCQ_PLUG_RELEASE_INDEFINITE`
over the already-open `nl_sock` — is dead code. Every hold and every release instead shells out
to the `tc` CLI via `system()`. `poker.c:120,140` calls `net_hold()`/`net_release()` around
**every single SIGSTOP/SIGCONT pair**, and POKER's own design intent is pauses firing "tens of
times per second" (`poker_batch_req=100` in `io_levels.conf`, i.e. every 100 requests).

**Why this matters:** `system()` is fork+exec+shell-parse+netlink-roundtrip — typically single-digit
to tens of milliseconds, not the microseconds the design assumed. That overhead sits *inside* the
pause window and is **not** part of the model's `delay` term (`main.py` only knows about the
model-computed `service_delay`, never about NetPoke's toggle cost). Two consequences:

1. `precise_sleep(accumulated_nano_sleep)` accounting subtracts `net_hold()`'s cost from the
   *next* batch's sleep (poker.c:126-128 measures `start_time` before `net_hold()`), but
   `net_release()`'s cost (after `precise_sleep`) is never subtracted from anything — it's pure,
   unmodeled extra wall-clock delay added to every pause cycle, extra to what the model intended.
2. Because it's per-pause-event overhead, it scales with pause *frequency*, not with the model's
   delay magnitude — so it distorts different services differently depending on how often their
   batches fire, breaking the very request-ratio-proportional relationship the model assumes.

**This is very likely the direct reason NetPoke's effect on RMSE has looked unclear/noisy so
far**: the mechanism currently does the opposite of what it was designed to do (add jitter,
not remove it), and that jitter is invisible to the model.

### F2 — Phase 4 "eBPF" is `/proc` polling through serial `kubectl exec`, not eBPF, and it is too coarse to see individual pauses

There is no eBPF/bpftrace code anywhere in the repo (`net_hold.c`'s own design doc even says
*"bpftrace on worker nodes (preflight checks); /proc polling works without it"* — bpftrace was
optional and was never wired in). The actual instrument,
[`residual_io_sampler.py`](../../slowpoke/evaluation/phase4_ebpf/residual_io_sampler.py), works
like this per loop iteration (`main()`, lines 203-293):

- `list_benchmark_pods()` → 1 `kubectl get pods` call
- for **every** non-target service: `pod_container_name()` (1 `kubectl get pod ... jsonpath` call)
  + `sample_pod_procs()` (1 `kubectl exec`) + `read_net_dev()` (1 more `kubectl exec`)

For a benchmark with 5 path services that's ~16 serialized `kubectl` round-trips per "0.2s"
loop iteration. Each `kubectl exec`/`get` against a real API server typically costs on the order
of 100ms+; 16 of them serialized easily take several seconds — nowhere near the nominal
`--interval 0.2` the script claims to sample at.

The published Phase 4 result confirms this quantitatively:
[`TABLE_EBPF_SUMMARY.md`](../results/cluster/ebpf/tables/TABLE_EBPF_SUMMARY.md) reports
**"SIGSTOP wins" = 69 (social), 14 (hotel), 18 (movie), 34 (boutique)** — i.e. across a
~40–50 minute run, the sampler caught a stopped process in only a few dozen samples total. Given
POKER pauses fire on the order of tens of times *per second*, the sampler is aliasing: it almost
always misses the pause windows entirely, and when it does land on one, the byte/syscall delta it
attributes to "during SIGSTOP" is actually the delta since the *previous* sample — which, given the
multi-second real interval, spans many run/pause cycles, not just the one caught stopped. The
reported Δ read/write/syscr/net-rx numbers are dominated by ordinary running-state I/O that happens
to fall in the same multi-second bucket, not I/O that specifically leaked through during a pause.

**Why this matters:** This is the O2/RQ2 evidence chain ("residual I/O during SIGSTOP explains the
prediction error"). As currently measured, it can't support that claim — the instrument's time
resolution is roughly 2–3 orders of magnitude coarser than the phenomenon it's trying to catch.
It also explains why Phase 4's RMSE "validated" Phase 3 (`TABLE_EBPF_SUMMARY.md` §2): that's not
independent mechanistic validation, it's just SlowPoke's own medium run repeated with a sampler
attached that mostly isn't seeing anything — the RMSE match is expected because it's the same
experiment, not confirmation of the residual-I/O hypothesis.

### F3 — The I/O-gap netem injection is a permanent, whole-run qdisc, not a pause-scoped one — fine as a stimulus, but it conflates "path service is I/O-heavy" with "pause completeness," and nothing currently separates the two

[`patch_netem_yaml.py`](../../slowpoke/evaluation/io_gap/patch_netem_yaml.py) installs
`tc qdisc add dev eth0 root netem delay <ms>` in a sidecar that starts once and never toggles —
it is active identically during baseline, ground truth, *and* slowdown, for the whole 40–50 minute
run (`io_levels.conf`: `IO_BOUTIQUE_L2_INJECT=productcatalog:50,currency:30`, etc.). That is a
legitimate design choice for making a service *intrinsically* I/O/latency-bound (matches the
docs' own framing as "stimulus, not the fix"), but it means the RMSE outcome is shaped by each
app's specific call pattern into the injected service (fan-out count per request, whether the
call is cacheable/idempotent, how much of the target's own critical path actually transits that
service) — none of which is measured or logged anywhere. That confound is the most plausible
explanation for the boutique outlier (L2 RMSE *falling* to 5.61% vs L0's 9.19%, opposite of
hotel/social/movie): **nothing currently distinguishes "the I/O-gap hypothesis is false for
boutique" from "cart's actual fan-out into product_catalog/currency is structurally different
from hometimeline's fan-out into poststorage."** Right now that's an open question, not a
measured fact — the project has been reporting it as a finding ("boutique = outlier, discuss as
case study") without the instrumentation to say why.

### F4 — Two physically separate copies of the POKER source (hygiene risk, not yet a live bug)

`slowpoke/src/poker/{poker.c,net_hold.c,net_hold.h}` (source of truth, edited here) and
`slowpoke/app/slowpoke/poker/*` (build staging copy, overwritten by
`build_netpoke_images.sh:41-42` before every `docker build`) are currently byte-identical —
confirmed by diff. But this project has already been burned once by exactly this class of bug
(`CONTINUE_FROM_HERE.md` §8.3: a sampler fix made locally didn't match what was running on the
VM until explicitly re-synced). Any manual edit made directly against the VM's checked-out copy
of `app/slowpoke/poker/` (rather than `src/poker/` + rebuild) will silently diverge from what's
in git and be clobbered on the next build. Worth a one-line safeguard (see plan below), not an
urgent fix.

---

## 3. What this means for the numbers you already have

| Result | Verdict | Action |
|---|---|---|
| Phase 1 L0 baselines | **Sound.** Model + POKER faithfully reproduce the paper's mechanism. | Keep as-is. |
| Phase 3 I/O-gap RMSE deltas (social/hotel/movie rising, boutique falling) | **Real measurements, incomplete explanation.** The rise is genuine evidence something changes when a path service becomes I/O-bound; *why* boutique differs is not yet known (F3). | Keep the numbers; stop asserting "boutique = outlier, no clear cause" as a closed finding — say it's an open question and instrument fan-out (§5, Step 6). |
| Phase 4 eBPF residual-I/O table | **Not strong enough to support RQ2 as published.** Sampling is ~2-3 orders of magnitude too coarse relative to pause frequency (F2). | Do not cite current numbers as "kernel evidence of residual I/O" in the thesis. Re-instrument (§5, Step 3) before writing Ch. 4. |
| Phase 5 NetPoke mechanism | **Implemented, but not to its own design — currently adds unmodeled overhead instead of a fast toggle (F1).** | Fix before any Phase 6 RMSE comparison is meaningful. |
| Any partial Phase 6 NetPoke numbers already gathered | **Not trustworthy yet** — inherits both F1 (mechanism adds noise) and F2 (can't verify residual I/O actually dropped). | Mark "preliminary, do not cite" (same treatment the project already gave the earlier 59%/8,709-byte numbers in `README.md`), redo after §5 Steps 1–5. |

---

## 4. The fix for NetPoke (what "best solution" means concretely)

1. **Make `net_hold()`/`net_release()` do what the design doc says**: reuse `plug_msg()` (already
   used by `plug_add()`/`plug_delete()` for qdisc creation) with `NLM_F_REPLACE` and action
   `TCQ_PLUG_BUFFER` (hold) / `TCQ_PLUG_RELEASE_INDEFINITE` (release), sent over the persistent
   `nl_sock`. Delete `tc_plug_action()`/`system()` and the dead `plug_change()` stub. This is a
   ~20-line change confined to `net_hold.c` — no change to `poker.c`'s call sites.
2. **Log every hold/release with `get_current_time_ns()`** (already available in `poker.c`) to a
   small local file per pod. This turns "did the toggle actually happen in microseconds" from a
   claim into a number you can report (closes design doc §6's never-implemented "Overhead" (T N2)
   validation).
3. **Replace the residual-I/O instrument** with something whose sampling resolution matches
   pause durations: either (a) a tight loop *inside* the pod (no `kubectl exec` round trip) polling
   `/proc/[pid]/stat` + `/proc/pid/io` + `/proc/net/dev` every 5–10ms to a local file, correlated
   post-hoc against POKER's own hold/release timestamp log; or, better if cluster access allows,
   (b) `bpftrace` probes on `tcp_sendmsg`/`tcp_cleanup_rbuf` on the worker node keyed by pid,
   correlated the same way — actual eBPF, matching what "Phase 4 eBPF" claims to be.
4. **Add the missing overhead-regression check**: run NetPoke ON at L0 (no I/O stimulus) and
   confirm RMSE is unchanged vs SIGSTOP-only L0 — this is explicitly called for in
   `poker-io-pause.md` §6 but has never been scheduled.
5. **Instrument fan-out** for the boutique-outlier question: log actual call counts from the
   target service into the injected path service per request (not just the static
   `request_ratio` config), so L1/L2 results can be explained rather than merely reported.

---

## 5. Revised schedule

| Step | Task | Est. |
|---|---|---|
| 0 | Mark existing partial Phase 5/6 NetPoke numbers "preliminary, not cited" (matches project's own precedent) | 0.5 day |
| 1 | Fix `net_hold.c` (F1): wire `plug_msg()` with `NLM_F_REPLACE`, remove `system()` path; add hold/release timestamp logging. Rebuild + push `*-pokerpp-netpoke` images. | 0.5–1 day |
| 2 | Mechanistic check: `strace -f -e trace=execve,clone -p <poker_pid>` during a run confirms **zero** `tc` subprocess spawns; measure per-toggle latency from the new log (should be µs–low-ms, not the multi-ms `system()` cost). | 0.5 day |
| 3 | Re-run residual-I/O measurement in-pod (no `kubectl exec` loop) correlated with POKER's hold/release log, SIGSTOP-only vs NetPoke-on, **one app first (social L2** — largest existing gap). This is the first trustworthy "does residual I/O shrink" result. | 1 day |
| 4 | Add the L0 overhead-only regression check (NetPoke on/off, one app minimum). | 0.5–1 day |
| 5 | Full L2 RMSE matrix, all four apps, NetPoke on, corrected mechanism → Table N1 / Fig N1 (RMSE bar chart: L0 vs L2-SIGSTOP vs L2-NetPoke). | 2–3 days |
| 6 | Instrument fan-out counts for boutique vs the other three apps; write up as either explanation or a documented limitation. | 1 day |
| 7 | Update Ch. 3–6 drafts: report F1–F3 as methodology findings (this is legitimate thesis content — a documented instrument defect and fix is stronger, more defensible work than an unexplained anomaly), then the corrected results. | writing, not cluster time |

**Total new cluster/engineering time: ~6–9 days** — similar order of magnitude to the original
Phase 5–6 estimate, but now sequenced so the measurement instruments are trustworthy *before*
scaling up to the full matrix, rather than after.

---

## 6. Figure set to actually confirm the gap and the fix

- **Fig I1** (already exists) — RMSE vs I/O level, 4 apps. Keep, but caption should note the
  boutique-outlier explanation is pending (§5 Step 6), not settled.
- **New — hold/release timing figure**: POKER's logged toggle timestamps overlaid on the intended
  pause window, SIGSTOP-only vs NetPoke, to show the toggle is now µs-scale (proves F1 is fixed).
- **New — Fig E2/N2 (residual I/O, corrected)**: bytes/syscalls attributed strictly to pause
  windows (using the in-pod/eBPF re-instrumentation from Step 3), SIGSTOP-only vs NetPoke-on, same
  benchmark/level. This is the actual O2/RQ2 evidence; the current Fig E2 cannot be trusted.
- **Fig N1** (planned, not yet run correctly) — RMSE bar chart L0 vs L2-SIGSTOP vs L2-NetPoke,
  four apps, after Step 5.
- **New — Table N2 (overhead)**: L0 RMSE and mean per-request latency, NetPoke off vs on, to show
  no regression on the compute-bound baseline (design doc §6, never done).
