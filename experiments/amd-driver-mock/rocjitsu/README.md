# Tiny HIP computation through RocJITsu

This isolated prerequisite runs upstream `HipVectorAddTest.CorrectResult`,
unchanged, against upstream RocJITsu's MI300X (`gfx942`) configuration. It is not
yet an integration with the project's profile/state or HAMi allocation.

The test launches 16 blocks of 64 threads. It adds two 1,024-element float arrays,
copies results back through HIP, and compares every element with a CPU reference
at tolerance `1e-5`. Test success requires zero differing elements.

```text
1. amdclang++ compiles unchanged upstream HIP vector-add for gfx942
2. Control: run directly, no GPU devices --> hipErrorNoDevice (expected failure)
3. RocJITsu launcher sets up the KMD interposer
4. Unchanged HIP/ROCr --> simulated KFD allocation, queue, dispatch
5. CPU executes emulated AMD GPU instructions
6. HIP copies output back --> original test compares all 1,024 values
```

Validated on 2026-10-19: 1/1 HIP vector-add test passed, all 1,024 results
compared with the CPU reference. The direct run fails with hipErrorNoDevice.
See [captured success](../evidence/rocjitsu/hip-verified-compute.log).

On this Apple Silicon/QEMU 10.2.2 setup, the runtime command needs
`QEMU_GUEST_BASE=0x800000000000`. Without it, queue creation returns EFAULT and
ROCr crashes during scratch cleanup. Debugging found a high context-save address;
shifting QEMU's guest base made the unchanged test pass. This is evidence for an
address-layout compatibility issue, not proof that all QEMU/ROCm combinations
need the setting. `QEMU_RESERVED_VA=0x800000000000` failed to allocate the vsyscall
page and is not a substitute. On native AMD64, omit these QEMU settings.

No physical GPU, privileged container, CUSE mount, HAMi source change, or second
project inventory is used. This upstream simulator configuration is a standalone
compute fixture. It must be replaced by a configuration derived from our single
profile/state authority before claiming HAMi integration.

## Reproduce on Apple Silicon with Podman

Prerequisites: running Linux Podman VM, x86-64 binfmt emulation, network access,
and space for the SDK/build cache. The successful `uname -m` below checks binary
emulation only. These scripts install packages only in disposable containers.
No new container image is built by this procedure.

From this experiment worktree root:

```sh
RUNTIME=podman
SOURCE="$PWD/tmp/rocjitsu-eval"
RESULTS="$PWD/tmp/rocjitsu-results"
PIN=0f80b261740a91e44ac2042e2f7eca6cdd8611a2
# For a fresh source directory:
git clone --filter=blob:none --sparse https://github.com/ROCm/rocm-systems.git "$SOURCE"
git -C "$SOURCE" sparse-checkout set emulation/rocjitsu shared
git -C "$SOURCE" checkout --detach "$PIN"
mkdir -p "$RESULTS/artifacts/bin" "$RESULTS/artifacts/lib"
$RUNTIME run --rm --platform linux/amd64 ubuntu:24.04 uname -m

$RUNTIME volume create amd-rocjitsu-x86-build
$RUNTIME run -d --platform linux/amd64 --name amd-rocjitsu-x86 \
  -v "$SOURCE:/source:ro" -v "$RESULTS:/results" \
  -v amd-rocjitsu-x86-build:/build ubuntu:24.04 sleep infinity
$RUNTIME exec -i amd-rocjitsu-x86 sh -s \
  < experiments/amd-driver-mock/rocjitsu/prepare-sdk.sh

# Compile the engine natively on ARM64, targeting AMD64. FlatBuffers' generated
# AMD64 tool runs through binfmt; source compilation uses native ARM64 GCC.
$RUNTIME volume create amd-rocjitsu-compute-build
$RUNTIME run -d --name amd-rocjitsu-compute \
  -v "$SOURCE:/source:ro" -v "$RESULTS:/results" \
  -v amd-rocjitsu-compute-build:/build \
  submod/amd-driver-mock:0.1.0-experiment.1-arm64 sleep infinity
$RUNTIME exec -i amd-rocjitsu-compute sh -s \
  < experiments/amd-driver-mock/rocjitsu/build-engine.sh

$RUNTIME cp amd-rocjitsu-compute:/build/librocjitsu.so "$RESULTS/artifacts/lib/"
$RUNTIME cp amd-rocjitsu-compute:/build/tools/rocjitsu/rocjitsu "$RESULTS/artifacts/bin/"
$RUNTIME cp amd-rocjitsu-compute:/build/lib/libgtest.a "$RESULTS/artifacts/lib/"
$RUNTIME cp amd-rocjitsu-compute:/build/dependencies/googletest-src/googletest/include \
  "$RESULTS/artifacts/gtest-include"
$RUNTIME exec -e QEMU_GUEST_BASE=0x800000000000 -i amd-rocjitsu-x86 sh -s \
  < experiments/amd-driver-mock/rocjitsu/verify-compute.sh
```

