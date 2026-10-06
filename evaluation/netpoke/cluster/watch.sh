#!/bin/bash
# SECOND WINDOW: live progress of whatever is running on the control node. Refreshes every 5 s. Ctrl-C to leave (the run is NOT affected).
#   ./cluster/watch.sh [seconds]
source "$(dirname "$0")/lib.sh"
ssh_run control 'mkdir -p ~/kit/control ~/results' || exit 1
scp_to "$KIT/control/progress.py" control '~/kit/control/progress.py' >/dev/null
scp_to "$KIT/control/slowlog.py"  control '~/kit/control/slowlog.py'  >/dev/null
a=$(_addr control) || exit 1
exec ssh "${_SSH[@]}" -t "$SSH_USER@$a" "watch -t -n ${1:-5} python3 ~/kit/control/progress.py"
