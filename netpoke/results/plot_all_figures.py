"""
NetPoke thesis figures — generates all PNGs from hardcoded results data.
Run: python3 plot_all_figures.py
Output: figures/ directory next to this script.
"""
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np

OUT = os.path.join(os.path.dirname(__file__), "figures")
os.makedirs(OUT, exist_ok=True)

# ── style ────────────────────────────────────────────────────────────────────
plt.rcParams.update({
    "font.family": "serif", "font.size": 11,
    "axes.spines.top": False, "axes.spines.right": False,
    "axes.grid": True, "grid.alpha": 0.3, "grid.linestyle": "--",
    "figure.dpi": 150,
})

APPS   = ["Boutique", "Hotel", "Social", "Movie"]
OPT    = list(range(0, 100, 10))   # 0%–90%
COLORS = {"gt": "#1f77b4", "pred": "#d62728", "sigstop": "#1f77b4", "netpoke": "#2ca02c"}

# ════════════════════════════════════════════════════════════════════════════
# DATA
# ════════════════════════════════════════════════════════════════════════════

# ── Fig 1 / B1: L0 baseline — Groundtruth vs Predicted (paper Fig 8 style) ──
# From TABLE_L0_SUMMARY + reference sample format; we have RMSE but not
# per-point GT/Pred for our cluster runs, so we reconstruct from the
# reference sample_output (paper artifact style) for the figure format demo,
# and use our cluster RMSE numbers in the annotation.
# For our cluster runs we only have RMSE, so we show the RMSE bar chart
# as the primary B1 figure, and the paper-style curve for the reference run.

# Reference sample data (paper artifact, TABLE_sample_L0.txt)
REF = {
    "Boutique": {
        "baseline": 4008.8,
        "gt":   [5829.6, 5930.0, 5917.9, 5773.9, 5915.3, 5767.8, 5988.3, 5432.0, 4855.2, 4392.6],
        "pred": [5989.9, 6181.6, 6231.2, 6389.0, 6245.9, 6220.9, 5927.3, 5432.6, 4878.1, 4365.4],
        "rmse": 5.12,
    },
    "Hotel": {
        "baseline": 1865.0,
        "gt":   [2044.3, 1993.5, 1984.7, 1974.1, 1999.8, 1984.7, 2040.0, 2003.3, 1958.2, 1955.1],
        "pred": [2002.0, 1974.1, 1904.5, 1962.4, 1999.6, 2054.7, 2055.7, 2016.1, 1952.7, 1968.6],
        "rmse": 1.89,
    },
    "Social": {
        "baseline": 1975.1,
        "gt":   [6155.4, 5401.2, 4606.9, 4016.5, 3540.4, 3115.7, 2810.4, 2559.3, 2343.9, 2174.2],
        "pred": [6461.6, 5273.0, 4524.6, 3893.8, 3461.2, 2995.6, 2774.5, 2498.4, 2304.2, 2116.9],
        "rmse": 2.83,
    },
    "Movie": {
        "baseline": 1541.3,
        "gt":   [1718.4, 1764.9, 1735.9, 1772.5, 1731.8, 1732.2, 1740.3, 1733.9, 1718.0, 1639.8],
        "pred": [1686.4, 1703.5, 1727.7, 1716.7, 1731.1, 1704.9, 1710.0, 1767.2, 1702.1, 1616.5],
        "rmse": 1.94,
    },
}

# Cluster L0 RMSE (TABLE_L0_SUMMARY, fresh run 2026-07-16/17)
CLUSTER_L0_RMSE = {"Boutique": 2.57, "Hotel": 20.65, "Social": 14.01, "Movie": 12.21}

# ── Fig 2 / I1: RMSE vs injection level (TABLE_IO_GAP_MATRIX, fresh) ────────
IO_RMSE = {
    "Boutique": {"L0": 2.57,  "L1": 4.85,  "L2": 3.53},
    "Hotel":    {"L0": 20.65, "L1": 20.03, "L2": 17.51},
    "Social":   {"L0": 14.01, "L1": 30.33, "L2": 33.61},
    "Movie":    {"L0": 12.21, "L1": 28.48, "L2": 13.84},
}

