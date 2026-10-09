#!/usr/bin/env bash
# Published images/chart only; no compiler or image build required.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/release.env"
CONFIG="$ROOT/demo/config.yaml"
CLUSTER="${CLUSTER_NAME:-amd-mock}"
SKIP=false
TEARDOWN=false
ERNIC=false
while [ "$#" -gt 0 ]; do
 case "$1" in
  --ernic) ERNIC=true; shift ;;
  --config) CONFIG="$2"; shift 2 ;;
  --skip-cluster) SKIP=true; shift ;;
  --teardown) TEARDOWN=true; shift ;;
  *) echo "usage: $0 [--config values.yaml] [--skip-cluster] [--teardown] [--ernic]" >&2; exit 1 ;;
 esac
done
if [ -n "${CONTAINER_RUNTIME:-}" ]; then
 export KIND_EXPERIMENTAL_PROVIDER="$CONTAINER_RUNTIME"
elif [ -z "${KIND_EXPERIMENTAL_PROVIDER:-}" ] && command -v podman >/dev/null && podman info >/dev/null 2>&1; then
 export KIND_EXPERIMENTAL_PROVIDER=podman
fi
if $ERNIC && [ "${KIND_EXPERIMENTAL_PROVIDER:-}" != podman ]; then
 echo "The ERNIC VM demo requires a running Podman machine and a Podman Kind cluster." >&2
 exit 1
fi
if $TEARDOWN; then
 python3 "$ROOT/demo/run.py" cleanup --config "$CONFIG" --context "kind-$CLUSTER"
 if $ERNIC; then KUBE_CONTEXT="kind-$CLUSTER" "$ROOT/scripts/ernic/cleanup.sh"; fi
 kind delete cluster --name "$CLUSTER"
 exit
fi
if ! $SKIP; then
 mkdir -p "$ROOT/tmp/demo"
 helm template kind "$ROOT/deployments/kind-node/config-chart" -f "$CONFIG" --show-only templates/kind.yaml > "$ROOT/tmp/demo/kind-config.yaml"
 # Refuse to destroy an existing cluster. Use --skip-cluster to upgrade it.
 if kind get clusters | grep -Fxq "$CLUSTER"; then
  echo "Cluster $CLUSTER exists; use --skip-cluster or --teardown." >&2; exit 1
 fi
 kind create cluster --name "$CLUSTER" --image "$IMAGE_REGISTRY/amd-mock-kind-node:$RELEASE_VERSION" \
  --config "$ROOT/tmp/demo/kind-config.yaml"
fi
# Use an explicit context: no accidental install into another current cluster.
helm upgrade --install amd-gpu-mock "oci://$IMAGE_REGISTRY/amd-gpu-mock" \
 --version "$CHART_VERSION" -n amd-mock --create-namespace \
 --kube-context "kind-$CLUSTER" --reset-values -f "$CONFIG" --wait --timeout 8m
printf '\nDemo environment ready. Run: python3 demo/run.py list\n'
printf 'Host ports and dashboard switches come from %s\n' "$CONFIG"
printf 'Use KUBECONFIG/current context for kind-%s when running demos.\n' "$CLUSTER"
helm template kind "$ROOT/deployments/kind-node/config-chart" -f "$CONFIG" --show-only templates/runtime.json | \
 python3 -c 'import sys,json; s=sys.stdin.read(); d=json.loads(s[s.index("{"):]); print("Mock dashboard: " + d["mockURL"] if d["mockDashboardEnabled"] else "Mock host dashboard disabled"); print("Grafana: " + d["grafanaURL"] + " (admin / configured password)" if d["grafanaEnabled"] else "Grafana disabled")'

if $ERNIC; then
 KUBE_CONTEXT="kind-$CLUSTER" ERNIC_CONTROL_PLANE="$CLUSTER-control-plane" "$ROOT/scripts/ernic/setup.sh"
fi
