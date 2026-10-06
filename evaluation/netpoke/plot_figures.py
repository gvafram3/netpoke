#!/usr/bin/env python3
"""
Regenerate the data figures of the NetPoke paper (Figs. 3, 5, 6, 7, 8 and 9) from the raw experiment logs.

    python3 evaluation/netpoke/plot_figures.py                       # paper data in evaluation/netpoke/results
    python3 evaluation/netpoke/plot_figures.py -r evaluation/results/netpoke -o /tmp/figs   # your own run

Every number is recomputed from the logs with control/slowlog.py, which applies the capped-request-counter
correction (paper Sec. 5.1, Algorithm 3). The script also prints the summary table so the figures can be checked
against the paper's tables. Requires matplotlib.
"""
import argparse, glob, os, re, statistics as st, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "control"))
from slowlog import parse_log, rmse_bias  # noqa: E402

OPT = [50, 45, 40, 35, 30, 25, 20, 15, 10, 5]           # level 0 = largest optimisation (p_t = 400 us)

# arm name (log prefix) -> folder under the results directory
ARMS = {
    "phase1_nolock":  "reproduction",
    "phase2_freeze":  "netbound_deep",     "deepq_hold":   "netbound_deep",
    "phase5_freeze":  "netbound_shallow",  "phase5_hold":  "netbound_shallow",
    "cpu_freeze":     "no_bottleneck",     "cpu_hold":     "no_bottleneck",
    "nocap_freeze":   "no_bottleneck",     "nocap_hold":   "no_bottleneck",
}


def load_arm(root, arm):
    """Return per-repetition truth, prediction and error lists for one arm, or None if no logs exist."""
    paths = sorted(glob.glob(os.path.join(root, ARMS[arm], f"{arm}_rep*.log"))) or \
            sorted(glob.glob(os.path.join(root, f"{arm}_rep*.log")))
    reps = []
    for p in paths:
        d = parse_log(p)
        if not d["finished"]:
            print(f"  skipping unfinished log {p}")
            continue
        gt, pr = d["final"]["Groundtruth"], d["final"]["Predicted"]
        reps.append({"gt": gt, "pr": pr, "err": [100 * (x - y) / y for x, y in zip(pr, gt)]})
    if not reps:
        return None
    mean = lambda key: [st.mean(r[key][i] for r in reps) for i in range(len(reps[0][key]))]
    rm = [rmse_bias(r["err"])[0] for r in reps]
    bs = [rmse_bias(r["err"])[1] for r in reps]
    return {"n": len(reps), "gt": mean("gt"), "pr": mean("pr"), "err": mean("err"),
            "rmse": st.mean(rm), "rmse_sd": st.stdev(rm) if len(rm) > 1 else 0.0,
            "bias": st.mean(bs), "bias_sd": st.stdev(bs) if len(bs) > 1 else 0.0,
            "worst": max(abs(e) for r in reps for e in r["err"])}


