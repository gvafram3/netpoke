#!/bin/bash
# Delete benchmark workloads in default without removing the kubernetes Service.
set -euo pipefail
kubectl delete deployment --all -n default --ignore-not-found=true
for svc in $(kubectl get svc -n default -o jsonpath='{.items[*].metadata.name}' 2>/dev/null); do
  [[ "$svc" == "kubernetes" ]] && continue
  kubectl delete svc "$svc" -n default --ignore-not-found=true
done
kubectl delete pod --all -n default --force --grace-period=0 2>/dev/null || true
