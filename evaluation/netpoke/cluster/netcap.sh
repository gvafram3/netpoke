#!/bin/bash
# Bandwidth cap on worker2's POD DATA traffic only (Weave tunnel, UDP 6783/6784), or remove it.
#   usage: netcap.sh <Mbit/s | off | show>
# Only the tunnel is capped: a cap on the whole NIC also throttled Kubernetes and Weave management traffic, which broke deploys.
# The cap sits on the host NIC because sch_plug is the pod's root qdisc (no child slots), so it must be another device.
source "$(dirname "$0")/lib.sh"
A="${1:?Mbit/s | off | show}"
ssh_run worker2 "IF=\$(ip -o -4 route show to default | awk '{print \$5}');
case '$A' in
  off)  sudo tc qdisc del dev \$IF root 2>/dev/null; echo 'cap removed';;
  show) ;;
  *)    sudo tc qdisc del dev \$IF root 2>/dev/null
        if sudo tc qdisc add dev \$IF root handle 1: htb default 20 &&
           sudo tc class add dev \$IF parent 1: classid 1:1 htb rate 10gbit &&
           sudo tc class add dev \$IF parent 1:1 classid 1:10 htb rate ${A}mbit ceil ${A}mbit &&
           sudo tc class add dev \$IF parent 1:1 classid 1:20 htb rate 9gbit ceil 10gbit &&
           sudo tc filter add dev \$IF parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip dport 6784 0xffff flowid 1:10 &&
           sudo tc filter add dev \$IF parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip dport 6783 0xffff flowid 1:10 &&
           { sudo tc qdisc add dev \$IF parent 1:10 handle 10: fq_codel 2>/dev/null || sudo tc qdisc add dev \$IF parent 1:10 handle 10: pfifo limit 1000; }
        then echo 'cap set: ${A} Mbit/s on Weave data traffic (UDP 6783/6784) leaving '\$IF'; everything else unlimited'
        else sudo tc qdisc del dev \$IF root 2>/dev/null; echo 'FAILED to set the cap - removed everything, NO cap is active'; fi;;
esac
echo '--- classes (1:10 = capped pod data, 1:20 = everything else)'
tc -s class show dev \$IF 2>/dev/null | grep -A2 'class htb 1:10\|class htb 1:20'
echo '--- qdiscs'; tc -s qdisc show dev \$IF | head -8"
