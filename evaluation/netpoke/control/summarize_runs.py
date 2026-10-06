#!/usr/bin/env python3
"""
Readable summary of slowpoke experiment logs.

  python3 summarize_runs.py [--out DIR] ~/results/phase1_nolock_rep*.log ~/results/phase5_*_rep*.log

Log files must be named <arm>_rep<N>.log; logs with the same <arm> are grouped as repetitions.
Prints labelled tables and also writes  DIR/summary.md, DIR/levels.csv and (if matplotlib exists) DIR/chart_<arm>.png.
Errors are RECOMPUTED from Groundtruth and Predicted:  error % = (predicted - truth) / truth * 100
   + = over-prediction (optimistic)     - = under-prediction
Level 0 = the LARGEST optimisation (main.py sweeps the target's processing time upward from its minimum).
"""
import re, sys, os, glob, csv, math, argparse, statistics as st
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from slowlog import parse_log, levels_info, rmse_bias

ap = argparse.ArgumentParser(); ap.add_argument("logs", nargs="*"); ap.add_argument("--out", default=os.path.expanduser("~/results/summary"))
a = ap.parse_args()
runs = {}
for pat in a.logs or [os.path.expanduser("~/results/*.log")]:
    for p in sorted(glob.glob(pat)):
        m = re.match(r"(.*)_rep(\d+)\.log$", os.path.basename(p))
        if not m: continue
        d = parse_log(p); info = levels_info(d)
        if d["finished"]:
            gt, pr = d["final"]["Groundtruth"], d["final"]["Predicted"]; partial = False
        else:
            ks = sorted(d["levels"]); gt = [d["levels"][k][0] for k in ks]; pr = [d["levels"][k][2] for k in ks]; partial = True
        if not gt: print(f"(skip {os.path.basename(p)}: no finished level yet)"); continue
        err = [100 * (x - y) / y for x, y in zip(pr, gt)]
        lv = info[0][:len(gt)] if info else [{"p": None, "pct": None}] * len(gt)
        if d.get("capped"): print(f"({os.path.basename(p)}: {d['capped']} capped measurement(s) - throughputs corrected by capped/planned counter)")
        runs.setdefault(m.group(1), []).append({"file": os.path.basename(p), "rep": int(m.group(2)), "gt": gt, "pred": pr, "err": err,
                                               "base": d["baseline"], "lv": lv, "partial": partial})
if not runs: sys.exit("no usable logs")
sd = lambda v: st.stdev(v) if len(v) > 1 else float("nan")
fmt = lambda m, s, w=2: f"{m:.{w}f}" + (f" ± {s:.{w}f}" if not math.isnan(s) else " (1 run)")
stats = {}
for arm, rs in runs.items():
    R = [rmse_bias(r["err"])[0] for r in rs]; B = [rmse_bias(r["err"])[1] for r in rs]
    W = [max(abs(e) for e in r["err"]) for r in rs]; Bs = [r["base"] for r in rs if r["base"]]
    stats[arm] = dict(n=len(rs), R=st.mean(R), Rs=sd(R), B=st.mean(B), Bs=sd(B), W=max(W), base=st.mean(Bs) if Bs else float("nan"),
                      partial=any(r["partial"] for r in rs))

def table(title, head, rows, left=(0,)):
    w = [max(len(str(x)) for x in col) for col in zip(head, *rows)]
    line = lambda r: "  ".join(str(x).ljust(w[i]) if i in left else str(x).rjust(w[i]) for i, x in enumerate(r))
    txt = [title, line(head), "  ".join("-" * x for x in w)] + [line(r) for r in rows]
    md = [f"### {title}", "", "| " + " | ".join(head) + " |", "|" + "|".join("---" for _ in head) + "|"] + ["| " + " | ".join(map(str, r)) + " |" for r in rows]
    return "\n".join(txt), "\n".join(md)
out_txt, out_md = [], []
def emit(t, m): out_txt.append(t); out_md.append(m)

hdr = ["ARM", "RUNS", "RMSE % (mean ± sd)", "BIAS % (mean ± sd)", "WORST |ERR| %", "BASELINE req/s"]
rows = [[arm + (" *" if s["partial"] else ""), s["n"], fmt(s["R"], s["Rs"]), fmt(s["B"], s["Bs"]), f"{s['W']:.1f}", f"{s['base']:.0f}" if not math.isnan(s["base"]) else "-"] for arm, s in stats.items()]
emit(*table("1. OVERVIEW  (RMSE = typical size of the error; BIAS = average signed error, + means over-prediction)", hdr, rows))
if any(s["partial"] for s in stats.values()): emit("  * = includes an unfinished run; only its completed levels are counted", "_* includes an unfinished run (completed levels only)_")

csv_rows = []
for arm, rs in runs.items():
    n = min(len(r["err"]) for r in rs); rows = []
    for i in range(n):
        g = [r["gt"][i] for r in rs]; p = [r["pred"][i] for r in rs]; e = [r["err"][i] for r in rs]; lv = rs[0]["lv"][i]
        dirn = "over (optimistic)" if st.mean(e) > 1 else ("under" if st.mean(e) < -1 else "close")
        rows.append([i, lv["p"] if lv["p"] is not None else "-", f"{lv['pct']:.0f}" if lv["pct"] is not None else "-", f"{st.mean(g):.0f}", f"{st.mean(p):.0f}",
                     f"{st.mean(e):+.2f}".replace("-0.00","+0.00"), (f"{min(e):+.1f} .. {max(e):+.1f}").replace("-0.0","+0.0"), dirn])
        csv_rows.append([arm, i, lv["p"], lv["pct"], st.mean(g), st.mean(p), st.mean(e), min(e), max(e), len(rs)])
    emit(*table(f"2. PER-LEVEL RESULTS — {arm}  (mean of {len(rs)} run(s))", ["LEVEL", "TARGET us", "OPT %", "TRUTH req/s", "PREDICTED", "ERROR %", "RANGE ACROSS RUNS", "DIRECTION"], rows))