def load_leak(root):
    """Byte leak (%) at the pod (A) and at the bottleneck (B) for each queue and system."""
    out = {}
    files = glob.glob(os.path.join(root, "leak_inapp", "result_*_pt400_*.txt")) + \
            glob.glob(os.path.join(root, "inpod_leak", "result_*_pt400_*.txt"))       # paper layout, or as pulled
    for p in files:
        m = re.search(r"result_(freeze|hold)_pt400_(\w+)\.txt$", p)
        if not m:
            continue
        txt = open(p).read()
        s = re.search(r"A pod: ([\d.]+)% of packets, ([\d.]+)% of bytes \| B bottleneck: ([\d.]+)% of packets, ([\d.]+)% of bytes", txt)
        if s:
            out[(m.group(2), m.group(1))] = {"A": float(s.group(2)), "B": float(s.group(4))}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("-r", "--results", default=os.path.join(HERE, "results"))
    ap.add_argument("-o", "--out", default=os.path.join(HERE, "figures"))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)

    D = {arm: load_arm(a.results, arm) for arm in ARMS}
    print(f"{'arm':16s} {'n':>2s} {'RMSE %':>14s} {'bias %':>15s} {'worst %':>8s}")
    for arm, v in D.items():
        if v:
            print(f"{arm:16s} {v['n']:2d} {v['rmse']:6.2f} ± {v['rmse_sd']:4.2f}  {v['bias']:+6.2f} ± {v['bias_sd']:4.2f} {v['worst']:8.1f}")

    import matplotlib
    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    plt.rcParams.update({"font.family": "DejaVu Serif", "font.size": 10.5, "legend.fontsize": 9.3,
                         "axes.spines.top": False, "axes.spines.right": False})
    RED, GREEN, BLACK, GREY = "#c01c28", "#2b7a2b", "#222222", "#8a8a8a"
    save = lambda name: (plt.savefig(os.path.join(a.out, name), dpi=300, bbox_inches="tight"), plt.close(),
                         print("  wrote", os.path.join(a.out, name)))

    # Paper Fig. 3: ground truth vs prediction, deep and shallow queue
    if D["phase2_freeze"] and D["phase5_freeze"] and D["phase5_hold"]:
        fig, ax = plt.subplots(1, 2, figsize=(9.6, 3.6))
        ax[0].plot(OPT, D["phase2_freeze"]["gt"], "o-", color=BLACK, label="Ground truth")
        ax[0].plot(OPT, D["phase2_freeze"]["pr"], "s--", color=RED, label="SlowPoke prediction")
        ax[0].set_title("(a) Network bottleneck, deep queue (fq_codel)", fontsize=9.8)
        ax[1].plot(OPT, D["phase5_freeze"]["gt"], "o-", color=BLACK, label="Ground truth")
        ax[1].plot(OPT, D["phase5_freeze"]["pr"], "s--", color=RED, label="SlowPoke")
        ax[1].plot(OPT, D["phase5_hold"]["pr"], "^-", color=GREEN, label="SlowPoke + NetPoke")
        ax[1].set_title("(b) Network bottleneck, shallow queue (pfifo, 20 packets)", fontsize=9.8)
        for x in ax:
            x.invert_xaxis(); x.grid(alpha=.25); x.legend(frameon=False)
            x.set_xlabel("Optimisation applied to target service (%)")
        ax[0].set_ylabel("End-to-end throughput (req/s)")
        plt.tight_layout(); save("truth_vs_pred.png")

    # Paper Fig. 5: egress leak at the bottleneck and at the pod
    L = load_leak(a.results)
    queues = [("fq_codel", "fq_codel\n(deep, default)"), ("pfifo20", "pfifo, 20 packets\n(shallow)"),
              ("pfifo5", "pfifo, 5 packets\n(very shallow)")]
    if all((q, s) in L for q, _ in queues for s in ("freeze", "hold")):
        fig, ax = plt.subplots(1, 2, figsize=(9.6, 3.7))
        for k, (pt, title) in enumerate((("B", "(a) Point B: shared bottleneck link"),
                                         ("A", "(b) Point A: paused pod's own interface"))):
            xs = range(len(queues))
            off = [L[(q, "freeze")][pt] for q, _ in queues]; on = [L[(q, "hold")][pt] for q, _ in queues]
            b1 = ax[k].bar([x - .19 for x in xs], off, .38, color=RED, label="SlowPoke (no hold)")
            b2 = ax[k].bar([x + .19 for x in xs], on, .38, color=GREEN, label="+ NetPoke (hold)")
            for bars in (b1, b2):
                for b in bars:
                    ax[k].text(b.get_x() + b.get_width() / 2, b.get_height() + 1, f"{b.get_height():.1f}",
                               ha="center", fontsize=8)
            ax[k].set_xticks(list(xs)); ax[k].set_xticklabels([t for _, t in queues], fontsize=8.6)
            ax[k].set_title(title, fontsize=9.8); ax[k].legend(frameon=False, fontsize=8.6)
        ax[0].set_ylabel("Bytes leaked during pauses\n(% of running rate)")
        plt.tight_layout(); save("leak.png")

    # Paper Fig. 6: error per level, shallow queue
    if D["phase5_freeze"] and D["phase5_hold"]:
        fig, ax = plt.subplots(figsize=(6.4, 3.8))
        ax.axhline(0, color=GREY, lw=1)
        ax.plot(OPT, D["phase5_freeze"]["err"], "s--", color=RED, label="SlowPoke (freeze only)")
        ax.plot(OPT, D["phase5_hold"]["err"], "^-", color=GREEN, label="SlowPoke + NetPoke")
        ax.fill_between(OPT, 0, D["phase5_freeze"]["err"], color=RED, alpha=.08)
        ax.fill_between(OPT, 0, D["phase5_hold"]["err"], color=GREEN, alpha=.08)
        ax.invert_xaxis(); ax.grid(alpha=.25); ax.legend(frameon=False)
        ax.set_xlabel("Optimisation applied to target service (%)")
        ax.set_ylabel("Prediction error (%)\n(+ = over-predicts, optimistic)")
        plt.tight_layout(); save("error_by_level.png")

    # Paper Fig. 8: no-bottleneck RMSE
    if all(D[k] for k in ("cpu_freeze", "cpu_hold", "nocap_freeze", "nocap_hold")):
        fig, ax = plt.subplots(figsize=(5.8, 3.7))
        groups = [("cpu_freeze", "cpu_hold", "Small payload"), ("nocap_freeze", "nocap_hold", "8 KB payload")]
        for g, (f, h, lab) in enumerate(groups):
            for dx, arm, col, name in ((-.19, f, RED, "SlowPoke (freeze only)"), (.19, h, GREEN, "+ NetPoke (hold)")):
                ax.bar(g + dx, D[arm]["rmse"], .38, yerr=D[arm]["rmse_sd"], capsize=4, color=col,
                       label=name if g == 0 else None)
                ax.text(g + dx, D[arm]["rmse"] + D[arm]["rmse_sd"] + .12, f"{D[arm]['rmse']:.2f}", ha="center", fontsize=8.6)
        ax.set_xticks([0, 1]); ax.set_xticklabels([g[2] for g in groups]); ax.set_ylabel("RMSE (%)")
        ax.legend(frameon=False); plt.tight_layout(); save("no_harm.png")

    # Paper Fig. 9: heatmap of per-level error across conditions
    rows = [("SlowPoke, deep queue", "phase2_freeze"), ("SlowPoke + NetPoke, deep queue", "deepq_hold"),
            ("SlowPoke, shallow queue", "phase5_freeze"), ("SlowPoke + NetPoke, shallow queue", "phase5_hold"),
            ("SlowPoke, no bottleneck, 8 KB", "nocap_freeze"), ("SlowPoke + NetPoke, no bottleneck, 8 KB", "nocap_hold")]
    rows = [(lab, arm) for lab, arm in rows if D[arm]]
    if rows:
        import numpy as np
        mat = np.array([D[arm]["err"] for _, arm in rows]); vmax = abs(mat).max()
        fig, ax = plt.subplots(figsize=(8.8, 0.6 * len(rows) + 0.8))
        im = ax.imshow(mat, cmap="RdYlGn_r", vmin=-vmax, vmax=vmax, aspect="auto")
        ax.set_xticks(range(10)); ax.set_xticklabels(OPT); ax.set_yticks(range(len(rows)))
        ax.set_yticklabels([r[0] for r in rows], fontsize=8.6); ax.set_xlabel("Optimisation applied to target service (%)")
        for i in range(mat.shape[0]):
            for j in range(mat.shape[1]):
                ax.text(j, i, f"{mat[i, j]:+.1f}", ha="center", va="center", fontsize=7.2,
                        color="white" if abs(mat[i, j]) > vmax * .55 else "black")
        fig.colorbar(im, ax=ax, fraction=.035, pad=.02).set_label("Prediction error (%)", fontsize=8.5)
        plt.tight_layout(); save("heatmap.png")

    # Paper Fig. 7: two-by-two design per level
    if all(D[k] for k in ("phase2_freeze", "deepq_hold", "phase5_freeze", "phase5_hold")):
        fig, ax = plt.subplots(1, 2, figsize=(9.6, 3.8), sharey=True)
        for x, (fz, hd, title) in zip(ax, (("phase2_freeze", "deepq_hold", "(a) Deep bottleneck queue (fq_codel)"),
                                            ("phase5_freeze", "phase5_hold", "(b) Shallow bottleneck queue (pfifo, 20 packets)"))):
            x.axhline(0, color=GREY, lw=1)
            x.plot(OPT, D[fz]["err"], "s--", color=RED, label="SlowPoke (freeze only)")
            x.plot(OPT, D[hd]["err"], "^-", color=GREEN, label="SlowPoke + NetPoke")
            x.invert_xaxis(); x.grid(alpha=.25); x.legend(frameon=False); x.set_title(title, fontsize=9.8)
            x.set_xlabel("Optimisation applied to target service (%)")
        ax[0].set_ylabel("Prediction error (%)\n(+ = over-predicts)")
        plt.tight_layout(); save("two_by_two.png")


if __name__ == "__main__":
    main()
