#!/bin/bash
# ./put.sh LOCAL NODE 'REMOTE'     e.g.  ./put.sh tests worker2 '~/'      (quote the remote path so ~ is not expanded locally)
source "$(dirname "$0")/lib.sh"; scp_to "${1:?local}" "${2:?node}" "${3:?remote}"
