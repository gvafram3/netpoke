#!/usr/bin/env python3
"""Build RMSE vs I/O level table (L0–L2) for thesis Ch. 3."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

# Reuse log parser from summarize_results.py
EVAL_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(EVAL_DIR))

from summarize_results import parse_summary, rmse  # noqa: E402

BENCHMARKS = ("boutique", "hotel", "social", "movie")
LEVELS = ("L0", "L1", "L2")

# Fixed -x targets (match io_levels.conf)
TARGETS = {
    "boutique": "cart",
    "hotel": "profile",
    "social": "hometimeline",
    "movie": "moviereviews",
}

# Path I/O injection via netem sidecars (L1/L2 only)
INJECT = {
    "L1": {
        "boutique": "productcatalog:30ms",
        "hotel": "rate:30ms",
        "social": "poststorage:30ms",
        "movie": "reviewstorage:30ms",
    },
    "L2": {
        "boutique": "productcatalog:50ms,currency:30ms",
        "hotel": "rate:50ms,user:30ms",
        "social": "poststorage:50ms,socialgraph:30ms",
        "movie": "reviewstorage:50ms,movieinfo:30ms",
    },
}


def level_label(bench: str, level: str) -> str:
    base = TARGETS[bench]
    if level == "L0":
        return base
    inj = INJECT[level][bench]
    return f"{base} (+netem {inj})"


def log_path(results: Path, bench: str, level: str) -> Path:
    if level == "L0":
        return results / f"{bench}_medium.log"
    return results / f"{bench}_io_{level}_medium.log"


def load_row(results: Path, bench: str, level: str) -> dict | None:
    path = log_path(results, bench, level)
    if not path.is_file():
        return None
    try:
        data = parse_summary(path.read_text())
    except ValueError as e:
        return {"error": str(e), "path": path}
    err = data["error_perc"]
    return {
        "baseline": data["baseline"],
        "rmse": rmse(err),
        "mean_abs": sum(abs(e) for e in err) / len(err),
        "path": path,
    }


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "results_dir",
        nargs="?",
        default="results",
        help="evaluation results directory (default: results)",
    )
    ap.add_argument(
        "-o",
        "--output",
        help="write CSV to this path (also prints table to stdout)",
    )
    args = ap.parse_args()

    results = Path(args.results_dir)
    if not results.is_dir():
        results = EVAL_DIR / args.results_dir

    rows: list[tuple[str, str, str, str, str, str]] = []

    print("RMSE vs I/O level (4 benchmarks × L0/L1/L2)")
    print("L0/L1/L2 share the same -x target; L1/L2 add path netem injection.")
    print(f"results: {results.resolve()}")
    print()
    hdr = f"{'App':<10} {'Level':<4} {'Target / injection':<32} {'Baseline':>12} {'RMSE %':>8} {'Mean|err|':>10}  Log"
    print(hdr)
    print("-" * len(hdr))

    for bench in BENCHMARKS:
        for level in LEVELS:
            tgt = level_label(bench, level)
            row = load_row(results, bench, level)
            if row is None:
                baseline_s = rmse_s = mean_s = "—"
                log_s = str(log_path(results, bench, level).name) + " (missing)"
            elif "error" in row:
                baseline_s = rmse_s = mean_s = "FAIL"
                log_s = f"{row['path'].name}: {row['error']}"
            else:
                baseline_s = f"{row['baseline']:.1f}"
                rmse_s = f"{row['rmse']:.2f}"
                mean_s = f"{row['mean_abs']:.2f}"
                log_s = row["path"].name
            print(
                f"{bench:<10} {level:<4} {tgt:<32} {baseline_s:>12} {rmse_s:>8} {mean_s:>10}  {log_s}"
            )
            rows.append((bench, level, tgt, baseline_s, rmse_s, mean_s))

    if args.output:
        out = Path(args.output)
        out.parent.mkdir(parents=True, exist_ok=True)
        with out.open("w") as f:
            f.write("app,level,target_injection,baseline_req_s,rmse_pct,mean_abs_err_pct\n")
            for r in rows:
                f.write(",".join(r) + "\n")
        print(f"\nWrote {out}")

    print("\n--- L2 vs L0 RMSE delta (thesis headline) ---")
    for bench in BENCHMARKS:
        l0 = load_row(results, bench, "L0")
        l2 = load_row(results, bench, "L2")
        if l0 and l2 and "rmse" in l0 and "rmse" in l2:
            delta = l2["rmse"] - l0["rmse"]
            sign = "+" if delta >= 0 else ""
            print(f"  {bench}: L0 {l0['rmse']:.2f}% → L2 {l2['rmse']:.2f}% ({sign}{delta:.2f} pp)")


if __name__ == "__main__":
    main()
