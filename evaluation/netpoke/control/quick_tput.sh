#!/bin/bash
# FAST calibration: throughput of the mutex app at chosen target processing times, NOTHING frozen (ground truth), ~2 min per point.
#   quick_tput.sh <yamls-dir> <p_t_us> [...]      e.g.  quick_tput.sh yamls-freeze 800 640 560 520 480 400      (SECS=20 sets the wrk duration)
# Saves FULL evidence for every point in ~/results/quick_tput/<time>_<yamls>/pt<p_t>/ : deploy log, client processes before the test,
# complete wrk output, pods afterwards (restarts), and both service logs - so a failed or 0 req/s point can be investigated directly.
YD="${1:?yamls dir}"; shift; SECS="${SECS:-20}"
OUT="$HOME/results/quick_tput/$(date +%Y%m%d_%H%M%S)_$YD"; mkdir -p "$OUT"
echo "yamls=$YD   (ground truth, no freezing)   wrk 8 threads, 512 connections, ${SECS}s   evidence: $OUT"
printf '%-10s %14s   %s\n' "TARGET us" "THROUGHPUT" "NOTES"
for pt in "$@"; do
  d="$OUT/pt$pt"; mkdir -p "$d"
  if ! MODE=truth "$HOME/kit/control/manual_point.sh" "$YD" "$pt" > "$d/deploy.log" 2>&1; then
    printf '%-10s %14s   %s\n' "$pt" "FAILED" "deploy failed - see $d/deploy.log"; tail -n 6 "$d/deploy.log" | sed 's/^/     /'; continue; fi
  CL=$(kubectl get pod -o name | grep ubuntu-client | head -1)
  kubectl exec "$CL" -- sh -c 'for p in /proc/[0-9]*; do c=$(tr "\0" " " < $p/cmdline 2>/dev/null); [ -n "$c" ] && echo "${p#/proc/} $c"; done' > "$d/client_procs_before.txt" 2>&1
  kubectl exec "$CL" -- /wrk/wrk -t8 -c512 --timeout 20s -d"${SECS}"s -L http://service1:80/ > "$d/wrk.txt" 2>&1
  kubectl get pods -o wide > "$d/pods_after.txt" 2>&1
  for s in service1 service2; do kubectl logs deploy/$s --tail=40 > "$d/${s}_log.txt" 2>&1; done
  rps=$(awk '/Requests\/sec:/{print $2}' "$d/wrk.txt"); note=$(grep -E "Non-2xx|Socket errors" "$d/wrk.txt" | tr '\n' ' ')
  [ -z "$rps" ] && note="no Requests/sec line: $(head -c 120 "$d/wrk.txt" | tr '\n' ' ')"
  n=$(grep -c "wrk" "$d/client_procs_before.txt"); [ "${n:-0}" -gt 0 ] && note="$note  [WARNING: $n wrk process(es) already running in the client before the test]"
  printf '%-10s %11s req/s   %s\n' "$pt" "${rps:-FAILED}" "$note"
done
echo "evidence saved in $OUT"
