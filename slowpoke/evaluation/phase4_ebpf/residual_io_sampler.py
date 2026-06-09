#!/usr/bin/env python3
"""
Sample residual I/O while service processes are in SIGSTOP (state T).

Runs on netpoke-control; uses kubectl exec into benchmark pods.
Writes JSONL: one record per sample window with bytes/syscalls delta during stopped state.

Optional: bpftrace on worker nodes (preflight checks); /proc polling works without it.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from typing import Any

PHASE4 = os.path.dirname(os.path.abspath(__file__))
EVAL = os.path.dirname(PHASE4)
IO_GAP = os.path.join(EVAL, "io_gap")


def sh(cmd: list[str], timeout: int = 60) -> str:
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if r.returncode != 0:
        raise RuntimeError(f"cmd failed ({r.returncode}): {' '.join(cmd)}\n{r.stderr.strip()}")
    return r.stdout


def sh_quiet(cmd: list[str], timeout: int = 30) -> tuple[int, str, str]:
    r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    return r.returncode, r.stdout, r.stderr


def load_target(bench: str) -> str:
    conf = os.path.join(IO_GAP, "io_levels.conf")
    key = f"IO_{bench.upper()}_L2_TARGET"
    with open(conf, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line.startswith(f"{key}="):
                return line.split("=", 1)[1].strip()
    raise KeyError(f"{key} not in io_levels.conf")


def k8s_app_label(service: str) -> str:
    """Map SlowPoke service name → Kubernetes app label."""
    m = {
        "product_catalog": "productcatalog",
        "productcatalog": "productcatalog",
        "post_storage": "poststorage",
        "poststorage": "poststorage",
        "social_graph": "socialgraph",
        "socialgraph": "socialgraph",
        "review_storage": "reviewstorage",
        "reviewstorage": "reviewstorage",
        "movie_info": "movieinfo",
        "movieinfo": "movieinfo",
        "hometimeline": "hometimeline",
        "moviereviews": "moviereviews",
    }
    return m.get(service, service.replace("_", ""))


def list_benchmark_pods(bench: str) -> dict[str, str]:
    """Return service_key → pod name for running benchmark pods."""
    out, _ = sh_quiet(["kubectl", "get", "pods", "-n", "default", "-o", "wide"], timeout=45)
    pods: dict[str, str] = {}
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) < 3 or parts[2] != "Running":
            continue
        name = parts[0]
        # pod names like cart-59dc846664-rvmfz
        svc = name.split("-")[0]
        pods[svc] = name
    return pods


def pod_container_name(pod: str) -> str:
    rc, out, _ = sh_quiet(
        ["kubectl", "get", "pod", "-n", "default", pod, "-o", "jsonpath={.spec.containers[0].name}"]
    )
    return out.strip() if rc == 0 and out.strip() else pod.split("-")[0]


def exec_in_pod(pod: str, container: str, script: str, timeout: int = 20) -> str:
    cmd = ["kubectl", "exec", "-n", "default", pod, "-c", container, "--", "sh", "-c", script]
    rc, out, err = sh_quiet(cmd, timeout=timeout)
    if rc != 0:
        raise RuntimeError(f"kubectl exec {pod}/{container}: {err.strip() or out.strip()}")
    return out


def sample_pod_procs(pod: str, container: str) -> list[dict[str, Any]]:
    """
    Return list of {pid, state, read_bytes, write_bytes, syscr, syscw} per process in pod.
    state 'T' = SIGSTOP stopped.
    """
    script = r"""
for statf in /proc/[0-9]*/stat; do
  pid=$(basename $(dirname $statf))
  state=$(awk '{print $3}' $statf 2>/dev/null)
  [ -z "$state" ] && continue
  rb=0; wb=0; sc=0; sw=0
  if [ -r /proc/$pid/io ]; then
    rb=$(awk '/^read_bytes:/{print $2}' /proc/$pid/io)
    wb=$(awk '/^write_bytes:/{print $2}' /proc/$pid/io)
    sc=$(awk '/^syscr:/{print $2}' /proc/$pid/io)
    sw=$(awk '/^syscw/{print $2}' /proc/$pid/io)
  fi
  echo "$pid $state $rb $wb $sc $sw"
done
"""
    try:
        out = exec_in_pod(pod, container, script)
    except RuntimeError:
        return []
    rows = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) < 6:
            continue
        rows.append(
            {
                "pid": int(parts[0]),
                "state": parts[1],
                "read_bytes": int(parts[2]),
                "write_bytes": int(parts[3]),
                "syscr": int(parts[4]),
                "syscw": int(parts[5]),
            }
        )
    return rows


def read_net_dev(pod: str, container: str) -> tuple[int, int]:
    script = r"""
