#!/usr/bin/env bash
# Live residual-I/O sampler stats (third SSH) — refreshes every WATCH_INTERVAL seconds.
#
#   export SLOWPOKE_TOP=~/slowpoke
#   export SLOWPOKE_EBPF_JSONL=~/slowpoke/evaluation/results/social_ebpf_L2_netpoke_residual.jsonl
#   cd ~/slowpoke/evaluation
#   WATCH_INTERVAL=10 ./phase4_ebpf/watch_ebpf_jsonl.sh --append
#
# Auto-pick jsonl from SLOWPOKE_ACTIVE_LOG or newest *_netpoke_residual.jsonl:
#   export SLOWPOKE_ACTIVE_LOG=~/slowpoke/evaluation/results/social_ebpf_L2_netpoke_medium.log
#   ./phase4_ebpf/watch_ebpf_jsonl.sh --append
#
set -u

EVAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$EVAL_DIR/results}"
INTERVAL="${WATCH_INTERVAL:-10}"
JSONL="${SLOWPOKE_EBPF_JSONL:-}"
MODE="append"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --once) MODE=once; shift ;;
    --append) MODE=append; shift ;;
    --fullscreen) MODE=fullscreen; shift ;;
    -h|--help)
      sed -n '2,14p' "$0"
      exit 0
      ;;
    *)
      if [[ -f "$1" ]]; then
        JSONL="$1"
      elif [[ -d "$1" ]]; then
        RESULTS_DIR="$1"
      fi
      shift
      ;;
  esac
done

pick_jsonl() {
  if [[ -n "$JSONL" && -f "$JSONL" ]]; then
    echo "$JSONL"
    return
  fi
  if [[ -n "${SLOWPOKE_ACTIVE_LOG:-}" ]]; then
    local derived="${SLOWPOKE_ACTIVE_LOG/_medium.log/_residual.jsonl}"
    if [[ -f "$derived" ]]; then
      echo "$derived"
      return
    fi
  fi
  local newest
  newest=$(ls -t "$RESULTS_DIR"/*_ebpf_L2_netpoke_residual.jsonl 2>/dev/null | head -1 || true)
  if [[ -n "$newest" && -f "$newest" ]]; then
    echo "$newest"
    return
  fi
  newest=$(ls -t "$RESULTS_DIR"/*_ebpf_L2_residual.jsonl 2>/dev/null | head -1 || true)
  if [[ -n "$newest" && -f "$newest" ]]; then
    echo "$newest"
    return
  fi
  echo ""
}

print_block() {
  local path
  path=$(pick_jsonl)
  echo "======== $(date '+%Y-%m-%d %H:%M:%S') ========"
  echo "── eBPF sampler $(date '+%H:%M:%S') ──"
  if [[ -z "$path" ]]; then
    echo "JSONL: (none yet — waiting for sampler to create file)"
    echo "  hint: export SLOWPOKE_EBPF_JSONL=.../social_ebpf_L2_netpoke_residual.jsonl"
    echo ""
    echo "Refresh every ${INTERVAL}s · Ctrl+C to stop"
    return
  fi
  echo "JSONL: $path"
  if [[ -f "$path" ]]; then
    ls -lh "$path" | awk '{print "size: " $5 "  mtime: " $6 " " $7 " " $8}'
    python3 - "$path" <<'PY'
import json, sys
path = sys.argv[1]
meta = {}
samples = 0
stopped = 0
nrx = ntx = scr = 0
try:
    with open(path, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            rec = json.loads(line)
            if rec.get("type") == "meta":
                meta = rec
            elif rec.get("type") == "sample":
                samples += 1
                if rec.get("stopped_pids", 0) > 0:
                    stopped += 1
                nrx += rec.get("delta_net_rx", 0)
                ntx += rec.get("delta_net_tx", 0)
                scr += rec.get("delta_syscr", 0)
except FileNotFoundError:
    print("  (file not found)")
    sys.exit(0)
except json.JSONDecodeError as e:
    print(f"  (partial write — retry next refresh: {e})")
    sys.exit(0)
bench = meta.get("benchmark", "?")
target = meta.get("target", "?")
print(f"benchmark: {bench}  target: {target}")
print(f"sample lines: {samples}   with_state_T (SIGSTOP windows): {stopped}")
print(f"Δ net rx (paused windows): {nrx:,} B   Δ net tx: {ntx:,} B   Δ syscr: {scr:,}")
if stopped == 0 and samples > 20:
    print("WARN: samples>0 but with_state_T=0 — sampler may not be catching pauses")
elif stopped > 0:
    print("OK: sampler seeing SIGSTOP windows")
PY
  else
    echo "  (file not created yet)"
  fi
  echo ""
  echo "Refresh every ${INTERVAL}s · Ctrl+C to stop · set SLOWPOKE_EBPF_JSONL to override"
}

case "$MODE" in
  once) print_block ;;
  append)
    echo "[ebpf-jsonl] Append mode — new snapshot every ${INTERVAL}s (scroll up for history)."
    while true; do
      print_block
      echo ""
      sleep "$INTERVAL"
    done
    ;;
  fullscreen)
    while true; do
      clear
      print_block
      sleep "$INTERVAL"
    done
    ;;
esac
