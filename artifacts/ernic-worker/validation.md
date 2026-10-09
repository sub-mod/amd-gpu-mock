# Initial artifact validation — 2026-10-08 (America/New_York)

Validated on an Apple-silicon Mac with Podman 6.0.2, the existing default libkrun
machine (16 GiB), and an existing Kubernetes v1.37.0 Kind control plane. This was
a fresh VM-worker installation; the control plane was retained.

The final run used a new state directory, SSH key, writable disk and guest
identity, with the normal registry pull enabled. Setup completed without
recovery flags or manual guest edits. No packages were installed on this path.

| Check | Result |
| --- | --- |
| Four image manifests anonymously readable from Docker Hub | PASS |
| Prepared artifact payload checksums and architecture | PASS, Linux ARM64 |
| New SSH host key and machine ID | PASS, differ from builder and earlier VM |
| Worker bootstrap and node readiness | PASS, Kubernetes v1.37.0 |
| NFD actual PCI discovery and operator NIC resource | PASS, one `amd.com/nic` |
| DRA claim, ResourceSlice and injected render-device match | PASS |
| NIC allocation metadata and discovered RDMA sysfs identity | PASS, `rocep0s4` |
| Application HTTP response | PASS, explicitly scripted simulation |
| Workload cgroups | PASS, 128 MiB memory and one CPU enforced |
| Published chart 0.2.12 upgrade and post-upgrade allocation | PASS |
| Real AMD exporter metrics and readiness | PASS with five-second probe timeout |
| Existing default dashboard and Grafana endpoints | HTTP 200 |

[Clean setup output](../../demo/gpu-network/single-node/clean-install.log),
[allocation output](../../demo/gpu-network/single-node/clean-demo.log),
[published-chart upgrade](../../demo/gpu-network/single-node/published-chart-upgrade.log),
[post-upgrade verification](../../demo/gpu-network/single-node/published-chart-demo.log),
and [runtime checks](../../demo/gpu-network/single-node/runtime-checks.log)
contain actual captured results. The clean VM initially used chart 0.2.11;
0.2.12 was subsequently published and validated to correct a one-second
readiness limit against a measured 1.015-second metrics response under TCG.

Integration corrections included discovering predictable RDMA names instead of
assuming `ionic_0`, waiting for asynchronous node registration, giving Helm
ownership of its NIC ConfigMap configuration through one derived-chart template
override, and waiting for workload deletion before worker drain. No upstream
QEMU, ERNIC, libvfio-user, controller or device-plugin source patches were used.

This validates discovery, allocation, injection and runtime setup. No RDMA
transfer, real GPU compute, GPU-direct DMA, SR-IOV or NIC fault injection was
performed in that single-node validation. Dashboard changes remain paused.
The separate [two-worker demo](../../demo/gpu-network/two-node/README.md) now
validates CPU-buffer payload transfer; it does not expand these earlier captures
to claim GPU-memory DMA.

## Later full-cluster validation

The subsequent [fresh deployment record](../../demo/gpu-network/single-node/fresh-deployment.md)
recreated both the Kind control plane and the default VM worker using the
published quick start, chart 0.2.12 and prepared artifact 0.1.0. Setup and the
combined GPU/NIC application verifier passed without local builds or manual
guest edits. The record links actual setup/application captures and explains
the observed startup waits. Earlier evidence above retains its original scope.

## Two-worker validation

The same prepared worker artifact 0.1.0 was used for two fresh workers with
published GPU chart 0.2.13 and mock image v0.2.7. The
[fresh-install capture](../../demo/gpu-network/two-node/fresh-install.log)
records successful GPU/NIC allocation, CPU-buffer SEND/RECV, RDMA WRITE WITH
IMMEDIATE, matching SHA-256 digests and deliberate corruption rejection.
That capture used the earlier two-namespace layout. The current
[captured demo run](../../demo/gpu-network/two-node/captured.log) verifies the
simplified one-namespace layout. See the demo's numbered architecture for the
execution order and precise proof boundaries.

The current layout also passed an uninterrupted [guest reboot check](../../demo/gpu-network/two-node/reboot-validation.log): both boot IDs changed, allocators recovered, and the complete allocation/payload/checksum suite passed again.
