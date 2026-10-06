#!/usr/bin/env python3
"""Turn the RESULT lines of leak_suite.sh into a labelled table.   usage: format_leak.py RAWFILE [--out DIR]"""
import re, sys, os, math, statistics as st, argparse, csv
ap = argparse.ArgumentParser(); ap.add_argument("raw"); ap.add_argument("--out", default="."); a = ap.parse_args()
G = {}; notes = []
for line in open(a.raw, errors="replace"):
    if "NOT AVAILABLE" in line: notes.append(line.strip()); continue
    if line.startswith("RESULT-FAILED"): notes.append(line.strip()); continue
    if not line.startswith("RESULT "): continue
    kv = dict(x.split("=", 1) for x in line.split()[1:])
    G.setdefault((kv["scen"], int(kv["hold"]), int(kv["pause_ms"])), []).append(kv)
if not G: sys.exit("no RESULT lines found (" + "; ".join(notes) + ")")
num = lambda v: float(v) if v not in ("NA", "") else float("nan")
mean = lambda xs: st.mean([x for x in xs if not math.isnan(x)]) if any(not math.isnan(x) for x in xs) else float("nan")
rows = []; csvr = []
for (sc, hold, pm), rs in sorted(G.items(), key=lambda kv: (kv[0][0] != "idle", kv[0][0], kv[0][1], kv[0][2])):
    run = mean([num(r["run_pkts"]) for r in rs]); pau = mean([num(r["paused_pkts"]) for r in rs])
    L = [num(r["leak_pct"]) for r in rs]; Lv = [x for x in L if not math.isnan(x)]
    D = [num(r["dropped"]) for r in rs]; Dv = [x for x in D if not math.isnan(x)]
    leak = f"{st.mean(Lv):.1f}  ({min(Lv):.1f} .. {max(Lv):.1f})" if Lv else "n/a"
    drops = f"{int(max(Dv))}" if Dv else "-"
    if sc == "idle": read = "CONTROL OK: nothing sent, nothing leaked" if pau == 0 else "unexpected traffic"
    elif hold == 0 and sc == "sender": read = "GAP CONFIRMED: frozen service keeps sending" if Lv and st.mean(Lv) >= 50 else "small leak"
    elif hold == 1: read = "HOLD WORKS" if (Lv and st.mean(Lv) <= 5 and (not Dv or max(Dv) == 0)) else "CHECK: leak or drops"
    else: read = "acknowledgements only (no data sent)"
    rows.append([sc, "ON" if hold else "off", pm, len(rs), f"{run:.1f}", f"{pau:.1f}", leak, drops, read])
    csvr.append([sc, hold, pm, len(rs), run, pau, st.mean(Lv) if Lv else "", max(Dv) if Dv else "", read])
head = ["SCENARIO", "HOLD", "PAUSE ms", "RUNS", "PKTS/WINDOW running", "PKTS/WINDOW frozen", "LEAK % mean (min..max)", "PLUG DROPS", "READING"]
w = [max(len(str(x)) for x in c) for c in zip(head, *rows)]
ln = lambda r: "  ".join(str(x).ljust(w[i]) for i, x in enumerate(r))
txt = ["LEAK TEST SUMMARY", "  LEAK % = traffic leaving the machine while the service is frozen, as a share of what leaves while it runs (0 % = perfect hold)",
       "  PLUG DROPS = packets the hold's queue had to discard (must be 0)", "", ln(head), "  ".join("-" * x for x in w)] + [ln(r) for r in rows]
if notes: txt += ["", "Notes: " + " | ".join(dict.fromkeys(notes))]
print("\n".join(txt)); os.makedirs(a.out, exist_ok=True)
md = ["# Leak test summary", "", "LEAK % = traffic leaving while the service is frozen ÷ traffic while running (0 % = perfect hold). PLUG DROPS must be 0.", "",
      "| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"] + ["| " + " | ".join(map(str, r)) + " |" for r in rows]
open(os.path.join(a.out, "leak_table.md"), "w").write("\n".join(md) + "\n")
with open(os.path.join(a.out, "leak_table.csv"), "w", newline="") as f:
    cw = csv.writer(f); cw.writerow(["scenario", "hold", "pause_ms", "runs", "pkts_running", "pkts_frozen", "leak_pct_mean", "plug_drops_max", "reading"]); cw.writerows(csvr)
print(f"\nSaved {os.path.join(a.out,'leak_table.md')} and leak_table.csv")
