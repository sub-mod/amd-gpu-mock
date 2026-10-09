# GPU and network worker demo

The [single-node demo](../../demo/gpu-network/single-node/README.md) adds one
ARM64 QEMU VM worker to an existing Podman Kind cluster. The worker contains
mock MI300X GPUs and an ERNIC-emulated PCI NIC. The Kind control plane schedules
one application requesting an AMD DRA GPU and an AMD Network Operator NIC.

```text
Kind control plane
  |-- AMD GPU DRA: ResourceSlice -> ResourceClaim
  |-- AMD Network Operator -> NIC device plugin
  |-- NFD: discover actual emulated PCI identity
  |
  +-- QEMU VM worker (Ubuntu ARM64, 4 CPUs, 3 GiB)
       |-- ERNIC PCI device -> ionic / ionic_rdma -> uverbs0
       |-- GPU mock agent -> mock sysfs and device nodes
       |-- kubelet + containerd -> NIC allocation + GPU CDI injection
       +-- Tiny LLM HTTP application: logs both allocations
```

## Setup

Run the normal README quick start, then `./scripts/ernic/setup.sh` and
`./demo/gpu-network/single-node/run.sh`. Alternatively,
`./demo/setup.sh --ernic` creates the cluster and adds this worker. The default
Podman machine is preserved. The VM uses QEMU TCG; nested KVM is not required.
The initial implementation supports ARM64 hosts and the standard Kind network.

Setup pulls published images and downloads checksum-verified Ubuntu guest
assets. All versions, source revisions and checksums are in
[`versions.env`](../../scripts/ernic/versions.env). Maintainers build and publish
images with `./scripts/ernic/build-images.sh --push`; users need no compiler.

## Configuration and source changes

QEMU, rocm-ernic, libvfio-user, AMD Network Operator and its NIC device plugin
are built from pinned upstream revisions without source patches. The project
adds image packaging, VM provisioning, Kubernetes configuration and the demo.
The GPU simulation remains the existing AMD GPU Mock layer; the upstream DRA
driver consumes its mock sysfs through the existing chart configuration.

A NodeFeatureRule matches the NIC's actual PCI identity (vendor `1dd8`, device
`1002`, subsystem `5400`). The plugin configuration selects its `ionic_rdma`
driver and disables hardware configuration through nicctl. Real Multus is
installed for the operator initialization path; the demo uses host networking
and creates no secondary network attachment. NIC metrics and health checks are
not enabled in this milestone.

The guest uses containerd's native CDI support and systemd cgroups with
`cgroupRoot: /`. It does not inherit Kind's container-specific `/kubelet` cgroup
root. No cgroup enforcement is disabled. Four virtual CPUs satisfy the upstream
ERNIC event-queue requirement. The VM memory is 3 GiB to stay within the
VFIO-user DMA region size limit. Direct kernel boot disables the unused virtio
NIC option ROM.

## Evidence and boundaries

The demo runner dumps application logs, sends an HTTP request, and verifies the
GPU claim against its ResourceSlice and injected render device. It also checks
NIC allocation metadata and that both resources belong to the same worker.
Captured output is stored beside the demo. Provisioning logs and private VM
state live under ignored `tmp/ernic/`; do not commit SSH keys or join credentials.
Bootstrap tokens expire after one hour and are revoked when setup exits.

The response is scripted. This milestone proves discovery and allocation, not
GPU inference or RDMA data transfer. The [two-node demo](../../demo/gpu-network/two-node/README.md)
is reserved for a separate future transfer/checksum milestone.

Remove the application with `./demo/gpu-network/single-node/run.sh --cleanup`.
Remove its dedicated VM worker with `./scripts/ernic/cleanup.sh`. Cleanup keeps
the Podman machine and cached downloads/disks.

First provisioning suspends only the apt `needrestart` scan, which otherwise
repeatedly inspects compressed kernel images under TCG. The script explicitly
starts/restarts containerd. Normal later package operations retain their usual
restart checks. Guest downloads are cached and checksum-verified on reuse.

The [prepared worker artifact](../../artifacts/ernic-worker/README.md) documents
the guest disk contents, sanitization, build and publication process. The default
setup pulls this disk and avoids guest package installation. The artifact is published and clean worker setup and allocation validation passed.

The upstream network chart hard-codes its device-plugin ConfigMap. Setup creates
a derived chart copy with exactly one template override from `plugin-config.yaml`,
so Helm owns the ERNIC configuration on both install and upgrade. The downloaded
upstream chart archive and controller/plugin source stay unchanged. This is a
manifest configuration customization, not an upstream source-code patch.

GPU installation enables DRA and disables the device plugin for the existing
`amd-gpu-mock` Helm release, including its existing mock nodes. The default
`demo/setup.sh` already uses DRA. If retaining device-plugin workloads matters,
use a separate demo cluster rather than switching their allocator in place.

Chart 0.2.12 gives exporter readiness a five-second timeout because a measured
metrics scrape on the emulated worker took 1.015 seconds. Override
`metricsExporter.readinessTimeoutSeconds` for slower hosts. The exporter remains
the existing published image; no image rebuild is required for this setting.
