#!/bin/sh
# In-pod residual I/O sampler (Phase 6, corrected instrument -- replaces the
# deprecated kubectl-exec-per-sample sampler; see finding F2 in
# netpoke/docs/METHODOLOGY_CRITIQUE_AND_FIX_PLAN.md).
#
# Runs entirely inside the container: one `kubectl exec` starts it as a
# background process, one `kubectl exec ... cat` retrieves the output file
# at the end. No kubectl round-trip per sample, so the interval below is a
# real interval, not an aspirational one defeated by API-server latency.
#
# Each line of the output is one JSON sample:
#   {"ts":<seconds since pod boot>,"rx":<bytes>,"tx":<bytes>,"procs":[{"pid":N,"comm":"x","state":"S","rb":N,"wb":N},...]}
#
# ts is directly comparable to the "uptime_s" field POKER now logs on every
# hold/release (see net_hold.c) -- both are seconds since the same
# underlying kernel boot clock (CLOCK_MONOTONIC / /proc/uptime), so a
# separate analysis pass can line samples up against real pause windows.
#
# Usage (inside the container, normally launched via a backgrounded kubectl exec):
#   residual_sampler_inpod.sh <interval_seconds> <output_file> <iface>
set -u

INTERVAL="${1:-0.01}"
OUT="${2:-/tmp/netpoke_residual.jsonl}"
IFACE="${3:-eth0}"
SELF_PID=$$

: > "$OUT"

while :; do
  ts=$(awk '{print $1}' /proc/uptime 2>/dev/null)
  rxtx=$(awk -F: -v ifc="$IFACE:" '$0 ~ ifc {print $2}' /proc/net/dev 2>/dev/null | awk '{print $1, $9}')
  rx=${rxtx%% *}
  tx=${rxtx##* }
  [ -n "$rx" ] || rx=0
  [ -n "$tx" ] || tx=0

  first=1
  {
    printf '{"ts":%s,"rx":%s,"tx":%s,"procs":[' "$ts" "$rx" "$tx"
    for statf in /proc/[0-9]*/stat; do
      pid=$(basename "$(dirname "$statf")")
      [ "$pid" = "$SELF_PID" ] && continue
      read -r _ comm state _ < "$statf" 2>/dev/null || continue
      rb=0
      wb=0
      if [ -r "/proc/$pid/io" ]; then
        while read -r key val; do
          case "$key" in
            read_bytes:) rb="$val" ;;
            write_bytes:) wb="$val" ;;
          esac
        done < "/proc/$pid/io" 2>/dev/null
      fi
      [ "$first" = 1 ] || printf ','
      first=0
      printf '{"pid":%s,"comm":"%s","state":"%s","rb":%s,"wb":%s}' "$pid" "$comm" "$state" "$rb" "$wb"
    done
    printf ']}\n'
  } >> "$OUT"

  sleep "$INTERVAL"
done
