# RocJITsu evaluation — 2026-10-19

Recommendation: retain RocJITsu as an optional compute backend candidate. A real
HIP vector-add now passes through it in the isolated evaluation. It is
not a replacement for the interfaces that made the HAMi experiment work.

Source: ROCm/rocm-systems at
`0f80b261740a91e44ac2042e2f7eca6cdd8611a2`, `emulation/rocjitsu`.
No upstream source modifications. Native Linux ARM64 inside Podman on macOS;
Ubuntu 24.04, GCC 13.3, CMake 3.28.3, Ninja 1.11.1, Python 3.12.

## Actual results

| Check | Result | Meaning |
|---|---|---|
| Native ARM64 CMake configure | Passed | Build system accepts this host |
| Upstream rocm_visibility_test | 24/24 passed | GPU selection parsing/filtering works in these unit cases |
| Initial ARM64 rocjitsu_tests build | Intentionally interrupted | Historical first evaluation, not a compiler failure |
| AMD64 launcher + KMD interposer | Built all 638 steps | Native ARM64-host cross-compiler; unchanged source |
| HIP vector-add through real ROCm 7.2 | Passed | 1,024 results compared against CPU reference |
| Same executable without simulator | Expected failure | hipErrorNoDevice; no physical GPU passed in |
| Matrix multiplication / LLM | Not run | No broader compute claim |
| HAMi + RocJITsu on native AMD64 | Passed in fresh CI cluster | Two 152-CU allocations, 64 MiB caps, accepted KFD masks and correct HIP output |
| HAMi + RocJITsu on Mac | Identity and memory checks passed; mask ioctl failed | QEMU process_vm_readv unavailable |

The initial native ARM64 container had no HIP SDK. The next milestone used
ROCm 7.2 AMD64 userspace through QEMU 10.2.2 in the existing ARM64 Podman VM.
Engine compilation ran natively with x86_64-linux-gnu GCC 13.3; the real HIP/ROCr
runtime and compiled gfx942 kernel ran under QEMU, with no physical GPU devices.

The default address layout failed: queue creation returned EFAULT, followed by a
ROCr ScratchCache::freeMain crash during error cleanup. GDB with the matching
ROCr symbols identified the failed AQL queue creation and high context-save
address. QEMU_GUEST_BASE=0x800000000000 made the unchanged test pass. A restricted
QEMU_RESERVED_VA failed at vsyscall allocation; disabling SDMA did not fix the
original crash. Address-base control is an environment requirement for this
validated setup, not a source patch or a general proof about all QEMU hosts.

The first passing test took about 3.9 seconds. The normal Release library was
restored after diagnostic debug information was used, then the reproducible
verification script reran compilation, expected-negative control, and positive
simulation. Captured logs: [evidence/rocjitsu](evidence/rocjitsu).
[Reproduction, scripts, and execution diagram](rocjitsu/README.md).

The dedicated HAMi demo remains separate. Evaluation containers are stopped,
with source, SDK and build caches retained for retry. That standalone milestone built no custom image and made no source patch.
The later allocation extension adds a compute image and branch-only CI.

## Boundary and proposed order

```text
1. Original profile/state: one authoritative MI300X identity and capacity
   |
2. AMD SMI + libdrm mock + CUSE --> unchanged HAMi discovery/allocation
   |
3. Allocated Pod: HIP application + HAMi library hooks
   |
4. Candidate RocJITsu KMD interposer --> simulated KFD queues/memory
   |
5. GPU ISA execution on CPU --> result compared with CPU reference
```

Steps 1–2 are existing experiment behavior. Steps 4–5 now work in the isolated
upstream compute test. Connecting step 3 to them remains unproven.
RocJITsu must use the same identity, topology and state; adding independent
simulated inventory would invalidate the test. Device-open/ioctl ownership must
be explicit so its interposer does not conflict with CUSE and library mocks.
HAMi's LD_AUDIT hooks and RocJITsu's LD_PRELOAD require composition testing.

Source review finds AMDKFD_IOC_SET_CU_MASK implemented in simulated_kfd.cpp,
including validation and queue CU selection. That is useful evidence of a
relevant interface, not evidence that HAMi masks reach execution. Likewise,
visibility tests do not demonstrate physical memory isolation or allocation
limits. No HSA_CU_MASK environment integration was established by this review.

