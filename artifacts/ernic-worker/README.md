# Prepared ERNIC worker artifact

`docker.io/submod/amd-ernic-worker:0.1.0` packages a prepared ARM64 VM disk for
the [GPU/network single-node demo](../../demo/gpu-network/single-node/README.md).
It is an OCI image used for file distribution, not a runnable container.
The image is published and clean worker setup and allocation validation passed.
See [validation.md](validation.md) for the tested scope and captured evidence.

## Contents

| File | Purpose |
| --- | --- |
| `/worker/worker-base.img` | Standalone compressed qcow2 Ubuntu 26.04 ARM64 disk |
| `/worker/Image.raw` | Direct-boot kernel extracted from the pinned Ubuntu image |
| `/worker/initrd` | Matching Ubuntu initrd |
| `/worker/manifest.json` | Kubernetes version, architecture, base checksum and payload SHA256 checksums |
| `/worker/packages.txt` | Installed Ubuntu package versions |

The disk includes containerd, runc, rdma-core, ibverbs-utils, kubeadm and kubelet
v1.37.0, CNI binaries, and a systemd kubelet unit. Kubernetes binaries and CNI
come from the installed Kind control-plane image. Ubuntu packages are installed
at build time; their exact installed versions are recorded in `packages.txt`. The base image and kernel inputs are pinned in
[`versions.env`](../../scripts/ernic/versions.env).

The disk is unjoined. Build cleanup removes the temporary build account, SSH
host keys, cloud-init state, machine identity, guest-specific IP configuration,
logs, and container cache. User setup supplies a fresh SSH key, hostname and
network configuration and creates short-lived Kubernetes join credentials.
The artifact contains no GPU model weights or RDMA transfer implementation.

QEMU, ERNIC and libvfio-user run outside the guest in the separate
`amd-ernic-lab` image. The existing GPU mock agent and upstream DRA driver are
installed by Helm after the VM joins Kubernetes. The Network Operator and NIC
device plugin are also installed separately. These layers are not baked into
the worker disk.

## Rebuild and publish

Maintainers need the normal ARM64 Podman Kind cluster, the published lab image,
and the tools required by `scripts/ernic/setup.sh`.

```bash
./artifacts/ernic-worker/build.sh          # build locally
./artifacts/ernic-worker/build.sh --push   # build and publish
```

The script creates an isolated builder VM, installs the guest dependencies,
stops before cluster join, sanitizes the guest, powers it down, and flattens its
disk with `qemu-img convert`. It hashes the payload and packages it using
[`Containerfile`](Containerfile). The build state is ignored under
`tmp/ernic-worker-build/`; it contains private local SSH keys and must not be
committed. An existing builder container causes setup to stop for inspection;
remove that dedicated builder before restarting a failed build.

Change the artifact tag in `versions.env` for a new release. Do not overwrite a
published release tag. Ubuntu package repositories can change, so this process
is source-pinned but does not promise bit-for-bit identical package resolution.
Preserve the resulting manifest and installed package inventory with release
validation logs.

## User setup and verification

```bash
./scripts/ernic/setup.sh
./demo/gpu-network/single-node/run.sh
```

Setup pulls the artifact through Podman, extracts the payload, checks its
SHA256 checksums and Kubernetes version, and creates a writable qcow2 overlay.
It skips guest apt installation and copies no Kubernetes tools from the control
plane on this path. Registry layers are cached by Podman. Published image digests are recorded in
[published-images.json](published-images.json); payload checksums are in
[manifest.json](manifest.json), and Ubuntu versions in [packages.txt](packages.txt). No Kind image change
is needed: the NIC requires the separate VM worker, which joins the existing
Kind control plane.

A release is ready only after a fresh artifact pull, unique cloud-init identity,
Ready worker, NIC discovery, GPU ResourceSlices, combined allocation and demo
HTTP response have been validated. This does not validate RDMA transfer or GPU
inference. Use `ERNIC_USE_PREPARED=false` only for maintainer builds or diagnosing
the raw Ubuntu provisioning path.

For local testing before publication, `ERNIC_PULL_PREPARED=false` uses the
locally built artifact. Default setup always checks the registry. A failed
unjoined VM can be resumed explicitly with `ERNIC_RESUME_UNJOINED=true`; keep
its node/container/state/SSH settings identical. This never replaces its disk.
RDMA device names are discovered rather than forced: Ubuntu may name the
interface `rocep0s4` instead of the kernel initial name `ionic_0`.

The initial build copied Kubernetes/CNI tools from published Kind image
`docker.io/submod/amd-mock-kind-node:0.2.2`
(`sha256:6106f4ec6ab84133acd817c9274671e9bded5219f93e4dc3c9a82b2ab930a774`).
The build script requires Kubernetes v1.37.0 inputs. The chart version is
independent of this node-image version.
