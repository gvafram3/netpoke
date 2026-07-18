#!/usr/bin/env python3
"""
Correlate in-pod residual-I/O samples against POKER's own pause-window
timestamps, so bytes/syscalls can be attributed strictly to real pause
windows instead of averaged across whatever ran in between (the flaw in the
deprecated kubectl-exec-per-sample sampler -- finding F2 in
netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md).

Pause windows come from POKER's unconditional `poker: pause_start` /
`poker: pause_end` markers (printed around every SIGSTOP/SIGCONT regardless
of whether NetPoke is enabled) -- this is what makes it possible to measure
the SIGSTOP-only baseline, not just the NetPoke case. The older
`netpoke: hold/release via=... uptime_s=...` lines are also recognized for
logs captured before this instrumentation existed, but `poker: pause_*` is
preferred when both are present.

Input: a directory containing, per pod, <pod>.jsonl (samples from
residual_sampler_inpod.sh) and <pod>.netpoke.log (grepped `poker: pause_`
and `netpoke:` lines from `kubectl logs`, which include a uptime_s field
comparable to the sampler's own ts).
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import sys

POKER_RE = re.compile(r"poker: pause_(start|end) uptime_s=([\d.]+)")
NETPOKE_RE = re.compile(r"netpoke: (hold|release) via=(\w+) took_ns=(\d+) uptime_s=([\d.]+)")
_KIND_MAP = {"start": "hold", "end": "release"}  # normalize to hold/release internally


def load_events(path: str) -> list[tuple[float, str]]:
    events: list[tuple[float, str]] = []
    if not os.path.isfile(path):
        return events
    with open(path, encoding="utf-8") as f:
        for line in f:
            m = POKER_RE.search(line)
            if m:
                kind, uptime_s = m.groups()
                events.append((float(uptime_s), _KIND_MAP[kind]))
                continue
            m = NETPOKE_RE.search(line)
            if m:
                kind, _via, _took_ns, uptime_s = m.groups()
                events.append((float(uptime_s), kind))
    events.sort(key=lambda e: e[0])
    return events


def pair_windows(events: list[tuple[float, str]]) -> list[tuple[float, float]]:
    """Pair consecutive hold->release into (start, end) windows. Tolerates a
    stray leading release or trailing unpaired hold by skipping it."""
    windows: list[tuple[float, float]] = []
    pending_hold: float | None = None
    for ts, kind in events:
        if kind == "hold":
            pending_hold = ts
        elif kind == "release" and pending_hold is not None:
            windows.append((pending_hold, ts))
            pending_hold = None
    return windows


def load_samples(path: str) -> list[dict]:
    samples = []
    if not os.path.isfile(path):
        return samples
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                samples.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    samples.sort(key=lambda s: s.get("ts", 0))
    return samples


def in_any_window(t: float, windows: list[tuple[float, float]]) -> bool:
    return any(start <= t <= end for start, end in windows)


def aggregate_procs(sample: dict) -> tuple[int, int]:
    rb = sum(p.get("rb", 0) for p in sample.get("procs", []))
    wb = sum(p.get("wb", 0) for p in sample.get("procs", []))
    return rb, wb


def analyze_pod(pod: str, samples: list[dict], windows: list[tuple[float, float]]) -> dict:
    in_pause = {"dr": 0, "dw": 0, "drx": 0, "dtx": 0, "intervals": 0}
    outside = {"dr": 0, "dw": 0, "drx": 0, "dtx": 0, "intervals": 0}
    windows_hit = set()

    prev = None
    for s in samples:
        # Skip malformed records -- e.g. from two sampler processes racing
        # to write the same output file (see run_residual_check.sh), which
        # can interleave writes into JSON that parses but is missing fields.
        if "ts" not in s or "procs" not in s:
            continue
        if prev is not None:
            t0, t1 = prev["ts"], s["ts"]
            mid = (t0 + t1) / 2
            rb0, wb0 = aggregate_procs(prev)
            rb1, wb1 = aggregate_procs(s)
            dr = max(0, rb1 - rb0)
            dw = max(0, wb1 - wb0)
            drx = max(0, s.get("rx", 0) - prev.get("rx", 0))
            dtx = max(0, s.get("tx", 0) - prev.get("tx", 0))
            bucket = in_pause if in_any_window(mid, windows) else outside
            bucket["dr"] += dr
            bucket["dw"] += dw
            bucket["drx"] += drx
            bucket["dtx"] += dtx
            bucket["intervals"] += 1
            if bucket is in_pause:
                for i, (wstart, wend) in enumerate(windows):
                    if wstart <= mid <= wend:
                        windows_hit.add(i)
        prev = s

    return {
        "pod": pod,
        "samples": len(samples),
        "windows_total": len(windows),
        "windows_hit": len(windows_hit),
        "in_pause": in_pause,
        "outside": outside,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("outdir")
    ap.add_argument("--netpoke", action="store_true",
                     help="label output as a NetPoke-on run (default: SIGSTOP-only baseline)")
    args = ap.parse_args()

    jsonl_files = sorted(glob.glob(os.path.join(args.outdir, "*.jsonl")))
    if not jsonl_files:
        print(f"No *.jsonl sample files in {args.outdir}", file=sys.stderr)
        return 1

    results = []
    for jf in jsonl_files:
        pod = os.path.basename(jf)[: -len(".jsonl")]
        log = os.path.join(args.outdir, f"{pod}.netpoke.log")
        samples = load_samples(jf)
        events = load_events(log)
        windows = pair_windows(events)
        if not samples:
            print(f"{pod}: 0 samples collected (sampler likely didn't survive to collection time)")
            continue
        if not windows:
            print(f"{pod}: {len(samples)} samples but 0 hold/release windows (never paused, or log missing)")
            continue
        results.append(analyze_pod(pod, samples, windows))

    if not results:
        print("\nNo pod had both samples and pause windows -- nothing to correlate.")
        return 1

    print(f"\n{'Pod':<20} {'Samples':>8} {'Windows':>9} {'Hit':>5} {'ΔreadB(pause)':>14} "
          f"{'ΔwriteB(pause)':>15} {'ΔnetRX(pause)':>14} {'ΔreadB(out)':>13} {'ΔnetRX(out)':>13}")
    print("-" * 130)
    tot_pause_rx = tot_outside_rx = 0
    tot_windows = tot_hit = 0
    for r in results:
        ip, out = r["in_pause"], r["outside"]
        print(f"{r['pod']:<20} {r['samples']:>8} {r['windows_total']:>9} {r['windows_hit']:>5} "
              f"{ip['dr']:>14} {ip['dw']:>15} {ip['drx']:>14} {out['dr']:>13} {out['drx']:>13}")
        tot_pause_rx += ip["drx"]
        tot_outside_rx += out["drx"]
        tot_windows += r["windows_total"]
        tot_hit += r["windows_hit"]

    print("-" * 130)
    print(f"Pause windows observed with >=1 overlapping sample: {tot_hit}/{tot_windows}")
    print(f"Total net RX during pause windows: {tot_pause_rx} bytes")
    print(f"Total net RX outside pause windows: {tot_outside_rx} bytes")
    if args.netpoke:
        if tot_pause_rx == 0:
            print("\n=> Residual ingress during pauses is ZERO across every window sampled — consistent with")
            print("   NetPoke's egress hold working as designed (TCP flow control stalls senders, so almost")
            print("   nothing arrives during the pause). Compare against the SIGSTOP-only run of the same")
            print("   scenario to see how much this actually reduced it.")
        else:
            print(f"\n=> Non-zero residual RX during pause windows ({tot_pause_rx} bytes over {tot_hit} windows)")
            print("   with NetPoke on — compare against the SIGSTOP-only run of the same scenario to see")
            print("   whether this is meaningfully smaller than the un-mitigated case.")
    else:
        print(f"\n=> SIGSTOP-only baseline: {tot_pause_rx} bytes of net RX leaked through during")
        print(f"   {tot_hit}/{tot_windows} observed pause windows. This is the number NetPoke is supposed")
        print("   to reduce — run the same scenario with netpoke=1 to compare.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
