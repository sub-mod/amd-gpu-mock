#!/usr/bin/env bash
# Add the published GPU mock/DRA deployment to an already joined ERNIC worker.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/scripts/release.env"
NODE="${ERNIC_NODE:-amd-ernic-worker-1}"
CONTEXT="${KUBE_CONTEXT:-kind-amd-mock}"
RELEASE="${GPU_RELEASE:-amd-gpu-mock}"
NS="${GPU_NAMESPACE:-amd-mock}"
k=(kubectl --context "$CONTEXT")
printf 'Waiting for NFD and Network Operator NIC allocation on %s...\n' "$NODE"
ready=false
for attempt in $(seq 1 120); do
 if "${k[@]}" get node "$NODE" -o json | python3 -c '
import json,sys
n=json.load(sys.stdin)
ready=(n["metadata"]["labels"].get("feature.node.kubernetes.io/amd-nic")=="true"
       and n["status"].get("allocatable",{}).get("amd.com/nic")=="1"
       and any(c["type"]=="Ready" and c["status"]=="True" for c in n["status"].get("conditions",[])))
sys.exit(0 if ready else 1)
'; then ready=true; break; fi
 sleep 5
done
$ready || { echo 'NIC discovery/allocation did not become ready within 10 minutes' >&2; exit 1; }
# Preserve existing mock nodes and explicitly opt this worker into the deployment.
while IFS= read -r existing; do
 [ -z "$existing" ] || "${k[@]}" label node "$existing" amd-gpu-mock.amd.com/enabled=true --overwrite
done < <("${k[@]}" -n "$NS" get pods -l app.kubernetes.io/instance="$RELEASE" -o json | python3 -c '
import json,sys
print("\n".join(sorted({p["spec"]["nodeName"] for p in json.load(sys.stdin)["items"] if p["spec"].get("nodeName")})))
')
"${k[@]}" label node "$NODE" amd-gpu-mock.amd.com/enabled=true amd-gpu-mock.amd.com/network-demo=true --overwrite
helm upgrade "$RELEASE" "oci://$IMAGE_REGISTRY/amd-gpu-mock" --version "$CHART_VERSION" \
 --kube-context "$CONTEXT" -n "$NS" --reuse-values \
 --set-json 'nodeSelector={"amd-gpu-mock.amd.com/enabled":"true"}' \
 --set-json 'dra.kubeletPlugin.nodeSelector={"amd-gpu-mock.amd.com/enabled":"true"}' \
 --set dra.enabled=true --set devicePlugin.enabled=false --wait --timeout 10m
"${k[@]}" -n "$NS" rollout status ds/"$RELEASE" --timeout=300s
"${k[@]}" -n "$NS" rollout status ds/"$RELEASE"-dra-kubeletplugin --timeout=300s
printf 'GPU mock and upstream AMD DRA enabled on %s.\n' "$NODE"
