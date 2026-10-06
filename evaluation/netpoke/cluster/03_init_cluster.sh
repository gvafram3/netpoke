#!/bin/bash
# kubeadm init on 'control', a pod network (CNI), metrics-server, then join the workers.
set -euo pipefail
source "$(dirname "$0")/lib.sh"
CRI="unix:///var/run/cri-dockerd.sock"; CNI="${CNI:-weave}"
if [ "$CNI" = flannel ]; then PODCIDR=10.244.0.0/16; CNI_YAML=https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
else PODCIDR=192.168.0.0/16; CNI_YAML=https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml; fi
echo "[03] kubeadm init on control (pod network: $CNI, $PODCIDR)"
ssh_run control "if [ ! -f /etc/kubernetes/admin.conf ]; then
  sudo kubeadm init --node-name control --cri-socket $CRI --pod-network-cidr=$PODCIDR
fi
mkdir -p \$HOME/.kube && sudo cp -f /etc/kubernetes/admin.conf \$HOME/.kube/config && sudo chown \$(id -u):\$(id -g) \$HOME/.kube/config"
echo "[03] CNI: $CNI"
ssh_run control "kubectl apply -f $CNI_YAML"
echo "[03] metrics-server (run.sh calls 'kubectl top'), pinned to control so it never steals CPU from service nodes"
ssh_run control "kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
kubectl -n kube-system patch deployment metrics-server --type=json -p='[{\"op\":\"add\",\"path\":\"/spec/template/spec/containers/0/args/-\",\"value\":\"--kubelet-insecure-tls\"}]'
kubectl -n kube-system patch deployment metrics-server -p '{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"control\"},\"tolerations\":[{\"key\":\"node-role.kubernetes.io/control-plane\",\"operator\":\"Exists\",\"effect\":\"NoSchedule\"}]}}}}'
kubectl -n kube-system patch deployment coredns -p '{\"spec\":{\"template\":{\"spec\":{\"nodeSelector\":{\"kubernetes.io/hostname\":\"control\"}}}}}'"
echo "[03] join workers"
JOIN=$(ssh_run control "sudo kubeadm token create --print-join-command" | tr -d '\r' | tail -n1)
for w in $NODES; do
  [ "$w" = control ] && continue
  ssh_run "$w" "if [ ! -f /etc/kubernetes/kubelet.conf ]; then sudo $JOIN --node-name $w --cri-socket $CRI; else echo 'already joined'; fi"
done
echo "[03] waiting for all nodes Ready (max ~5 min)"
for i in $(seq 1 60); do
  READY=$(ssh_run control "kubectl get nodes --no-headers 2>/dev/null | grep -c ' Ready'" | tr -d '\r' | tail -n1)
  [ "${READY:-0}" -ge "$(echo $NODES | wc -w)" ] && break; sleep 5
done
ssh_run control "kubectl get nodes -o wide; echo; kubectl get pods -A -o wide"
echo "[03] DONE. Next: ./cluster/04_day0_checks.sh"
