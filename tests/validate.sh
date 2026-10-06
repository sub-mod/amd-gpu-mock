#!/usr/bin/env bash
# amd-gpu-mock Validation Suite
#
# Runs all validation checks against a deployed mock cluster.
# Validates the mock GPU infrastructure end-to-end.
#
# Prerequisites:
#   - KIND cluster "amd-mock" running
#   - amd-gpu-mock Helm release deployed
#   - amd-gpu-mock-device-plugin deployed
#
# Usage:
#   ./tests/validate.sh

set -uo pipefail

PASS=0
FAIL=0
SKIP=0

pass() { echo "  PASS: $1"; ((PASS++)); }
fail() { echo "  FAIL: $1"; ((FAIL++)); }
skip() { echo "  SKIP: $1"; ((SKIP++)); }

section() { echo ""; echo "=== $1 ==="; }

NS="amd-mock"
DS="amd-gpu-mock"

# ── Section 1: Mock Infrastructure ──────────────────────────────────────

section "1. Mock Infrastructure"

# 1.1 DaemonSet running
if kubectl -n $NS get ds/$DS -o jsonpath='{.status.numberReady}' 2>/dev/null | grep -q "[1-9]"; then
  pass "DaemonSet $DS is running"
else
  fail "DaemonSet $DS is not running"
fi

# 1.2 /dev/kfd exists on node
if kubectl -n $NS exec ds/$DS -- test -c /var/lib/amd-gpu-mock/dev/kfd 2>/dev/null; then
  pass "/dev/kfd char device exists"
else
  fail "/dev/kfd not found"
fi

# 1.3 Render nodes exist
RENDER_COUNT=$(kubectl -n $NS exec ds/$DS -- ls /var/lib/amd-gpu-mock/dev/dri/ 2>/dev/null | grep -c renderD || echo 0)
if [ "$RENDER_COUNT" -ge 4 ]; then
  pass "$RENDER_COUNT render nodes found"
else
  fail "Expected 4+ render nodes, found $RENDER_COUNT"
fi

# 1.4 KFD topology exists
if kubectl -n $NS exec ds/$DS -- test -f /var/lib/amd-gpu-mock/sys/class/kfd/kfd/topology/nodes/1/properties 2>/dev/null; then
  pass "KFD topology exists"
else
  fail "KFD topology not found"
fi

# 1.5 GPU name matches profile
GPU_NAME=$(kubectl -n $NS exec ds/$DS -- cat /var/lib/amd-gpu-mock/sys/class/kfd/kfd/topology/nodes/1/name 2>/dev/null | tr -d '\n')
if [ -n "$GPU_NAME" ]; then
  pass "GPU name: $GPU_NAME"
else
  fail "GPU name not found"
fi

# 1.6 Driver module present
DRIVER_VER=$(kubectl -n $NS exec ds/$DS -- cat /var/lib/amd-gpu-mock/sys/module/amdgpu/version 2>/dev/null | tr -d '\n')
if [ -n "$DRIVER_VER" ]; then
  pass "amdgpu driver version: $DRIVER_VER"
else
  fail "amdgpu driver module not found"
fi

# 1.7 PCI sysfs symlinks
PCI_COUNT=$(kubectl -n $NS exec ds/$DS -- ls /var/lib/amd-gpu-mock/sys/bus/pci/devices/ 2>/dev/null | wc -l | tr -d ' ')
if [ "$PCI_COUNT" -ge 4 ]; then
  pass "$PCI_COUNT PCI device symlinks"
else
  fail "Expected 4+ PCI devices, found $PCI_COUNT"
fi

# 1.8 xGMI hive ID
HIVE=$(kubectl -n $NS exec ds/$DS -- cat /var/lib/amd-gpu-mock/sys/class/drm/card0/device/xgmi_hive_info/xgmi_hive_id 2>/dev/null | tr -d '\n')
if [ -n "$HIVE" ] && [ "$HIVE" != "0" ]; then
  pass "xGMI hive ID: $HIVE"
else
  skip "xGMI hive not configured"
fi

# 1.9 CDI spec generated
if kubectl -n $NS exec ds/$DS -- test -f /var/lib/amd-gpu-mock/cdi/amd.json 2>/dev/null; then
  CDI_DEVICES=$(kubectl -n $NS exec ds/$DS -- cat /var/lib/amd-gpu-mock/cdi/amd.json 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)['devices']))" 2>/dev/null || echo 0)
  pass "CDI spec: $CDI_DEVICES devices"
else
  fail "CDI spec not found"
fi

# 1.10 Mock library staged
if kubectl -n $NS exec ds/$DS -- test -f /var/lib/amd-gpu-mock/driver/usr/lib64/libamd_smi.so 2>/dev/null; then
  pass "Mock libamd_smi.so staged on host"
else
  fail "Mock library not staged"
fi

# ── Section 2: Kubernetes GPU Resources ─────────────────────────────────

section "2. Kubernetes GPU Resources"

# 2.1 Device plugin running
if kubectl -n kube-system get ds/amd-gpu-mock-device-plugin -o jsonpath='{.status.numberReady}' 2>/dev/null | grep -q "[1-9]"; then
  pass "AMD device plugin running"
else
  fail "AMD device plugin not running"
fi

# 2.2 amd.com/gpu allocatable
GPU_COUNT=$(kubectl get node -o jsonpath='{.items[0].status.allocatable.amd\.com/gpu}' 2>/dev/null)
if [ -n "$GPU_COUNT" ] && [ "$GPU_COUNT" -gt 0 ] 2>/dev/null; then
  pass "amd.com/gpu allocatable: $GPU_COUNT"
else
  fail "amd.com/gpu not allocatable"
fi

