# AMD GPU Operator

Deploy the AMD GPU Operator on top of amd-gpu-mock. The Operator's device
plugin and node labeller are covered by the SIM_ENABLE smoke test.
Operator-owned metrics exporter integration is not yet validated. For tested
real AMD telemetry, use the separate [telemetry setup](telemetry.md).

## Prerequisites

- amd-gpu-mock deployed with both bundled allocators disabled:
  `--set dra.enabled=false --set devicePlugin.enabled=false`
- cert-manager installed

## Install

```bash
# cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace \
  --version v1.15.1 --set crds.enabled=true --wait

# Label nodes for GPU Operator targeting
kubectl label node --all feature.node.kubernetes.io/amd-gpu=true

# Install GPU Operator (driver disabled for mock)
helm repo add rocm https://rocm.github.io/gpu-operator
helm install amd-gpu-operator rocm/gpu-operator-charts \
  --namespace kube-amd-gpu --create-namespace \
  --version v1.5.0 \
  --set kmm.enabled=false --set kmm.watch=false \
  --set remediation.enabled=false \
  --set node-feature-discovery.enabled=false --set installdefaultNFDRule=false \
  --set deviceConfig.spec.driver.enable=false \
  --set deviceConfig.spec.metricsExporter.enable=false

# Use mock-aware controller image with SIM_ENABLE
kubectl -n kube-amd-gpu set image deployment/amd-gpu-operator-gpu-operator-charts-controller-manager \
  manager=docker.io/submod/gpu-operator-sim:latest
kubectl -n kube-amd-gpu set env deployment/amd-gpu-operator-gpu-operator-charts-controller-manager \
  SIM_ENABLE=true
```

## How SIM_ENABLE works

The AMD GPU Operator's operand init containers check for the amdgpu kernel
driver before starting:

```bash
while [ ! -d /sys/class/kfd ] || [ ! -d /sys/module/amdgpu/drivers/ ]; do
    echo "amdgpu driver is not loaded"; sleep 2
done
```

With `SIM_ENABLE=true`, this check is bypassed — init containers exit
immediately. The main containers then mount the mock sysfs tree from
`/var/lib/amd-gpu-mock/sys` at `/sys`, discovering GPUs from the mock
topology instead of real kernel sysfs.

AMD already uses `SIM_ENABLE` in the metrics exporter, config manager, and
test runner operands. The patched controller image
(`docker.io/submod/gpu-operator-sim:latest`) extends it to the device plugin
and node labeller — using the same pattern.

Fork: [github.com/sub-mod/gpu-operator](https://github.com/sub-mod/gpu-operator)

## Verify

```bash
# Inspect enabled operands
kubectl -n kube-amd-gpu get pods

# GPUs registered by the Operator's device plugin
kubectl get node -o jsonpath='{.items[0].status.allocatable.amd\.com/gpu}'
# → 8

# Current Operator smoke suite (DME, KMM and NFD disabled)
python3 tests/operator-e2e.py
```

## What the Operator deploys

| Operand | What it reads | What it produces |
|---------|-------------|-----------------|
| Device Plugin | Mock sysfs (`/sys/module/amdgpu/drivers/`) | `amd.com/gpu: 8` on the node |
| Metrics Exporter | Requires matching AMD SMI runtime and mounts | Operator-owned deployment not validated; use telemetry guide |
| Node Labeller | Mock sysfs (KFD topology properties) | GPU node labels (model, VRAM, CUs) |
| NFD Worker | PCI discovery | Disabled in current smoke coverage |

## Uninstall

```bash
helm uninstall amd-gpu-operator --namespace kube-amd-gpu
```

## Validation limits

SIM_ENABLE bypasses readiness checks; it does not prove the device library
or every Operator operand works. The published controller is a fork image,
not a merged upstream AMD feature. The upstream draft PR was closed; no new
upstream Operator PR is part of this telemetry release. The smoke test covers
controller identity, init completion, plugin/labeller readiness, eight-GPU
capacity and exact one-GPU injection. Operator-managed DRA, remediation,
KMM, NFD and the full exporter operand stack remain unvalidated.

Chart 0.2.13 can run its standalone exporter and bundled Prometheus/Grafana
alongside the Operator smoke setup. Those collectors are owned by the mock
chart, not the Operator. The isolated Operator CI job disables bundled
monitoring so it continues to test only controller/plugin/labeller behavior.
