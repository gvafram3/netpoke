#!/usr/bin/env python3
"""Summarize Phase 4 residual I/O JSONL + optional SlowPoke log RMSE."""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import sys

PHASE4 = os.path.dirname(os.path.abspath(__file__))
EVAL = os.path.dirname(PHASE4)


def parse_rmse_from_log(log_path: str) -> float | None:
    if not os.path.isfile(log_path):
        return None
    try:
        import subprocess

        r = subprocess.run(
            [sys.executable, os.path.join(EVAL, "summarize_results.py"), log_path],
            capture_output=True,
            text=True,
            timeout=120,
        )
        m = re.search(r"RMSE \(error %\):\s*([\d.]+)%", r.stdout)
        return float(m.group(1)) if m else None
    except Exception:
        return None


def load_jsonl(path: str) -> tuple[dict, list[dict]]:
    meta: dict = {}
    samples: list[dict] = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            if rec.get("type") == "meta":
                meta = rec
            elif rec.get("type") == "sample":
                samples.append(rec)
    return meta, samples


def summarize_one(jsonl: str, log: str | None) -> dict:
    meta, samples = load_jsonl(jsonl)
    stopped_windows = sum(1 for s in samples if s.get("stopped_pids", 0) > 0)
    total_dr = sum(s.get("delta_read_bytes", 0) for s in samples)
    total_dw = sum(s.get("delta_write_bytes", 0) for s in samples)
    total_scr = sum(s.get("delta_syscr", 0) for s in samples)
    total_scw = sum(s.get("delta_syscw", 0) for s in samples)
    total_nrx = sum(s.get("delta_net_rx", 0) for s in samples)
    total_ntx = sum(s.get("delta_net_tx", 0) for s in samples)
    rmse = parse_rmse_from_log(log) if log else None
    return {
        "benchmark": meta.get("benchmark", "?"),
        "target": meta.get("target", "?"),
        "samples": len(samples),
        "windows_with_sigstop": stopped_windows,
        "total_delta_read_bytes": total_dr,
        "total_delta_write_bytes": total_dw,
        "total_delta_syscr": total_scr,
        "total_delta_syscw": total_scw,
        "total_delta_net_rx": total_nrx,
        "total_delta_net_tx": total_ntx,
        "rmse_pct": rmse,
        "jsonl": jsonl,
        "log": log or "",
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("results_dir", nargs="?", default=os.path.join(EVAL, "results"))
    ap.add_argument("-o", "--csv", default="")
    args = ap.parse_args()
    rdir = args.results_dir

    rows = []
    for bench in ("social", "hotel", "movie", "boutique"):
        jsonl = os.path.join(rdir, f"{bench}_ebpf_L2_residual.jsonl")
        log = os.path.join(rdir, f"{bench}_ebpf_L2_medium.log")
        if os.path.isfile(jsonl):
            rows.append(summarize_one(jsonl, log if os.path.isfile(log) else None))

    if not rows:
        print(f"No *_ebpf_L2_residual.jsonl in {rdir}", file=sys.stderr)
        return 1

    print("Phase 4 — residual I/O during SIGSTOP (L2 runs)")
    print(f"results: {rdir}\n")
    hdr = (
        f"{'App':<10} {'Target':<14} {'SIGSTOP wins':>12} {'Δ read B':>12} {'Δ write B':>12} "
        f"{'Δ syscr':>10} {'Δ net rx':>12} {'RMSE%':>8}"
    )
    print(hdr)
    print("-" * len(hdr))
    for r in rows:
        rmse = f"{r['rmse_pct']:.2f}" if r["rmse_pct"] is not None else "—"
        print(
            f"{r['benchmark']:<10} {r['target']:<14} {r['windows_with_sigstop']:>12} "
            f"{r['total_delta_read_bytes']:>12} {r['total_delta_write_bytes']:>12} "
            f"{r['total_delta_syscr']:>10} {r['total_delta_net_rx']:>12} {rmse:>8}"
        )

    if args.csv:
        os.makedirs(os.path.dirname(os.path.abspath(args.csv)) or ".", exist_ok=True)
        with open(args.csv, "w", newline="", encoding="utf-8") as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
            w.writeheader()
            w.writerows(rows)
        print(f"\nWrote {args.csv}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
