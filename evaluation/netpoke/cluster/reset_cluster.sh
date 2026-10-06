#!/bin/bash
# Undo kubeadm init/join on ALL nodes (use if 03 went wrong or you want to switch CNI). Keeps Docker/kubeadm installed.
source "$(dirname "$0")/lib.sh"
read -r -p "This wipes the Kubernetes cluster on all nodes. Type RESET > " a; [ "$a" = RESET ] || exit 0
for n in $NODES; do echo "== $n"
  ssh_run "$n" 'sudo kubeadm reset -f --cri-socket unix:///var/run/cri-dockerd.sock >/dev/null 2>&1; sudo rm -rf /etc/cni/net.d $HOME/.kube /var/lib/weave; sudo iptables -F; sudo iptables -t nat -F; sudo systemctl restart docker cri-docker; echo reset done'
done
