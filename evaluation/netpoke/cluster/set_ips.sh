#!/bin/bash
# Update the four public IPs in cluster/config.env after a stop/start.
#   ./cluster/set_ips.sh <control-ip> <worker0-ip> <worker1-ip> <worker2-ip>
set -euo pipefail
cd "$(dirname "$0")"
[ $# -eq 4 ] || { echo "usage: $0 CONTROL_IP WORKER0_IP WORKER1_IP WORKER2_IP   (public IPv4 addresses, in that order)"; exit 1; }
[ -f config.env ] || { echo "config.env is missing: cp config.env.example config.env"; exit 1; }
names=(control worker0 worker1 worker2)
for i in 0 1 2 3; do
  ip="${@:$((i+1)):1}"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || { echo "not an IPv4 address: '$ip'"; exit 1; }
  sed -i "s|^IP_${names[$i]}=.*|IP_${names[$i]}=\"$ip\"|" config.env
done
grep -E "^IP_" config.env
