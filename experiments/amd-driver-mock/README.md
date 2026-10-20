# AMD driver interface mock proposal

Status: design only. No new mock libraries, device emulator, installer or HAMi
integration is implemented here. This isolated experiment is intended to become
a separate project, provisionally named `amd-gpu-driver-mock`.

## Why a separate project

`amd-gpu-mock` supplies a Kubernetes lab, discovery surfaces, telemetry simulation
and demos. The proposed project supplies a reusable Linux driver-interface test
backend for software that needs more than sysfs. HAMi is the first consumer, not
a dependency or the project identity.

Keep the existing mock quick start unchanged. A future optional setup adapter
would install a pinned driver-mock release and select it explicitly. The driver
mock should also be usable without Kubernetes or this repository.

## Component ownership

| Project | Responsibility |
| --- | --- |
| amd-gpu-mock | Cluster setup, workload/demo orchestration, dashboard and published lab artifacts |
| Proposed amd-gpu-driver-mock | Openable simulated devices, compatible discovery/management library interfaces, deterministic state and fault responses |
| HAMi | Real inventory registration, scheduling, share accounting and allocation settings |
| Hardware validation | Actual HIP computation, VRAM enforcement and compute throttling |

One topology/state authority must drive sysfs, DRM-library responses and AMD SMI
identity. A running combined setup must not independently invent GPU inventories
in each project. Define a versioned state contract and an adapter rather than
copying implementations between repositories.

```text
[1] Explicit setup configuration selects backend and GPU inventory
                             |
[2] Driver mock owns consistent GPU identity, capacity and fault state
                +------------+--------------+
                v            v              v
[3]          sysfs     openable device   library responses
                |            |          libdrm + AMD SMI
                +------------+--------------+
                             v
[4] Unmodified HAMi plugin discovers and registers inventory
                             |
[5] HAMi scheduler allocates shares --> plugin configures consumer
                             |
[6] Assertions compare inventory, allocation and injected settings
```

## Backend choices

- `surfaces`: the current lab's discovery/SMI setup; not sufficient for HAMi's
  driver-capacity queries. This is an integration label, not a new driver-mock
  implementation.
- `library`: proposed compatible libdrm_amdgpu and AMD SMI implementations plus
  an openable simulated device. Tests cover user-space ABI behavior; upstream
  libdrm is replaced at this boundary.
- `device`: future device/DRM ioctl emulation, retaining upstream libdrm. This
  needs a separate feasibility decision and Linux kernel/device support.

Begin with `library`; do not silently fall back from `device` or report failed
initialization as success. Kernel module and CUSE approaches are candidates for
an openable device, not implemented or assumed-compatible solutions. Go opens
the device before the C library call, so replacing libc open alone is insufficient.

The setup example is illustrative and has no loader today. An eventual loader
must validate backend availability and supported capabilities before changing
any node. The proposed backend selector belongs in the integrating setup, not in
HAMi source. Device-plugin mode must exclude other allocators on the same GPUs.

## Initial interface audit

Pin the exact HAMi commit, library ABI/header versions, CPU architecture and
Linux environment before implementation. Source locations reviewed:

- [HAMi DRM discovery](https://github.com/Project-HAMi/amd-device-plugin/blob/main/internal/pkg/amdgpu/amdgpu.go):
  native device open, amdgpu_device_initialize/deinitialize,
  amdgpu_query_gpu_info and amdgpu_query_info for memory.
- [HAMi SMI discovery](https://github.com/Project-HAMi/amd-device-plugin/blob/main/internal/pkg/amdsmi/amdsmi.go):
  initialization/shutdown, BDF-to-handle lookup, UUID, ASIC name, memory partition
  and accelerator partition profiles.

Those links describe reviewed entry points, not a completed exhaustive call
trace. Build a symbol/structure/error compatibility checklist from a pinned
version. Unsupported APIs must return their documented failure, not fake success.
Keep the first milestone to SPX discovery; partition control is later work.

## First milestones

1. Standalone client opens one simulated MI300X and reads consistent identity,
   memory and compute-unit capacity through the selected library ABI.
2. Unmodified HAMi plugin registers that same inventory on a dedicated Kind
   worker. Capture image/source provenance and real registration output.
3. Two scripted consumers receive fractional allocations on that physical GPU;
   assert the allocation annotations, CU masks, memory-limit settings and devices.
4. Requests exceeding available budgets remain Pending; release admits a waiting
   request. Verify restart behavior and one injected discovery failure.

No milestone claims HIP execution, actual memory isolation, cgroup VRAM
accounting or hardware compute enforcement. An AMD kernel is not required to
validate scheduler accounting, but it is required for the corresponding real
hardware behavior. No kernel-level memory-controller behavior should be declared
working merely because a configuration file or environment variable is present.

## Packaging and extraction

Keep implementation under this experiment until its state/API boundaries are
reviewable. Before extraction, choose the final project name and release contract.
Create a standalone repo only when explicitly requested; no GitHub repo or PR is
created by this design branch.

The standalone deliverable should include headers/ABI compatibility records,
reproducible AMD64/ARM64 builds where supported, image build/publish scripts,
published versioned artifacts, standalone smoke tests, HAMi integration tests,
actual captured logs and cleanup. Do not require users to custom-build images in
the normal setup. Kernel-coupled artifacts, if introduced, need their own supported
kernel matrix and installation/uninstallation story.
