#!/usr/bin/env python3
"""RMSE vs I/O level — paper-style line plot (thesis Fig. I1 / Phase 3)."""
from __future__ import annotations

import argparse
import csv
import sys
from pathlib import Path

import matplotlib.pyplot as plt

IO_GAP = Path(__file__).resolve().parent
EVAL = IO_GAP.parent
sys.path.insert(0, str(EVAL))

from summarize_io_gap_matrix import BENCHMARKS, load_row, log_path  # noqa: E402

LEVELS = ("L0", "L1", "L2")
LEVEL_X = {"L0": 0, "L1": 1, "L2": 2}
COLORS = {
    "boutique": "#1f77b4",
    "hotel": "#ff7f0e",
    "social": "#2ca02c",
    "movie": "#d62728",
}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("results_dir", nargs="?", default="results")
    ap.add_argument(
        "-o",
        "--output",
        default=None,
        help="output PNG (default: <results>/fig_io_gap_rmse.png)",
    )
    args = ap.parse_args()

    results = Path(args.results_dir)
    if not results.is_dir():
        results = EVAL / args.results_dir

    out = Path(args.output) if args.output else results / "fig_io_gap_rmse.png"

    plt.figure(figsize=(7, 4.5))
    for bench in BENCHMARKS:
        xs, ys = [], []
        for level in LEVELS:
            row = load_row(results, bench, level)
            if row and "rmse" in row:
                xs.append(LEVEL_X[level])
                ys.append(row["rmse"])
        if xs:
            plt.plot(
                xs,
                ys,
                marker="o",
                label=bench,
                color=COLORS.get(bench, None),
                linewidth=2,
            )

    plt.xticks([0, 1, 2], ["L0\n(baseline)", "L1\n(moderate I/O)", "L2\n(heavy I/O)"])
    plt.ylabel("RMSE (%)")
    plt.xlabel("I/O intensity level")
    plt.title("Throughput prediction RMSE vs path I/O intensity")
    plt.legend()
    plt.grid(True, linestyle=":", alpha=0.6)
    plt.tight_layout()
    out.parent.mkdir(parents=True, exist_ok=True)
    plt.savefig(out, dpi=150)
    pdf = out.with_suffix(".pdf")
    plt.savefig(pdf)
    plt.close()
    print(f"Wrote {out}")
    print(f"Wrote {pdf}")


if __name__ == "__main__":
    main()
