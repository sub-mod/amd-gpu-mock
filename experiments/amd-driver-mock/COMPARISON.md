# Comparison with the original implementation

Initial original baseline: `main` at
`4531c4df390e409442676c4852a5f61cf0a5ea46`.
The investigation branch starts from the same tracked tree as
`feat/openshift-demos` at `47a64e5`; those prior OpenShift changes are not
attributed to this driver experiment. Compare driver increments with `6a1d6ee`,
the committed design checkpoint, and compare shared fixes with the original
baseline. Do not merge the whole experimental branch just to take one fix.

## Shared code and candidate fixes

| Area | Original implementation | Experiment | Merge-back decision |
| --- | --- | --- | --- |
| Profiles and state | MI300X profile and Go topology/SMI renderer | Reused directly; adapter selects one GPU | Preserve one source; no second independent inventory |
| KFD unique_id | Profile hex text copied into the kernel-facing property | Render unsigned decimal, matching the kernel's KFD ABI | Small correctness fix; regression fails on original baseline and passes here |
| AMD SMI BDF lookup | amdsmi_get_processor_handle_from_bdf returns NOT_SUPPORTED | Resolve handle from the same snapshot identity used for enumeration | Small additive identity capability; test valid, unknown, null and uninitialized calls |
| Allocation | Upstream AMD DRA or ROCm device plugin | HAMi plugin and scheduler instead, on a dedicated cluster | Optional integration only; never double-advertise devices |
| Openable devices | Character nodes used for injection/stat checks, without a backing AMD driver | Genuine CUSE-backed character devices, dynamically assigned majors | Keep experimental until portable host requirements and isolation are reviewed |
| Driver capacity query | No libdrm_amdgpu simulator | ABI-compatible subset reads original-renderer capacity | Separate backend/project candidate |
| GPU computation | No HIP execution | Still no HIP execution | No expanded compute claim |

## Independent candidate commits

- `db01620`: decimal KFD unique IDs and standalone regression test.
- `91984ab`: AMD SMI BDF lookup and extension of the original C ABI test suite.

Both are on the experiment branch only. Neither requires CUSE or HAMi to be
installed. They are candidates for a later cherry-pick into main, not merged
changes to the default branch.

## Current new boundaries

The library backend replaces libdrm_amdgpu and AMD SMI; it does not validate the
real libdrm-to-amdgpu ioctl path. CUSE makes native open succeed, but raw compute
ioctls are not implemented. This backend's dynamic character-device numbers are
intentionally different from the original stat-only DRM numbers.

The private Linux Podman volume needs `dev` for its device nodes. No host GPU
node is removed or relabelled: dedicated Kind mount-namespace bind mounts expose
the simulated endpoints at the paths HAMi expects. No unrelated cluster, normal
quick start or OpenShift setup is changed.

The Fedora Podman VM had CONFIG_CUSE=m but no installed cuse module. The matching
kernel-modules-extra RPM was downloaded, verified with rpmkeys and extracted
under /tmp, then only its matching CUSE module was loaded. This is a host
prerequisite, not an image capability. A container image cannot supply a missing
host driver just by including a device filename.

HAMi's current chart and published v2.10.0 image are not a compatible pair for
this pinned main checkout (unknown --extender-bind). Use a source-matched
scheduler build, not source edits that suppress the flag.

## Iteration discipline

For every new interface: record its real caller, baseline behavior, changed
behavior, test evidence, missing APIs and merge-back classification. Keep
unsupported operations explicit. Shared fixes should have narrow commits and
standalone tests, so they can be reviewed/cherry-picked without experimental
images or CUSE dependencies. Do not merge them into main until asked.

## RocJITsu evaluation

[Evaluation and captured results](ROCJITSU.md): experiment-only scripts and
evidence. Original main and the HAMi experiment still do not run HIP kernels
by themselves. An isolated unchanged upstream HIP vector-add now passes with
ROCm 7.2, cross-built RocJITsu and AMD64 QEMU userspace on ARM64. All 1,024 values
are compared to a CPU reference. Direct execution without the simulator fails
with hipErrorNoDevice. QEMU guest-base configuration fixes the observed high-VA
queue setup failure without source patches. No integration/isolation claim or
additional merge-back implementation from this milestone.
