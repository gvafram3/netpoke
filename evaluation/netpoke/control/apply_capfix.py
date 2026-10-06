# Adds the capped-counter correction to slowlog.py and a visible note to progress.py and summarize_runs.py. Idempotent.
import re, sys, os
os.chdir(sys.argv[1] if len(sys.argv) > 1 else ".")
ok = True
s = open("slowlog.py").read()
if "_correct_capping" not in s:
    old = '    d["finished"] = "Error percentage" in d["final"]\n    return d\n'
    new = r'''    d["finished"] = "Error percentage" in d["final"]
    _correct_capping(d, lines)
    return d

def _correct_capping(d, lines):
    """run.sh's fix_req_num can cap the per-thread request counter (A -> B), but main.py still computes throughput as
    NUM_REQ / mean(stop times), i.e. as if A requests per thread were sent. The true throughput is reported * B/A.
    Measurements appear in log order: baseline, then (ground truth, slowdown) for each level. Predictions are recomputed
    with main.py's own per-level delta, recovered as 1/slowdown_reported - 1/predicted_reported."""
    ratios, thr, pending = [], [], 1.0
    for line in lines:
        m = re.search(r"fix_req_num: capping counter (\d+) -> (\d+)", line)
        if m: pending = int(m.group(2)) / int(m.group(1))
        m = re.search(r"\[exp\] Throughput:\s*([0-9.eE+-]+)", line)
        if m: thr.append(float(m.group(1))); ratios.append(pending); pending = 1.0
    d["capped"] = sum(1 for r in ratios if r < 1.0)
    if not d["capped"]: return
    corr = [t * r for t, r in zip(thr, ratios)]
    if corr: d["baseline"] = corr[0]
    for i, (g, s, p, e) in list(d["levels"].items()):
        gi, si = 1 + 2 * i, 2 + 2 * i
        if si >= len(corr) or any(math.isnan(x) for x in (s, p)) or s <= 0 or p <= 0: continue
        delta = 1.0 / s - 1.0 / p
        gc, sc = corr[gi], corr[si]
        pc = 1.0 / (1.0 / sc - delta) if 1.0 / sc - delta > 0 else float("nan")
        d["levels"][i] = (gc, sc, pc, 100.0 * (pc - gc) / gc)
    if d["finished"]:
        ks = sorted(d["levels"])
        d["final"] = {"Groundtruth": [d["levels"][k][0] for k in ks], "Slowdown": [d["levels"][k][1] for k in ks],
                      "Predicted": [d["levels"][k][2] for k in ks], "Error percentage": [d["levels"][k][3] for k in ks]}
'''
    if old not in s: print("slowlog.py: anchor not found"); ok = False
    else:
        s = s.replace(old, new, 1)
        if "import re, ast, math" not in s: s = s.replace("import re, ast", "import re, ast, math", 1)
        open("slowlog.py", "w").write(s); print("slowlog.py: correction added")
else: print("slowlog.py: already has the correction")
s = open("progress.py").read()
if "capped request counter" not in s:
    old = '''print(f"Baseline : {d['baseline']:.1f} req/s" if d["baseline"] else "Baseline : (not measured yet)")'''
    if old not in s: print("progress.py: anchor not found"); ok = False
    else:
        s = s.replace(old, old + '''\nif d.get("capped"): print(f"Note     : {d['capped']} measurement(s) had a capped request counter; throughputs below are CORRECTED (x capped/planned)")''', 1)
        open("progress.py", "w").write(s); print("progress.py: note added")
else: print("progress.py: already has the note")
s = open("summarize_runs.py").read()
if "capped measurement(s)" not in s:
    old = "        runs.setdefault(m.group(1), []).append({"
    if old not in s: print("summarize_runs.py: anchor not found"); ok = False
    else:
        s = s.replace(old, '''        if d.get("capped"): print(f"({os.path.basename(p)}: {d['capped']} capped measurement(s) - throughputs corrected by capped/planned counter)")\n''' + old, 1)
        open("summarize_runs.py", "w").write(s); print("summarize_runs.py: note added")
else: print("summarize_runs.py: already has the note")
sys.exit(0 if ok else 1)
