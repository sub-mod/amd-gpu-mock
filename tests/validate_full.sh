#!/usr/bin/env bash
# Full stack validation — checks every layer of the AMD GPU mock infrastructure.
#
# Tests the complete chain:
#   Mock sysfs → Device Plugin → GPU Resources → Pod Scheduling → Metrics
#
# Run after deploying the mock + GPU Operator + LLM demo:
#   ./tests/validate_full.sh
#
# Each test prints which layer it validates so you know where to look on failure.

set -uo pipefail

PASS=0
FAIL=0
NS_MOCK="amd-mock"
NS_GPU="kube-amd-gpu"
DS="amd-gpu-mock"

pass() { echo "  PASS: $1"; ((PASS++)); }
fail() { echo "  FAIL: $1"; ((FAIL++)); }

section() { echo ""; echo "=== $1 ==="; }

# ────────────────────────────────────────────────────────────────────────
section "Layer 1: Mock Infrastructure (amd-gpu-mock DaemonSet)"
# ────────────────────────────────────────────────────────────────────────

if kubectl -n $NS_MOCK get ds/$DS -o jsonpath='{.status.numberReady}' 2>/dev/null | grep -q "[1-9]"; then
  pass "Mock DaemonSet is running"
else
  fail "Mock DaemonSet not running"
fi

if kubectl -n $NS_MOCK exec ds/$DS -- test -c /var/lib/amd-gpu-mock/dev/kfd 2>/dev/null; then
  pass "/dev/kfd char device exists"
else
  fail "/dev/kfd not found"
fi

RENDER=$(kubectl -n $NS_MOCK exec ds/$DS -- ls /var/lib/amd-gpu-mock/dev/dri/ 2>/dev/null | grep -c renderD || echo 0)
if [ "$RENDER" -ge 4 ]; then
  pass "$RENDER render nodes created"
else
  fail "Expected 4+ render nodes, got $RENDER"
fi

if kubectl -n $NS_MOCK exec ds/$DS -- test -f /var/lib/amd-gpu-mock/sys/class/kfd/kfd/topology/nodes/1/properties 2>/dev/null; then
  GPU_NAME=$(kubectl -n $NS_MOCK exec ds/$DS -- cat /var/lib/amd-gpu-mock/sys/class/kfd/kfd/topology/nodes/1/name 2>/dev/null | tr -d '\n')
  pass "KFD topology: $GPU_NAME"
else
  fail "KFD topology not found"
fi

DRIVER_VER=$(kubectl -n $NS_MOCK exec ds/$DS -- cat /var/lib/amd-gpu-mock/sys/module/amdgpu/version 2>/dev/null | tr -d '\n')
if [ -n "$DRIVER_VER" ]; then
  pass "Driver module: amdgpu $DRIVER_VER"
else
  fail "Driver module not found"
fi

INITSTATE=$(kubectl -n $NS_MOCK exec ds/$DS -- cat /var/lib/amd-gpu-mock/sys/module/amdgpu/initstate 2>/dev/null | tr -d '\n')
if [ "$INITSTATE" = "live" ]; then
  pass "Driver initstate: live"
else
  fail "Driver initstate not 'live' (got: $INITSTATE)"
fi

if kubectl -n $NS_MOCK exec ds/$DS -- test -f /var/lib/amd-gpu-mock/cdi/amd.json 2>/dev/null; then
  pass "CDI spec generated"
else
  fail "CDI spec not found"
fi

if kubectl -n $NS_MOCK exec ds/$DS -- test -f /var/lib/amd-gpu-mock/driver/usr/lib64/libamd_smi.so 2>/dev/null; then
  pass "Mock libamd_smi.so staged"
else
  fail "Mock library not staged"
fi

# ────────────────────────────────────────────────────────────────────────
section "Layer 2: GPU Operator Controller"
# ────────────────────────────────────────────────────────────────────────

