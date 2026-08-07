#!/usr/bin/env bash
# Generic Phase 3 runner: one benchmark × I/O level → one *_io_L*_medium.log
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
if [[ ! -f "$SLOWPOKE_TOP/src/main.py" ]]; then
  echo "ERROR: SLOWPOKE_TOP=$SLOWPOKE_TOP is invalid (no src/main.py)" >&2
  exit 1
fi

IO_GAP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVAL_DIR="$(cd "$IO_GAP_DIR/.." && pwd)"
# shellcheck source=io_levels.conf
source "$IO_GAP_DIR/io_levels.conf"

usage() {
  cat <<'EOF'
Usage: run_io_medium.sh <benchmark> <level> <outfile>

  benchmark : boutique | hotel | social | movie
  level     : L1 | L2   (L0 = standard run-*-medium.sh baseline)
  outfile   : e.g. results/boutique_io_L1_medium.log

Examples:
  ./io_gap/run_io_medium.sh boutique L1 results/boutique_io_L1_medium.log
  ./io_gap/run_io_medium.sh hotel L2 results/hotel_io_L2_medium.log

Environment:
  SLOWPOKE_TOP          SlowPoke tree (default ~/slowpoke)
  SLOWPOKE_IO_GAP_LEVEL echoed into the log (set automatically)
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

BENCH="${1:?benchmark required (boutique|hotel|social|movie)}"
LEVEL="${2:?level required (L1|L2)}"
OUTFILE="${3:?outfile required}"

if [[ "$OUTFILE" == //* ]]; then
  echo "ERROR: outfile path starts with // — RESULTS_DIR was empty when the caller built this path." >&2
  echo "  Fix: export REP=rep2; export RESULTS_DIR=~/slowpoke/evaluation/results/\$REP" >&2
  exit 1
fi

case "$LEVEL" in
  L1|L2) ;;
  *)
    echo "ERROR: level must be L1 or L2 (L0 uses run-*-medium.sh)" >&2
    exit 1
    ;;
esac

case "$BENCH" in
  boutique|hotel|social|movie) ;;
  *)
    echo "ERROR: unknown benchmark '$BENCH'" >&2
    exit 1
    ;;
esac

var="IO_${BENCH^^}_${LEVEL}_TARGET"
TARGET="${!var:-}"
if [[ -z "$TARGET" ]]; then
  echo "ERROR: no target configured for $BENCH $LEVEL ($var)" >&2
  exit 1
fi

var_req="IO_NUM_REQ_${BENCH^^}"
NUM_REQ="${!var_req:-100000}"

OUTDIR="$(dirname "$OUTFILE")"
mkdir -p "$OUTDIR"
OUTFILE="$(cd "$OUTDIR" && pwd)/$(basename "$OUTFILE")"

if [[ -f "$OUTFILE" ]] && grep -q 'Error Perc:' "$OUTFILE"; then
  echo "WARNING: $OUTFILE already complete — refusing to truncate." >&2
  echo "  Backup first: cp -a $OUTFILE results/saved/$(basename "$OUTFILE").bak" >&2
  exit 2
fi

export SLOWPOKE_IO_GAP_LEVEL="$LEVEL"
export SLOWPOKE_IO_GAP_BENCHMARK="$BENCH"
export SLOWPOKE_IO_GAP_TARGET="$TARGET"

var_inject="IO_${BENCH^^}_${LEVEL}_INJECT"
INJECT="${!var_inject:-}"

RESTORE_IO=0
if [[ -n "$INJECT" ]]; then
  bash "$IO_GAP_DIR/apply_io_injection.sh" "$BENCH" "$LEVEL"
  RESTORE_IO=1
fi

cleanup() {
  if (( RESTORE_IO )); then
    bash "$IO_GAP_DIR/restore_io_injection.sh" || true
  fi
}
trap cleanup EXIT

{
  echo "# io_gap run: benchmark=$BENCH level=$LEVEL target=$TARGET inject=${INJECT:-none}"
  echo "# started: $(date -Is)"
  echo "# SLOWPOKE_TOP=$SLOWPOKE_TOP"
} >"$OUTFILE"

cd "$EVAL_DIR"
bash "$SLOWPOKE_TOP/evaluation/safe_delete_workloads.sh"

python3 -u "$SLOWPOKE_TOP/src/main.py" \
  -b "$BENCH" -r mix -x "$TARGET" \
  --num_exp "$IO_NUM_EXP" \
  -t "$IO_THREAD" -c "$IO_CONN" \
  --poker_batch_req "$IO_POKER_BATCH_REQ" \
  --repetitions "$IO_REPETITIONS" \
  --num_req "$NUM_REQ" >>"$OUTFILE"

echo "# finished: $(date -Is)" >>"$OUTFILE"
