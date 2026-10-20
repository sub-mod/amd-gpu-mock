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
AMD64 container; no ARM cross-builder is needed. That variant has not been run
in this evaluation.

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
