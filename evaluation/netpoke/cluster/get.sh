#!/bin/bash
# ./get.sh NODE 'REMOTE' LOCAL     e.g.  ./get.sh worker2 /tmp/pod_eth0.txt ~/pod_eth0.txt
source "$(dirname "$0")/lib.sh"; scp_from "${1:?node}" "${2:?remote}" "${3:?local}"
