#!/usr/bin/env bash
# Phase 4 smoke test (~5–10 min): boutique L2 + residual sampler.
#
# On netpoke-control:
#   export SLOWPOKE_TOP=~/slowpoke
#   cd ~/slowpoke/evaluation
#   bash phase4_ebpf/preflight_ebpf.sh
#   bash phase4_ebpf/run_ebpf_smoke.sh
#
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
EVAL="$SLOWPOKE_TOP/evaluation"

bash "$EVAL/phase4_ebpf/preflight_ebpf.sh"
echo ""
echo "=== Phase 4 smoke: boutique L2 + residual I/O sampler ==="
bash "$EVAL/phase4_ebpf/run_ebpf_one_L2.sh" boutique smoke

RES="$EVAL/results/boutique_ebpf_L2_residual.jsonl"
echo ""
echo "Smoke output: $RES"
echo "Lines: $(wc -l <"$RES")"
echo "SIGSTOP windows:"
python3 - "$RES" <<'PY'
import json, sys
path = sys.argv[1]
stopped = 0
samples = 0
with open(path) as f:
    for line in f:
        r = json.loads(line)
        if r.get("type") != "sample":
            continue
        samples += 1
        if r.get("stopped_pids", 0) > 0:
            stopped += 1
print(f"  samples={samples}  with_state_T={stopped}")
if stopped == 0:
    print("  WARN: no SIGSTOP (state T) observed — check cluster load or re-run during active benchmark")
else:
    print("  PASS: sampler saw paused processes")
PY

echo ""
echo "Next: full suite in screen:"
echo "  screen -S phase4-ebpf"
echo "  WATCH_INTERVAL=10 ./phase4_ebpf/run_ebpf_all_L2.sh"