awk 'NR>2 {rx+=$2; tx+=$10} END {print rx, tx}' /proc/net/dev 2>/dev/null || echo 0 0
"""
    try:
        out = exec_in_pod(pod, container, script, timeout=15)
        a, b = out.strip().split()[:2]
        return int(a), int(b)
    except (RuntimeError, ValueError):
        return 0, 0


def main_py_running() -> bool:
    rc, _, _ = sh_quiet(["pgrep", "-f", r"python3.*main\.py"])
    return rc == 0


def parse_services_arg(s: str) -> list[str]:
    return [x.strip() for x in s.split(",") if x.strip()]


def main() -> int:
    ap = argparse.ArgumentParser(description="Residual I/O sampler during SIGSTOP (state T)")
    ap.add_argument("-b", "--benchmark", required=True)
    ap.add_argument("-x", "--target", default="", help="target service (default from io_levels L2)")
    ap.add_argument("-o", "--output", required=True, help="JSONL output path")
    ap.add_argument("--interval", type=float, default=0.2, help="sample period seconds")
    ap.add_argument("--services", default="", help="comma-separated k8s svc prefixes to watch (default: all pods)")
    ap.add_argument("--wait-main", action="store_true", help="wait for main.py before sampling")
    ap.add_argument("--max-seconds", type=int, default=0, help="stop after N seconds (0 = until main.py exits)")
    args = ap.parse_args()

    target = args.target or load_target(args.benchmark)
    os.makedirs(os.path.dirname(os.path.abspath(args.output)) or ".", exist_ok=True)

    meta = {
        "type": "meta",
        "ts": datetime.now(timezone.utc).isoformat(),
        "benchmark": args.benchmark,
        "target": target,
        "interval_s": args.interval,
        "method": "proc_stat_T_plus_io",
    }
    with open(args.output, "w", encoding="utf-8") as fout:
        fout.write(json.dumps(meta) + "\n")

    if args.wait_main:
        print("[ebpf_sampler] waiting for main.py...", flush=True)
        for _ in range(600):
            if main_py_running():
                break
            time.sleep(1)
        else:
            print("[ebpf_sampler] timeout waiting for main.py", file=sys.stderr)
            return 1

    print(f"[ebpf_sampler] sampling -> {args.output}", flush=True)
    t0 = time.time()
    prev: dict[str, dict] = {}

    while True:
        if args.max_seconds and (time.time() - t0) > args.max_seconds:
            break
        if not args.max_seconds and args.wait_main and not main_py_running():
            if time.time() - t0 > 5:
                break

        pods = list_benchmark_pods(args.benchmark)
        if args.services:
            want = {k8s_app_label(s) for s in parse_services_arg(args.services)}
            pods = {k: v for k, v in pods.items() if k in want}

        sample_ts = datetime.now(timezone.utc).isoformat()
        stopped_pids = 0
        delta_read = 0
        delta_write = 0
        delta_syscr = 0
        delta_syscw = 0
        delta_net_rx = 0
        delta_net_tx = 0
        per_svc: dict[str, Any] = {}

        for svc, pod in sorted(pods.items()):
            if svc == k8s_app_label(target):
                continue
            ctr = pod_container_name(pod)
            try:
                procs = sample_pod_procs(pod, ctr)
                nrx, ntx = read_net_dev(pod, ctr)
            except RuntimeError as e:
                per_svc[svc] = {"error": str(e)}
                continue

            svc_stopped = 0
            svc_dr = svc_dw = svc_scr = svc_scw = 0
            key = f"{svc}:{pod}"
            cur_io = sum(p["read_bytes"] + p["write_bytes"] for p in procs)
            pmap = prev.get(key, {"io": cur_io, "nrx": nrx, "ntx": ntx, "procs": {}})

            for p in procs:
                if p["state"] == "T":
                    svc_stopped += 1
                    stopped_pids += 1
                    pk = str(p["pid"])
                    old = pmap["procs"].get(pk, p)
                    svc_dr += max(0, p["read_bytes"] - old.get("read_bytes", p["read_bytes"]))
                    svc_dw += max(0, p["write_bytes"] - old.get("write_bytes", p["write_bytes"]))
                    svc_scr += max(0, p["syscr"] - old.get("syscr", p["syscr"]))
                    svc_scw += max(0, p["syscw"] - old.get("syscw", p["syscw"]))
                pmap["procs"][str(p["pid"])] = p

            svc_drx = max(0, nrx - pmap.get("nrx", nrx))
            svc_dtx = max(0, ntx - pmap.get("ntx", ntx))
            pmap["nrx"], pmap["ntx"] = nrx, ntx
            prev[key] = pmap

            delta_read += svc_dr
            delta_write += svc_dw
            delta_syscr += svc_scr
            delta_syscw += svc_scw
            delta_net_rx += svc_drx
            delta_net_tx += svc_dtx
            if svc_stopped or svc_dr or svc_dw:
                per_svc[svc] = {
                    "stopped_pids": svc_stopped,
                    "delta_read_bytes": svc_dr,
                    "delta_write_bytes": svc_dw,
                    "delta_syscr": svc_scr,
                    "delta_syscw": svc_scw,
                    "delta_net_rx": svc_drx,
                    "delta_net_tx": svc_dtx,
                }

        rec = {
            "type": "sample",
            "ts": sample_ts,
            "elapsed_s": round(time.time() - t0, 3),
            "main_py_running": main_py_running(),
            "stopped_pids": stopped_pids,
            "delta_read_bytes": delta_read,
            "delta_write_bytes": delta_write,
            "delta_syscr": delta_syscr,
            "delta_syscw": delta_syscw,
            "delta_net_rx": delta_net_rx,
            "delta_net_tx": delta_net_tx,
            "services": per_svc,
        }
        with open(args.output, "a", encoding="utf-8") as fout:
            fout.write(json.dumps(rec) + "\n")

        time.sleep(args.interval)

    print(f"[ebpf_sampler] done ({time.time() - t0:.1f}s)", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
