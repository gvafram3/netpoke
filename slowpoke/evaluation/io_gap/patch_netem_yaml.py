#!/usr/bin/env python3
"""Insert tc netem sidecar container into a SlowPoke service deployment yaml."""
import sys
from pathlib import Path


def patch(src: Path, dst: Path, delay_ms: int, tag: str) -> None:
    text = src.read_text()
    if "tc-netem-sidecar" in text:
        dst.write_text(text)
        return
    sidecar = f'''        - name: "tc-netem-sidecar"
          image: nicolaka/netshoot:latest
          command:
            - /bin/sh
            - -c
            - |
              echo "[io_gap {tag}] tc netem {delay_ms}ms on eth0"
              sleep 5
              tc qdisc add dev eth0 root netem delay {delay_ms}ms
              while true; do sleep 60; done
          securityContext:
            capabilities:
              add:
                - NET_ADMIN
          imagePullPolicy: Always
'''
    marker = "      affinity:"
    if marker not in text:
        raise SystemExit(f"Could not find deployment affinity marker in {src}")
    out = text.replace(marker, sidecar + marker, 1)
    dst.write_text(out)


if __name__ == "__main__":
    if len(sys.argv) != 5:
        raise SystemExit(f"usage: {sys.argv[0]} SRC DST DELAY_MS TAG")
    patch(Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]), sys.argv[4])