Next useful milestone: run this verified computation inside a HAMi-allocated
Pod, derive simulator identity/configuration from the shared profile/state,
and validate hook composition, queue masks and memory-limit behavior. The
current computation uses upstream's standalone MI300X configuration; it is not
evidence of shared state, enforced slicing, HAMi integration or fault propagation.
Avoid PyTorch/LLM scope until that boundary passes. The validated runtime is
AMD64 userspace on ARM64 via QEMU, not native ARM64 ROCm.

## Comparison with original main

Against pinned main 4531c4df390e409442676c4852a5f61cf0a5ea46, neither main nor
the current HAMi mock runs HIP kernels by itself. This isolated RocJITsu test
adds evidence that an optional backend can execute a real HIP kernel without
hardware. It does not change either implementation's current compute support.
New files are experiment-only setup/build/verification scripts, documentation
and logs. No changed shared runtime interface, second project inventory, root
README change, main merge or new merge-back implementation. The independent
decimal-KFD-ID and SMI-BDF candidate fixes remain unchanged.

## Upstream references

- [Overview](https://rocm.github.io/rocm-systems/rocjitsu/)
- [Architecture](https://rocm.github.io/rocm-systems/rocjitsu/architecture/)
- [Build instructions](https://github.com/ROCm/rocm-systems/blob/0f80b261740a91e44ac2042e2f7eca6cdd8611a2/emulation/rocjitsu/docs/building.md)
- [VFIO route](https://rocm.github.io/rocm-systems/rocjitsu/qemu-vfio/): documented
  Linux x86-64, single gfx1250 profile, user-supplied compatible guest artifacts.
  It is a different experiment from this ARM64 MI300X userspace path.

## Initial ARM64 evaluation commands (historical)

After sparse-cloning emulation/rocjitsu and shared from the pinned repo, mount
that source read-only at /source in the existing Ubuntu-based experiment image,
with a separate Linux build volume at /build; install cmake and ninja-build.

```sh
cmake -S /source/emulation/rocjitsu -B /build -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DFETCHCONTENT_BASE_DIR=/build/dependencies \
  -DROCJITSU_ENABLE_VFIO=OFF -DROCJITSU_HOST_CPU_BASELINE=default
cmake --build /build --target rocm_visibility_test -j2
/build/tests/rocm_visibility_test
# Attempted but interrupted; do not count as a completed build:
cmake --build /build --target rocjitsu_tests -j2
```

## Allocated-Pod extension and platform boundary

The next extension now runs actual HAMi allocation, using the shared renderer
snapshot and architecture-matched upstream hook. On the tested Mac, both Pods
passed HIP memory-cap enforcement (single/cumulative overflow rejection and
free/reallocate), raw GPU identity and PCI address checks. The actual CU-mask
ioctl fails: QEMU 10.2.2 user-mode returns ENOSYS for process_vm_readv, reproduced
independently. The driver safely returns EFAULT. The test does not skip it or
replace safe pointer access with memcpy. The earlier vector-add success is
therefore not a masked-computation success.

ROCr 7.2's local mask getter cache is also unsuitable for proof when its setter
returns early through the driver. The diagnostic observer forwards original
ioctls and requires matching masks plus driver acceptance. See
[allocated execution diagram and AMD64 workflow](rocjitsu/README.md#hami-allocated-computation-and-amd64).

Native AMD64 Linux validation runs on the experiment branch only, with Docker,
CUSE and a real kernel implementing the syscall. No PR or main merge. Explicit
shared-state projection is a functional 304-CU topology, not physical layout;
local-mode simulators do not establish cross-Pod shared VRAM or live fault state.

### Native AMD64 result

[Source-built fresh-cluster run](https://github.com/sub-mod/amd-gpu-mock/actions/runs/39354225951)
passed. Both actual Pod logs were inspected: KFD masks 0–151 and 152–303 were
accepted (result=0), each Pod enforced a 64 MiB HIP cap, overflow/cumulative
allocation rejection and reuse after free passed, identity was
GPU-9c4f000000000001 / 0000:05:00.0, and both unchanged HIP vector-add tests
passed all 1,024 CPU-reference comparisons. Raw evidence is in
[evidence/rocjitsu/native-amd64](evidence/rocjitsu/native-amd64).

This adds native AMD64 support to the optional driver experiment, not native
ARM64 ROCm or a fix for QEMU's missing syscall. The original main baseline and
normal quick start are unchanged. The reusable decimal KFD ID and AMD SMI BDF
fixes remain isolated earlier commits; this integration is experiment-only.