Use fresh resource names or reuse the existing stopped containers with `start`;
never delete the unrelated `amd-driver-mock-state` or HAMi cluster to retry this.
On native AMD64 Linux, install the SDK and run `build-engine.sh` in the same
AMD64 container; no ARM cross-builder is needed. The native AMD64 CI workflow
uses this path and passed both source-build and allocated-computation checks.

`prepare-sdk.sh` pins the ROCm packages and gives their signed repository priority
over Ubuntu's older HIP packages. `build-engine.sh` uses explicit x86-64 baseline,
VFIO off, and no upstream source patches. The cross-build intentionally disables
HIP fixture discovery; `verify-compute.sh` separately compiles the original test
using ROCm 7.2, the cross-built GoogleTest archive, and runtime rpath/loader path.
The AMD64 SDK path explicitly avoids using Ubuntu's HSA/HIP runtime libraries.

Retain named volumes to avoid rebuilding. To stop just this evaluation:

```sh
podman stop amd-rocjitsu-compute amd-rocjitsu-x86
# Optional deletion of this evaluation only:
podman rm amd-rocjitsu-compute amd-rocjitsu-x86
podman volume rm amd-rocjitsu-compute-build amd-rocjitsu-x86-build
```

See [evaluation](../ROCJITSU.md) for results and remaining interface boundaries.

## HAMi-allocated computation and AMD64

### Fedora/Linux AMD64: use the published images

