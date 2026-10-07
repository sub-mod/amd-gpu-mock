# Same-GPU partition allocation

Chart 0.2.11 and mock image v0.2.6 add a fixed **MI300X DPX/NPS2** topology.
Eight physical 192-GiB GPUs become sixteen schedulable 96-GiB devices,
with 152 compute units per partition. Siblings retain one PCI bus address
and KFD physical unique ID; each has its own card, render minor, KFD node,
and logical UUID. The first partition appears under the PCI driver binding;
the second appears under `amdgpu_xcp_*`, as expected by AMD's discovery code.

This models AMD compute/memory partition discovery and allocation. It does
not implement SR-IOV virtual functions, MxGPU VM passthrough, kernel execution,
DMA isolation or real VRAM protection. It also does not let users request
arbitrary slice sizes. Only SPX and MI300X DPX/NPS2 are supported as startup
configurations in this release. Other dashboard partition modes remain
virtual display demos.

AMD's [MI300X partition guide](https://instinct.docs.amd.com/projects/amdgpu-docs/en/latest/gpu-partitioning/mi300x/quick-start-guide.html)
describes the hardware compute and memory modes. The unchanged
[AMD DRA driver v1.0.0](https://github.com/ROCm/k8s-gpu-dra-driver/blob/v1.0.0/docs/driver-attributes.md)
supports pre-partitioned devices and matching their parent PCI identity.
The mock adds those devices below the driver; it does not manufacture
ResourceSlices or ResourceClaim allocations.

## Install

Create the cluster using the root README quick start. On a **fresh cluster**,
add one setting to the same chart installation:

```bash
helm install amd-gpu-mock oci://docker.io/submod/amd-gpu-mock \
  --version 0.2.11 -n amd-mock --create-namespace \
  --set gpu.partition=DPX --wait --timeout 5m
```

The published node image remains `amd-mock-kind-node:0.2.2`; no custom image
build is needed. DRA remains the default allocator. The mock dashboard and
Grafana start through the same quick start port mappings.

Do not change SPX/DPX while workloads or allocated claims exist. Drain and
delete claims first, and preferably recreate the local cluster to remove old
host devices. DPX startup mode rejects dashboard profile/tray changes and
virtual repartition requests with HTTP 409. Switching topology requires a
new startup configuration and driver discovery after the mock is ready.
The chart defaults to SPX, preserving the existing whole-GPU quick start.

## Allocation path

```text
MI300X physical parent: 192 GiB, one PCI BDF / KFD unique ID
  | fixed startup DPX/NPS2
  +-- partition 0: 96 GiB, cardN/renderDN, PCI driver DRM path
  +-- partition 1: 96 GiB, cardM/renderDM, amdgpu_xcp platform path
          |
          v
Unchanged AMD DRA discovery -> ResourceSlice (same pciBusID)
          |
          v
Scheduler -> ResourceClaim: left + right, match parent pciBusID
          |
          v
Kubelet -> AMD NodePrepare -> claim CDI spec -> container runtime
          |                                  |
          +--> container left: renderDN      +--> container right: renderDM

Pod deletion + claim deletion -> AMD NodeUnprepare -> remove claim CDI spec
                             -> released partition available for reuse
```

## Responsibilities of each layer

| Layer | Responsibility | Mocked or real |
| --- | --- | --- |
| Mock node agent | Renders fixed DPX/NPS2 DRM/KFD sysfs topology, capacities, shared parent BDF/KFD identity and distinct logical card/render devices. Creates fake character device nodes. | Mock hardware/driver discovery surfaces |
| AMD DRA discovery | Reads those surfaces, recognizes pre-partitioned AMD devices, and publishes their attributes and capacities in ResourceSlices. | Unchanged upstream AMD driver |
| Kubernetes API server | Stores and validates DeviceClasses, ResourceSlices, ResourceClaims and Pods. | Real Kubernetes |
| Kubernetes scheduler | Selects available partitions, enforces the same-parent PCI constraint, and writes the claim allocation. Keeps consumers Pending when no matching partition is free. | Real Kubernetes |
| Kubelet | Requests preparation of allocated claims and passes the driver's per-request CDI references to the container runtime. | Real Kubernetes |
| AMD DRA NodePrepare | Creates claim-specific CDI device specifications for the allocated partitions. | Unchanged upstream AMD driver |
| Container runtime | Applies CDI edits, exposing each container's assigned card/render devices and the shared KFD interface. | Real container runtime |
| AMD DRA NodeUnprepare | Removes the released claim's CDI specification. Deleting the explicit ResourceClaim releases its allocation for subsequent scheduling. | Unchanged upstream AMD driver plus real Kubernetes claim lifecycle |
| Demo/test runner | Creates normal claims and pods, reads their allocations, checks device visibility, and captures logs. | Test orchestration; does not assign devices itself |

The allocation implementation does not write fabricated ResourceSlices,
patch claim allocation status, bypass the scheduler, or mount chosen render
devices directly into demo pods. The mock supplies the discovery inputs;
the AMD driver, Kubernetes and container runtime produce the allocation and
injection results through their normal interfaces.

### Simulation boundaries

Synthetic sysfs and fake character nodes intentionally replace hardware-facing
surfaces. They describe the topology and permit device-injection tests; they
do not provide a functional AMD kernel driver or GPU execution. The published
mock stack also uses container/node integration to expose the staged discovery
surfaces to the driver. The AMD DRA driver source remains unchanged.

For telemetry, the mock AMD SMI library supplies synthetic device state to the
real AMD metrics exporter. This is a separate path from DRA allocation.
The same-GPU allocation suite does not establish correct per-partition exporter
workload attribution or physical fault propagation across sibling partitions.

The dashboard's runtime SPX/DPX/QPX/CPX controls remain a virtual display
simulation when using the normal SPX startup configuration. They do not create
schedulable partitions. Schedulable DPX/NPS2 comes from the fixed startup
configuration described here, which blocks runtime topology changes.

### What the recorded checks establish

The [captured demo evidence](../../demo/partition-allocation/README.md) verifies
AMD discovery and advertised capacities, same-parent scheduler allocation,
per-container character-device visibility, exhaustion, claim CDI cleanup,
released-device reuse, sibling continuity, and allocation continuity through
a driver pod replacement. This supports the allocation path above. It does
not certify the entire project as free of workarounds, or establish hardware
compute, DMA or memory isolation.

## Two containers, one physical GPU

A ResourceClaim has two named requests, each selecting `amdgpu-partition`.
Its `matchAttribute: resource.kubernetes.io/pciBusID` constraint asks the
scheduler to place both requests on the same physical parent. Each container
references the shared claim plus its own `request: left` or `request: right`.
Kubelet asks the real AMD driver to prepare the claim, and the runtime applies
its CDI device edits. Each container sees `/dev/kfd` and its own card/render
pair. It cannot see the sibling render device through that allocation.

The scheduler picks the parent; no hard-coded GPU address is needed for this
case. Separate pods can select the same specific parent through a CEL
`pciBusID` selector. ResourceClaims own their allocations: deleting a pod
alone does not free an explicitly created claim. Delete the claim as well.

## Run the proof

```bash
python3 tests/dra/partition-allocation.py
```

This uses the selected kubeconfig and creates the dedicated namespace
`amd-demo-partition-allocation`. It refuses to overwrite an existing namespace.
The test checks:

- AMD publishes sixteen `amdgpu-partition` devices, grouped into eight parents.
- Two pods receive different partitions of one selected parent.
- Each container has exactly its allocated character render device and KFD.
- A third same-parent consumer stays Pending when both partitions are occupied.
- Deleting one pod and claim lets the waiting consumer reuse that device;
  the sibling remains Ready with its original allocation.
- Restarting AMD's DRA plugin preserves both live allocations.
- Two containers in one pod receive different partitions with the same parent,
  `dpx_nps2` profile and 96-GiB advertised capacity each.

The final two-container pod stays Running for inspection. Remove its namespace
to release both partitions. [The demo](../../demo/partition-allocation/README.md)
includes actual captured output. CI runs both source and published-image paths;
`PARTITION_MODE=DPX tests/dra/discovery-check.sh mi300x` separately exercises
AMD's unchanged low-level discovery in a private Linux mount namespace.

## Scope of the proof

The successful test proves scheduler exclusivity and per-container device
injection. Character nodes are mocks; passing these tests does not prove
hardware compute or memory isolation. The dashboard exposes logical indices,
`partition_index`, `memory_partition`, and the shared `pci_bdf`.
Per-partition AMD exporter workload attribution and physical fault propagation
are separate from this allocation proof and are not asserted by this test.

Maintainers build and publish the mock image and chart with
`scripts/build-mock-images.sh --push`. This leaves the existing node, AMD DRA,
and real exporter image tags intact.

Use `podman login docker.io` before publishing, or set `REGISTRY_AUTHFILE` to
an existing Docker-compatible registry auth file. Credentials are never
embedded in the source or images.
