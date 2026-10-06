#!/usr/bin/env python3
"""
Leak during REAL poker pauses, using poker's own uptime-based markers.
  leak_by_uptime.py CAPTURE_TXT MARKERS_TXT OFFSET_S [guard_ms=2] [label]
CAPTURE_TXT : tcpdump -n -tt text (epoch timestamps)            MARKERS_TXT: pod log lines 'poker: pause_start|pause_end uptime_s=X'
OFFSET_S    : epoch - uptime on the SAME machine (measured when the capture started)
Leak = packets per ms inside pause windows / packets per ms in equally long windows starting 10 ms after each pause.
"""
import re, sys, bisect, statistics as st
cap, mk, off = sys.argv[1], sys.argv[2], float(sys.argv[3])
G = (float(sys.argv[4]) if len(sys.argv) > 4 else 2.0) / 1000; label = sys.argv[5] if len(sys.argv) > 5 else cap
S, E = [], []
for l in open(mk, errors="replace"):
    m = re.search(r"pause_(start|end) uptime_s=([0-9.]+)", l)
    if m: (S if m.group(1) == "start" else E).append(float(m.group(2)) + off)
E.sort(); wins = []
for s in sorted(S):
    k = bisect.bisect_left(E, s)
    if k < len(E) and E[k] - s >= 0.005: wins.append((s, E[k]))
T, L = [], []
for l in open(cap, errors="replace"):
    m = re.match(r"(\d+\.\d+)\s.*?(?:length:? |tcp )(\d+)", l)
    if m: T.append(float(m.group(1))); L.append(int(m.group(2)))
if not T: print(f"{label}: no packets in capture"); sys.exit(1)
o = sorted(range(len(T)), key=T.__getitem__); T = [T[i] for i in o]; L = [L[i] for i in o]
C = [0]; [C.append(C[-1] + x) for x in L]
def tally(a, b):
    i, j = bisect.bisect_left(T, a), bisect.bisect_right(T, b); return j - i, C[j] - C[i]
inside = [(s, e) for s, e in wins if s >= T[0] and e + (e - s) + 0.01 <= T[-1]]
if not inside:
    print(f"{label}: 0 of {len(wins)} pause windows fall inside the capture ({T[0]:.3f}..{T[-1]:.3f}); first pause at {wins[0][0] if wins else 'none'} - clock offset wrong or no pauses")
    sys.exit(1)
pp = pb = rp = rb = ms = 0.0
for s, e in inside:
    Lw = (e - s) - 2 * G
    n, b = tally(s + G, e - G); pp += n; pb += b
    r0 = e + 0.01; n, b = tally(r0 + G, r0 + G + Lw); rp += n; rb += b
    ms += Lw * 1000
print(f"{label}: {len(inside)} pauses analysed (of {len(wins)} logged), median pause {st.median(e - s for s, e in inside) * 1000:.1f} ms")
print(f"   running: {rp / ms:8.3f} pkt/ms {rb / ms:9.1f} B/ms   paused: {pp / ms:8.3f} pkt/ms {pb / ms:9.1f} B/ms")
print(f"   LEAK = {100 * pp / rp if rp else float('nan'):.1f}% of packets, {100 * pb / rb if rb else float('nan'):.1f}% of bytes   [0% = the resource is idle during pauses]")