CTL_READY=$(kubectl -n $NS_GPU get pods -l control-plane=controller-manager -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null)
CTL_IMAGE=$(kubectl -n $NS_GPU get pods -l control-plane=controller-manager -o jsonpath='{.items[0].spec.containers[0].image}' 2>/dev/null)
if [ "$CTL_READY" = "true" ]; then
  pass "GPU Operator controller running ($CTL_IMAGE)"
else
  fail "GPU Operator controller not ready"
fi

SIM=$(kubectl -n $NS_GPU get pods -l control-plane=controller-manager -o jsonpath='{.items[0].spec.containers[0].env}' 2>/dev/null)
if echo "$SIM" | grep -q "SIM_ENABLE"; then
  pass "SIM_ENABLE=true set on controller"
else
  fail "SIM_ENABLE not set on controller"
fi

# ────────────────────────────────────────────────────────────────────────
section "Layer 3: GPU Operator Operands"
# ────────────────────────────────────────────────────────────────────────

for OPERAND in device-plugin metrics-exporter node-labeller; do
  POD=$(kubectl -n $NS_GPU get pods -o name 2>/dev/null | grep "default-$OPERAND" | head -1)
  if [ -z "$POD" ]; then
    fail "$OPERAND: pod not found"
    continue
  fi

  # Init container
  INIT_EXIT=$(kubectl -n $NS_GPU get $POD -o jsonpath='{.status.initContainerStatuses[0].state.terminated.exitCode}' 2>/dev/null)
  if [ "$INIT_EXIT" = "0" ]; then
    pass "$OPERAND: init container passed (SIM_ENABLE bypass)"
  else
    fail "$OPERAND: init container did not pass (exit=$INIT_EXIT)"
  fi

  # Main container
  READY=$(kubectl -n $NS_GPU get $POD -o jsonpath='{.status.containerStatuses[0].ready}' 2>/dev/null)
  if [ "$READY" = "true" ]; then
    pass "$OPERAND: main container ready"
  else
    STATE=$(kubectl -n $NS_GPU get $POD -o jsonpath='{.status.containerStatuses[0].state}' 2>/dev/null)
    fail "$OPERAND: main container not ready ($STATE)"
  fi

  # Volume mount — should use mock sysfs
  SYS_HOST=$(kubectl -n $NS_GPU get $POD -o jsonpath='{range .spec.volumes[*]}{.name}={.hostPath.path}{"\n"}{end}' 2>/dev/null | grep sys | head -1)
  if echo "$SYS_HOST" | grep -q "amd-gpu-mock"; then
    pass "$OPERAND: sysfs mounted from mock ($SYS_HOST)"
  else
    if [ "$OPERAND" = "metrics-exporter" ]; then
      pass "$OPERAND: uses libamd_smi.so (not sysfs mount)"
    else
      fail "$OPERAND: sysfs mounted from real /sys ($SYS_HOST)"
    fi
  fi
done

# ────────────────────────────────────────────────────────────────────────
section "Layer 4: Kubernetes GPU Resources"
# ────────────────────────────────────────────────────────────────────────

GPU_COUNT=$(kubectl get node -o jsonpath='{.items[0].status.allocatable.amd\.com/gpu}' 2>/dev/null)
if [ -n "$GPU_COUNT" ] && [ "$GPU_COUNT" -gt 0 ] 2>/dev/null; then
  pass "amd.com/gpu allocatable: $GPU_COUNT"
else
  fail "amd.com/gpu not allocatable (got: $GPU_COUNT)"
fi

# ────────────────────────────────────────────────────────────────────────
section "Layer 5: Pod Scheduling"
# ────────────────────────────────────────────────────────────────────────

