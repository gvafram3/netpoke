#!/usr/bin/env python3
"""Live dashboard for a running (or finished) slowpoke experiment.  Run on the control node, normally via: watch -t -n 5 python3 progress.py
usage: progress.py [logfile]      (default: the most recently written ~/results/*.log)"""
import os, sys, glob, time, subprocess, datetime as dt
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slowlog import parse_log, levels_info, steps, rmse_bias

def sh(cmd, t=8):
    try: return subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=t).stdout.strip()
    except Exception: return ""
def hms(s): s = int(max(s, 0)); return f"{s//3600:02d}:{(s%3600)//60:02d}:{s%60:02d}"

logs = sorted(glob.glob(os.path.expanduser("~/results/*.log")), key=os.path.getmtime)
path = sys.argv[1] if len(sys.argv) > 1 else (logs[-1] if logs else None)
now = time.time()
print(f"==== NetPoke run monitor ====  {dt.datetime.now():%Y-%m-%d %H:%M:%S}")
if not path or not os.path.exists(path):
    print("No log yet in ~/results. Start a run in the other window."); sys.exit()
d = parse_log(path); age = now - os.path.getmtime(path)
pid = sh("pgrep -f 'src/[m]ain.py' | head -1"); running = bool(pid)
elapsed = float(sh(f"ps -o etimes= -p {pid}") or 0) if running else None
done, total = steps(d)
print(f"Run      : {os.path.basename(path)}")
state = "RUNNING" if running else ("FINISHED" if d["finished"] else "NOT RUNNING (stopped or failed)")
print(f"Status   : {state}   log last updated {int(age)} s ago" + (f"   elapsed {hms(elapsed)}" if elapsed else ""))
if total:
    w = 30; k = int(w * done / total)
    eta = f"   ETA ~{hms(elapsed/done*(total-done))} (about {dt.datetime.now()+dt.timedelta(seconds=elapsed/done*(total-done)):%H:%M})" if running and elapsed and done else ""
    print(f"Progress : [{'#'*k}{'.'*(w-k)}] {done}/{total} steps ({100*done//total}%){eta}")
info = levels_info(d)
c = d["current"]
if c and running:
    what = {"base": "baseline (unoptimised) run", "gt": "ground-truth run", "sd": "slowdown run", "done": "between steps"}[c[0]]
    lvl = f"level {c[1]+1}/{len(d['range'])}, " if c[1] is not None and d["range"] else ""
    print(f"Now      : {lvl}{what}  ->  {d['stage'] or 'starting'}")
print(f"Baseline : {d['baseline']:.1f} req/s" if d["baseline"] else "Baseline : (not measured yet)")
if d.get("capped"): print(f"Note     : {d['capped']} measurement(s) had a capped request counter; throughputs below are CORRECTED (x capped/planned)")
print()
n = len(d["range"]) if d["range"] else 0
print(f"{'LEVEL':>5} {'TARGET us':>9} {'OPT %':>6} {'TRUTH req/s':>12} {'SLOWED req/s':>13} {'PREDICTED':>10} {'ERROR %':>8}")
errs = []
for i in range(n):
    p = info[0][i] if info else {"p": "?", "pct": None}
    pc = f"{p['pct']:.0f}" if p["pct"] is not None else "-"
    if i in d["levels"]:
        g, s, pr, e = d["levels"][i]; errs.append(e)
        print(f"{i:5d} {p['p']:9} {pc:>6} {g:12.1f} {s:13.1f} {pr:10.1f} {e:+8.2f}")
    else:
        print(f"{i:5d} {p['p']:9} {pc:>6} {'...':>12} {'...':>13} {'...':>10} {'...':>8}")
if errs:
    r, b = rmse_bias(errs)
    print(f"\nSo far ({len(errs)} level(s)):  RMSE {r:.2f} %   bias {b:+.2f} %   (bias + = over-predicts, i.e. optimistic)")
print("\nCluster:")
pods = sh("kubectl get pods --no-headers -o wide 2>/dev/null | awk '{printf \"  %-24s %-9s %s\\n\",$1,$3,$7}'")
print(pods or "  (no application pods right now)")
top = sh("kubectl top nodes --no-headers 2>/dev/null | awk '{printf \"  %-9s CPU %-5s MEM %s\\n\",$1,$3,$5}'")
print(top or "  (kubectl top not ready)")
print("\nLast log lines:")
for l in d["tail"][-5:]: print("  " + l[:118])