# ── Fig 3 / N2: SIGSTOP-only vs NetPoke-on at L2 (TABLE_N2) ─────────────────
N2 = {
    "Boutique": {"sigstop_l2": 3.53,  "netpoke_l2": 10.26},
    "Hotel":    {"sigstop_l2": 17.51, "netpoke_l2": 10.25},
    "Social":   {"sigstop_l2": 33.61, "netpoke_l2": 18.69},
    "Movie":    {"sigstop_l2": 13.84, "netpoke_l2": 10.23},
}

# ── Fig 4 / N3: L0 overhead (TABLE_N3) ──────────────────────────────────────
N3 = {
    "Boutique": {"sigstop": 2.57,  "netpoke": 9.13},
    "Hotel":    {"sigstop": 20.65, "netpoke": 14.13},
    "Social":   {"sigstop": 14.01, "netpoke": 17.35},
    "Movie":    {"sigstop": 12.21, "netpoke": 12.13},
}

# ── Fig 5 / N1: Residual I/O (TABLE_RESIDUAL_MATRIX) ────────────────────────
RESIDUAL = {
    "Boutique L0": {"sigstop": 8.43, "netpoke": 7.06},
    "Boutique L2": {"sigstop": 3.28, "netpoke": 4.28},
    "Hotel L2":    {"sigstop": 9.52, "netpoke": 3.33},
    "Social L2":   {"sigstop": 8.91, "netpoke": 4.00},
    "Movie L2":    {"sigstop": 6.89, "netpoke": 1.59},
}

# ════════════════════════════════════════════════════════════════════════════
# HELPERS
# ════════════════════════════════════════════════════════════════════════════
def save(name):
    path = os.path.join(OUT, name)
    plt.savefig(path, bbox_inches="tight")
    plt.close()
    print(f"  {path}")

def rmse_bar(ax, apps, values_dict, colors, labels, title, ylabel="RMSE (%)"):
    x = np.arange(len(apps))
    w = 0.8 / len(values_dict)
    for i, (key, color, label) in enumerate(zip(values_dict, colors, labels)):
        vals = [values_dict[key][a] for a in apps]
        bars = ax.bar(x + i*w - (len(values_dict)-1)*w/2, vals, w*0.9,
                      color=color, label=label, zorder=3)
        for bar, v in zip(bars, vals):
            ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.3,
                    f"{v:.1f}", ha="center", va="bottom", fontsize=8)
    ax.set_xticks(x)
    ax.set_xticklabels(apps)
    ax.set_ylabel(ylabel)
    ax.set_title(title, fontweight="bold")
    ax.legend(fontsize=9)

# ════════════════════════════════════════════════════════════════════════════
# FIG 1a — Paper-style Groundtruth vs Predicted curves (reference sample run)
# 4-panel macro figure matching SlowPoke Fig 8
# ════════════════════════════════════════════════════════════════════════════
print("Generating figures...")
fig, axes = plt.subplots(1, 4, figsize=(16, 4), sharey=False)
fig.suptitle("Fig 1 — SlowPoke Baseline: Groundtruth vs Predicted Throughput\n"
             "(Reference artifact sample run — paper Fig. 8 style)", fontweight="bold")
for ax, app in zip(axes, APPS):
    d = REF[app]
    ax.plot(OPT, d["gt"],   "o-", color=COLORS["gt"],   label="Groundtruth", lw=2, ms=5)
    ax.plot(OPT, d["pred"], "s--", color=COLORS["pred"], label="Predicted",   lw=2, ms=5)
    ax.set_title(app)
    ax.set_xlabel("Optimised processing time (%)")
    ax.set_ylabel("Throughput (req/s)")
    ax.annotate(f"RMSE = {d['rmse']:.2f}%", xy=(0.97, 0.97), xycoords="axes fraction",
                ha="right", va="top", fontsize=9,
                bbox=dict(boxstyle="round,pad=0.3", fc="white", ec="gray", alpha=0.8))
    if app == APPS[0]:
        ax.legend(fontsize=8, loc="upper right")
