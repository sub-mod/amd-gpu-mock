# GPU and network worker demo

This demo adds one Ubuntu ARM64 VM worker to an existing Podman Kind cluster.
Kubernetes schedules one application onto that worker and allocates both:

- One simulated AMD MI300X GPU through **Dynamic Resource Allocation (DRA)**.
- One ERNIC-emulated Pensando NIC through the **NIC device plugin deployed by
  the AMD Network Operator**.

DRA is a Kubernetes allocation mechanism, not a GPU model. The GPU and NIC use
separate allocation paths. The NIC belongs to the worker; it is not attached to
the simulated GPU. The application receives access to both on the same worker.

The application is a Tiny LLM **simulation**: it returns scripted text over HTTP.
This milestone demonstrates device discovery and allocation. It does not execute
GPU inference or transfer data through RDMA.

## Where the components run

The Kind control plane runs the Kubernetes API and scheduler. The application
runs on the added VM worker, which joins the same Kubernetes cluster.

```text
Apple-silicon Mac
|
+-- Default Podman Linux VM (preserved by setup)
    |
    +-- Kind control-plane container
    |   +-- Kubernetes API: Pods, ResourceClaims, ResourceSlices, NetworkConfig
    |   +-- Scheduler: selects a worker with the requested GPU and NIC
    |   +-- AMD Network Operator controller: reconciles NetworkConfig
    |
    +-- Dedicated ERNIC lab container
        +-- rocm-ernic process: emulates the Pensando PCI NIC
        |       ^
        |       | VFIO-user socket (emulated PCI device interface)
        |       v
        +-- QEMU VM worker: Ubuntu ARM64, 4 virtual CPUs, 3 GiB RAM
            +-- Kernel: ionic + ionic_rdma -> NIC and RDMA device nodes
            +-- NFD worker: discovers the emulated PCI identity
            +-- NIC device plugin: advertises amd.com/nic to kubelet
            +-- GPU mock agent: supplies simulated GPU sysfs/device nodes
            +-- AMD DRA driver: discovers GPUs and prepares allocations
            +-- kubelet + containerd: start Pods with allocated devices
            +-- Tiny LLM application Pod: one GPU claim + one NIC resource
```

The diagram shows responsibilities, not every Pod deployed by the charts.
QEMU uses TCG software emulation; nested KVM is not required. The default
implementation supports ARM64 hosts and the standard Kind network.

## How the application gets its devices

The [workload YAML](../../demo/gpu-network/single-node/workload.yaml) requests a
GPU using a `ResourceClaimTemplate` with device class `gpu.amd.com`. It requests
a NIC using the container resource limit `amd.com/nic: 1`. Its node selector
restricts placement to the demo worker (`amd-ernic-worker-1` by default).

```text
GPU discovery and allocation                 NIC discovery and allocation
----------------------------                 ----------------------------
GPU mock agent on VM                         ERNIC emulates a PCI NIC
  | simulated sysfs/device nodes               | ionic + ionic_rdma drivers
  v                                            v
Upstream AMD DRA driver                       NFD discovers PCI identity
  | publishes ResourceSlices                   | applies amd-nic node label
  v                                            v
Kubernetes sees available GPUs               Network Operator reconciles config
  |                                            | deploys NIC device plugin
  |                                            v
  |                                          Kubelet advertises amd.com/nic: 1
  |                                            |
  +---------------------+----------------------+
                        v
       Pod requests a GPU claim and amd.com/nic: 1
                        |
       Scheduler selects VM; GPU claim is allocated
                        |
                        v
                 Kubelet starts Pod
                  |               |
                  v               v
        AMD DRA prepares      NIC plugin Allocate
        GPU CDI entries       returns devices/metadata
                 |               |
                 +-------+-------+
                         v
             containerd starts application
             /dev/kfd + one renderD* device
             /dev/infiniband/* + NIC metadata
```

**CDI (Container Device Interface)** describes how the runtime exposes the
allocated GPU devices to the container. The guest uses containerd's native CDI
support. The NIC follows Kubernetes' device-plugin API rather than DRA.

NFD (Node Feature Discovery) matches the NIC's actual emulated PCI identity:
vendor `1dd8`, device `1002`, subsystem vendor `1dd8`, subsystem device `5400`.
The NIC plugin selects the `ionic` PCI driver and requires an RDMA-capable device;
`ionic_rdma` provides the RDMA interface. Its name may be `ionic_0` or a
predictable name such as `rocep0s4`.

## Networking in this milestone

The application uses `hostNetwork: true`, sharing the worker's network namespace.
Allocation reserves the NIC resource in Kubernetes, but does not give this Pod
an isolated network interface. No secondary network attachment is created.
Real Multus is installed for the upstream operator initialization path.

```text
Kind cluster network
        |
        v
Lab bridge/TAP <-> ERNIC emulation <-> worker's ionic network interface
                                         |
                                         +-- Kubernetes worker connection
                                         +-- host-network application HTTP

Separate QEMU user-mode network <-> virtio NIC <-> guest SSH management
```

The HTTP request checks application availability and reports device evidence;
it is not an RDMA transfer test. The worker's cluster connection also uses the
emulated NIC, so disconnecting it could affect Kubernetes connectivity.
NIC fault controls, NIC metrics and health checks are not part of this demo.

