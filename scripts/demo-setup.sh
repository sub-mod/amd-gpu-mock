#!/usr/bin/env bash
# amd-gpu-mock: One-command demo setup
#
# Deploys the complete AMD GPU mock stack + LLM demo on a local cluster.
# Uses the published OCI Helm chart — no build required.
# Works on macOS (Podman) and Linux (Docker).
#
# Usage:
#   ./scripts/demo-setup.sh                    # Full setup from scratch
#   ./scripts/demo-setup.sh --skip-cluster     # Skip cluster creation
#   ./scripts/demo-setup.sh --profile mi325x   # Use a different GPU profile
#   ./scripts/demo-setup.sh --teardown         # Clean up everything

set -uo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-amd-mock}"
GPU_PROFILE="${GPU_PROFILE:-mi300x}"
CHART="oci://docker.io/submod/amd-gpu-mock"
CHART_VERSION="0.2.1"
SKIP_CLUSTER=false
TEARDOWN=false
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Parse args
while [[ $# -gt 0 ]]; do
  case $1 in
    --skip-cluster) SKIP_CLUSTER=true; shift ;;
    --profile) GPU_PROFILE="$2"; shift 2 ;;
    --teardown) TEARDOWN=true; shift ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Detect container runtime
if command -v podman &>/dev/null && podman machine info &>/dev/null 2>&1; then
  RUNTIME="podman"
  export KIND_EXPERIMENTAL_PROVIDER=podman
elif command -v docker &>/dev/null; then
  RUNTIME="docker"
else
  echo "ERROR: Neither podman nor docker found. Install one first."
  exit 1
fi

echo "============================================"
echo "  AMD GPU Mock — Demo Setup"
echo "  Runtime: $RUNTIME"
echo "  Profile: $GPU_PROFILE"
echo "  Cluster: $CLUSTER_NAME"
echo "============================================"
echo ""

# ── Teardown ───────────────────────────────────────────────────────────
if $TEARDOWN; then
  echo "Tearing down..."
  kubectl delete -f "$SCRIPT_DIR/deployments/tiny-llm-demo.yaml" 2>/dev/null || true
  kubectl delete -f "$SCRIPT_DIR/deployments/partition-demo.yaml" 2>/dev/null || true
  helm uninstall amd-gpu-mock -n amd-mock 2>/dev/null || true
  kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
  echo "Done."
  exit 0
fi

# ── Step 1: Create cluster ─────────────────────────────────────────────
if ! $SKIP_CLUSTER; then
  echo "Step 1/4: Creating KIND cluster..."
  kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true

  # Try the custom node image (enables GPU Operator support on x86).
  # Falls back to standard kindest/node on macOS/ARM where the custom
  # image's systemd sysfs mounts fail under Rosetta emulation.
  KIND_NODE_IMAGE="docker.io/submod/amd-mock-kind-node:0.2.1"

  if kind create cluster --name "$CLUSTER_NAME" --image "$KIND_NODE_IMAGE" 2>/dev/null; then
    echo "Using custom KIND node image (GPU Operator support enabled)"
  else
    echo "Custom node image failed (expected on macOS/ARM). Using standard image."
    echo "Note: GPU Operator integration requires x86 Linux."
    kind delete cluster --name "$CLUSTER_NAME" 2>/dev/null || true
    kind create cluster --name "$CLUSTER_NAME"
  fi
  echo ""
fi

# ── Step 2: Install from OCI Helm chart ────────────────────────────────
echo "Step 2/4: Installing AMD GPU mock (profile: $GPU_PROFILE)..."
helm install amd-gpu-mock "$CHART" \
  --version "$CHART_VERSION" \
  --namespace amd-mock --create-namespace \
  --set gpu.profile="$GPU_PROFILE"

kubectl -n amd-mock rollout status ds/amd-gpu-mock --timeout=120s
kubectl -n kube-system rollout status ds/amd-gpu-mock-device-plugin --timeout=120s

# Wait for GPU resources to register
sleep 10
GPU_COUNT=$(kubectl get node -o jsonpath='{.items[0].status.allocatable.amd\.com/gpu}' 2>/dev/null)
echo "GPUs detected: $GPU_COUNT"
echo ""

# ── Step 3: Deploy LLM demo ───────────────────────────────────────────
echo "Step 3/4: Deploying Tiny LLM demo..."
kubectl apply -f "$SCRIPT_DIR/deployments/tiny-llm-demo.yaml"
echo ""

# ── Step 4: Wait for LLM ──────────────────────────────────────────────
echo "Step 4/4: Waiting for LLM pod..."
kubectl wait --for=condition=Ready pod -l app=tiny-llm --timeout=60s 2>/dev/null || true
echo ""

# ── Summary ────────────────────────────────────────────────────────────
echo "============================================"
echo "  Demo Ready!"
echo "============================================"
echo ""
echo "  GPUs:       $GPU_COUNT x AMD Instinct (profile: $GPU_PROFILE)"
echo ""
echo "  Dashboard:  kubectl -n amd-mock port-forward ds/amd-gpu-mock 8080:8080"
echo "              then open http://localhost:8080"
echo ""
echo "  LLM status: kubectl get pods -l app=tiny-llm"
echo "  LLM logs:   kubectl logs -l app=tiny-llm"
echo ""
echo "  Partition:  curl -X POST 'http://localhost:8080/api/partitions/set?mode=CPX'"
echo "              kubectl apply -f $SCRIPT_DIR/deployments/partition-demo.yaml"
echo ""
echo "  Teardown:   $0 --teardown"
echo "============================================"
