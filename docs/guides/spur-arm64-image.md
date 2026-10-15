# Native ARM64 Spur image

This artifact packages Spur 0.14.0 from upstream revision
`bd28e6395547377cb47c7d911390f99432a5fc73` for Linux ARM64.
The intended image is `docker.io/submod/spur:0.14.0-arm64.1`.
Published digest: `sha256:b3fd4a8887e8f4cc6b3530fba281c3b181db5cd2cbea53548594aba415cc85c2`.
Native build, publication and OpenShift queueing validation passed on October 15,
2026. [Build/test output](../../artifacts/spur-arm64/build-evidence.log),
[provenance](../../artifacts/spur-arm64/image.json) and
[live OpenShift output](../../demo/openshift/spur/captured.log).

## What differs from upstream

The pinned upstream image is AMD64. Its Dockerfile also downloads an x86-64
Protobuf compiler. The build script selects the ARM64 Protobuf 25.1 asset and
preserves the upstream AlmaLinux 8 builder, Ubuntu 24.04 runtime, Rust 1.95.0,
Cargo.lock and six-binary layout.

A real native build exposed four MPI-plugin FFI buffers declared as `i8`.
Linux ARM64 C `char` uses an unsigned representation, while the called functions
expect Rust `c_char`. The separately reviewable
[portability patch](../../artifacts/spur-arm64/c-char-portability.patch) changes
those four buffer initializers and the existing unit-test buffer to `c_char`.
It does not change queueing, GPU allocation, authentication or job execution.
The image is therefore a downstream patched build, not the unmodified upstream
image. Its embedded Git metadata marks the source dirty.

No upstream PR was opened. Building the image does not establish MPI runtime
support: the optional OpenPMIx plugin remains disabled, as in upstream's default
container build. The included validation passed 20 existing MPI-plugin unit tests (one ignored),
not an actual distributed MPI workload. All six binaries also passed native
`--help` execution checks. Only controller/operator/job behavior was exercised
in the OpenShift integration.

## Rebuild and publish

From the AMD GPU mock repository root:

```bash
./artifacts/spur-arm64/build.sh
# Maintainers with write access to the image registry:
./artifacts/spur-arm64/build.sh --push
```

The default engine is Podman. Set `CONTAINER_RUNTIME=docker` for Docker.
Use a Linux ARM64 engine for native compilation. An AMD64 engine would need
separately configured ARM64 emulation. `SPUR_ARM64_IMAGE` changes the output tag;
`SPUR_BUILD_DIR` changes the cache location. Normal users pull the published
artifact; they do not need Rust or an image build.

The script downloads the pinned source, applies the patch, derives the build
recipe and builds all six binaries: `spur`, `spurctld`, `spurd`, `spurstepd`,
`spurauthd` and `spur-k8s-operator`. It runs
`cargo test --release --locked -p spurd --lib mpi_plugin::tests`, checks the OCI
architecture and executes `spur --version` before publication.

The build directory contains the source archive, generated Containerfile,
`provenance.json` with source/lockfile/recipe hashes and, after pushing,
`published-digest.txt`. The image labels identify source revision and license.
The base images and package repositories follow the pinned upstream recipe;
rebuilding is source reproducible, not a guarantee of identical image bytes.

## OpenShift Local demonstration

The OpenShift adapter is in `demo/openshift/spur/`. It uses the existing mock
AMD device-plugin capacity and the same controller/operator configuration as
the Kind demo, with OpenShift namespace and SCC adaptation.

It temporarily removes the known Tiny LLM GPU consumer so Spur can own its
managed node's whole GPU pool; unrelated GPU consumers cause setup to fail.
It supplies Spur's documented GPU-type/memory node labels from the installed
MI300X mock configuration. GPU capacity still comes from the real device plugin.

Controller and operator Pods explicitly require `restricted-v2`. The test also
checks the SCC actually selected for Spur-created job Pods. It does not grant
privileged or anyuid SCC access to the Spur service accounts.

Run the setup/test commands from the [OpenShift demo sequence](openshift-demos.md).
The workload checks real character-device injection and queue transitions,
returns completed jobs, and leaves their logs available for inspection. No GPU
computation, model inference, MPI transfer or performance claim is made.

## Observed execution order

```text
[1] Patched pinned source -> native ARM64 build + existing unit tests
[2] Publish image -> CRC pulls the digest (no runtime architecture emulation)
[3] Spur controller + operator -> discover actual amd.com/gpu capacity
[4] First SpurJob -> Spur selects crc -> operator creates eight-GPU Pod
[5] AMD device plugin / kubelet / CRI-O -> device injection -> restricted-v2 job
[6] Second SpurJob stays queued, without a Pod, while the pool is occupied
[7] First job completes -> Spur releases pool -> second job receives one GPU
[8] Second job completes -> completed Pods and logs remain for inspection
```

Spur owns placement: its operator creates node-pinned Pods after Spur selects
the node. This does not validate default-scheduler node selection or multi-node
placement. The integration uses the device-plugin path, not DRA.
