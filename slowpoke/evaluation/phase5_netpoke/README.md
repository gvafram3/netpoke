# Phase 5 — NetPoke implementation

Design: `netpoke/design/poker-io-pause.md`

## What was added

| File | Role |
|------|------|
| `slowpoke/src/poker/net_hold.c` | `sch_plug` netlink helper |
| `slowpoke/src/poker/net_hold.h` | API |
| `slowpoke/src/poker/poker.c` | `net_hold()` before SIGSTOP, `net_release()` after SIGCONT |
| `slowpoke/app/slowpoke/poker/*` | Docker build copy (run `sync_to_app.sh` after edits) |

Runtime control:

- `SLOWPOKE_NETPOKE=1` — enable egress hold
- `SLOWPOKE_NET_IFACE=eth0` — interface (default `eth0`)

Without `SLOWPOKE_NETPOKE=1`, poker behaves like stock SlowPoke (A/B with same binary).

## Cluster steps (netpoke-control)

### 1. Sync code to VM

From Cloud Shell (after `git pull` on `netpoke/experiments`):

```bash
gcloud compute scp --recurse netpoke/slowpoke/src/poker netpoke-control:~/slowpoke/src/ --zone=us-central1-a
gcloud compute scp --recurse netpoke/slowpoke/evaluation/phase5_netpoke netpoke-control:~/slowpoke/evaluation/ --zone=us-central1-a
```

### 2. Confirm kernel support (no rebuild)

Fastest — no boutique deploy:

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation
bash phase5_netpoke/test_sch_plug.sh --netshoot
```

Or against a real SlowPoke pod (namespace **default**, not `boutique`):

```bash
bash phase5_netpoke/deploy_smoke_pod.sh shipping
bash phase5_netpoke/test_sch_plug.sh shipping
```

### 3. Rebuild & push images

On a machine with Docker (build context `slowpoke/app`):

```bash
cd slowpoke/app
bash ../src/poker/sync_to_app.sh
docker build --build-arg BENCHMARK=boutique -f ../scripts/build/PrebuiltDockerfile . -t YOUR_REGISTRY/boutique-pokerpp-netpoke
# repeat for social, hotel, movie; push; update YAML image tags
```

### 4. Patch YAMLs for NET_ADMIN

```bash
python3 phase5_netpoke/patch_netpoke_caps.py boutique/yamls/shipping.yaml boutique/yamls/shipping_netpoke.yaml
kubectl apply -f boutique/yamls/shipping_netpoke.yaml
```

Or patch all poker deployments before Phase 6 matrix.

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
