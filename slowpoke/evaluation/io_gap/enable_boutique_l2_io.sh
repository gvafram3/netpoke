#!/usr/bin/env bash
# Deprecated: use apply_io_injection.sh (kept for backward compatibility).
set -euo pipefail
IO_GAP="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "$IO_GAP/apply_io_injection.sh" boutique L2