plt.tight_layout()
save("fig1_baseline_gt_vs_pred_reference.png")

# ════════════════════════════════════════════════════════════════════════════
# FIG 1b — Cluster L0 RMSE bar chart (our actual run)
# ════════════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(7, 4))
x = np.arange(len(APPS))
bars = ax.bar(x, [CLUSTER_L0_RMSE[a] for a in APPS], color=COLORS["gt"],
              zorder=3, width=0.5)
for bar, app in zip(bars, APPS):
    ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.3,
            f"{CLUSTER_L0_RMSE[app]:.2f}%", ha="center", va="bottom", fontsize=10)
ax.axhline(2.07, color="gray", ls="--", lw=1.2, label="Paper headline (2.07%)")
ax.set_xticks(x); ax.set_xticklabels(APPS)
ax.set_ylabel("RMSE (%)")
ax.set_title("Fig 1b — Cluster L0 Baseline RMSE (SIGSTOP-only, 2026-07-16/17)",
             fontweight="bold")
ax.legend(fontsize=9)
plt.tight_layout()
save("fig1b_cluster_l0_rmse.png")

# ════════════════════════════════════════════════════════════════════════════
# FIG 2 — RMSE vs I/O injection level (L0 / L1 / L2)
# Line plot per app — the core I/O-gap figure
# ════════════════════════════════════════════════════════════════════════════
LEVELS = ["L0", "L1", "L2"]
APP_COLORS = ["#1f77b4", "#ff7f0e", "#2ca02c", "#9467bd"]
fig, ax = plt.subplots(figsize=(7, 5))
for app, color in zip(APPS, APP_COLORS):
    vals = [IO_RMSE[app][l] for l in LEVELS]
    ax.plot(LEVELS, vals, "o-", color=color, label=app, lw=2.2, ms=7)
    ax.annotate(f"{vals[-1]:.1f}%", xy=(2, vals[-1]),
                xytext=(5, 0), textcoords="offset points",
                va="center", fontsize=8.5, color=color)
ax.set_ylabel("RMSE (%)")
ax.set_xlabel("I/O injection level")
ax.set_title("Fig 2 — RMSE vs I/O Injection Level (SIGSTOP-only)\n"
             "RQ1: Does I/O-boundedness increase prediction error?", fontweight="bold")
ax.legend(fontsize=9)
plt.tight_layout()
save("fig2_rmse_vs_io_level.png")

# ════════════════════════════════════════════════════════════════════════════
# FIG 2b — L2 − L0 delta bar chart (ranked)
# ════════════════════════════════════════════════════════════════════════════
deltas = {a: IO_RMSE[a]["L2"] - IO_RMSE[a]["L0"] for a in APPS}
sorted_apps = sorted(APPS, key=lambda a: deltas[a], reverse=True)
colors_delta = ["#2ca02c" if deltas[a] > 0 else "#d62728" for a in sorted_apps]
fig, ax = plt.subplots(figsize=(7, 4))
x = np.arange(len(sorted_apps))
bars = ax.bar(x, [deltas[a] for a in sorted_apps], color=colors_delta, zorder=3, width=0.5)
for bar, app in zip(bars, sorted_apps):
    v = deltas[app]
    ax.text(bar.get_x() + bar.get_width()/2,
            bar.get_height() + (0.3 if v >= 0 else -1.2),
            f"{v:+.2f} pp", ha="center", va="bottom", fontsize=10)
ax.axhline(0, color="black", lw=0.8)
ax.set_xticks(x); ax.set_xticklabels(sorted_apps)
ax.set_ylabel("RMSE change L0 → L2 (pp)")
ax.set_title("Fig 2b — L2 − L0 RMSE Delta (SIGSTOP-only)\n"
             "Positive = I/O gap confirmed; negative = reversed", fontweight="bold")
