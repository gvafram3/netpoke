#!/bin/bash
# Stop the detached run on the control node and clean up the deployed pods; restores the original yamls.
source "$(dirname "$0")/lib.sh"
read -r -p "Stop the running experiment on control? Type STOP > " a; [ "$a" = STOP ] || exit 0
ssh_run control 'screen -S run -X quit 2>/dev/null; pkill -f "run_series[.]sh"; pkill -f "run_arm[.]sh"; pkill -f "src/[m]ain[.]py"; sleep 2
E=~/slowpoke/evaluation/mutex; [ -d $E/yamls-orig ] && { rm -rf $E/yamls; cp -r $E/yamls-orig $E/yamls; echo "original yamls restored"; }
kubectl delete deployments,services --all --ignore-not-found >/dev/null 2>&1; echo "stopped; pods removed"; screen -ls 2>/dev/null | grep "[.]run" || echo "(no run session left)"'
