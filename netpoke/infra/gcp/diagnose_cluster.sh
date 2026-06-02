#!/bin/bash
# Print a full inventory of the NetPoke GCP cluster and flag issues before step 2.
# Run from Cloud Shell after cloning the repo:
#   cd netpoke/infra/gcp   # from clone root ~/netpoke — see inner netpoke/ dir
#   cp -n config.env.example config.env && ./diagnose_cluster.sh

set -euo pipefail
cd "$(dirname "$0")"

if [[ -f config.env ]]; then
  # shellcheck disable=SC1091
  source config.env
else
  GCP_PROJECT="${GCP_PROJECT:-$(gcloud config get-value project 2>/dev/null)}"
  CLUSTER_PREFIX="${CLUSTER_PREFIX:-netpoke}"
  NETWORK_TAG="${NETWORK_TAG:-netpoke-cluster}"
  GCP_ZONE="${GCP_ZONE:-us-central1-a}"
  NUM_WORKERS="${NUM_WORKERS:-3}"
fi

gcloud config set project "$GCP_PROJECT" >/dev/null

echo "================================================================"
echo "NetPoke cluster diagnosis"
echo "  Project:  $GCP_PROJECT"
echo "  Default zone (from config.env): $GCP_ZONE"
echo "  Prefix:   $CLUSTER_PREFIX"
echo "================================================================"
echo ""

echo "==> VMs tagged ${NETWORK_TAG} (all zones)"
gcloud compute instances list \
  --filter="tags.items=${NETWORK_TAG}" \
  --format="table(name,zone.basename(),machineType.basename(),status,INTERNAL_IP,EXTERNAL_IP)"

echo ""
echo "==> Expected VMs vs actual"
EXPECTED=(
  "${CLUSTER_PREFIX}-control"
  "${CLUSTER_PREFIX}-loadgen"
)
for i in $(seq 1 "$NUM_WORKERS"); do
  EXPECTED+=("${CLUSTER_PREFIX}-worker${i}")
done

ISSUES=0
for vm in "${EXPECTED[@]}"; do
  if ! gcloud compute instances list --filter="name=${vm}" --format="value(name)" | grep -qx "$vm"; then
    echo "  MISSING: $vm"
    ISSUES=$((ISSUES + 1))
  fi
done

echo ""
echo "==> Per-VM zone map (for config.env overrides)"
for vm in "${EXPECTED[@]}"; do
  line="$(gcloud compute instances list --filter="name=${vm}" \
    --format="csv[no-heading](name,zone.basename(),status)" 2>/dev/null || true)"
  if [[ -z "$line" ]]; then
    continue
  fi
  name="${line%%,*}"
  rest="${line#*,}"
  zone="${rest%%,*}"
  status="${rest##*,}"
  echo "  $name  zone=$zone  status=$status"
  if [[ "$status" != "RUNNING" ]]; then
    echo "    !! Not RUNNING — start or recreate before ./02_initialize_cluster.sh"
    ISSUES=$((ISSUES + 1))
  fi
done

echo ""
echo "==> Zone consistency check"
mapfile -t ZONES < <(gcloud compute instances list --filter="tags.items=${NETWORK_TAG} AND status=RUNNING" \
  --format="value(zone.basename())" | sort -u)
if [[ "${#ZONES[@]}" -eq 1 ]]; then
  echo "  OK: all RUNNING nodes in zone ${ZONES[0]}"
elif [[ "${#ZONES[@]}" -gt 1 ]]; then
  echo "  WARN: RUNNING nodes span zones: ${ZONES[*]}"
  echo "       Kubernetes can work across zones in one region, but"
  echo "       ./02_initialize_cluster.sh needs per-VM zone settings (see config.env.example)."
  ISSUES=$((ISSUES + 1))
else
  echo "  WARN: no RUNNING nodes with tag ${NETWORK_TAG}"
  ISSUES=$((ISSUES + 1))
fi

LOADGEN_ZONE_ACTUAL="$(gcloud compute instances list --filter="name=${CLUSTER_PREFIX}-loadgen" \
  --format="value(zone.basename())" 2>/dev/null || true)"
