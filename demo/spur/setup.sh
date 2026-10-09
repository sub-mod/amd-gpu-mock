#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/demo/spur/versions.env"
CLUSTER="${SPUR_CLUSTER:-amd-spur}"
export KUBECONFIG="${SPUR_KUBECONFIG:-$ROOT/tmp/spur/kubeconfig}"
mkdir -p "$(dirname "$KUBECONFIG")"
command -v kind >/dev/null
command -v helm >/dev/null
command -v kubectl >/dev/null
if ! kind get clusters | grep -Fxq "$CLUSTER"; then
  kind create cluster --name "$CLUSTER" \
    --image docker.io/submod/amd-mock-kind-node:0.2.2 \
    --config "$ROOT/demo/spur/kind.yaml" --kubeconfig "$KUBECONFIG"
else
  kind export kubeconfig --name "$CLUSTER" --kubeconfig "$KUBECONFIG"
fi
helm upgrade --install amd-gpu-mock oci://docker.io/submod/amd-gpu-mock \
  --version 0.2.12 --namespace amd-mock --create-namespace \
  --set dra.enabled=false --set devicePlugin.enabled=true \
  --set monitoring.enabled=false --set metricsExporter.enabled=false \
  --set dashboard.enabled=false --wait --timeout 5m
kubectl -n kube-system rollout status ds/amd-gpu-mock-device-plugin --timeout=180s
kubectl wait nodes -l spur.amd.com/managed=true \
  --for='jsonpath={.status.allocatable.amd\.com/gpu}=8' --timeout=180s
# Namespace is reserved for this demo; its RBAC never binds the default service account.
kubectl create namespace amd-demo-spur --dry-run=client -o yaml | kubectl apply -f -
curl -fsSL "https://raw.githubusercontent.com/ROCm/spur/$SPUR_COMMIT/examples/k8s/spurjob-crd.yaml" | kubectl apply -f -
kubectl wait --for=condition=Established crd/spurjobs.spur.amd.com --timeout=60s
if ! kubectl -n amd-demo-spur get secret spur-auth >/dev/null 2>&1; then
  python3 - <<'AUTH' | kubectl apply -f -
import base64, json, secrets
print(json.dumps({'apiVersion': 'v1', 'kind': 'Secret',
                  'metadata': {'name': 'spur-auth', 'namespace': 'amd-demo-spur'},
                  'data': {'jwt-key': base64.b64encode(secrets.token_hex(32).encode()).decode()}}))
AUTH
fi
kubectl -n amd-demo-spur create configmap spur-config \
  --from-file=spur.conf="$ROOT/demo/spur/spur.conf" --dry-run=client -o yaml | kubectl apply -f -
SPUR_IMAGE="$SPUR_IMAGE" python3 "$ROOT/demo/spur/manifests.py" | kubectl apply -f -
kubectl -n amd-demo-spur rollout status deploy/spurctld --timeout=300s
kubectl -n amd-demo-spur rollout status deploy/spur-k8s-operator --timeout=300s
printf '\nSpur ready. Run: %s/demo/spur/run.py\n' "$ROOT"
