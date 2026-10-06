"""Parse the log written by slowpoke's src/main.py (shared by progress.py and summarize_runs.py)."""
import re, ast, math

STAGES = [("Deleting all services", "removing previous pods"), ("Waiting for all pods to be deleted", "waiting for old pods to go"),
          ("Deploying all services", "deploying pods"), ("Waiting for all pods to be running", "waiting for pods to start"),
          ("Checking heartbeat", "checking service connectivity"), ("Running warmup test", "warm-up (3 s)"),
          ("Running the actual test", "MEASURING throughput"), ("Checking the resource usage", "collecting CPU usage"),
          ("Test finished with status", "step finished")]

def _f(x):
    try: return float(x)
    except Exception: return float("nan")

def parse_log(path):
    d = {"range": None, "baseline": None, "levels": {}, "current": None, "stage": None, "finished": False,
         "final": {}, "tail": []}
    lines = open(path, errors="replace").read().splitlines()
    d["tail"] = lines[-8:]
    for line in lines:
        m = re.search(r"\[test\.py\] Actual processing time range: (\[.*\])", line)
        if m:
            try: d["range"] = ast.literal_eval(m.group(1))
            except Exception: pass
        m = re.search(r"\[test\.py\] Baseline throughput:\s*([0-9.eE+-]+)", line)
        if m: d["baseline"] = float(m.group(1))
        if "[test.py] Running baseline experiment" in line: d["current"] = ("base", None)
        m = re.search(r"Running (\d+)th groundtruth exp", line)
        if m: d["current"] = ("gt", int(m.group(1)))
        m = re.search(r"Running (\d+)th slowdown exp", line)
        if m: d["current"] = ("sd", int(m.group(1)))
        m = re.search(r"Finished running (\d+)th optmization experiment: groundtruth->(\S+?), slowdown->(\S+?), predicted->(\S+?), err->(\S+)", line)
        if m:
            i = int(m.group(1)); d["levels"][i] = tuple(_f(m.group(k)) for k in (2, 3, 4, 5)); d["current"] = ("done", i)
        for key, label in STAGES:
            if key in line and "echo" not in line: d["stage"] = label
        m = re.search(r"\[test\.py\] (Groundtruth|Slowdown|Predicted|Error percentage):\s*(\[.*\])", line)
        if m:
            try: d["final"][m.group(1)] = ast.literal_eval(m.group(2))
            except Exception: pass
    d["finished"] = "Error percentage" in d["final"]
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

def levels_info(d):
    """target processing times and optimisation size per level (baseline = last time + step, as main.py builds the range)"""
    r = d["range"]
    if not r: return None
    step = (r[1] - r[0]) if len(r) > 1 else None
    base = r[-1] + step if step else None
    return [{"p": p, "d": (base - p) if base else None, "pct": (100.0 * (base - p) / base) if base else None} for p in r], base

def steps(d):
    n = len(d["range"]) if d["range"] else None
    if n is None: return 0, None
    total = 1 + 2 * n
    if d["finished"]: return total, total
    c = d["current"]
    if c is None or d["baseline"] is None and c[0] != "base": return 0, total
    kind, i = c
    done = {"base": 0, "gt": 1 + 2 * (i or 0), "sd": 2 + 2 * (i or 0), "done": 1 + 2 * ((i or 0) + 1)}[kind]
    return done, total

def rmse_bias(errs):
    errs = [e for e in errs if not math.isnan(e)]
    if not errs: return float("nan"), float("nan")
    return math.sqrt(sum(e * e for e in errs) / len(errs)), sum(errs) / len(errs)