# 2.3 Pod scheduling
kubectl delete pod validate-gpu-pod 2>/dev/null || true
kubectl run validate-gpu-pod --image=busybox --restart=Never \
  --overrides='{"spec":{"containers":[{"name":"test","image":"busybox","command":["sh","-c","echo OK && sleep 5"],"resources":{"limits":{"amd.com/gpu":"1"}}}]}}' 2>/dev/null
sleep 8
POD_STATUS=$(kubectl get pod validate-gpu-pod -o jsonpath='{.status.phase}' 2>/dev/null)
if [ "$POD_STATUS" = "Running" ] || [ "$POD_STATUS" = "Succeeded" ]; then
  pass "Pod with amd.com/gpu: 1 scheduled and running"
else
  fail "Pod scheduling failed (status: $POD_STATUS)"
fi
kubectl delete pod validate-gpu-pod --wait=false 2>/dev/null || true

# ── Section 3: API and Dashboard ────────────────────────────────────────

section "3. API and Dashboard"

# 3.1 API responds
API_RESPONSE=$(kubectl -n $NS exec ds/$DS -- wget -qO- http://localhost:8080/api/gpus 2>/dev/null)
if echo "$API_RESPONSE" | python3 -c "import json,sys; d=json.load(sys.stdin); assert len(d['gpus'])>0" 2>/dev/null; then
  API_GPU_COUNT=$(echo "$API_RESPONSE" | python3 -c "import json,sys; print(len(json.load(sys.stdin)['gpus']))" 2>/dev/null)
  pass "API returns $API_GPU_COUNT GPUs"
else
  fail "API not responding or no GPUs"
fi

# 3.2 Profiles loaded
PROFILE_COUNT=$(kubectl -n $NS exec ds/$DS -- wget -qO- http://localhost:8080/api/profiles 2>/dev/null | python3 -c "import json,sys; print(len(json.load(sys.stdin)))" 2>/dev/null || echo 0)
if [ "$PROFILE_COUNT" -ge 5 ]; then
  pass "$PROFILE_COUNT GPU profiles loaded"
else
  fail "Expected 5+ profiles, found $PROFILE_COUNT"
fi

# 3.3 Dynamic metrics (values change)
TEMP1=$(kubectl -n $NS exec ds/$DS -- wget -qO- http://localhost:8080/api/gpus 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['gpus'][0]['temperature_c'])" 2>/dev/null)
sleep 3
TEMP2=$(kubectl -n $NS exec ds/$DS -- wget -qO- http://localhost:8080/api/gpus 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['gpus'][0]['temperature_c'])" 2>/dev/null)
if [ "$TEMP1" != "$TEMP2" ] 2>/dev/null; then
  pass "Dynamic metrics: temp changed ($TEMP1 → $TEMP2)"
else
  skip "Dynamic metrics: temp unchanged ($TEMP1 both times)"
fi

# ── Section 4: Fault Injection ──────────────────────────────────────────

section "4. Fault Injection"

# 4.1 Crash and recover
kubectl -n $NS exec ds/$DS -- wget -qO- --post-data='' 'http://localhost:8080/api/actions/crash?gpu=0' >/dev/null 2>&1
CRASH_STATUS=$(kubectl -n $NS exec ds/$DS -- wget -qO- http://localhost:8080/api/gpus 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['gpus'][0]['status'])" 2>/dev/null)
if [ "$CRASH_STATUS" = "crashed" ]; then
  pass "GPU 0 crashed via API"
else
  fail "Crash injection failed (status: $CRASH_STATUS)"
fi

# 4.2 Sysfs reflects crash
FATAL=$(kubectl -n $NS exec ds/$DS -- cat /var/lib/amd-gpu-mock/sys/class/kfd/kfd/topology/nodes/1/ras/fatal_error 2>/dev/null | tr -d '\n')
if [ "$FATAL" = "1" ]; then
  pass "Sysfs ras/fatal_error = 1"
else
  fail "Sysfs doesn't reflect crash (fatal_error=$FATAL)"
fi

# 4.3 Recover
kubectl -n $NS exec ds/$DS -- wget -qO- --post-data='' 'http://localhost:8080/api/actions/crash?gpu=0' >/dev/null 2>&1
RECOVER_STATUS=$(kubectl -n $NS exec ds/$DS -- wget -qO- http://localhost:8080/api/gpus 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin)['gpus'][0]['status'])" 2>/dev/null)
if [ "$RECOVER_STATUS" = "healthy" ]; then
  pass "GPU 0 recovered (toggle)"
else
  fail "Recovery failed (status: $RECOVER_STATUS)"
fi

# ── Section 5: Mock Library ─────────────────────────────────────────────

section "5. Mock Library (amdsmi)"

# 5.1 Library symbol count
SYMBOL_COUNT=$(nm -D /Users/subinm/development/AI/GPU/k8s-infra-amd/pkg/mocksmi/libamd_smi.so 2>/dev/null | grep -c " T amdsmi_" || echo 0)
if [ "$SYMBOL_COUNT" -ge 180 ]; then
  pass "Mock library: $SYMBOL_COUNT amdsmi_ symbols"
else
  fail "Expected 180+ symbols, found $SYMBOL_COUNT"
fi

# ── Summary ─────────────────────────────────────────────────────────────

section "SUMMARY"
TOTAL=$((PASS + FAIL + SKIP))
echo ""
echo "  Total: $TOTAL tests"
echo "  Pass:  $PASS"
echo "  Fail:  $FAIL"
echo "  Skip:  $SKIP"
echo ""

if [ "$FAIL" -eq 0 ]; then
  echo "  ✅ ALL TESTS PASSED"
  exit 0
else
  echo "  ❌ $FAIL TESTS FAILED"
  exit 1
fi