if [[ -n "$LOADGEN_ZONE_ACTUAL" && "$LOADGEN_ZONE_ACTUAL" != "$GCP_ZONE" ]]; then
  echo ""
  echo "  LOADGEN is in ${LOADGEN_ZONE_ACTUAL} but GCP_ZONE=${GCP_ZONE}"
  echo "  Add to config.env:  LOADGEN_ZONE=\"${LOADGEN_ZONE_ACTUAL}\""
fi

echo ""
echo "==> External IPs in region us-central1 (quota IN_USE_ADDRESSES is often 4)"
EXT_COUNT=0
while IFS= read -r _; do
  EXT_COUNT=$((EXT_COUNT + 1))
done < <(gcloud compute instances list \
  --filter="status=RUNNING AND -networkInterfaces.accessConfigs.natIP:*" \
  --format="value(networkInterfaces[0].accessConfigs[0].natIP)" 2>/dev/null | grep -v '^$' || true)
echo "  RUNNING VMs with a public NAT IP (all zones in project): $EXT_COUNT"
gcloud compute instances list \
  --filter="tags.items=${NETWORK_TAG}" \
  --format="table(name,zone.basename(),status,networkInterfaces[0].accessConfigs[0].natIP:label=EXTERNAL_IP)"
if [[ "$EXT_COUNT" -ge 4 ]]; then
  echo "  !! At or above typical quota of 4 — run ./fix_ip_quota.sh before starting more VMs"
  ISSUES=$((ISSUES + 1))
fi

echo ""
echo "==> Instances per zone (GCP default limit is often 4 per zone)"
gcloud compute instances list --filter="tags.items=${NETWORK_TAG}" \
  --format="csv[no-heading](zone.basename(),name)" | sort | awk -F, '{a[$1]++} END {for (z in a) print "  " z ": " a[z] " netpoke VMs"}'

echo ""
echo "==> vCPU in use (RUNNING instances, this project)"
gcloud compute instances list --filter="status=RUNNING" \
  --format="csv[no-heading](name,machineType.basename())" | while IFS=, read -r n mt; do
  vcpu="$(echo "$mt" | sed -n 's/e2-standard-\([0-9]*\)/\1/p')"
  [[ -z "$vcpu" ]] && vcpu="?"
  echo "  $n  $mt  (${vcpu} vCPU)"
done
echo "  (Quota target for full cluster: 12 vCPU = 2+4+3x2)"

echo ""
echo "==> Firewall rule ${NETWORK_TAG}-allow-internal"
if gcloud compute firewall-rules describe "${NETWORK_TAG}-allow-internal" >/dev/null 2>&1; then
  gcloud compute firewall-rules describe "${NETWORK_TAG}-allow-internal" \
    --format="yaml(name,network,direction,sourceTags,targetTags,allowed)"
else
  echo "  MISSING — run ./01_create_cluster.sh or create the rule manually"
  ISSUES=$((ISSUES + 1))
fi

echo ""
echo "==> Can SSH reach control plane? (quick check)"
CONTROL="${CLUSTER_PREFIX}-control"
CTRL_ZONE="$(gcloud compute instances list --filter="name=${CONTROL}" --format="value(zone.basename())")"
if [[ -n "$CTRL_ZONE" ]]; then
  if gcloud compute ssh "$CONTROL" --zone "$CTRL_ZONE" --quiet --command "echo ok && uname -a" 2>/dev/null; then
    echo "  SSH to ${CONTROL} in ${CTRL_ZONE}: OK"
  else
    echo "  SSH to ${CONTROL}: FAILED (check IAM / OS Login / first-time key prompt)"
    ISSUES=$((ISSUES + 1))
  fi
else
  echo "  Control VM not found"
  ISSUES=$((ISSUES + 1))
fi

echo ""
echo "==> Kubernetes already installed on control?"
if [[ -n "$CTRL_ZONE" ]]; then
  if gcloud compute ssh "$CONTROL" --zone "$CTRL_ZONE" --quiet --command "command -v kubectl && kubectl get nodes 2>/dev/null || echo 'no cluster yet'" 2>/dev/null; then
    :
  fi
fi

echo ""
echo "================================================================"
if [[ "$ISSUES" -eq 0 ]]; then
  echo "No blocking issues detected. Next: ./02_initialize_cluster.sh"
else
  echo "$ISSUES issue(s) above — fix before step 2 (see README troubleshooting)."
fi
echo "================================================================"
