# How it works

The project models discovery, allocation and telemetry contracts on CPU-only
Kubernetes nodes. It is inspired by [NVIDIA Moka](https://github.com/NVIDIA/k8s-test-infra).
A scheduled GPU pod proves allocation and device injection, not GPU execution.

## From quick start to a GPU pod

1. The published kind image starts Kubernetes v1.37.0 with CDI enabled.
2. Chart 0.2.9 starts the mock node agent and AMD DRA driver by default.
3. The agent reads a profile, writes mock KFD/PCI/DRM/driver sysfs, creates
   character devices and initializes runtime state.
4. AMD's unchanged driver discovers the mounted sysfs and publishes ResourceSlices.
5. Kubernetes matches ResourceClaim requests and reserves GPUs.
6. Kubelet asks the driver to prepare the claim. Its per-claim CDI specification
   identifies the allocated device nodes.
7. Containerd injects those nodes into the consumer. Deleting the consumer
   triggers unprepare and the allocation lifecycle described in the
   [DRA guide](guides/dra.md).

The alternative [device-plugin path](guides/device-plugin.md) registers
`amd.com/gpu` capacity and allocates physical GPUs to extended-resource requests.
The allocators run separately to avoid independent allocation of one pool.

## Why real AMD consumers discover devices

KFD topology files describe GPU names, SIMD counts, memory, GFX targets and
NUMA nodes. PCI and DRM paths provide vendor/device IDs, BDFs, product names,
render minors and driver links. `/sys/module/amdgpu` is a staged directory,
not a loaded kernel driver. Device nodes use the expected character-device
major/minor numbers but have no functional AMD kernel implementation.

The Operator fork's SIM_ENABLE mode skips driver init waits and directs its
plugin and node labeller at this tree. That smoke test does not establish
full Operator support; see [its scope](guides/gpu-operator.md#validation-limits).

## Dashboard to AMD SMI to Grafana

The quick-start dashboard is accessible at localhost:8080 without port-forwarding.
Its GPU values come directly from node-agent runtime state. Healthy readings
vary each second. Overheat, Busy, Idle, Crash, Recover and ECC controls modify
that state and synchronize mock sysfs and atomic per-GPU SMI snapshot files.

The default chart [monitoring setup](guides/telemetry.md) installs the real AMD
Device Metrics Exporter and GPU Agent. Their binaries remain unchanged. GPU
Agent invokes a replacement AMD SMI device library that reads the snapshots;
it returns values through AMD's official ABI 27 structures. The exporter
then constructs the actual AMD Prometheus metrics. Standard Prometheus
scrapes them and standard Grafana queries them. Workload attribution comes
from kubelet's real pod-resources API with either allocator.

The node agent's diagnostic `/metrics` is a separate endpoint. Its presence
alone does not demonstrate real exporter integration. Likewise, the legacy
handwritten SMI library staged for other consumers is not the dedicated
exporter backend.

All six per-GPU dashboard actions have live integration tests through the
real pipeline, including recovery. Crash currently zeroes readings rather
than making AMD SMI return device-lost errors. Health-service events, alert
rules and automatic remediation are not enabled. Collection and scraping
introduce a delay relative to the dashboard. ARM64 explicitly emulates AMD's
x86 collector binaries using QEMU.

## Profiles and virtual partition state

Seven profiles describe MI210 through MI355X. MI250X exposes 16 GCD devices,
each with 64 GiB; MI300A exposes four devices; the other profiles expose eight.
Install the selected profile before allocation. Runtime fleet switching is
useful for dashboard exploration, but allocation consumers require rediscovery
and matching device nodes; do not switch with active claims. Per-tray switching
still lacks immediate renderer synchronization.

The partition API models SPX/DPX/QPX/CPX as virtual entries. Eight MI300X GPUs
produce 64 dashboard entries in CPX, each reporting one eighth of the physical
memory. Kubernetes still has eight physical allocation units. The
`partition-demo.yaml` schedules four workloads on physical GPUs; it does not
implement AMD compute partition isolation, NVIDIA MIG, MxGPU or SR-IOV.

## Where the implementation lives

| Path | Responsibility |
| --- | --- |
| `cmd/node-agent` | Profile loading, renderer, simulator and API startup |
| `pkg/gpu/kfd` | Sysfs/devices/CDI, runtime state, dashboard and atomic SMI bridge |
| `pkg/mocksmi/exporter` | Official-header AMD SMI replacement for the real collector |
| `pkg/mocksmi` | Legacy SMI library for other consumers |
| `deployments/helm/amd-gpu-mock` | Node agent, allocator selection and optional exporter |
| `deployments/metrics-exporter` | Collector runtime, monitoring values and Grafana dashboard |
| `scripts/setup-monitoring.sh` | Optional external Prometheus Operator monitoring installation |
| `scripts/build-telemetry-images.sh` | Reproducible maintainer build and publication |
| `tests/telemetry` | ABI, dashboard actions, Grafana queries and consumer attribution |

The [testing guide](guides/testing.md) distinguishes validated contracts from
unimplemented hardware behavior. The Tiny LLM demo produces scripted output;
it downloads no model weights and runs no inference.

The [demo folder](../demo/README.md) provides presenter commands and a shared
configuration for both dashboard ports and enable switches. The default
Grafana host port is 3000; both dashboards work without port-forwards.
