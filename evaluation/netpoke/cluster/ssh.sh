#!/bin/bash
# ./ssh.sh NODE            interactive login          ./ssh.sh NODE 'command'   run one command
source "$(dirname "$0")/lib.sh"; n="${1:?node}"; shift
if [ $# -eq 0 ]; then ssh_login "$n"; else ssh_run "$n" "$@"; fi
