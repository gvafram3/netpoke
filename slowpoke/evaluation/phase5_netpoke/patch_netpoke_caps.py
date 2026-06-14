#!/usr/bin/env python3
"""Add NET_ADMIN + SLOWPOKE_NETPOKE=1 to a SlowPoke service deployment yaml."""
import sys
from pathlib import Path


def patch(src: Path, dst: Path) -> None:
    text = src.read_text()
    if "SLOWPOKE_NETPOKE" in text and "NET_ADMIN" in text:
        dst.write_text(text)
        return

    if "          env:" not in text:
        raise SystemExit(f"Could not find env block in {src}")

    env_patch = '''            - name: SLOWPOKE_NETPOKE
              value: "1"
            - name: SLOWPOKE_NET_IFACE
              value: "eth0"
'''
    text = text.replace("          env:\n", "          env:\n" + env_patch, 1)

    cap_block = '''          securityContext:
            capabilities:
              add:
                - NET_ADMIN
'''
    marker = "          ports:"
    if marker not in text:
        raise SystemExit(f"Could not find ports marker in {src}")
    text = text.replace(marker, cap_block + marker, 1)

    dst.write_text(text)


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit(f"usage: {sys.argv[0]} SRC_YAML DST_YAML")
    patch(Path(sys.argv[1]), Path(sys.argv[2]))
