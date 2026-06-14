#!/usr/bin/env python3
"""Add NET_ADMIN, SLOWPOKE_NETPOKE=1, and gvafram3 NetPoke image to a deployment yaml."""
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


def patch(src: Path, dst: Path, benchmark: str) -> None:
    text = src.read_text()

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
        env_patch = '''            - name: SLOWPOKE_NETPOKE
              value: "1"
            - name: SLOWPOKE_NET_IFACE
              value: "eth0"
'''
        text = text.replace("          env:\n", "          env:\n" + env_patch, 1)

    if "NET_ADMIN" not in text:
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
    if len(sys.argv) not in (3, 4):
        raise SystemExit(f"usage: {sys.argv[0]} SRC_YAML DST_YAML [benchmark]")
    bench = sys.argv[3] if len(sys.argv) == 4 else "boutique"
    patch(Path(sys.argv[1]), Path(sys.argv[2]), bench)
