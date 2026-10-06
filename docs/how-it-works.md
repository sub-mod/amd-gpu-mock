# How amd-gpu-mock Works

amd-gpu-mock is a pure software simulation framework for AMD Instinct GPUs.
It does not do SR-IOV, hardware virtualization, or GPU passthrough. It takes
a CPU-only node with **no GPUs at all** and intercepts the management API
calls that the cluster uses to look for hardware.

## The Trick

When you deploy amd-gpu-mock on a CPU-only Kubernetes node, here is exactly
what happens:

```
                        WHAT THE CLUSTER SEES
                        =====================

    "I am a server with 8x AMD Instinct MI300X GPUs,
     192 GB HBM3 each, connected via xGMI fabric,
     running amdgpu driver 6.19.4 on ROCm 10.0.0"

                              |
                              |  (this is a lie)
                              |
                        WHAT'S REALLY THERE
                        ===================

    A laptop running Podman with a KIND container.
    Zero GPUs. Zero AMD hardware. Just CPU and RAM.
```

## The Layer Cake

Every GPU management tool reads from a stack of interfaces. amd-gpu-mock
fakes each layer, from the bottom up:

```
┌─────────────────────────────────────────────────────────────────┐
│                    YOUR APPLICATION                             │
│    (LLM, training job, inference server)                        │
│    Requests: amd.com/gpu: 1                                     │
│    ↓ gets scheduled by Kubernetes                               │
├─────────────────────────────────────────────────────────────────┤
│                 KUBERNETES SCHEDULER                            │
│    Sees: "This node has 8 amd.com/gpu available"                │
│    ↓ asks the device plugin                                     │
├─────────────────────────────────────────────────────────────────┤
│              AMD GPU OPERATOR (SIM_ENABLE mode)                 │  ← REAL
│    ├── Device Plugin    → reads mock sysfs → amd.com/gpu: 8    │    AMD
│    ├── Metrics Exporter → reads mock libamd_smi.so             │    CODE
│    └── Node Labeller    → reads mock sysfs → GPU labels        │
│    ↓ registers GPUs with kubelet                                │
├─────────────────────────────────────────────────────────────────┤
│         amd-container-runtime (CDI runtime handler)             │  ← REAL
│    containerd → amd-container-runtime → reads /etc/cdi/amd.json │    AMD
│    → injects /dev/kfd + libraries into containers               │    CODE
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│   ┌──────────────────────────────────────────────────────────┐  │
│   │              amd-gpu-mock MOCK LAYER                     │  │  ← OUR
│   │                                                          │  │    CODE
│   │   KFD Sysfs         Device Nodes      PCI Sysfs          │  │
│   │   /sys/class/kfd/   /dev/kfd           /sys/bus/pci/     │  │
│   │   └── topology/     /dev/dri/renderD*  └── devices/      │  │
│   │       └── nodes/    /dev/dri/card*         └── 0000:*    │  │
│   │           ├── 0/ (CPU)                                   │  │
│   │           ├── 1/ (GPU 0)    Driver Module                │  │
│   │           ├── 2/ (GPU 1)    /sys/module/amdgpu/          │  │
│   │           └── ...           ├── initstate → "live"       │  │
│   │                             ├── version → "6.19.4"       │  │
│   │   Mock libamd_smi.so       └── drivers/pci:amdgpu/      │  │
│   │   (185 API symbols)                                      │  │
│   │   ↑ loaded by metrics       CDI Specs                    │  │
│   │     exporter + amd-smi      /etc/cdi/amd.json            │  │
│   └──────────────────────────────────────────────────────────┘  │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                    ACTUAL HARDWARE                              │
│                                                                 │
│              ┌─────────────────────────┐                       │
│              │    Your Laptop's CPU     │                       │
│              │    (Apple M-series or    │                       │
│              │     Intel/AMD x86)       │                       │
│              │                          │                       │
│              │    Zero GPUs.            │                       │
│              │    Zero AMD hardware.    │                       │
│              └─────────────────────────┘                       │
└─────────────────────────────────────────────────────────────────┘
```

## What Each Piece Fakes