verd = []
def v(arm_prefix): return [(k, s) for k, s in stats.items() if k.startswith(arm_prefix)]
for k, s in v("phase1"):
    r, b = s["R"], s["B"]; ok = r <= 3 and abs(b) <= 1.5
    verd.append([f"Gate 1 (reproduce the paper) — {k}", "PASS" if ok else ("INVESTIGATE" if r <= 5 else "STOP"), f"RMSE {r:.2f}% (need ≤3), |bias| {abs(b):.2f}% (need ≤1.5); paper reports <1% for this experiment"])
for k, s in v("phase2_freeze"):
    ok = s["R"] >= 10 and s["B"] > 0
    verd.append([f"Gate 2 (network-bound, freeze only) — {k}", "PASS" if ok else "NOT MET", f"RMSE {s['R']:.1f}% (want ≥10), bias {s['B']:+.1f}% (want > 0). Approximate: judge the plateau levels in the table above"])
for pre in ("phase5", "cpu"):
    F = stats.get(f"{pre}_freeze"); H = stats.get(f"{pre}_hold")
    if not (F and H): continue
    if pre == "phase5":
        gain = F["R"] - H["R"]; thr = 2 * F["Rs"] if not math.isnan(F["Rs"]) else float("nan")
        if math.isnan(thr): res, why = "NEED ≥2 RUNS", "cannot judge spread with 1 run"
        else:
            ok = gain > thr and abs(H["B"]) < abs(F["B"]); res = "IMPROVEMENT" if ok else "INCONCLUSIVE"
            why = f"RMSE freeze {F['R']:.2f}% → hold {H['R']:.2f}% (gain {gain:+.2f}; needs > 2×sd = {thr:.2f}); bias freeze {F['B']:+.2f}% → hold {H['B']:+.2f}%"
        verd.append(["Gate 5 (does the hold fix it?)", res, why])
    else:
        spread = max([x for x in (F["Rs"], H["Rs"]) if not math.isnan(x)] or [float("nan")])
        if math.isnan(spread): res, why = "NEED ≥2 RUNS", "cannot judge spread with 1 run"
        else:
            ok = abs(H["R"] - F["R"]) <= spread; res = "NO HARM" if ok else "HOLD CHANGES RESULT"
            why = f"RMSE freeze {F['R']:.2f}% vs hold {H['R']:.2f}% (difference {H['R']-F['R']:+.2f}; run-to-run sd {spread:.2f})"
        verd.append(["Gate 5b (CPU-bound, no harm)", res, why])
if verd:
    emit(*table("3. GATE VERDICTS  (thresholds are the lab's own judgement, not the paper's; with fewer than 3 runs treat them as provisional)", ["GATE", "VERDICT", "WHY"], verd, left=(0, 1, 2)))
print("\n\n".join(out_txt))
os.makedirs(a.out, exist_ok=True)
open(os.path.join(a.out, "summary.md"), "w").write("# Results summary\n\n" + "\n\n".join(out_md) + "\n")
with open(os.path.join(a.out, "levels.csv"), "w", newline="") as f:
    w = csv.writer(f); w.writerow(["arm", "level", "target_us", "optimisation_pct", "truth_req_s", "predicted_req_s", "error_pct_mean", "error_pct_min", "error_pct_max", "runs"]); w.writerows(csv_rows)
made = []
try:
    import matplotlib; matplotlib.use("Agg"); import matplotlib.pyplot as plt
    for arm, rs in runs.items():
        n = min(len(r["err"]) for r in rs); x = [rs[0]["lv"][i]["p"] if rs[0]["lv"][i]["p"] is not None else i for i in range(n)]
        fig, ax = plt.subplots(2, 1, figsize=(7, 6), sharex=True)
        ax[0].plot(x, [st.mean(r["gt"][i] for r in rs) for i in range(n)], "o-", label="truth (really optimised)")
        ax[0].plot(x, [st.mean(r["pred"][i] for r in rs) for i in range(n)], "s--", label="predicted by SlowPoke"); ax[0].set_ylabel("throughput (req/s)"); ax[0].legend(); ax[0].set_title(arm)
        ax[1].bar(range(n), [st.mean(r["err"][i] for r in rs) for i in range(n)]); ax[1].axhline(0, color="k", lw=.8)
        ax[1].set_ylabel("error %  (+ = over-predicts)"); ax[1].set_xlabel("target processing time (us); left = biggest optimisation"); ax[1].set_xticks(range(n)); ax[1].set_xticklabels(x, rotation=45)
        fig.tight_layout(); fp = os.path.join(a.out, f"chart_{arm}.png"); fig.savefig(fp, dpi=130); plt.close(fig); made.append(fp)
except Exception as e:
    print(f"(charts skipped: {e})")
print(f"\nSaved: {os.path.join(a.out,'summary.md')}, {os.path.join(a.out,'levels.csv')}" + "".join(f", {os.path.basename(m)}" for m in made) + f"   (folder {a.out})")
