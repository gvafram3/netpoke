#!/bin/bash
# Runs ON a node. Tests that the kernel supports what NetPoke needs (sch_plug, htb, netem).
R(){ printf '%-52s %s\n' "$1" "$2"; }
echo "== $(hostname): kernel $(uname -r), $(nproc) vCPU, $(free -m | awk '/Mem:/{print $2}') MB"
sudo ip link del d0 2>/dev/null
sudo ip link add d0 type veth peer name d1 || { R "veth create" FAIL; exit 1; }
t(){ local name="$1"; shift; if sudo tc qdisc add dev d0 root "$@" 2>/tmp/tcerr; then sudo tc qdisc del dev d0 root; R "$name" PASS; else R "$name" "FAIL ($(head -c 80 /tmp/tcerr))"; fi; }
t "qdisc plug (THE key one)"        plug limit 100000
t "qdisc tbf  (bandwidth cap, Phase 2)" tbf rate 100mbit burst 256kb latency 50ms
t "qdisc netem (optional delay tests)"  netem delay 1ms
# plug control verbs, exactly what net_hold does over netlink: one PASS/FAIL line per verb.
if sudo tc qdisc add dev d0 root plug limit 100000 2>/tmp/tcerr; then
  R "plug: qdisc added (it starts BLOCKED by design)" PASS
  for v in "release_indefinite" "block" "release_indefinite" "release" "limit 200000"; do
    if err=$(sudo tc qdisc change dev d0 root plug $v 2>&1); then R "  plug $v" PASS; else R "  plug $v" "FAIL ($(echo "$err" | tr '\n' ' ' | head -c 80))"; fi
  done
  sudo tc qdisc del dev d0 root
fi
sudo ip link del d0 2>/dev/null
if command -v docker >/dev/null; then R "docker" "$(sudo docker --version | cut -d, -f1)"; else R docker MISSING; fi
R "kubelet" "$(kubelet --version 2>/dev/null)"
R "default NIC (for the tbf cap)" "$(ip -o -4 route show to default | awk '{print $5}')"
R "openvswitch (Weave fastdp)" "$(sudo modprobe openvswitch 2>&1 && echo loaded || echo 'MISSING - Weave falls back to slow userspace mode')"