### 1. KFD Sysfs Topology (the primary discovery surface)

The AMD K8s device plugin doesn't call a library — it reads files:

```
/sys/class/kfd/kfd/topology/nodes/1/properties
    ↓
    simd_count 912              ← "this GPU has 912 SIMD units"
    local_mem_size 206158430208 ← "192 GB of VRAM"
    vendor_id 4098              ← "0x1002 = AMD"
    device_id 29857             ← "0x74a1 = MI300X"
    gfx_target_version 90400   ← "gfx942 architecture"
    num_xcc 8                   ← "8 XCDs (compute dies)"
```

Our node agent writes these files from a GPU profile YAML. The device plugin
reads them and thinks it found a real GPU.

### 2. Device Nodes

```
/dev/kfd          ← char device 234:0 (KFD compute interface)
/dev/dri/renderD128  ← char device 226:128 (GPU 0 render node)
/dev/dri/renderD129  ← char device 226:129 (GPU 1)
...
/dev/dri/renderD135  ← char device 226:135 (GPU 7)
/dev/dri/card0..7    ← char device 226:0..7 (DRM card nodes)
```

Created with `mknod` by the node agent. The device plugin checks these
exist and tells kubelet to mount them into GPU workload containers.

### 3. Mock libamd_smi.so (the management library)

```
Real AMD stack:        Our mock:
amd-smi (Python CLI)   amd-smi (Python CLI)
    ↓                      ↓
libamd_smi.so          libamd_smi.so (MOCK — 185 symbols)
    ↓                      ↓
KFD kernel driver      Config YAML → returns fake values
    ↓
Real GPU silicon       (nothing — just returns profile data)
```

When `amd-smi` or the Device Metrics Exporter loads `libamd_smi.so`,
they get our mock library instead. It answers every API call with values
from the GPU profile: temperature, power, memory, clock speeds, ECC
counts, partition mode.

### 4. PCI and DRM Sysfs

```
/sys/bus/pci/devices/0000:05:00.0 → ../../../devices/pci0000:00/0000:05:00.0
    vendor: 0x1002 (AMD)
    device: 0x74a1 (MI300X)
    class:  0x038000 (Processing Accelerator)
    numa_node: 0

/sys/class/drm/card0/device/
    xgmi_hive_info/xgmi_hive_id: 0x1234567890abcdef
    xgmi_device_id: 0x0001
    numa_node: 0
```

Topology-aware consumers (DRA drivers, NUMA schedulers) read these
to understand which GPUs share a PCIe root complex or xGMI fabric.

### 5. Driver Module

```
/sys/module/amdgpu/
    initstate: live      ← amd-smi checks this before anything else
    version: 6.19.4      ← driver version string
    refcnt: 1            ← module is loaded
    drivers/pci:amdgpu/  ← device plugin walks this directory
        0000:05:00.0/drm/card0/device/vendor: 0x1002
        0000:26:00.0/drm/card1/device/vendor: 0x1002
        ...
```

The GPU Operator's init containers check for the driver before starting.
With `SIM_ENABLE=true`, this check is bypassed:

```bash
# AMD's SIM_ENABLE pattern (already in metrics exporter, extended to all operands):
if [ "$SIM_ENABLE" = "true" ]; then exit 0; fi;
while [ ! -d /sys/class/kfd ] || [ ! -d /sys/module/amdgpu/drivers/ ]; do
    echo "amdgpu driver is not loaded"; sleep 2
done
```

With `SIM_ENABLE`, the init containers pass immediately. The main containers
then mount the mock sysfs at `/sys` and discover GPUs from the mock topology.

## The Flow: From Helm Install to Scheduled GPU Pod

