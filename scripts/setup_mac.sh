#!/usr/bin/env bash
# amd-gpu-mock: macOS setup (Apple Silicon or Intel)
#
# Installs prerequisites, creates a KIND cluster with Podman, and deploys
# the full AMD GPU mock stack with 8x MI300X GPUs.
#
# Usage:
#   ./scripts/setup_mac.sh                    # Full setup
#   ./scripts/setup_mac.sh --profile mi325x   # Different GPU profile
#   ./scripts/setup_mac.sh --teardown         # Clean up everything

set -uo pipefail

GPU_PROFILE="${1:-mi300x}"
CLUSTER_NAME="amd-mock"
CHART="oci://docker.io/submod/amd-gpu-mock"
CHART_VERSION="0.2.12"

if [ "${1:-}" = "--teardown" ]; then
  echo "Tearing down..."
  helm uninstall amd-gpu-mock -n amd-mock 2>/dev/null || true
  KIND_EXPERIMENTAL_PROVIDER=podman kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
  echo "Done."
  exit 0
fi

if [ "${1:-}" = "--profile" ]; then
  GPU_PROFILE="${2:-mi300x}"
fi

echo "============================================"
echo "  AMD GPU Mock — macOS Setup"
echo "  Profile: $GPU_PROFILE"
echo "============================================"
echo ""

# ── Step 1: Check and install prerequisites ────────────────────────────
echo "Step 1/5: Checking prerequisites..."

if ! command -v brew &>/dev/null; then
  echo "ERROR: Homebrew not found. Install from https://brew.sh"
  exit 1
fi

for tool in kind helm kubectl; do
  if ! command -v $tool &>/dev/null; then
    echo "  Installing $tool..."
    brew install $tool
  else
    echo "  $tool: $(command -v $tool)"
  fi
done

if ! command -v podman &>/dev/null; then
  echo "ERROR: Podman not found. Install from https://podman.io"
  echo "  Or: brew install podman"
  exit 1
fi
echo "  podman: $(command -v podman)"
echo ""

# ── Step 2: Ensure Podman VM is running ────────────────────────────────
echo "Step 2/5: Ensuring Podman VM is running..."

if ! podman machine info 2>/dev/null | grep -q "Running"; then
  echo "  Starting Podman VM..."
  podman machine init 2>/dev/null || true
  podman machine start 2>&1 || true
fi

# Install Rosetta if needed (Apple Silicon only)
if [ "$(uname -m)" = "arm64" ]; then
  if ! /usr/bin/pgrep -q oahd 2>/dev/null; then
    echo "  Installing Rosetta for x86 container support..."
    softwareupdate --install-rosetta --agree-to-license 2>/dev/null || true
  fi
fi

echo "  Podman VM: $(podman machine list --format '{{.Name}} {{.CPUs}}CPUs {{.Memory}}' 2>/dev/null | head -1)"
echo ""

# ── Step 3: Create KIND cluster ────────────────────────────────────────
echo "Step 3/5: Creating KIND cluster..."
export KIND_EXPERIMENTAL_PROVIDER=podman

kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
kind create cluster --name "$CLUSTER_NAME" \
  --image docker.io/submod/amd-mock-kind-node:0.2.2 \
  --config "$(cd "$(dirname "$0")/.." && pwd)/deployments/kind-node/kind-config.yaml"
kubectl wait --for=condition=Ready node/${CLUSTER_NAME}-control-plane --timeout=60s
echo ""

# ── Step 4: Install AMD GPU mock from OCI chart ───────────────────────
echo "Step 4/5: Installing AMD GPU mock..."
helm install amd-gpu-mock "$CHART" \
  --version "$CHART_VERSION" \
  --namespace amd-mock --create-namespace \
  --set gpu.profile="$GPU_PROFILE" \
  --set dra.enabled=false --set devicePlugin.enabled=true

echo "  Waiting for mock..."
kubectl -n amd-mock rollout status ds/amd-gpu-mock --timeout=120s
echo "  Waiting for device plugin..."
kubectl -n kube-system rollout status ds/amd-gpu-mock-device-plugin --timeout=120s
sleep 10
echo ""

# ── Step 5: Verify ────────────────────────────────────────────────────
echo "Step 5/5: Verifying..."
GPU_COUNT=$(kubectl get node -o jsonpath='{.items[0].status.allocatable.amd\.com/gpu}' 2>/dev/null)
GPU_NAME=$(kubectl -n amd-mock exec ds/amd-gpu-mock -- cat /var/lib/amd-gpu-mock/sys/class/kfd/kfd/topology/nodes/1/name 2>/dev/null)

echo "  GPUs:    $GPU_COUNT"
echo "  Profile: $GPU_NAME"
echo ""

if [ "$GPU_COUNT" = "8" ] || [ "$GPU_COUNT" = "4" ]; then
  echo "============================================"
  echo "  Setup Complete!"
  echo "============================================"
  echo ""
  echo "  Dashboard:"
  echo "    http://localhost:8080"
  echo "  Grafana: http://localhost:3000 (admin / amdmock)"
  echo "    open http://localhost:8080"
  echo ""
  echo "  Deploy LLM demo:"
  echo "    kubectl apply -f deployments/tiny-llm-demo.yaml"
  echo "    kubectl logs -l app=tiny-llm"
  echo ""
  echo "  GPU partitioning:"
  echo "    curl -X POST 'http://localhost:8080/api/partitions/set?mode=CPX'"
  echo "    kubectl apply -f deployments/partition-demo.yaml"
  echo ""
  echo "  Teardown:"
  echo "    ./scripts/setup_mac.sh --teardown"
  echo "============================================"
else
  echo "WARNING: Expected 4 or 8 GPUs, got: $GPU_COUNT"
  echo "Check: kubectl -n amd-mock logs ds/amd-gpu-mock"
  echo "Check: kubectl -n kube-system logs -l app.kubernetes.io/name=amd-gpu-device-plugin"
fi
