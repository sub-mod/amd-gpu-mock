# Published experiment artifacts

All three images are public Linux ARM64 artifacts, version
`0.1.0-experiment.1-arm64`. Immutable manifest and image-config digests plus
anonymous registry-access verification are recorded in published-images.json.
These are experimental lab images, not production driver packages.

| Image under docker.io/submod | Contents | Build recipe |
| --- | --- | --- |
| amd-driver-mock | Ubuntu 24.04, libfuse/CUSE provider, mock libdrm_amdgpu, original AMD SMI ABI 27 backend with BDF lookup, native probe, original Go renderer and profiles; development compiler/tools retained | Containerfile |
| amd-driver-mock-hami | Backend runtime plus native ARM64 HAMi AMD plugin from pinned unchanged source, hwloc runtime and native unchanged amd-hami-core audit library | Hami.Containerfile |
| amd-driver-mock-scheduler | Ubuntu 24.04 and native HAMi scheduler built from pinned unchanged source | Scheduler.Containerfile |

The scheduler chart separately uses the real upstream kube-scheduler matching
the Kind Kubernetes version, and published webhook certificate jobs. No NVIDIA
plugin is enabled for this AMD lab. The AMD plugin chart is rendered unchanged,
then deploy.py applies the explicit mock image, library/state/sysfs mounts and
documented settings. This is a deployment adapter, not a HAMi source patch.

## Native source builds

build-images.sh fetches the exact source revisions in versions.env and verifies
the amd-hami-core submodule pin. It builds the plugin against the official ABI 27
header already recorded in the original repository's SMI provenance. The
scheduler build needs cgo because HAMi imports the NVIDIA NVML bindings even in
an AMD-only deployment; that does not mean a real NVIDIA GPU or driver is used.

The audit library builds from the upstream C sources. Workloads can load it
natively, but this demo does not invoke a real HIP allocator through its hooks.
No artificial HIP backend is supplied to make an enforcement test pass.

Build contexts include the pinned upstream checkouts, exclude their Git metadata,
and exclude image tar archives, logs and unrelated temporary files. Normal setup
pulls the images and does not execute these builds. A new source change should
receive a new image tag and new captured validation; publishing refuses an
existing tag.

## Host versus image

The image contains a userspace CUSE service; the matching CUSE kernel module
belongs to the Linux host. See HOST.md. Device state is held in an experiment
volume with dev enabled on Podman, then mounted into the dedicated Kind node.
Deleting the cluster and provider before the volume releases the device handles.
A reboot or provider restart is not yet an automatic-recovery contract.