```
    YOU                          CLUSTER                       NODE
     │                              │                            │
     │  helm install amd-gpu-mock   │                            │
     ├─────────────────────────────►│                            │
     │                              │  create DaemonSet          │
     │                              ├───────────────────────────►│
     │                              │                            │
     │                              │  Node agent starts         │
     │                              │  ┌─────────────────────┐   │
     │                              │  │ Read mi300x.yaml     │   │
     │                              │  │ Write /sys/class/kfd │   │
     │                              │  │ Write /dev/kfd       │   │
     │                              │  │ Write /dev/dri/*     │   │
     │                              │  │ Write CDI specs      │   │
     │                              │  │ Stage libamd_smi.so  │   │
     │                              │  │ Start API :8080      │   │
     │                              │  └─────────────────────┘   │
     │                              │                            │
     │  helm install gpu-operator    │                            │
     ├─────────────────────────────►│  (SIM_ENABLE=true)         │
     │                              │                            │
     │                              │  GPU Operator deploys:     │
     │                              │  ┌─────────────────────┐   │
     │                              │  │ Device plugin        │   │
     │                              │  │  → reads mock sysfs  │   │
     │                              │  │  → finds 8 GPUs      │   │
     │                              │  │  → registers amd.com │   │
     │                              │  │ Metrics exporter      │   │
     │                              │  │  → reads mock library │   │
     │                              │  │ Node labeller         │   │
     │                              │  │  → reads mock sysfs   │   │
     │                              │  └─────────────────────┘   │
     │                              │                            │
     │                              │  kubelet updates:          │
     │                              │  allocatable:              │
     │                              │    amd.com/gpu: 8          │
     │                              │                            │
     │  kubectl apply llm-demo.yaml │                            │
     ├─────────────────────────────►│                            │
     │                              │  Scheduler sees GPU        │
     │                              │  ┌─────────────────────┐   │
     │                              │  │ Pod needs amd.com/gpu│   │
     │                              │  │ Node has 8 available │   │
     │                              │  │ → Schedule here      │   │
     │                              │  └─────────────────────┘   │
     │                              │                            │
     │                              │  Pod starts with:          │
     │                              │    /dev/kfd ✓              │
     │                              │    /dev/dri/renderD128 ✓   │
     │                              │                            │
     │  ◄── Pod logs: "Model loaded on mock AMD GPU node!" ──►  │
```

## What Works vs What Doesn't

```
    ┌─────────────────────────────────────────────────────────┐
    │                    WORKS (Control Plane)                 │
    │                                                         │
    │  ✓ GPU discovery and enumeration                        │
    │  ✓ Kubernetes scheduling (amd.com/gpu resources)        │
    │  ✓ Device plugin registration                           │
    │  ✓ amd-smi Python interface (sees 8x MI300X)            │
    │  ✓ Prometheus GPU metrics (temperature, power, util)    │
    │  ✓ Grafana dashboards with live telemetry               │
    │  ✓ Fault injection (crash, ECC, overheat)               │
    │  ✓ Compute partitioning (SPX/CPX — up to 64 vGPUs)     │
    │  ✓ Profile switching (MI210 → MI355X)                   │
    │  ✓ CDI container device injection                       │
    │  ✓ xGMI/Infinity Fabric topology                        │
    │  ✓ NUMA node association                                │
    │  ✓ RVS sysfs-level validation (Steps 1-4)               │
    └─────────────────────────────────────────────────────────┘

    ┌─────────────────────────────────────────────────────────┐
    │               DOESN'T WORK (Data Plane)                 │
    │                                                         │
    │  ✗ HIP/ROCm kernel execution — no real GPU silicon      │
    │  ✗ GPU memory allocation — no real HBM                  │
    │  ✗ KFD ioctl calls — /dev/kfd has no kernel driver      │
    │  ✗ RVS rvs -g — needs ioctl to enumerate GPUs           │
    │  ✗ Real CUDA/HIP matrix math — will crash               │
    │  ✗ GPU Direct / RDMA — no physical PCIe device          │
    │  ✗ SR-IOV / VF passthrough — no IOMMU                   │
    └─────────────────────────────────────────────────────────┘

    The rule: if software READS hardware state → works.
              if software EXECUTES on hardware → doesn't work.
```

## Compute Partitioning (AMD's MIG Equivalent)

