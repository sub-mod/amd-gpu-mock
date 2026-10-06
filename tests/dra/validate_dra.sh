#!/usr/bin/env bash
# amd-gpu-mock DRA validation
#
# Installs AMD's DRA driver (ROCm/k8s-gpu-dra-driver, unmodified) against the
# mock, then checks that it publishes a ResourceSlice for the mock GPUs and
# that a pod claiming a GPU through DRA starts with its device nodes.
#
# Prerequisites:
#   - Kubernetes 1.34+ (resource.k8s.io/v1); the mock kind node image is 1.37
#   - linux/amd64 nodes (AMD publishes amd64 driver images only)
#   - amd-gpu-mock installed WITHOUT its bundled device plugin:
#       helm install amd-gpu-mock oci://docker.io/submod/amd-gpu-mock \
#         --version 0.1.0 -n amd-mock --create-namespace \
#         --set devicePlugin.enabled=false
#   - kubectl, helm (3 or 4) and git
#
# Usage:
#   ./tests/dra/validate_dra.sh
#   KEEP=1 ./tests/dra/validate_dra.sh      # leave the driver installed
#
# Environment:
#   DRA_REF        AMD driver tag to install (default v1.0.0; keep in step
#                  with deployments/dra/values-mock.yaml)
#   INSTALL_DRIVER 0 to test the driver already installed by the mock chart
#   DRA_IMAGE     driver image repository (default AMD published repository)
#   DRA_IMAGE_TAG driver image tag (default DRA_REF); override for local builds
#   EXPECTED_GPUS  total devices on mock agent nodes (default 8)
#   TEST_NS        unused namespace for test workloads (default amd-dra-test)
#
# Selector scenarios require MI300X. Use a dedicated test cluster and a
# mock image built from this checkout, not an older published image.
#   MOCK_SYS       mock sysfs root on the node (default /var/lib/amd-gpu-mock/sys)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DRA_REPO="${DRA_REPO:-https://github.com/ROCm/k8s-gpu-dra-driver.git}"
DRA_REF="${DRA_REF:-v1.0.0}"
DRA_NS="${DRA_NS:-kube-amd-gpu}"
DRA_IMAGE="${DRA_IMAGE:-docker.io/rocm/k8s-gpu-dra-driver}"
DRA_IMAGE_TAG="${DRA_IMAGE_TAG:-$DRA_REF}"
RELEASE="amd-dra"
TEST_NS="${TEST_NS:-amd-dra-test}"
EXPECTED_GPUS="${EXPECTED_GPUS:-8}"
export MOCK_SYS="${MOCK_SYS:-/var/lib/amd-gpu-mock/sys}"
KEEP="${KEEP:-0}"
INSTALL_DRIVER="${INSTALL_DRIVER:-1}"
NODE_LABEL_KEY="amd-gpu-mock.amd.com/type"
NODE_LABEL_VALUE="sgpu"

PASS=0
FAIL=0
pass() { echo "  PASS: $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL: $1"; FAIL=$((FAIL + 1)); }
section() { echo ""; echo "=== $1 ==="; }
die() { echo "ERROR: $1" >&2; exit 1; }

for bin in kubectl helm git python3; do
    command -v "$bin" >/dev/null || die "$bin not found"
done

kubectl --request-timeout=10s get nodes >/dev/null || die "cannot reach the Kubernetes API for the current context"
if kubectl get namespace "$TEST_NS" >/dev/null 2>&1; then
    die "test namespace $TEST_NS already exists; choose an unused TEST_NS"
fi
WORK="$(mktemp -d)"
cleanup() {
    if [ "$KEEP" != "1" ]; then
        kubectl delete namespace "$TEST_NS" --ignore-not-found --wait=false >/dev/null 2>&1 || true
        if [ -f "$WORK/dra.yaml" ]; then
            kubectl delete -n "$DRA_NS" -f "$WORK/dra.yaml" --ignore-not-found >/dev/null 2>&1 || true
        fi
    fi
    rm -rf "$WORK"
}
trap cleanup EXIT

# ── 1. Preconditions ─────────────────────────────────────────────────────

section "1. Preconditions"

if kubectl api-resources --api-group=resource.k8s.io -o name 2>/dev/null | grep -q '^resourceslices'; then
    pass "cluster serves resource.k8s.io (DRA)"
else
    die "cluster does not serve resource.k8s.io; DRA needs Kubernetes 1.34+"
fi

AGENT_NODES="$(kubectl get pods -A -l app.kubernetes.io/name=amd-gpu-mock \
    --field-selector=status.phase=Running -o jsonpath='{.items[*].spec.nodeName}')"
[ -n "$AGENT_NODES" ] || die "no running amd-gpu-mock agent pods; install the mock chart first"
pass "mock agent running on: $AGENT_NODES"

# AMD's device plugin and DRA driver must not both hand out the same GPUs.
if kubectl get ds -A -l app.kubernetes.io/component=device-plugin -o name 2>/dev/null | grep -q .; then
    die "the mock chart's device plugin is running; reinstall with --set devicePlugin.enabled=false"
