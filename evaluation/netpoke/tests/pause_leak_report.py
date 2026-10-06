#!/usr/bin/env python3
"""
Leak during REAL POKER pauses, inside the real cluster.

Inputs
  --pcap  tcpdump text captured with:   tcpdump -n -tt -l -i <if> 'src host <pod ip> and tcp'
  --logs  the frozen pod's log with timestamps: kubectl logs --timestamps deploy/service2
          (needs the unconditional 'poker: pause_start' / 'poker: pause_end' markers from your poker.c)
Output: packets/bytes per ms while paused vs while running, i.e. LEAK %.  0% = the hold is airtight.

Where to capture (do both, they answer different questions):
  * INSIDE the pod netns (nsenter -t <pid> -n ... -i eth0): what leaves the pod after the plug  -> is the hold working?
  * on the node NIC (-i ens4):                              what actually reaches the wire      -> did the resource idle?
"""
import re, sys, argparse, datetime as dt, statistics as st

ap = argparse.ArgumentParser()
ap.add_argument("--pcap", required=True); ap.add_argument("--logs", required=True)
ap.add_argument("--guard-ms", type=float, default=2.0, help="ignore this much at each window edge (log/pcap clock jitter)")
ap.add_argument("--min-pause-ms", type=float, default=5.0, help="ignore pauses shorter than this")
a = ap.parse_args(); G = a.guard_ms / 1000

def iso(ts):                      # 2026-09-19T12:00:00.123456789Z  ->  epoch seconds
    ts = ts.rstrip("Z"); base, _, frac = ts.partition(".")
    d = dt.datetime.strptime(base, "%Y-%m-%dT%H:%M:%S").replace(tzinfo=dt.timezone.utc)
    return d.timestamp() + (float("0." + frac) if frac else 0.0)

starts, ends = [], []
for line in open(a.logs, errors="replace"):
    m = re.match(r"(\S+Z)\s+.*", line)
    if not m: continue
    if "pause_start" in line: starts.append(iso(m.group(1)))
    elif "pause_end" in line: ends.append(iso(m.group(1)))
if not starts or not ends: sys.exit("no pause_start/pause_end markers in --logs (is your poker.c logging them? did you use --timestamps?)")
wins = []
for s in starts:
    e = next((x for x in ends if x > s), None)
    if e and (e - s) * 1000 >= a.min_pause_ms: wins.append((s, e))
if not wins: sys.exit("no pause windows long enough")

pk = []
for line in open(a.pcap, errors="replace"):
    m = re.match(r"(\d+\.\d+)\s.*\blength (\d+)", line)
    if m: pk.append((float(m.group(1)), int(m.group(2))))
if not pk: sys.exit("no packets parsed from --pcap (need 'tcpdump -n -tt -l' text output)")
pk.sort(); t_lo, t_hi = pk[0][0], pk[-1][0]

def tally(x0, x1):
    n = b = 0
    for t, ln in pk:
        if x0 <= t <= x1: n += 1; b += ln
    return n, b
paused, running = [], []
for (s, e) in wins:
    if s < t_lo or e > t_hi: continue
    L = e - s
    paused.append((tally(s + G, e - G), (L - 2 * G) * 1000))
    r0 = e + 0.01                      # a same-length window that starts 10 ms after the pause ended
    running.append((tally(r0 + G, r0 + L - G), (L - 2 * G) * 1000))
if not paused: sys.exit("pause windows fall outside the capture")
rate = lambda w, i: st.mean(x[0][i] / x[1] for x in w)     # per ms
lk = 100 * rate(paused, 0) / rate(running, 0) if rate(running, 0) else float("nan")
lb = 100 * rate(paused, 1) / rate(running, 1) if rate(running, 1) else float("nan")
print(f"pause windows analysed : {len(paused)}   (median length {st.median(x[1] for x in paused)+2*a.guard_ms:.1f} ms)")
print(f"running  : {rate(running,0):8.3f} pkt/ms  {rate(running,1):10.1f} B/ms")
print(f"paused   : {rate(paused,0):8.3f} pkt/ms  {rate(paused,1):10.1f} B/ms")
print(f"LEAK     : {lk:.1f}% (packets)   {lb:.1f}% (bytes)      [0% = airtight hold, ~100% = pause does nothing to the network]")
