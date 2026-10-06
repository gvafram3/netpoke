#!/bin/bash
# Node-level "pod": namespace ns1 (10.0.0.2) wired to the host (10.0.0.1) by a veth pair.
# Needs root. Works on any Linux VM.
ip netns del ns1 2>/dev/null; ip link del veth0 2>/dev/null
ip netns add ns1
ip link add veth0 type veth peer name veth1
ip link set veth1 netns ns1
ip addr add 10.0.0.1/24 dev veth0; ip link set veth0 up
ip netns exec ns1 ip addr add 10.0.0.2/24 dev veth1
ip netns exec ns1 ip link set veth1 up; ip netns exec ns1 ip link set lo up
echo TOPO_LEAK_READY
