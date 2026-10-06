#!/bin/bash
# Control-node version of netcap.sh: cap worker2's pod data (Weave UDP 6783/6784) at <Mbit/s> with a chosen bottleneck queue.
#   ctl_netcap.sh <Mbit/s | off | show> [queue, default fq_codel]      e.g.  ctl_netcap.sh 175 pfifo limit 20
set -o pipefail
source ~/kit/control/ctl_lib.sh; ensure_hostshell || exit 1
A="${1:?Mbit/s | off | show}"; shift; LEAF="${*:-fq_codel}"
H "IF=\$(ip -o -4 route show to default | awk '{print \$5}')
case '$A' in
  off)  tc qdisc del dev \$IF root 2>/dev/null; echo 'cap removed';;
  show) ;;
  *)    tc qdisc del dev \$IF root 2>/dev/null
        if tc qdisc add dev \$IF root handle 1: htb default 20 &&
           tc class add dev \$IF parent 1: classid 1:1 htb rate 10gbit &&
           tc class add dev \$IF parent 1:1 classid 1:10 htb rate ${A}mbit ceil ${A}mbit &&
           tc class add dev \$IF parent 1:1 classid 1:20 htb rate 9gbit ceil 10gbit &&
           tc filter add dev \$IF parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip dport 6784 0xffff flowid 1:10 &&
           tc filter add dev \$IF parent 1: protocol ip prio 1 u32 match ip protocol 17 0xff match ip dport 6783 0xffff flowid 1:10 &&
           tc qdisc add dev \$IF parent 1:10 handle 10: $LEAF
        then echo 'cap set: ${A} Mbit/s, bottleneck queue: $LEAF'
        else tc qdisc del dev \$IF root 2>/dev/null; echo 'FAILED to set the cap - NO cap is active'; exit 1; fi;;
esac
tc -s qdisc show dev \$IF | grep -A2 'parent 1:10' | head -3" 2>&1 | grep -v "quantum of class"
