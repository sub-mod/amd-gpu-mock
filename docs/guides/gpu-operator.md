# AMD GPU Operator

Deploy the AMD GPU Operator on top of amd-gpu-mock. The Operator's device
plugin, metrics exporter, and node labeller run against the mock
infrastructure using `SIM_ENABLE` mode.

## Prerequisites

- amd-gpu-mock deployed (`helm install amd-gpu-mock ...`)
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
SIM_ENABLE=true helm install amd-gpu-operator rocm/gpu-operator-charts \
  --namespace kube-amd-gpu --create-namespace \
  --set kmm.enabled=false \
  --set deviceConfig.spec.driver.enable=false

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
# All operands should be Running
kubectl -n kube-amd-gpu get pods

# GPUs registered by the Operator's device plugin
kubectl get node -o jsonpath='{.items[0].status.allocatable.amd\.com/gpu}'
# → 8

# Full stack validation (27 tests, 8 layers)
./tests/validate_full.sh
```

## What the Operator deploys

| Operand | What it reads | What it produces |
|---------|-------------|-----------------|
| Device Plugin | Mock sysfs (`/sys/module/amdgpu/drivers/`) | `amd.com/gpu: 8` on the node |
| Metrics Exporter | Mock `libamd_smi.so` | Prometheus GPU metrics |
| Node Labeller | Mock sysfs (KFD topology properties) | GPU node labels (model, VRAM, CUs) |
| NFD Worker | PCI vendor ID from feature file | `feature.node.kubernetes.io/amd-gpu=true` |

## Uninstall

```bash
helm uninstall amd-gpu-operator --namespace kube-amd-gpu
```
