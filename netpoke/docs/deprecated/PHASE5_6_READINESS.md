# Phase 5–6 readiness (start immediately after Phase 4 boutique completes)

**Prerequisite:** All four `*_ebpf_L2_medium.log` complete (21 throughput lines + `Error Perc:`).

---

## Step 0 — Close Phase 4 (same day as boutique)

```bash
export SLOWPOKE_TOP=~/slowpoke
cd ~/slowpoke/evaluation
bash phase4_ebpf/finalize_phase4_results.sh
```

Download `~/netpoke_presentation_pack_*.tar.gz` → commit to `netpoke/results/cluster/`.

Update [`TABLE_EBPF_SUMMARY.md`](../results/cluster/ebpf/tables/TABLE_EBPF_SUMMARY.md) boutique row from CSV.

---

## Step 1 — Phase 5: Implement NetPoke (O3 / RQ3)

**Design:** [`design/poker-io-pause.md`](../design/poker-io-pause.md)

| Task | Detail | Pass |
|------|--------|------|
| 1 | Confirm `sch_plug` in pod: `tc qdisc add dev eth0 root plug limit 1000` | succeeds in movie/boutique pod |
| 2 | Add `net_hold.c` / netlink helper | `net_hold()` / `net_release()` |
| 3 | Wrap `SIGSTOP`/`SIGCONT` in `slowpoke/src/poker/poker.c` | NET_HOLD before STOP, NET_RELEASE after CONT |
| 4 | Build flag | `SLOWPOKE_NETPOKE=1` or compile-time `-DNETPOKE` |
| 5 | Container | `NET_ADMIN` on POKER image; rebuild & push images |
| 6 | Smoke | Hold/release without full benchmark |

**Files to touch:**

- `slowpoke/src/poker/poker.c`
- `slowpoke/src/poker/net_hold.c` (new)
- POKER Dockerfile / k8s YAML caps

---

## Step 2 — Phase 5 validation (mechanistic, fast)

Re-run **one** app with sampler + NetPoke on (social L2 recommended):

```bash
export SLOWPOKE_NETPOKE=1
bash phase4_ebpf/run_ebpf_one_L2.sh social   # after adapting script to honor NETPOKE
```

**Success:** Δ net rx during pause windows **drops toward zero** vs Phase 4 SIGSTOP-only row for social.

---

## Step 3 — Phase 6: Full evaluation matrix (O4 / RQ4)

Re-run **L2 only** for all four apps with NetPoke:

| App | Script pattern | Log name |
|-----|----------------|----------|
| Each | `SLOWPOKE_NETPOKE=1 bash io_gap/run_io_medium.sh <app> L2 results/<app>_io_L2_netpoke_medium.log` | new logs |

**Comparison table (thesis headline T N1):**

| App | L0 RMSE | L2 SIGSTOP (Phase 3) | L2 NetPoke (Phase 6) | Δ toward L0? |
|-----|---------|----------------------|----------------------|--------------|
| Social | 10.34% | 24.64% | *TBD* | target ↓ |
| Hotel | 10.23% | 16.28% | *TBD* | target ↓ |
| Movie | 13.97% | 16.72% | *TBD* | target ↓ |
| Boutique | 9.19% | 5.61% | *TBD* | no regression |

**Success criterion:** L2 NetPoke RMSE moves **toward L0** on social/hotel/movie; L0 with NetPoke **unchanged** (no regression).

**Fig N1:** Grouped bar — Phase 3 L2 vs Phase 6 L2 NetPoke (extend `plot_io_gap_rmse.py` or new `plot_netpoke_comparison.py`).

---

## Step 4 — Experiment order (recommended)

1. `sch_plug` pod smoke test (1 hour)  
2. Social L2 + NetPoke + sampler (~1 h) — mechanistic proof  
3. Social L2 full NetPoke eval (~1 h)  
4. Hotel → movie → boutique L2 NetPoke (~3 h)  
5. Optional: L0 spot-check one app with NetPoke (regression)  

Total Phase 5–6: **~2–3 days** cluster time (similar to Phase 3 suite).

---

## Step 5 — Branch & sync discipline

- Experiment branch: **`netpoke/experiments`**
- Sync VM: Cloud Shell `git pull` + `gcloud compute scp` (never curl raw GitHub)
- After Phase 6: `bash scripts/build_presentation_pack.sh` → add `netpoke/` folder to pack for Phase 6 figures

---

## Scripts to add in Phase 5–6 (planned)

| Script | Purpose |
|--------|---------|
| `phase6_netpoke/run_netpoke_one_L2.sh` | One app L2 with `SLOWPOKE_NETPOKE=1` |
| `phase6_netpoke/run_netpoke_all_L2.sh` | Full 4-app matrix |
| `phase6_netpoke/plot_netpoke_comparison.py` | Fig N1 before/after bars |
| `phase6_netpoke/summarize_netpoke_matrix.py` | Table N1 CSV |

Create these when `net_hold.c` is merged — do not block Phase 4 finalize.

---

## Immediate next action (you, now)

1. Wait for boutique `21/21` + `Error Perc:`  
2. Run `finalize_phase4_results.sh`  
3. Download presentation pack  
4. Start `sch_plug` test in a boutique pod while reading `poker-io-pause.md`  

See also [`figures-and-tables-master.md`](figures-and-tables-master.md).
