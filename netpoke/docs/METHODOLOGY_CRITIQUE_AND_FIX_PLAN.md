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
