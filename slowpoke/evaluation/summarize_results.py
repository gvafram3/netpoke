#!/usr/bin/env python3
"""Print SlowPoke summary tables and RMSE from *_medium.log (artifact / paper style)."""
import argparse
import ast
import math
import re
import sys
from pathlib import Path


def parse_summary(text: str) -> dict:
    """Prefer the final Summary block; fall back to last [test.py] arrays."""
    patterns = {
        "baseline": r"Baseline throughput:\s*([0-9.eE+-]+)",
        "groundtruth": r"Groundtruth:\s*(\[[^\]]+\])",
        "slowdown": r"Slowdown:\s*(\[[^\]]+\])",
        "predicted": r"Predicted:\s*(\[[^\]]+\])",
        "error_perc": r"Error Perc:\s*(\[[^\]]+\])",
    }
    # Search from the last Summary section backward
    idx = text.rfind("Summary:")
    chunk = text[idx:] if idx >= 0 else text
    data = {}
    for key, pat in patterns.items():
        m = None
        for m in re.finditer(pat, chunk):
            pass
        if m is None:
            m = re.search(pat, text)
        if not m:
            raise ValueError(f"Could not find `{key}` in log (run may be incomplete)")
        val = m.group(1)
        data[key] = float(val) if key == "baseline" else ast.literal_eval(val)
    return data


def rmse(errors: list[float]) -> float:
    return math.sqrt(sum(e * e for e in errors) / len(errors))


def print_report(name: str, data: dict) -> None:
    gt, sd, pred, err = data["groundtruth"], data["slowdown"], data["predicted"], data["error_perc"]
    n = len(gt)
    print(f"\n{'=' * 72}")
    print(f"  {name}")
    print(f"{'=' * 72}")
    print(f"  Baseline throughput: {data['baseline']:.4f} req/s")
    print(f"  Points: {n} (optimized processing time 0%..{(n - 1) * 10}%)")
    print()
    print(f"  {'i':>2}  {'Groundtruth':>14}  {'Slowdown':>14}  {'Predicted':>14}  {'Error %':>10}")
    print(f"  {'-' * 2}  {'-' * 14}  {'-' * 14}  {'-' * 14}  {'-' * 10}")
    for i in range(n):
        pct = i * 10
        print(
            f"  {pct:2d}%  {gt[i]:14.2f}  {sd[i]:14.2f}  {pred[i]:14.2f}  {err[i]:10.2f}"
        )
    print()
    print(f"  Mean |error|: {sum(abs(e) for e in err) / len(err):.2f}%")
    print(f"  RMSE (error %): {rmse(err):.2f}%")
    print(f"  (Artifact guide: mostly within ~10%, often 0–4% per point)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("logs", nargs="+", help="e.g. results/boutique_medium.log")
    args = ap.parse_args()
    ok = 0
    for path in args.logs:
        p = Path(path)
        if not p.is_file():
            print(f"SKIP: {path} not found", file=sys.stderr)
            continue
        try:
            data = parse_summary(p.read_text())
            print_report(p.name, data)
            ok += 1
        except ValueError as e:
            print(f"FAIL: {p.name}: {e}", file=sys.stderr)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
