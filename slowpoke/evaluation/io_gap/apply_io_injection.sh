#!/usr/bin/env bash
# Apply netem sidecar yamls for benchmark × level (fixed -x target, path I/O only).
set -euo pipefail

export SLOWPOKE_TOP="${SLOWPOKE_TOP:-$HOME/slowpoke}"
IO_GAP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=io_levels.conf
source "$IO_GAP/io_levels.conf"

BENCH="${1:?benchmark}"
LEVEL="${2:?L1 or L2}"

var="IO_${BENCH^^}_${LEVEL}_INJECT"
INJECT="${!var:-}"
if [[ -z "$INJECT" ]]; then
  echo "[io_gap] no injection configured for $BENCH $LEVEL"
  exit 0
fi

STAMP="$IO_GAP/.io_injection_active"
YAML_DIR="$SLOWPOKE_TOP/evaluation/$BENCH/yamls"

resolve_yaml_file() {
  local bench="$1" svc="$2"
  case "$bench:$svc" in
    boutique:shipping) echo shipping.yaml ;;
    hotel:rate) echo rate.yaml ;;
    hotel:user) echo user.yaml ;;
    social:poststorage) echo post_storage.yaml ;;
    social:socialgraph) echo social_graph.yaml ;;
    movie:reviewstorage) echo review_storage.yaml ;;
    movie:movieinfo) echo movie_info.yaml ;;
    *)
      echo "ERROR: unknown service $svc for $bench" >&2
      return 1
      ;;
  esac
}

IFS=',' read -ra PAIRS <<< "$INJECT"
for pair in "${PAIRS[@]}"; do
  svc="${pair%%:*}"
  delay="${pair##*:}"
  yfile=$(resolve_yaml_file "$BENCH" "$svc")
  base="$YAML_DIR/$yfile"
  if [[ ! -f "$base" ]]; then
    echo "ERROR: missing $base" >&2
    exit 1
  fi
  if grep -q 'tc-netem-sidecar' "$base" 2>/dev/null; then
    echo "[io_gap] WARN: $base already has netem sidecar — restore first"
    bash "$IO_GAP/restore_io_injection.sh"
  fi
  bak="$YAML_DIR/${yfile}.io_l0bak"
  cp -a "$base" "$bak"
  python3 "$IO_GAP/patch_netem_yaml.py" "$base" "$base" "$delay" "${BENCH}-${LEVEL}-${svc}"
  echo "${BENCH}/${yfile}|${bak}" >>"$STAMP"
  echo "[io_gap] $BENCH $LEVEL: ${svc} netem ${delay}ms → $yfile"
done

date -Is >>"$STAMP"
