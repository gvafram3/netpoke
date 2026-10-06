#!/bin/bash
# Install Docker + cri-dockerd + Kubernetes 1.29 on all nodes. The install RUNS ON EACH MACHINE BY ITSELF (detached),
# so a dropped internet connection on your PC does not stop it. This script only starts it and checks on it.
# Safe to re-run at any time: it never starts a second copy, and skips machines that already finished.
source "$(dirname "$0")/lib.sh"
mkdir -p "$KIT/logs"
echo "[02] starting the install on each machine (it continues even if your connection drops)"
for n in $NODES; do
  role=worker; [ "$n" = control ] && role=control
  st=$(ssh_run "$n" 'if grep -q "BOOTSTRAP OK" ~/bootstrap.log 2>/dev/null; then echo DONE;
                     elif pgrep -f "bash .*bootstrap_node[.]sh" >/dev/null; then echo RUNNING; else echo START; fi' | tr -d '\r' | tail -n1)
  case "$st" in
    DONE)    echo "  $n: already installed";;
    RUNNING) echo "  $n: install already running - not starting another";;
    START)   scp_to "$KIT/node/bootstrap_node.sh" "$n" '~/bootstrap_node.sh' >/dev/null || { echo "  $n: could not copy the installer"; continue; }
             ssh_run "$n" "nohup setsid bash ~/bootstrap_node.sh $role > ~/bootstrap.log 2>&1 < /dev/null & echo started" | tr -d '\r' | tail -n1 | sed "s/^/  $n: /";;
    *)       echo "  $n: could not reach it right now (will keep checking)";;
  esac
done
echo "[02] waiting for all machines (checks every 20 s; you may close this window and re-run the script later)"
declare -A S; t0=$(date +%s)
while :; do
  line=""; all_done=1; any_fail=0
  for n in $NODES; do
    s=$(RETRIES=2 ssh_run "$n" 'if grep -q "BOOTSTRAP OK" ~/bootstrap.log 2>/dev/null; then echo OK;
          elif grep -q "FAILED at line" ~/bootstrap.log 2>/dev/null; then echo FAILED;
          elif pgrep -f "bash .*bootstrap_node[.]sh" >/dev/null; then echo running; else echo STOPPED; fi' 2>/dev/null | tr -d '\r' | tail -n1)
    [ -n "$s" ] || s="no-connection"
    S[$n]="$s"; line="$line  $n=$s"
    case "$s" in OK) ;; FAILED|STOPPED) any_fail=1;; *) all_done=0;; esac
  done
  printf '  %4ss %s\n' "$(( $(date +%s) - t0 ))" "$line"
  [ $all_done -eq 1 ] && break
  sleep 20
done
for n in $NODES; do scp_from "$n" '~/bootstrap.log' "$KIT/logs/bootstrap_$n.log" >/dev/null 2>&1 || echo "  (could not fetch $n's log)"; done
for n in $NODES; do echo "---- $n (${S[$n]}) - last lines of logs/bootstrap_$n.log"; tail -n 5 "$KIT/logs/bootstrap_$n.log" 2>/dev/null; done
if [ $any_fail -eq 0 ]; then echo "[02] DONE. Next: ./cluster/03_init_cluster.sh"
else echo "[02] SOME NODES FAILED or STOPPED. Send: grep -n 'FAILED' logs/bootstrap_*.log ; tail -n 40 logs/bootstrap_<node>.log"
     echo "     (a STOPPED machine with no FAILED line was usually cut off earlier - just re-run this script)"; exit 1; fi