plt.tight_layout()
save("fig2b_l2_l0_delta.png")

# ════════════════════════════════════════════════════════════════════════════
# FIG 3 — SIGSTOP-only vs NetPoke-on at L2 (grouped bar)
# ════════════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(8, 5))
x = np.arange(len(APPS))
w = 0.25
l0_vals     = [CLUSTER_L0_RMSE[a]      for a in APPS]
sigstop_vals= [N2[a]["sigstop_l2"]     for a in APPS]
netpoke_vals= [N2[a]["netpoke_l2"]     for a in APPS]

b0 = ax.bar(x - w, l0_vals,      w, color="#aec7e8", label="L0 baseline (SIGSTOP-only)", zorder=3)
b1 = ax.bar(x,     sigstop_vals, w, color=COLORS["sigstop"], label="L2 SIGSTOP-only", zorder=3)
b2 = ax.bar(x + w, netpoke_vals, w, color=COLORS["netpoke"], label="L2 NetPoke-on", zorder=3)

for bars in (b0, b1, b2):
    for bar in bars:
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.3,
                f"{bar.get_height():.1f}", ha="center", va="bottom", fontsize=7.5)

ax.set_xticks(x); ax.set_xticklabels(APPS)
ax.set_ylabel("RMSE (%)")
ax.set_title("Fig 3 — End-to-End RMSE: L0 Baseline vs L2 SIGSTOP-only vs L2 NetPoke-on\n"
             "RQ4: Does NetPoke restore prediction accuracy?", fontweight="bold")
ax.legend(fontsize=9)
plt.tight_layout()
save("fig3_n2_rmse_comparison.png")

# ════════════════════════════════════════════════════════════════════════════
# FIG 3b — NetPoke recovery % (social headline)
# ════════════════════════════════════════════════════════════════════════════
recovery = {}
for a in APPS:
    gap   = N2[a]["sigstop_l2"] - CLUSTER_L0_RMSE[a]
    recov = N2[a]["sigstop_l2"] - N2[a]["netpoke_l2"]
    recovery[a] = (recov / gap * 100) if gap > 0 else None

fig, ax = plt.subplots(figsize=(7, 4))
x = np.arange(len(APPS))
vals  = [recovery[a] if recovery[a] is not None else 0 for a in APPS]
cols  = ["#2ca02c" if v > 0 else "#d62728" for v in vals]
bars  = ax.bar(x, vals, color=cols, zorder=3, width=0.5)
for bar, app in zip(bars, APPS):
    v = recovery[app]
    label = f"{v:.0f}%" if v is not None else "N/A\n(no gap)"
    ax.text(bar.get_x() + bar.get_width()/2,
            max(bar.get_height(), 0) + 1,
            label, ha="center", va="bottom", fontsize=10)
ax.axhline(100, color="gray", ls="--", lw=1, label="Full recovery (100%)")
ax.axhline(0,   color="black", lw=0.8)
ax.set_xticks(x); ax.set_xticklabels(APPS)
ax.set_ylabel("Gap recovered by NetPoke (%)")
ax.set_title("Fig 3b — Fraction of I/O Gap Recovered by NetPoke at L2\n"
             "(gap = SIGSTOP-only L2 RMSE − L0 baseline RMSE)", fontweight="bold")
ax.legend(fontsize=9)
plt.tight_layout()
save("fig3b_netpoke_recovery_pct.png")

# ════════════════════════════════════════════════════════════════════════════
# FIG 4 — L0 overhead: SIGSTOP-only vs NetPoke-on (no injection)
# ════════════════════════════════════════════════════════════════════════════
fig, ax = plt.subplots(figsize=(7, 4))
x = np.arange(len(APPS))
w = 0.3
b1 = ax.bar(x - w/2, [N3[a]["sigstop"] for a in APPS], w,
            color=COLORS["sigstop"], label="SIGSTOP-only L0", zorder=3)