This AMD64 target is for x86-64 Linux users, including Fedora. Native Ubuntu
24.04 CI passed a fresh installation from all four public images:
[published-image validation](https://github.com/sub-mod/amd-gpu-mock/actions/runs/39357566039).
Fedora installation has not yet been validated. Windows is outside this milestone.
The existing Mac ARM64 allocation setup is unchanged.

Install Docker with a running daemon, Kind v0.33.0 or newer, kubectl, Helm, Git
and Python 3. Run from the repository root on `experiment/amd-driver-mock`.
The runtime's Linux host must provide CUSE; on Fedora load it before setup:

```bash
uname -m # must report x86_64
sudo modprobe cuse
test -c /dev/cuse
docker run --rm --privileged docker.io/submod/amd-driver-mock:0.1.0-experiment.2-amd64 sh -ec 'test -c /dev/cuse'
```

If the module is missing, install your distribution's module package matching
the running kernel before continuing. An image cannot supply the host kernel
module. These commands use Docker; rootless Podman is not validated for this lab.

```bash
export CONTAINER_RUNTIME=docker
export DRIVER_MOCK_CONFIG=experiments/amd-driver-mock/config.amd64.json
experiments/amd-driver-mock/setup.sh

mkdir -p tmp/rocjitsu-eval/emulation/rocjitsu/configs
curl -fsSL https://raw.githubusercontent.com/ROCm/rocm-systems/0f80b261740a91e44ac2042e2f7eca6cdd8611a2/emulation/rocjitsu/configs/gfx942_cdna3_kmd.json \
  -o tmp/rocjitsu-eval/emulation/rocjitsu/configs/gfx942_cdna3_kmd.json
docker pull docker.io/submod/amd-driver-mock-compute:0.1.0-experiment.1-amd64
kind load docker-image docker.io/submod/amd-driver-mock-compute:0.1.0-experiment.1-amd64 --name amd-hami-driver
python3 experiments/amd-driver-mock/rocjitsu/run-pods.py

# Inspect actual workload output; tests leave Pods available.
kubectl --kubeconfig tmp/hami/kubeconfig -n amd-driver-mock-demo logs compute-left
kubectl --kubeconfig tmp/hami/kubeconfig -n amd-driver-mock-demo logs compute-right
# When finished, remove only the dedicated experiment resources:
experiments/amd-driver-mock/cleanup.sh
```

No SDK, compiler or custom image build is required. Image digests and source pins
are in [published-images.amd64.json](../published-images.amd64.json).
Actual fresh-install logs are in
[published-amd64 evidence](../evidence/rocjitsu/published-amd64).


The allocation extension is in `run-pods.py`. It reads the original renderer's
live KFD properties and AMD SMI identity, then generates a functional 304-CU
configuration with `shared-config.py`. Both Pods request `amd.com/gpu: 1`,
`amd.com/gpucores: 50`, and `amd.com/gpumem: 64`; no ROCR/HIP visibility, CU mask,
memory limit or LD_AUDIT value is manually supplied. The unchanged HAMi scheduler
and plugin provide those values.

```text
1. Original profile -> renderer state -> AMD SMI/libdrm mock -> HAMi discovery
2. Pod requests -> HAMi scheduler assigns UUID + 152 CUs + 64 MiB
3. Kubelet Allocate -> device plugin injects devices, CU mask, memory limit,
   and architecture-matched upstream HAMi audit library
4. Same renderer snapshot -> RocJITsu config: KFD UUID, PCI address, 304 CUs,
   192 GiB raw VRAM (8 XCD x 2 functional engines x 19 CUs)
5. Unchanged HIP/ROCr -> HAMi memory hooks -> RocJITsu KFD ioctl -> CPU execution
6. Diagnostic ioctl observer checks the original CU mask and driver result;
   application compares 1,024 results with the CPU reference
```

This is a functional topology, not a simulation of the precise MI300X floorplan
or disabled physical CUs. Each application uses local-mode execution with its
own simulator instance, derived from the same authoritative snapshot. It does
not establish a shared cross-Pod GPU memory pool, physical isolation, contention,
performance fidelity or live fault-state propagation.

Native AMD64 Linux is the target for the allocated-mask test. On the tested Mac,
identity and memory checks pass inside genuinely allocated Pods, but QEMU 10.2.2
user-mode does not implement `process_vm_readv`. RocJITsu uses that syscall to
safely copy a CU-mask buffer; the actual KFD request fails with EFAULT. The test
fails rather than replacing the syscall with unsafe memory copies or ignoring
the rejected mask. The earlier standalone vector-add success does not remove
this limitation.

ROCr 7.2 also returns from `AqlQueue::SetCUMasking` before updating the cache used
by `GetCUMasking` when the global mask is set. Therefore the getter's zero mask
is not used as proof. `mask-audit.c` is a diagnostic observer, not an allocation
backend: it forwards the original ioctl and buffer unchanged, checks the actual
mask against the plugin-provided range, and requires driver acceptance. A
failure exits the workload. It does not fabricate a successful driver reply.

The dedicated lab selects the AMD64 hook via upstream `HOST_HOOK_PATH`; the
script restores its original value afterward. On ARM64 this does not silently
replace the normal ARM64 hook. The new image contains an AMD64 hook compiled
from the same pinned `amd-hami-core` source as the plugin's ARM64 hook.

The native AMD64 workflow builds all three allocation-stack images, a matching
SDK/engine/payload and the compute image with Docker, then creates the dedicated
Kind cluster and runs the actual Pod tests. It requires CUSE from the Linux
host; a container image cannot supply that kernel facility.

- [AMD64 workflow](../../../.github/workflows/driver-mock-amd64.yaml)
- `build-images.sh`: supports native AMD64 and ARM64 builds, verifies matching
  publication-tag architecture, supports `DRIVER_MOCK_PLATFORM` explicitly.
- `prepare-sdk.sh` + `build-engine.sh` + `build-payload.sh`: reproduce payloads.
- `build-compute-image.sh --push`: build and publish a new AMD64 compute tag.
- `run-pods.py`: verify allocated computation; fails on missing mask support.

For locally built stack images, `DRIVER_MOCK_SKIP_PULL=1` explicitly loads plugin
and scheduler images into Kind. Default setup continues to pull published
images. Use the default runtime architecture on native AMD64 Linux; no QEMU
address-base setting is required there. Native AMD64 build support is separate
from the previously published ARM64 experiment tags.

### What the native AMD64 logs prove

[Fresh native AMD64 source-built run](https://github.com/sub-mod/amd-gpu-mock/actions/runs/39354225951)
passed. The actual left/right logs are captured under
[../evidence/rocjitsu/native-amd64](../evidence/rocjitsu/native-amd64).

```text
left:  KFD_MASK ... result=0 errno=0 expected=0:0-151 match=yes
right: KFD_MASK ... result=0 errno=0 expected=0:152-303 match=yes
both:  HIP PCI address: 0000:05:00.0
both:  visible_memory=67108864 expected=67108864
both:  PASS: HIP memory cap, cumulative accounting, and free/reallocate
both:  [  PASSED  ] 1 test.
both:  PASS: allocated Pod computation complete
```

The HAMi OOM error/warning lines are expected: the probe deliberately requests
too much memory and requires hipErrorOutOfMemory. They are evidence of rejected
allocations, not an unexpected Pod crash. The cache-getter zero is the documented
ROCr 7.2 issue; the accepted KFD requests are the mask evidence. The observer
fails on a mismatched mask or rejected driver request.

The test checks normal HIP API enforcement and mask propagation, not security
against bypassing those hooks, exact silicon execution placement, physical
VRAM isolation, performance partitioning, a shared cross-Pod execution engine,
or dashboard fault/telemetry propagation into RocJITsu.
