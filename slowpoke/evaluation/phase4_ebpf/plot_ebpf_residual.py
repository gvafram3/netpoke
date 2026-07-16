#!/usr/bin/env python3
"""Phase 4 figures: residual I/O during SIGSTOP (thesis Ch. 4 / Fig E1–E2)."""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

import matplotlib.pyplot as plt

PHASE4 = Path(__file__).resolve().parent
EVAL = PHASE4.parent
sys.path.insert(0, str(PHASE4))

from summarize_ebpf_residual import summarize_one  # noqa: E402

BENCHMARKS = ("social", "hotel", "movie", "boutique")
COLORS = {
    "boutique": "#1f77b4",
    "hotel": "#ff7f0e",
    "social": "#2ca02c",
    "movie": "#d62728",
}


def load_rows(results_dir: Path) -> list[dict]:
    rows = []
    for bench in BENCHMARKS:
        jsonl = results_dir / f"{bench}_ebpf_L2_residual.jsonl"
        log = results_dir / f"{bench}_ebpf_L2_medium.log"
        if not jsonl.is_file():
            continue
        rows.append(summarize_one(str(jsonl), str(log) if log.is_file() else None))
    return rows


def fig_rmse_bars(rows: list[dict], out: Path) -> None:
    labels = [r["benchmark"] for r in rows if r.get("rmse_pct") is not None]
    rmse = [r["rmse_pct"] for r in rows if r.get("rmse_pct") is not None]
    if not labels:
        print("Skip fig_rmse_bars: no RMSE data", file=sys.stderr)
        return
    colors = [COLORS.get(b, "#888888") for b in labels]
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.bar(labels, rmse, color=colors, edgecolor="black", linewidth=0.5)
    ax.set_ylabel("RMSE (%)")
    ax.set_xlabel("Application (L2 + SIGSTOP-only)")
    ax.set_title("Phase 4 — prediction error at heavy I/O (L2)")
    ax.grid(axis="y", linestyle=":", alpha=0.6)
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    fig.savefig(out.with_suffix(".pdf"))
    plt.close(fig)
    print(f"Wrote {out}")


def fig_residual_bars(rows: list[dict], out: Path) -> None:
    labels = [r["benchmark"] for r in rows]
    wins = [r["windows_with_sigstop"] for r in rows]
    net_gb = [r["total_delta_net_rx"] / 1e9 for r in rows]
    colors = [COLORS.get(r["benchmark"], "#888888") for r in rows]
    fig, ax1 = plt.subplots(figsize=(8, 4.5))
    x = range(len(labels))
    w = 0.35
    ax1.bar([i - w / 2 for i in x], wins, width=w, label="SIGSTOP windows", color="#6baed6")
    ax1.set_ylabel("Pause windows observed")
    ax1.set_xticks(list(x))
    ax1.set_xticklabels(labels)
    ax2 = ax1.twinx()
    ax2.bar([i + w / 2 for i in x], net_gb, width=w, label="Δ net RX (GB)", color="#fd8d3c")
    ax2.set_ylabel("Cumulative Δ net RX during pauses (GB)")
    ax1.set_title("Phase 4 — residual network activity during SIGSTOP (L2)")
    lines1, lab1 = ax1.get_legend_handles_labels()
    lines2, lab2 = ax2.get_legend_handles_labels()
    ax1.legend(lines1 + lines2, lab1 + lab2, loc="upper left")
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    fig.savefig(out.with_suffix(".pdf"))
    plt.close(fig)
    print(f"Wrote {out}")


def fig_rmse_vs_residual(rows: list[dict], out: Path) -> None:
    pts = [(r["benchmark"], r["rmse_pct"], r["total_delta_net_rx"]) for r in rows if r.get("rmse_pct")]
    if len(pts) < 2:
        print("Skip fig_rmse_vs_residual: need ≥2 apps with RMSE", file=sys.stderr)
        return
    fig, ax = plt.subplots(figsize=(6, 5))
    for bench, rmse, nrx in pts:
        ax.scatter(nrx / 1e9, rmse, s=120, color=COLORS.get(bench, "#888888"), label=bench, zorder=3)
        ax.annotate(bench, (nrx / 1e9, rmse), textcoords="offset points", xytext=(6, 4), fontsize=9)
    ax.set_xlabel("Cumulative Δ net RX during pauses (GB)")
    ax.set_ylabel("RMSE at L2 (%)")
    ax.set_title("Prediction error vs residual ingress during pause")
    ax.grid(True, linestyle=":", alpha=0.6)
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    fig.savefig(out.with_suffix(".pdf"))
    plt.close(fig)
    print(f"Wrote {out}")


def write_csv(rows: list[dict], out: Path) -> None:
    if not rows:
        return
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    print(f"Wrote {out}")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("results_dir", nargs="?", default=str(EVAL / "results"))
    ap.add_argument("-o", "--output-dir", default=None, help="figures output directory")
    args = ap.parse_args()
    rdir = Path(args.results_dir)
    odir = Path(args.output_dir) if args.output_dir else rdir
    odir.mkdir(parents=True, exist_ok=True)

    rows = load_rows(rdir)
    if not rows:
        print(f"No *_ebpf_L2_residual.jsonl in {rdir}", file=sys.stderr)
        return 1

    write_csv(rows, odir / "ebpf_residual_summary.csv")
    fig_rmse_bars(rows, odir / "fig_ebpf_rmse_L2.png")
    fig_residual_bars(rows, odir / "fig_ebpf_residual_io.png")
    fig_rmse_vs_residual(rows, odir / "fig_ebpf_rmse_vs_netrx.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
