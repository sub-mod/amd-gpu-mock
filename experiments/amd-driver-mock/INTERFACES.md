# Implemented interfaces and deliberate gaps

Pins are in versions.env. HAMi AMD source is unchanged at
35c84ab2b224f7f43c74bb68e307dfd244c71bae; scheduler source is unchanged at
84c75baf89b2bec4fd11660126ad2660b9d957f2; native audit library source is the
plugin's amd-hami-core submodule at 4621eb67396c67014358c67aa5b074d608b5c466.

## Implemented experiment boundary

| Interface | Implementation | Validation |
| --- | --- | --- |
| Native open | Actual Linux CUSE endpoints for card, render and KFD paths | Standalone client and both workload Pods open character devices |
| amdgpu_device_initialize/deinitialize | Restricted simulated handles; match the provider's dynamic major and profile inventory | Positive open; reject /dev/null and invalid handles |
| amdgpu_query_gpu_info | Device ID and active CU count from original rendered KFD properties | Original MI300X gives 304 CUs |
| amdgpu_query_info AMDGPU_INFO_MEMORY | Whole-GPU VRAM from the original profile's rendered local_mem_size | 206158430208 bytes; reject unknown query/buffer size |
| AMD SMI identity | Reuse original ABI 27 mock; add BDF-to-handle resolution | Full existing C ABI suite plus null/unknown/uninitialized/roundtrip checks |
| Native hook | Unmodified amd-hami-core compiled for ARM64 and mounted by real plugin | LD_AUDIT path and configured limits reach Pods; native Python loads it |
| Mock health | Existing RAS fatal_error state makes simulated initialization fail | Real HAMi heartbeat/ListAndWatch makes kubelet allocatable zero, then four after recovery |

The dynamic device majors and library replacement are explicit simulation
contracts. The real AMD kernel/libdrm ioctl path is not under test. Raw ioctls
return ENOTTY. Firmware queries return EOPNOTSUPP. No blanket success stubs are
added for GPU control or execution.

## Gaps discovered during implementation

- Original hexadecimal KFD unique_id text made HAMi parse zero and take its APU
  path. Correct decimal rendering restores GPU-9c4f000000000001 identity.
- AMD SMI previously lacked BDF lookup even though it could enumerate BDFs.
- CUSE needs a matching host module; it is not provided by an ordinary container.
- Podman volumes default to nodev; the private device volume needs dev.
- A chart from pinned HAMi main is incompatible with the published v2.10.0 image
  (--extender-bind). Build the scheduler from its matching pin.
- Hardware partition profile APIs remain NOT_SUPPORTED. The discovery path
  logs/falls back as upstream implements; the experiment only promises SPX.
- Native ARM64, one GPU, fixed library handles and a one-GPU health failure are
  covered. Multiple GPUs, removal/reappearance of complete inventory, physical
  partition control and recovery of CUSE after a provider/VM restart remain work.
- HSA masks and memory-limit variables are configured, not exercised by HIP.
  The kernel dmem backend is explicitly off; no actual memory cgroup limit or
  VRAM enforcement is claimed.
- No dashboard server is launched by this isolated experiment. Fault tests
  change the original renderer's RAS state through the provider; a dashboard
  adapter to the same state is future integration.
- No OpenShift/CRC, AMD64 or Docker clean-install result is claimed.

## RocJITsu compute prerequisite

An unchanged upstream gfx942 HIP vector-add passes against the real ROCm 7.2
runtime with RocJITsu's KMD interposer/CPU execution engine in isolated AMD64
userspace under ARM64 Podman/QEMU. The no-simulator control fails with no device.
See [results and scripts](ROCJITSU.md). No shared interface is changed: this is
not yet wired to the project's profile/state, AMD SMI/libdrm mock or HAMi hooks.
QEMU guest-base configuration is needed on the tested host. The following allocation extension verifies identity and memory accounting in
Mac Pods, but its actual CU-mask ioctl fails because QEMU user-mode lacks
process_vm_readv. Native AMD64 validation is separate. Shared fault state,
native ARM64 ROCm, cross-Pod shared VRAM and physical isolation remain unverified.