b2 = ax.bar(x + w/2, [N3[a]["netpoke"] for a in APPS], w,
            color=COLORS["netpoke"], label="NetPoke-on L0", zorder=3)
for bars in (b1, b2):
    for bar in bars:
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.3,
                f"{bar.get_height():.2f}", ha="center", va="bottom", fontsize=8.5)
ax.set_xticks(x); ax.set_xticklabels(APPS)
ax.set_ylabel("RMSE (%)")
ax.set_title("Fig 4 — L0 RMSE Overhead: SIGSTOP-only vs NetPoke-on (No I/O Injection)\n"
             "RQ5: Does NetPoke cost accuracy even with nothing to fix?", fontweight="bold")
ax.legend(fontsize=9)
plt.tight_layout()
save("fig4_n3_l0_overhead.png")

# ════════════════════════════════════════════════════════════════════════════
# FIG 5 — Residual network I/O during pause windows (TABLE_N1)
# ════════════════════════════════════════════════════════════════════════════
labels  = list(RESIDUAL.keys())
sig_vals = [RESIDUAL[k]["sigstop"] for k in labels]
net_vals = [RESIDUAL[k]["netpoke"] for k in labels]
x = np.arange(len(labels))
w = 0.3
fig, ax = plt.subplots(figsize=(9, 4.5))
b1 = ax.bar(x - w/2, sig_vals, w, color=COLORS["sigstop"], label="SIGSTOP-only", zorder=3)
b2 = ax.bar(x + w/2, net_vals, w, color=COLORS["netpoke"], label="NetPoke-on",   zorder=3)
for bars in (b1, b2):
    for bar in bars:
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.1,
                f"{bar.get_height():.2f}%", ha="center", va="bottom", fontsize=8)
ax.set_xticks(x); ax.set_xticklabels(labels, rotation=15, ha="right")
ax.set_ylabel("Residual RX during pause windows\n(% of outside-pause rate)")
ax.set_title("Fig 5 — Residual Network I/O During SIGSTOP Pause Windows\n"
             "RQ3: Does the egress hold suppress residual I/O?", fontweight="bold")
ax.legend(fontsize=9)
plt.tight_layout()
save("fig5_n1_residual_io.png")

# ════════════════════════════════════════════════════════════════════════════
# FIG 6 — Full cross-experiment summary (3-condition RMSE, all apps)
# L0 baseline / L2 SIGSTOP-only / L2 NetPoke-on — the thesis overview figure
# ════════════════════════════════════════════════════════════════════════════
fig, axes = plt.subplots(1, 4, figsize=(16, 4.5), sharey=False)
fig.suptitle("Fig 6 — Full Experiment Summary: RMSE Across All Conditions\n"
             "L0 baseline → L2 SIGSTOP-only → L2 NetPoke-on", fontweight="bold")
conditions = ["L0\nbaseline", "L2\nSIGSTOP-only", "L2\nNetPoke-on"]
cond_colors = ["#aec7e8", COLORS["sigstop"], COLORS["netpoke"]]
for ax, app in zip(axes, APPS):
    vals = [CLUSTER_L0_RMSE[app], N2[app]["sigstop_l2"], N2[app]["netpoke_l2"]]
    bars = ax.bar(conditions, vals, color=cond_colors, zorder=3, width=0.5)
    for bar, v in zip(bars, vals):
        ax.text(bar.get_x() + bar.get_width()/2, bar.get_height() + 0.3,
                f"{v:.1f}%", ha="center", va="bottom", fontsize=9)
    ax.set_title(app, fontweight="bold")
    ax.set_ylabel("RMSE (%)")
    ax.tick_params(axis="x", labelsize=8)
plt.tight_layout()
save("fig6_full_summary_all_apps.png")

print(f"\nDone. {len(os.listdir(OUT))} figures written to {OUT}/")