## Set up and run

From the repository root, after the normal README quick start:

```bash
./scripts/ernic/setup.sh
./demo/gpu-network/single-node/run.sh
```

Alternatively, `./demo/setup.sh --ernic` creates the cluster and adds the worker.
See the [single-node demo](../../demo/gpu-network/single-node/README.md) for
prerequisites, commands for inspecting the running Pod, and overrides.

Setup pulls the published [prepared worker artifact](../../artifacts/ernic-worker/README.md)
and checksum-verified guest assets; users need no compiler or custom image build.
The artifact documentation explains disk contents, sanitization and rebuilding.
First boot and image pulls still take several minutes under TCG. Versions,
source revisions and checksums are pinned in
[`versions.env`](../../scripts/ernic/versions.env). Maintainers publish supporting
images with `./scripts/ernic/build-images.sh --push`.

GPU setup enables DRA and disables the GPU device plugin for the existing
`amd-gpu-mock` Helm release, including its existing mock nodes. The default
`demo/setup.sh` already uses DRA. Use a separate demo cluster if you need to
retain existing GPU device-plugin workloads.

### Helm upgrades on an existing worker

Re-running `./scripts/ernic/setup.sh` detects the joined worker and still runs
both Helm steps. The network release is reconciled from the pinned upstream
chart plus the ERNIC ConfigMap override. The GPU release is upgraded to the
published `CHART_VERSION` in `scripts/release.env` (currently `0.2.12`), preserving
existing values with `--reuse-values` except for explicit worker selectors and
DRA/device-plugin settings. It requires an existing GPU Helm release.

The full `./demo/setup.sh --skip-cluster --ernic` path first reapplies chart
defaults plus `demo/config.yaml` using `--reset-values`. Neither path installs
unpublished local GPU chart edits or automatically selects newer registry tags.
See the demo's [Helm update details](../../demo/gpu-network/single-node/README.md#how-setup-applies-helm-updates).

## What the logs prove

The runner dumps application logs, sends an HTTP request, and runs the
[allocation verifier](../../demo/gpu-network/single-node/verify.py).

| Evidence | What is checked |
| --- | --- |
| Pod placement | The application runs on the selected VM worker. |
| GPU ResourceClaim | Exactly one GPU is allocated by `gpu.amd.com` from that worker's pool. |
| GPU ResourceSlice and render device | The allocated GPU exists in the advertised pool and matches the injected render-device minor. |
| NIC allocation | The Pod requests one NIC; its allocation metadata names an RDMA device visible in sysfs. |
| Container devices | GPU and RDMA character device nodes are present. |
| HTTP response | The application responds and explicitly reports `simulation: true`. |

Actual captured output is linked from the demo's
[captured-run section](../../demo/gpu-network/single-node/README.md#captured-run).
Fresh worker installation and allocation were validated against the published
artifact in an existing Kind cluster; the evidence does not represent recreation
of the entire control plane. The [two-node demo](../../demo/gpu-network/two-node/README.md)
is reserved for a future transfer/checksum milestone. No GPU compute, RDMA data
transfer or GPU-direct DMA is claimed by the current logs.

## Upstream components and project configuration

QEMU, rocm-ernic, libvfio-user, AMD Network Operator and its NIC device plugin
are built from pinned upstream revisions without source patches. This project
adds packaging, VM provisioning, Kubernetes configuration and the demo. The
upstream AMD DRA driver consumes the existing GPU mock layer's sysfs view.

The network chart hard-codes its device-plugin ConfigMap. Setup creates a
derived chart copy with one template override from
[`plugin-config.yaml`](../../scripts/ernic/plugin-config.yaml), so Helm owns the
ERNIC configuration on install and upgrade. The upstream source archive stays
unchanged. This is a manifest configuration customization. Hardware configuration
through `nicctl` is disabled, and Network Operator driver installation is disabled:
the guest uses its existing `ionic` and `ionic_rdma` kernel drivers.

The guest uses systemd cgroups with `cgroupRoot: /`, instead of Kind's
container-specific `/kubelet` root. CPU and memory enforcement remain enabled.
Four virtual CPUs satisfy ERNIC's event-queue requirement; 3 GiB RAM stays within
the VFIO-user DMA region size limit. Direct kernel boot disables the unused
virtio NIC option ROM.

The prepared disk avoids guest package installation. When rebuilding from the
raw guest, provisioning suspends the apt `needrestart` scan for that process to
avoid expensive kernel-image scans under TCG, and explicitly starts/restarts
containerd. Later package operations retain their usual restart checks.

Chart 0.2.12 gives GPU exporter readiness a five-second timeout after measured
metrics requests exceeded the previous one-second default under emulation.
Override `metricsExporter.readinessTimeoutSeconds` for slower hosts. This setting
uses the existing exporter image.

## Cleanup and local state

```bash
./demo/gpu-network/single-node/run.sh --cleanup  # remove the application
./scripts/ernic/cleanup.sh                     # remove the dedicated VM worker
```

Cleanup preserves the Podman machine and cached downloads/disks. Provisioning
logs and private VM state live under ignored `tmp/ernic/` by default. Do not
commit SSH keys or join credentials. Bootstrap tokens expire after one hour and
are revoked when setup exits.
