# Optional openable devices and libdrm capacity queries

The default mock provides discovery, allocation and telemetry surfaces. The
optional CUSE/library backend additionally supports consumers that open DRM
character devices and call a small subset of `libdrm_amdgpu`. HAMi motivated this
interface extension; neither HAMi nor RocJITsu is required to use it.

```text
[1] Existing profile YAML -> original Go renderer / live state
                |                 |                   |
                v                 v                   v
[2] Mock sysfs topology      Mock AMD SMI        Mock libdrm_amdgpu
    identity and RAS         identity/telemetry  device initialize,
                |                 |             CU count / VRAM / name
                +-----------------+-------------------+
                                  |
[3] Real consumer discovery -> real DRA OR device-plugin allocation
                                  |
[4] CDI / kubelet injects assigned CUSE-backed character devices
                                  |
[5] Consumer opens device -> kernel CUSE -> userspace device handler
    Unsupported reads/writes/ioctls fail; no GPU execution is supplied.
```

This is a library API simulator, not an implementation of the real AMD kernel
ioctl protocol. Applications issuing raw AMDGPU/KFD ioctls are not covered.
RocJITsu remains a separate experimental computation extension.

## Host and installation

Use a dedicated CPU-only Linux node with a running Docker/Podman runtime.
The host kernel must provide CUSE (`sudo modprobe cuse`, then check `/dev/cuse`).
For a VM-backed runtime, load it in that Linux VM. A container image cannot
supply a missing host kernel module. The provider is privileged infrastructure;
allocated workload Pods do not need privileged mode. Real AMDGPU nodes are
rejected. Existing DRM nodes inherited by CPU VMs (for example virtual displays)
are covered by reversible bind mounts inside the dedicated node; the underlying
nodes are never deleted. Bidirectional propagation exposes that overlay to the
node's kubelet. Cleanup removes the overlay and restores the underlying device.
Do not use the simulated node for unrelated DRM workloads during the demo.

Use Kind v0.33.0+, kubectl v1.37, Helm and Python 3. After loading CUSE in the
runtime's Linux kernel, create a dedicated cluster using the normal node image:

```bash
# For Podman: export KIND_EXPERIMENTAL_PROVIDER=podman
kind create cluster --name amd-mock \
  --image docker.io/submod/amd-mock-kind-node:0.2.2 \
  --config deployments/kind-node/kind-config.yaml

helm install amd-gpu-mock oci://docker.io/submod/amd-gpu-mock \
  --version 0.2.15 -n amd-mock --create-namespace \
  --set driverMock.enabled=true \
  --set image.repository=docker.io/submod/amd-gpu-mock-driver \
  --set image.tag=v0.1.1 --wait --timeout 5m

DRIVER_IMAGE=docker.io/submod/amd-gpu-mock-driver:v0.1.1 \
  python3 -u tests/driver-mock/allocated.py
```

The consumer requests a real DRA allocation, opens only its injected render/KFD
nodes, and queries the staged libdrm library. It checks profile capacity, both
memory query layouts, short buffers, unsupported operations and invalid handles.
It prints `PASS: allocated workload native KFD/render access and libdrm capacity`
and cleans up its test namespace. The cluster and dashboards stay available.
No compiler or image build is required. See [release provenance](../evidence/driver-mock/published-images.json),
[validation logs](../evidence/driver-mock/README.md), and the
[build recipe](../../deployments/driver-mock/Dockerfile).

For the AMD device-plugin allocator, add `--set dra.enabled=false` and
`--set devicePlugin.enabled=true` to installation; set `ALLOCATOR=device-plugin`
when running the probe. Use separate clusters for the two allocators.
The ordinary quick start continues to use the lightweight backend.
Native-open tests currently use the container's default UID 0 without privileged
mode; non-root and OpenShift SCC access are separate validation work.

When finished:

```bash
helm uninstall amd-gpu-mock -n amd-mock
kind delete cluster --name amd-mock
```

