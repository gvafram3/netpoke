#!/bin/bash
# Run commands on worker2's HOST from the control node, through a privileged helper pod (namespace 'tools', so the
# experiment scripts - which only look at the default namespace - never see or wait for it).
NS=tools; HP=hostshell-w2
ensure_hostshell(){
  kubectl get ns $NS >/dev/null 2>&1 || kubectl create ns $NS >/dev/null
  if ! kubectl -n $NS get pod $HP >/dev/null 2>&1; then
    kubectl -n $NS apply -f - >/dev/null <<YAML
apiVersion: v1
kind: Pod
metadata: {name: $HP}
spec:
  nodeName: worker2
  hostNetwork: true
  hostPID: true
  tolerations: [{operator: Exists}]
  containers:
  - name: s
    image: ubuntu:24.04
    command: ["sleep", "infinity"]
    securityContext: {privileged: true}
YAML
  fi
  kubectl -n $NS wait --for=condition=Ready pod/$HP --timeout=240s >/dev/null || { echo "helper pod on worker2 is not ready"; return 1; }
  kubectl -n $NS exec $HP -- which nsenter >/dev/null || { echo "helper pod has no nsenter"; return 1; }
}
# H 'command'        : run a shell command in worker2's host namespaces (as root)
H(){ kubectl -n $NS exec $HP -- nsenter -t 1 -m -u -i -n -p -- bash -c "$1"; }
# HPUT /host/path < localfile : copy stdin to a file on worker2's host
HPUT(){ kubectl -n $NS exec -i $HP -- nsenter -t 1 -m -u -i -n -p -- bash -c "cat > $1"; }
