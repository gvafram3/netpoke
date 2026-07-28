#!/usr/bin/env python3
"""Add NET_ADMIN, gvafram3 NetPoke image, and SLOWPOKE_NETPOKE to a deployment yaml.

Usage:
  patch_netpoke_caps.py SRC_YAML DST_YAML [benchmark]           # SLOWPOKE_NETPOKE=1 (netpoke/)
  patch_netpoke_caps.py SRC_YAML DST_YAML [benchmark] --sigstop # SLOWPOKE_NETPOKE=0 (netpoke-sigstop/)

Both variants use the same gvafram3 image and NET_ADMIN capability so the
pause-window markers (poker: pause_start/pause_end) are always present.
The only difference is whether the sch_plug egress hold is active.
"""
import re
import sys
from pathlib import Path

DOCKER_USER = "gvafram3"
DOCKER_REPO = "mucache"

# Upstream SlowPoke tags -> NetPoke tags for this thesis cluster.
IMAGE_MAP = {
    "boutique": (f"yizhengx/{DOCKER_REPO}:boutique-pokerpp", f"{DOCKER_USER}/{DOCKER_REPO}:boutique-pokerpp-netpoke"),
    "social": (f"yizhengx/{DOCKER_REPO}:social-pokerpp", f"{DOCKER_USER}/{DOCKER_REPO}:social-pokerpp-netpoke"),
    "hotel": (f"yizhengx/{DOCKER_REPO}:hotel-pokerpp", f"{DOCKER_USER}/{DOCKER_REPO}:hotel-pokerpp-netpoke"),
    "movie": (f"yizhengx/{DOCKER_REPO}:movie-pokerpp", f"{DOCKER_USER}/{DOCKER_REPO}:movie-pokerpp-netpoke"),
}


def strip_netem_sidecar(text: str) -> str:
    """Remove Phase 3 io_gap netem sidecar if present on the VM copy."""
    if "tc-netem-sidecar" not in text:
        return text
    return re.sub(
        r'\n        - name: "tc-netem-sidecar"\n.*?(?=\n      affinity:)',
        "\n",
        text,
        count=1,
        flags=re.DOTALL,
    )


def patch(src: Path, dst: Path, benchmark: str, sigstop: bool = False) -> None:
    netpoke_value = "0" if sigstop else "1"
    text = strip_netem_sidecar(src.read_text())

    old_img, new_img = IMAGE_MAP.get(benchmark, (None, None))
    if old_img and old_img in text:
        text = text.replace(old_img, new_img)
    elif new_img:
        text = re.sub(
            r"(image:\s*)yizhengx/mucache:[^\s]+",
            rf"\1{new_img}",
            text,
            count=1,
        )

    if "SLOWPOKE_NETPOKE" not in text:
        if "          env:" not in text:
            raise SystemExit(f"Could not find env block in {src}")
        env_patch = f'''            - name: SLOWPOKE_NETPOKE
              value: "{netpoke_value}"
            - name: SLOWPOKE_NET_IFACE
              value: "eth0"
'''
        text = text.replace("          env:\n", "          env:\n" + env_patch, 1)
    else:
        # Already present (e.g. re-patching a netpoke/ yaml into netpoke-sigstop/):
        # update the value in place rather than inserting a duplicate entry.
        text = re.sub(
            r'(- name: SLOWPOKE_NETPOKE\s*\n\s*value:\s*)"[^"]*"',
            rf'\1"{netpoke_value}"',
            text,
        )

    # NET_ADMIN must be on the poker container, not only on a removed netem sidecar.
    cap_block = '''          securityContext:
            capabilities:
              add:
                - NET_ADMIN
'''
    if not re.search(
        r"securityContext:\s*\n\s*capabilities:\s*\n\s*add:\s*\n\s*- NET_ADMIN\s*\n\s*ports:",
        text,
    ):
        marker = "          ports:"
        if marker not in text:
            raise SystemExit(f"Could not find ports marker in {src}")
        text = text.replace(marker, cap_block + marker, 1)

    dst.write_text(text)


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("-")]
    flags = [a for a in sys.argv[1:] if a.startswith("-")]
    if len(args) not in (2, 3):
        raise SystemExit(
            f"usage: {sys.argv[0]} SRC_YAML DST_YAML [benchmark] [--sigstop]"
        )
    bench = args[2] if len(args) == 3 else "boutique"
    patch(Path(args[0]), Path(args[1]), bench, sigstop="--sigstop" in flags)
