#!/usr/bin/env bash
# Deprecated alias — use run_io_gap_all.sh (includes live monitor on SSH 1).
exec "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run_io_gap_all.sh" "$@"
