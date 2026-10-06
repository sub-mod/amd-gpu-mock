# Architecture

## Design principle

Simulate the contract surfaces that AMD GPU consumers read, not the GPUs
themselves. If software **reads** hardware state — the mock answers.
If software **executes** on the GPU — it needs real hardware.

## System overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    YOUR APPLICATION                             │
│    (LLM, training job, inference server)                        │
│    Requests: amd.com/gpu: 1                                     │
│    ↓ gets scheduled by Kubernetes                               │
├─────────────────────────────────────────────────────────────────┤
│              AMD GPU OPERATOR (SIM_ENABLE mode)                 │
│    ├── Device Plugin      → reads mock sysfs                    │
│    ├── Metrics Exporter   → reads mock libamd_smi.so            │
│    └── Node Labeller      → reads mock sysfs                    │
│    ↓ registers amd.com/gpu with kubelet                         │
├─────────────────────────────────────────────────────────────────┤
│              amd-gpu-mock (Node Agent DaemonSet)                │
│    ├── KFD sysfs topology (/sys/class/kfd/kfd/topology/)        │
│    ├── Device nodes (/dev/kfd, /dev/dri/renderD*, /dev/dri/card*)│
│    ├── PCI sysfs (/sys/bus/pci/devices/)                        │
│    ├── Driver module (/sys/module/amdgpu/)                      │
│    ├── Mock libamd_smi.so (185 symbols)                         │
│    ├── CDI specs (/var/lib/amd-gpu-mock/cdi/amd.json)           │
│    ├── Prometheus /metrics endpoint                             │
│    └── Web dashboard + REST API                                 │
├─────────────────────────────────────────────────────────────────┤
│              KIND Node (docker.io/submod/amd-mock-kind-node)    │
│    ├── amd-container-runtime (CDI runtime handler)              │
│    ├── containerd: enable_cdi = true, AMD runtime registered    │
│    └── CDI specs at /etc/cdi/ resolved at container creation    │
├─────────────────────────────────────────────────────────────────┤
│              Podman (macOS) or Docker (Linux)                   │
└─────────────────────────────────────────────────────────────────┘
```

## Components

### Node Agent (DaemonSet)

The core component. Reads a GPU profile YAML and stages all simulated
surfaces onto the host filesystem:

- **KFD sysfs** — `/sys/class/kfd/kfd/topology/nodes/*/properties` with
  per-GPU properties (SIMD count, VRAM, vendor ID, device ID, gfx target)
- **Device nodes** — `/dev/kfd` (char 234:0), `/dev/dri/renderD128..N`
  (char 226:128+N), `/dev/dri/card0..N` (char 226:N)
- **PCI sysfs** — vendor/device/class/numa_node per GPU, root complex symlinks
- **Driver module** — `/sys/module/amdgpu/initstate` (live), version, refcount,
  driver bindings per BDF with DRM card entries
- **CDI specs** — `amd.json` matching `amd-ctk cdi generate` format
- **Mock library** — `libamd_smi.so` staged for metrics exporter
- **Dynamic metrics** — time-varying temperature, power, utilization, clocks
- **API server** — REST endpoints for fleet management and fault injection
- **Prometheus metrics** — `/metrics` endpoint with per-GPU labels

### KIND Node Image

`docker.io/submod/amd-mock-kind-node:latest` — includes:

- **amd-container-runtime** — CDI-aware OCI runtime hook, registered with
  containerd as the default runc handler. When a container references a CDI
  device (`amd.com/gpu=0`), the runtime resolves the CDI spec and injects
  the device nodes, mounts, and environment variables.
- **amd-ctk** — CDI spec toolkit (not used at runtime, but available for
  manual spec generation)
- **containerd config** — `enable_cdi = true` with AMD runtime registered
- **CDI spec directories** — `/etc/cdi/` and `/var/run/cdi/` where the
  node agent writes the mock CDI specs

Cross-compiled from [ROCm/container-toolkit](https://github.com/ROCm/container-toolkit)
source for native arm64 (macOS) and amd64 (Linux).

### GPU Operator Integration (SIM_ENABLE)

The AMD GPU Operator (v1.5.0) runs in `SIM_ENABLE` mode using a patched
controller image (`docker.io/submod/gpu-operator-sim:latest`). When
`SIM_ENABLE=true`:

- Init containers skip `/sys/class/kfd` and `/sys/module/amdgpu` checks
- Operand pods mount mock sysfs from `/var/lib/amd-gpu-mock/sys` at `/sys`
- Device plugin discovers GPUs from mock sysfs topology
- Metrics exporter reads mock `libamd_smi.so`
- Node labeller derives GPU labels from mock properties

### Helm Chart

`oci://docker.io/submod/amd-gpu-mock:0.1.0` — deploys the node agent
DaemonSet and device plugin as a single install. Includes:
- ConfigMap with GPU profile
- DaemonSet (node agent + device plugin)
- Service for metrics scraping
- ServiceMonitor for Prometheus auto-discovery (opt-in)

## Mock surfaces and consumers

| Mock Surface | Created by | Read by |
|---|---|---|
| KFD sysfs topology | Node Agent | Device Plugin, Node Labeller |
| Driver module sysfs | Node Agent | Device Plugin (discovery), Node Labeller |
| Device nodes | Node Agent (mknod) | Device Plugin (health check), kubelet (pod mount) |
| PCI sysfs | Node Agent | Node Labeller (topology labels) |
| CDI specs | Node Agent | containerd (device injection) |
| Mock libamd_smi.so | Node Agent (staged) | Metrics Exporter (gpuagent), amd-smi |
| /metrics endpoint | Node Agent API | Prometheus |
| Dashboard API | Node Agent API | Web browser |