```
                    SPX Mode (default)
                    ==================
    ┌──────────┐ ┌──────────┐     ┌──────────┐
    │  GPU 0   │ │  GPU 1   │ ... │  GPU 7   │
    │ 192 GB   │ │ 192 GB   │     │ 192 GB   │
    │ 750W     │ │ 750W     │     │ 750W     │
    │ 304 CUs  │ │ 304 CUs  │     │ 304 CUs  │
    └──────────┘ └──────────┘     └──────────┘
    amd.com/gpu: 8 total

                    CPX Mode (8 partitions per GPU)
                    ==============================
    ┌──┬──┬──┬──┬──┬──┬──┬──┐ ┌──┬──┬──┬──┬──┬──┬──┬──┐
    │p0│p1│p2│p3│p4│p5│p6│p7│ │p0│p1│p2│p3│p4│p5│p6│p7│ ... × 8
    │24│24│24│24│24│24│24│24│ │24│24│24│24│24│24│24│24│
    │GB│GB│GB│GB│GB│GB│GB│GB│ │GB│GB│GB│GB│GB│GB│GB│GB│
    └──┴──┴──┴──┴──┴──┴──┴──┘ └──┴──┴──┴──┴──┴──┴──┴──┘
         GPU 0 (8 XCDs)              GPU 1 (8 XCDs)
    amd.com/gpu: 64 total

    Each partition:
      - 24 GB HBM3 (192 / 8)
      - 93W power cap (750 / 8)
      - 1 XCD (38 CUs)
      - Independent scheduling unit
```

## Files That Changed (What We Built)

```
amd-gpu-mock/
│
├── cmd/
│   ├── node-agent/main.go       ← Entrypoint: reads profile, stages
│   │                                sysfs, creates device nodes,
│   │                                starts API server + dashboard
│   └── nri-plugin/main.go       ← NRI containerd injection plugin
│
├── pkg/gpu/kfd/
│   ├── renderer.go              ← Writes KFD sysfs, PCI sysfs, DRM,
│   │                                driver module, device nodes
│   ├── profile.go               ← Go types for GPU profile YAML
│   ├── state.go                 ← Runtime GPU state, fleet management,
│   │                                compute partitioning, tray logic
│   ├── api.go                   ← REST API: status, control, profiles,
│   │                                partitions, fault injection, metrics
│   ├── dashboard.go             ← Embedded HTML/JS web dashboard
│   ├── dynamic.go               ← Time-varying metrics simulator
│   └── cdi.go                   ← CDI spec generator (amd-ctk format)
│
├── pkg/mocksmi/
│   ├── mock_amdsmi.c            ← 28 core amdsmi_* C functions
│   ├── stubs.c                  ← 157 stub functions (NOT_SUPPORTED)
│   ├── amdsmi_types.h           ← AMD SMI type definitions
│   └── libamd_smi.so            ← Compiled mock library (185 symbols)
│
├── profiles/                    ← 7 GPU profiles (YAML)
│   ├── mi210.yaml               64 GB, CDNA 2, 300W
│   ├── mi250x.yaml              128 GB, CDNA 2, 500W
│   ├── mi300a.yaml              128 GB, CDNA 3, 550W (APU)
│   ├── mi300x.yaml              192 GB, CDNA 3, 750W (default)
│   ├── mi325x.yaml              256 GB, CDNA 3, 1000W
│   ├── mi350x.yaml              288 GB, CDNA 4, 1000W
│   └── mi355x.yaml              288 GB, CDNA 4, 1400W
│
├── deployments/
│   ├── helm/amd-gpu-mock/       ← Helm chart (DaemonSet + ConfigMap)
│   ├── tiny-llm-demo.yaml       ← LLM demo requesting amd.com/gpu
│   ├── partition-demo.yaml      ← Multi-LLM on GPU partitions
│   ├── grafana-dashboard.yaml   ← 6-panel GPU telemetry dashboard
│   ├── rvs-validation.yaml      ← RVS validation job
│   └── kind-node/               ← Custom KIND node image (CDI-enabled)
│
├── tests/
│   ├── validate.sh              ← 20-test mock validation suite
│   └── validate_full.sh         ← 27-test full stack validation (8 layers)
├── scripts/
│   ├── demo-setup.sh            ← One-command demo deployment
│   └── setup_mac.sh             ← macOS-specific setup with prerequisites
└── docs/                        ← Architecture, how-it-works, profiles
```