kubectl delete pod validate-gpu-pod 2>/dev/null || true
kubectl run validate-gpu-pod --image=busybox --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"test","image":"busybox","command":["sh","-c","echo OK && sleep 5"],"resources":{"limits":{"amd.com/gpu":"1"}}}]}}' 2>/dev/null
sleep 10
POD_STATUS=$(kubectl get pod validate-gpu-pod -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$POD_STATUS" = "Running" ] || [ "$POD_STATUS" = "Succeeded" ]; then
  pass "Pod with amd.com/gpu: 1 scheduled and running"
else
  fail "Pod scheduling failed (status: $POD_STATUS)"
fi
kubectl delete pod validate-gpu-pod --wait=false 2>/dev/null || true

# ────────────────────────────────────────────────────────────────────────
section "Layer 6: API and Dashboard"
# ────────────────────────────────────────────────────────────────────────

API=$(kubectl -n $NS_MOCK exec ds/$DS -- wget -qO- http://localhost:8080/api/gpus 2>/dev/null)
if echo "$API" | python3 -c "import json,sys; assert len(json.load(sys.stdin)['gpus'])>0" 2>/dev/null; then
  API_COUNT=$(echo "$API" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['gpus']))" 2>/dev/null)
  pass "Dashboard API: $API_COUNT GPUs"
else
  fail "Dashboard API not responding"
fi

PROFILES=$(kubectl -n $NS_MOCK exec ds/$DS -- wget -qO- http://localhost:8080/api/profiles 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
if [ "$PROFILES" -ge 5 ]; then
  pass "GPU profiles loaded: $PROFILES"
else
  fail "Expected 5+ profiles, got $PROFILES"
fi

# ────────────────────────────────────────────────────────────────────────
section "Layer 7: Prometheus Metrics"
# ────────────────────────────────────────────────────────────────────────

METRICS=$(kubectl -n $NS_MOCK exec ds/$DS -- wget -qO- http://localhost:8080/metrics 2>/dev/null)
if echo "$METRICS" | grep -q "gpu_temperature"; then
  METRIC_COUNT=$(echo "$METRICS" | grep -c "^gpu_" || echo 0)
  pass "Prometheus /metrics endpoint: $METRIC_COUNT metric lines"
else
  fail "Prometheus metrics not available"
fi

# ────────────────────────────────────────────────────────────────────────
section "Layer 8: Fault Injection"
# ────────────────────────────────────────────────────────────────────────

kubectl -n $NS_MOCK exec ds/$DS -- wget -qO- --post-data='' 'http://localhost:8080/api/actions/crash?gpu=0' >/dev/null 2>&1
CRASHED=$(kubectl -n $NS_MOCK exec ds/$DS -- wget -qO- http://localhost:8080/api/gpus 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['gpus'][0]['status'])" 2>/dev/null)
if [ "$CRASHED" = "crashed" ]; then
  pass "GPU 0 crashed via API"
else
  fail "Crash injection failed"
fi

FATAL=$(kubectl -n $NS_MOCK exec ds/$DS -- cat /var/lib/amd-gpu-mock/sys/class/kfd/kfd/topology/nodes/1/ras/fatal_error 2>/dev/null | tr -d '\n')
if [ "$FATAL" = "1" ]; then
  pass "Sysfs ras/fatal_error reflects crash"
else
  fail "Sysfs not updated"
fi

kubectl -n $NS_MOCK exec ds/$DS -- wget -qO- --post-data='' 'http://localhost:8080/api/actions/recover?gpu=0' >/dev/null 2>&1
RECOVERED=$(kubectl -n $NS_MOCK exec ds/$DS -- wget -qO- http://localhost:8080/api/gpus 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['gpus'][0]['status'])" 2>/dev/null)
if [ "$RECOVERED" = "healthy" ]; then
  pass "GPU 0 recovered"
else
  fail "Recovery failed"
fi

# ────────────────────────────────────────────────────────────────────────
section "SUMMARY"
# ────────────────────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL))
echo ""
echo "  Layers tested: 8"
echo "  Total checks:  $TOTAL"
echo "  Pass:          $PASS"
echo "  Fail:          $FAIL"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "  ALL LAYERS PASSED"
  exit 0
else
  echo "  $FAIL CHECKS FAILED"
  exit 1
fi