fi
pass "bundled device plugin disabled"

for node in $AGENT_NODES; do
    if [ -z "$(kubectl get node "$node" -o jsonpath="{.metadata.labels.${NODE_LABEL_KEY//./\\.}}")" ]; then
        kubectl label node "$node" "$NODE_LABEL_KEY=$NODE_LABEL_VALUE" >/dev/null
        echo "  labelled $node $NODE_LABEL_KEY=$NODE_LABEL_VALUE"
    fi
done

# ── 2. Install AMD's DRA driver against the mock ─────────────────────────

section "2. Install AMD DRA driver $DRA_REF"

if [ "$INSTALL_DRIVER" = 1 ]; then
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$DRA_REF" "$DRA_REPO" "$WORK/dra" \
    || die "could not fetch $DRA_REPO@$DRA_REF"

# Render, then point only the plugin's /sys hostPath at the mock tree.
if helm template "$RELEASE" "$WORK/dra/helm-charts-k8s" \
        --namespace "$DRA_NS" \
        --kube-version 1.34.0 --api-versions resource.k8s.io/v1 \
        -f "$REPO_ROOT/deployments/dra/values-mock.yaml" --set-string "image.repository=$DRA_IMAGE" --set-string "image.tag=$DRA_IMAGE_TAG" \
    | "$REPO_ROOT/deployments/dra/sys-remap.sh" > "$WORK/dra.yaml"; then
    pass "chart rendered, /sys remapped to $MOCK_SYS"
else
    die "rendering AMD's chart failed"
fi

kubectl create namespace "$DRA_NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl apply -n "$DRA_NS" -f "$WORK/dra.yaml" >/dev/null || die "kubectl apply failed"

fi

DS="$(kubectl get ds -n "$DRA_NS" -l app.kubernetes.io/component=kubeletplugin -o jsonpath='{.items[0].metadata.name}')"
[ -n "$DS" ] || die "kubelet plugin DaemonSet not found in $DRA_NS"
if kubectl rollout status -n "$DRA_NS" "ds/$DS" --timeout=300s >/dev/null; then
    pass "kubelet plugin $DS ready (driver-init found the mock driver)"
else
    fail "kubelet plugin $DS not ready"
    kubectl logs -n "$DRA_NS" "ds/$DS" --all-containers --tail=30 2>&1 | sed 's/^/    | /'
fi

# ── 3. ResourceSlice ─────────────────────────────────────────────────────

section "3. ResourceSlice"

# Check every device on the agent nodes, rather than counting other AMD
# drivers in the cluster or accepting only the first device's attributes.
valid=0
for _ in $(seq 1 30); do
    # Intentional word splitting: AGENT_NODES is kubectl's node-name list.
    # shellcheck disable=SC2086
    if kubectl get resourceslices -o json | python3 "$REPO_ROOT/tests/dra/check-slices.py" "$EXPECTED_GPUS" $AGENT_NODES; then
        valid=1
        break
    fi
    sleep 2
done
if [ "$valid" -eq 1 ]; then
    pass "all mock ResourceSlice devices have attributes and capacities"
else
    fail "mock ResourceSlice validation failed"
fi

# ── 4. Claim a GPU ───────────────────────────────────────────────────────

section "4. Claim a GPU through DRA"

kubectl create namespace "$TEST_NS" --dry-run=client -o yaml | kubectl apply -f - >/dev/null
kubectl -n "$TEST_NS" delete pod dra-gpu-demo --ignore-not-found >/dev/null 2>&1
kubectl -n "$TEST_NS" apply -f "$REPO_ROOT/deployments/dra/demo.yaml" >/dev/null || fail "applying demo.yaml failed"
if kubectl -n "$TEST_NS" wait pod/dra-gpu-demo --for=condition=Ready --timeout=180s >/dev/null 2>&1; then
    pass "pod with a ResourceClaim is running"
    if kubectl -n "$TEST_NS" exec dra-gpu-demo -- test -c /dev/kfd 2>/dev/null; then
        pass "/dev/kfd injected into the pod"
    else
        fail "/dev/kfd not present in the pod"
    fi
    # shellcheck disable=SC2016 # expanded by the shell inside the pod
    if kubectl -n "$TEST_NS" exec dra-gpu-demo -- sh -c '
        set -- /dev/dri/renderD*; [ "$#" -eq 1 ] && test -c "$1" || exit 1
        set -- /dev/dri/card*; [ "$#" -eq 1 ] && test -c "$1"
    ' >/dev/null 2>&1; then
        pass "exactly one card and one render character device injected"
    else
        fail "allocated pod must have exactly one card and one render character device"
    fi
else
    fail "pod with a ResourceClaim did not start"
    kubectl -n "$TEST_NS" describe pod dra-gpu-demo 2>&1 | tail -15 | sed 's/^/    | /'
fi

# ── 5. Selectors and reallocation ────────────────────────────────────────
section "5. Selectors and reallocation"
# This scenario intentionally uses MI300X. Use a dedicated single-node test
# cluster so no other consumer can satisfy or interfere with these claims.
make_pod() {
    local name="$1" template="$2"
    sed -e "s/name: dra-gpu-demo/name: $name/" \
        -e "s/resourceClaimTemplateName: amd-gpu/resourceClaimTemplateName: $template/" \
        "$REPO_ROOT/deployments/dra/demo.yaml" | kubectl -n "$TEST_NS" apply -f - >/dev/null
}
make_pod dra-selector amd-mi300x
if kubectl -n "$TEST_NS" wait pod/dra-selector --for=condition=Ready --timeout=180s >/dev/null 2>&1; then
    pass "matching productName selector allocates a GPU"
else
    fail "matching productName selector did not start"
fi
# Create a selector that cannot match any rendered profile.
sed -e 's/name: amd-mi300x/name: amd-no-match/' \
    -e 's/AMD_Instinct_MI300X_OAM/DOES_NOT_EXIST/' \
    "$REPO_ROOT/deployments/dra/demo.yaml" | kubectl -n "$TEST_NS" apply -f - >/dev/null
make_pod dra-no-match amd-no-match
sleep 10
phase="$(kubectl -n "$TEST_NS" get pod dra-no-match -o jsonpath='{.status.phase}')"
claim="$(kubectl -n "$TEST_NS" get pod dra-no-match -o jsonpath='{.status.resourceClaimStatuses[0].resourceClaimName}')"
if [ "$phase" = Pending ] && [ -n "$claim" ] && \
    [ -z "$(kubectl -n "$TEST_NS" get resourceclaim "$claim" -o jsonpath='{.status.allocation}')" ]; then
    pass "nonmatching selector stays Pending with an unallocated claim"
else
    fail "nonmatching selector unexpectedly allocated, or claim was not created"
fi
claim="$(kubectl -n "$TEST_NS" get pod dra-gpu-demo -o jsonpath='{.status.resourceClaimStatuses[0].resourceClaimName}')"
allocated="$(kubectl -n "$TEST_NS" get resourceclaim "$claim" -o jsonpath='{.status.allocation.devices.results[0].device}')"
pool="$(kubectl -n "$TEST_NS" get resourceclaim "$claim" -o jsonpath='{.status.allocation.devices.results[0].pool}')"
kubectl get resourceslices -o json > "$WORK/slices.json"
bdf="$(python3 - "$WORK/slices.json" "$pool" "$allocated" <<'JSON'
import json, sys
with open(sys.argv[1]) as stream:
    slices = json.load(stream)['items']
for item in slices:
    spec = item['spec']
    if spec['driver'] != 'gpu.amd.com' or spec['pool']['name'] != sys.argv[2]:
        continue
    for device in spec['devices']:
        if device['name'] == sys.argv[3]:
            print(device['attributes']['resource.kubernetes.io/pciBusID']['string'])
            sys.exit(0)
raise SystemExit('allocated device has no PCI address')
JSON
)"
kubectl -n "$TEST_NS" delete pod dra-gpu-demo --wait=true --timeout=120s >/dev/null
if [ -n "$claim" ] && kubectl -n "$TEST_NS" wait "resourceclaim/$claim" --for=delete --timeout=120s >/dev/null 2>&1; then
    pass "generated claim removed after pod deletion"
else
    fail "generated claim not removed after pod deletion"
fi
python3 - "$bdf" <<'JSON' > "$WORK/reclaim.json"
import json, sys
if not sys.argv[1]:
    raise SystemExit("original claim has no allocated device")
print(json.dumps({"apiVersion": "resource.k8s.io/v1", "kind": "ResourceClaimTemplate",
 "metadata": {"name": "amd-reclaim"}, "spec": {"spec": {"devices": {"requests": [
 {"name": "gpu", "exactly": {"deviceClassName": "gpu.amd.com", "selectors": [
 {"cel": {"expression": 'device.attributes["resource.kubernetes.io"].pciBusID == ' + json.dumps(sys.argv[1])}}
 ]}}
 ]}}}}))
JSON
kubectl -n "$TEST_NS" apply -f "$WORK/reclaim.json" >/dev/null
make_pod dra-gpu-demo amd-reclaim
if kubectl -n "$TEST_NS" wait pod/dra-gpu-demo --for=condition=Ready --timeout=180s >/dev/null 2>&1; then
    new_claim="$(kubectl -n "$TEST_NS" get pod dra-gpu-demo -o jsonpath='{.status.resourceClaimStatuses[0].resourceClaimName}')"
    new_device="$(kubectl -n "$TEST_NS" get resourceclaim "$new_claim" -o jsonpath='{.status.allocation.devices.results[0].device}')"
    if [ "$new_device" = "$allocated" ]; then
        pass "same GPU allocates after prior pod and claim deletion"
    else
        fail "reallocation returned $new_device instead of $allocated"
    fi
else
    fail "reallocation pod did not start"
fi

# ── Summary ──────────────────────────────────────────────────────────────

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$KEEP" = "1" ] && echo "KEEP=1: AMD's DRA driver and the demo pod were left installed."
[ "$FAIL" -eq 0 ]
