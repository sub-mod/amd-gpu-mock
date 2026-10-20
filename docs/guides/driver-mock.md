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

The image and chart installation commands will be recorded here with verified
published digests after the source-backed compatibility matrix passes. The
ordinary quick start and image remain unchanged; CUSE is opt-in through
`driverMock.enabled=true` and the dedicated driver image.

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
  Profile changes reconcile endpoints. Simulated crashes remove owned host
  paths; recovery restores the registered endpoints, not legacy dummy numbers.
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