Consumer containers must explicitly use the staged library at
`/var/lib/amd-gpu-mock/driver/usr/lib64/libdrm_amdgpu.so.1` (mount the overlay
read-only and select it with `LD_LIBRARY_PATH`). Set `AMD_DRIVER_MOCK_ROOT` when
that overlay is mounted elsewhere. Ordinary workloads are not globally
preloaded with a replacement libdrm.

## Supported interfaces and lifecycle

- Native opens of KFD, card and render nodes, using dynamically registered CUSE
  numbers rather than a `/dev/null` substitute.
- `amdgpu_device_initialize/deinitialize`, GPU CU count/device ID, VRAM capacity,
  and profile-derived marketing name. Other GPU-info fields are zero/unspecified.
  `AMDGPU_INFO_VRAM_GTT` returns its capacity structure; `AMDGPU_INFO_MEMORY`
  returns the full heap structure or a requested prefix, including HAMi's short
  query. Zero/oversized buffers are rejected. Heap usage follows the existing
  simulated SMI state; all profile VRAM is modeled as CPU-accessible and GTT is
  unmodeled (zero). These are simulated values, not host allocations.
  See the [Linux UAPI](https://github.com/torvalds/linux/blob/master/include/uapi/drm/amdgpu_drm.h).
- Unknown queries and firmware queries return `EOPNOTSUPP`; malformed handles or
  buffers are rejected. Raw ioctls return `ENOTTY`, reads/writes `EOPNOTSUPP`.
- Multiple GPUs and fixed partition inventory use the same original renderer.
  Profile changes reconcile endpoints. Simulated crashes withdraw driver
  bindings and remove unbound owned host paths. Protected bind overlays remain
  in place while live RAS state rejects libdrm calls; recovery restores missing
  paths using registered endpoints, not legacy dummy numbers.
- The driver image supplies the existing ABI 27 AMD SMI shim, including BDF
  lookup, using the original renderer's same SMI state.
- Fatal RAS state rejects libdrm capacity/initialization calls. This does not
  promise automatic workload eviction or real hardware failure behavior.
- Provider shutdown removes owned nodes. An unclean restart re-registers the
  endpoints and replaces stale nodes. Existing open handles across provider
  death are not guaranteed to recover; applications must reopen/retry.

## Build and validation

```bash
scripts/build-driver-mock-images.sh
# Maintainer publication, after validation:
scripts/build-driver-mock-images.sh --push

# Native Docker example (Linux host with CUSE loaded):
docker build -f deployments/driver-mock/Dockerfile -t local/amd-gpu-mock-driver:test .
CONTAINER_RUNTIME=docker DRIVER_IMAGE=local/amd-gpu-mock-driver:test \
  python3 -u tests/driver-mock/native.py
```

Build recipes live in `deployments/driver-mock/`; the default mock image is not
changed. Both Linux AMD64 and ARM64 are build targets. Windows is out of scope.

The `driver-backend` workflow runs native CUSE checks on both architectures,
all seven profile/device-plugin suites, DRA basic/lifecycle/focused suites,
fixed DPX allocation, unclean Kubernetes provider restart followed by a fresh
allocated native-open/libdrm check, scripted Tiny LLM/presenter demos, dashboard, real exporter
telemetry and attribution. Captured CI results distinguish planned checks from
passed checks. The existing default-backend workflows remain regression gates.
No HIP computation, DMA, physical isolation or performance fidelity is claimed.

## Rolling updates and mounted state

The node agent preserves staged state during shutdown so collectors and
allocators retain their mounted directory inodes. Startup reconciles inventory
inside the existing sysfs directory and replaces SMI state files atomically.
Both forced and graceful restart checks require stable sys/SMI directory inodes,
then repeat native calls from a newly allocated Pod. Final directory removal
belongs to dedicated cluster teardown. Existing open CUSE handles still require
application retry/reopening when their backing provider is replaced.
