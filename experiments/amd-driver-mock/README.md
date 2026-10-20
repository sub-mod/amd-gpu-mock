# AMD driver interface mock with HAMi

Experimental library-level backend for one simulated AMD Instinct MI300X. The
unmodified HAMi AMD plugin reads consistent capacity/identity through mock DRM
and AMD SMI interfaces, registers four share slots, and allocates two Pods on the
same GPU. A third waits for capacity, then runs after one consumer is removed.

This branch is the prototype for a separate `amd-gpu-driver-mock` project. No
separate GitHub repository or upstream PR has been created. The normal AMD mock
quick start is unchanged.

## What runs at each layer

```text
[1] config.json selects library backend, MI300X, SPX and one physical GPU
                            |
[2] Original Go profile/renderer --> shared sysfs + AMD SMI state
                            |
        +-------------------+------------------------+
        v                   v                        v
[3] CUSE character     mock libdrm_amdgpu       existing mock AMD SMI
    endpoints         capacity/health ABI      + BDF lookup
        +-------------------+------------------------+
                            v
[4] Unmodified HAMi plugin --> actual node inventory + kubelet share slots
                            |
[5] HAMi webhook + scheduler --> two 50%-CU, 96-GiB allocations on one GPU
                            |
[6] Kubelet + plugin Allocate --> device nodes, HSA_CU_MASK, memory hook settings
                            |
[7] Consumer prints actual identities/settings and opens CUSE devices
                            |
[8] Third Pod stays Pending --> delete one consumer --> budget is reused
```

The native device open is backed by Linux CUSE. This is not a /dev/null alias,
regular-file replacement, or fabricated HAMi allocation annotation. The
libdrm_amdgpu library is deliberately replaced: the real AMD kernel/ioctl path
is not being validated. Raw unsupported ioctls return ENOTTY.

## Run from a fresh experiment

Validated platform: Linux ARM64 in this Mac's default Podman VM, Kind Kubernetes
v1.37.0. Requires running Podman, Kind, kubectl, Helm, Git, Python 3 and host CUSE.
See [host prerequisites](HOST.md). AMD64, Docker and CRC are not validated yet.
Do not run this on a node where another allocator owns the same GPUs.

```bash
# From this worktree's repository root. No compiler or image build is needed.
experiments/amd-driver-mock/setup.sh
python3 -u experiments/amd-driver-mock/verify.py
python3 -u experiments/amd-driver-mock/tests/lifecycle.py

# Inspect the retained consumers and their actual environment/device evidence.
kubectl --kubeconfig tmp/hami/kubeconfig -n amd-driver-mock-demo get pods
kubectl --kubeconfig tmp/hami/kubeconfig -n amd-driver-mock-demo logs right

# Destroy only this experiment's dedicated cluster, provider and volume.
experiments/amd-driver-mock/cleanup.sh
```

Setup refuses an existing experiment cluster or volume rather than overwriting
it. It uses the published images in config.json and downloads the two pinned
upstream chart/source checkouts. It compiles nothing. It writes its own kubeconfig
under tmp/hami; it does not switch or deploy into the user's default context.
If setup fails halfway, run cleanup.sh before starting over.

Override `DRIVER_MOCK_CONFIG=/path/to/config.json` to choose a configuration file.
Only the tested library/MI300X/single-GPU/SPX/four-share combination is accepted
currently. Unsupported backends fail before provisioning; there is no silent
fallback. The older setup.example.yaml is a design sketch, not an installer input.

## What the tests establish

| Test | Result being checked |
| --- | --- |
| Native probe | Open real CUSE device; read 304 CUs and 192 GiB from original-renderer state; reject wrong query/buffer and /dev/null |
| SMI ABI | Existing enumeration/sensors/ECC/concurrency checks plus BDF roundtrip, unknown BDF, null output and uninitialized state |
| Inventory | Actual HAMi annotation contains one GPU with 196608 MiB, 304 CUs and four slots; kubelet advertises four slots |
| Two consumers | Same physical UUID, disjoint 152-CU masks, 98304m memory-limit settings, native character-device opens |
| Exhaustion/reuse | Third Pod is unbound/Pending at full memory/CU budget; removal admits it while the sibling remains Running |
| Restart | Both consumer Pod UIDs survive plugin replacement; advertisement returns |
| Fault/recovery | RAS fatal_error makes simulated DRM initialization fail; real plugin heartbeat reduces kubelet allocatable to zero and recovery restores four |

Configured memory limits and CU masks do not prove GPU memory isolation or
compute throttling. The workload is Python device/environment inspection, not
HIP or inference. The dmem kernel backend is explicitly disabled. The native
amd-hami-core hook is compiled unchanged and injected, but its allocation hooks
are not exercised by a real HIP allocator.

The experiment does not start the original dashboard. Its fault test changes the
shared renderer's RAS state; a dashboard adapter is future work. No automatic
workload eviction is claimed. See [implemented interfaces and gaps](INTERFACES.md).

## Evidence and comparison with main

[Captured evidence](evidence/README.md) contains actual logs and artifact
provenance. Logs are historical runs, not output fabricated by the scripts.
[COMPARISON.md](COMPARISON.md) distinguishes the original baseline, shared fixes
and experiment-only behavior.

Two narrow commits are candidates for review/cherry-pick into main:

- `db01620`: emit decimal KFD unique IDs, matching the kernel ABI. Its new
  regression fails against the original main baseline and passes here.
- `91984ab`: resolve AMD SMI handles by BDF, with original C ABI suite coverage.

Neither is merged into main. CUSE, library replacement and HAMi setup remain
isolated experiment code.

## Rebuild and publish

Source pins are in versions.env. All custom image build recipes are included;
images and their recorded digests are listed in published-images.json.

```bash
# Developer-only build; ordinary setup pulls the published images.
experiments/amd-driver-mock/build-images.sh

# Publish a NEW tag after native checks and integration validation.
DRIVER_MOCK_IMAGE_TAG=0.1.0-experiment.2-arm64 \
  experiments/amd-driver-mock/build-images.sh --push
```

Publishing requires an existing registry login. The script refuses an existing
published tag. The build script supports ARM64 and AMD64, and requires the published tag
suffix to match the image architecture. ARM64 published tags remain unchanged. Build contexts exclude logs, archives and unrelated temporary files.
Kernel-coupled ioctl emulation, multi-GPU support and standalone repo extraction
remain separate iterations.

[Artifact contents and provenance](ARTIFACTS.md) explain what is bundled in each
image and which dependencies belong to the Linux host instead.

[RocJITsu evaluation](ROCJITSU.md) records ARM64 build checks and the remaining compute boundary.
