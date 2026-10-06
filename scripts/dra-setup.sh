#!/usr/bin/env bash
# Install the published DRA stack. No compiler, source checkout of AMD's
# driver, image build, or registry credentials are required.
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/release.env
source "$REPO_ROOT/scripts/release.env"
CLUSTER_NAME="${CLUSTER_NAME:-amd-dra}"
for bin in kind kubectl helm; do command -v "$bin" >/dev/null; done
kind_version="$(kind version)"
if [[ ! "$kind_version" =~ v([0-9]+)\.([0-9]+)\.([0-9]+) ]] ||
   { [ "${BASH_REMATCH[1]}" -eq 0 ] && [ "${BASH_REMATCH[2]}" -lt 33 ]; }; then
    echo "Kubernetes 1.37 requires kind v0.33.0 or newer; found $kind_version" >&2
    exit 1
fi
if [ -n "${CONTAINER_RUNTIME:-}" ]; then
    RUNTIME="$CONTAINER_RUNTIME"
elif command -v podman >/dev/null && podman info >/dev/null 2>&1; then
    RUNTIME=podman
else
    RUNTIME=docker
fi
[ "$RUNTIME" != podman ] || export KIND_EXPERIMENTAL_PROVIDER=podman
export KUBECONFIG="${KUBECONFIG:-$REPO_ROOT/tmp/$CLUSTER_NAME.kubeconfig}"
mkdir -p "$(dirname "$KUBECONFIG")"
if [ "${1:-}" = --teardown ]; then
    kind delete cluster --name "$CLUSTER_NAME"
    exit 0
fi
[ "$#" -eq 0 ] || { echo "usage: $0 [--teardown]" >&2; exit 1; }
if kind get clusters | grep -Fxq "$CLUSTER_NAME"; then
    echo "Cluster $CLUSTER_NAME already exists; choose another CLUSTER_NAME" >&2
    exit 1
fi
kind create cluster --name "$CLUSTER_NAME" \
    --image "$IMAGE_REGISTRY/amd-mock-kind-node:$RELEASE_VERSION" \
    --kubeconfig "$KUBECONFIG" --wait 120s
helm install amd-gpu-mock "oci://$IMAGE_REGISTRY/amd-gpu-mock" \
    --version "$RELEASE_VERSION" --namespace amd-mock --create-namespace \
    --set devicePlugin.enabled=false --set dra.enabled=true
kubectl -n amd-mock rollout status ds/amd-gpu-mock --timeout=120s
kubectl -n amd-mock rollout status ds/amd-gpu-mock-dra-kubeletplugin --timeout=180s
kubectl apply -f "$REPO_ROOT/deployments/dra/demo.yaml"
kubectl wait pod/dra-gpu-demo --for=condition=Ready --timeout=180s
kubectl exec dra-gpu-demo -- ls -l /dev/kfd /dev/dri
echo "DRA ready. Inspect with: KUBECONFIG=$KUBECONFIG kubectl get resourceslices"
