# Phase 5 — NetPoke implementation

Design: `netpoke/design/poker-io-pause.md`

**Docker Hub:** `gvafram3/mucache` — tags `*-pokerpp-netpoke` (see `images.env`).

## What was added

| File | Role |
|------|------|
| `slowpoke/src/poker/net_hold.c` | `sch_plug` netlink helper |
| `slowpoke/src/poker/net_hold.h` | API |
| `slowpoke/src/poker/poker.c` | `net_hold()` before SIGSTOP, `net_release()` after SIGCONT |
| `phase5_netpoke/images.env` | Registry `gvafram3/mucache` |
| `phase5_netpoke/build_netpoke_images.sh` | Build/push all four benchmarks |

Runtime control:

- `SLOWPOKE_NETPOKE=1` — enable egress hold
- `SLOWPOKE_NET_IFACE=eth0` — interface (default `eth0`)

Without `SLOWPOKE_NETPOKE=1`, poker behaves like stock SlowPoke (A/B with same binary).

## Cluster steps (netpoke-control)

### 1. Sync code to VM

From Cloud Shell (after `git pull` on `netpoke/experiments`):

```bash
gcloud compute scp --recurse slowpoke/src/poker netpoke-control:~/slowpoke/src/ --zone=us-central1-a
gcloud compute scp --recurse slowpoke/evaluation/phase5_netpoke netpoke-control:~/slowpoke/evaluation/ --zone=us-central1-a
```

### 2. Confirm kernel support (no rebuild)

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation
bash phase5_netpoke/test_sch_plug.sh --netshoot
```

### 3. Build & push images

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation

sudo docker login   # username: gvafram3

bash phase5_netpoke/build_netpoke_images.sh boutique
PUSH=1 bash phase5_netpoke/build_netpoke_images.sh boutique

# all four benchmarks when ready:
PUSH=1 bash phase5_netpoke/build_netpoke_images.sh all
```

Tags produced:

| Benchmark | Image |
|-----------|--------|
| boutique | `gvafram3/mucache:boutique-pokerpp-netpoke` |
| social | `gvafram3/mucache:social-pokerpp-netpoke` |
| hotel | `gvafram3/mucache:hotel-pokerpp-netpoke` |
| movie | `gvafram3/mucache:movie-pokerpp-netpoke` |

### 4. Patch YAMLs for NET_ADMIN + NetPoke image

```bash
bash phase5_netpoke/patch_all_netpoke_yamls.sh boutique
kubectl apply -f boutique/yamls/netpoke/shipping.yaml
```

Or one service:

```bash
python3 phase5_netpoke/patch_netpoke_caps.py \
  boutique/yamls/shipping.yaml boutique/yamls/netpoke/shipping.yaml boutique
kubectl apply -f boutique/yamls/netpoke/shipping.yaml
```

### 5. Mechanistic validation (Phase 5)

```bash
export SLOWPOKE_NETPOKE=1
bash phase4_ebpf/run_ebpf_one_L2.sh social   # after redeploy with new images
```

Expect Δ net rx during pauses → near zero vs Phase 4.

## Local compile (Linux)

```bash
cd slowpoke/src/poker
bash build_poker.sh
```
