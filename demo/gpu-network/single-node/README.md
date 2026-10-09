# Single node: Tiny LLM with a GPU and NIC

One VM worker has mock MI300X GPUs and an emulated Pensando NIC. The same
Tiny LLM container requests one GPU through Kubernetes Dynamic Resource Allocation (DRA), using the AMD DRA driver,
and one `amd.com/nic` through the NIC device plugin deployed by AMD Network Operator. It returns a scripted HTTP response, prints
its allocated devices, and stays running for inspection.

## Architecture

The application runs on the VM worker, not on the Kind control plane. The NIC
belongs to the worker, alongside its simulated GPUs. GPU allocation uses DRA;
NIC allocation uses the Kubernetes device-plugin API.

```text
Default Podman Linux VM
|
+-- Kind control plane
|   +-- API + scheduler
|   +-- AMD Network Operator controller
|            | deploys/reconciles NIC device plugin on worker
|            v
+-- ERNIC lab container
    +-- rocm-ernic <-- VFIO-user socket --> QEMU VM worker
        emulated NIC                       |
                                           +-- ionic + ionic_rdma kernel drivers
                                           |   +-- NFD discovers PCI NIC
                                           |   +-- NIC plugin -> amd.com/nic: 1
                                           |
                                           +-- GPU mock agent -> mock MI300X sysfs
                                           |   +-- AMD DRA -> GPU ResourceSlices
                                           |
                                           +-- kubelet + containerd
                                               +-- Tiny LLM application Pod
                                                   GPU ResourceClaim -> CDI devices
                                                   amd.com/nic: 1 -> RDMA devices
                                                   HTTP -> scripted text + evidence
```

The scheduler places the Pod on the selected worker when both resources are
available. The container sees `/dev/kfd`, one `/dev/dri/renderD*`, RDMA device
nodes and NIC allocation metadata. It uses `hostNetwork: true`, sharing the
worker network; allocation does not create an isolated or secondary network.
The HTTP response demonstrates application availability and allocation evidence,
not GPU computation or RDMA data transfer. See the
[integration guide](../../../docs/guides/gpu-network.md) for the detailed flows.

## Set up and run

On an Apple-silicon Mac with a running Podman VM, kind, kubectl, Helm,
Python3, SSH and curl, run from the repository root:

```bash
./demo/setup.sh --ernic
./demo/gpu-network/single-node/run.sh
```

For an existing README quick-start cluster:

```bash
./scripts/ernic/setup.sh
./demo/gpu-network/single-node/run.sh
```

Setup pulls published images; no compiler, custom kernel build, or user image
build is required. It pulls a prepared Ubuntu ARM64 worker disk and adds a real
VM worker to the existing Kind control plane. It preserves the default Podman
machine. First boot and image pulls take several minutes under QEMU TCG.
See [the integration guide](../../../docs/guides/gpu-network.md) for pins,
configuration changes, log locations, and maintainer image builds. The
[worker artifact](../../../artifacts/ernic-worker/README.md) documents the disk
contents and rebuild process.

The allocation check Pod from earlier ERNIC experiments must release the NIC
before this demo can run. If you created that specific check Pod, delete it
with `kubectl delete pod ernic-allocated`. The demo never deletes unrelated
NIC consumers; a busy NIC correctly leaves it Pending.

## How setup applies Helm updates

Setup uses published, pinned inputs, rather than automatically selecting the
newest registry version or installing local chart edits.

| Entry point | Helm behavior |
| --- | --- |
| `./demo/setup.sh --ernic` | Installs/upgrades `amd-gpu-mock` from the published OCI chart, using `CHART_VERSION` in `scripts/release.env` (currently `0.2.12`). Resets values to chart defaults plus `demo/config.yaml`, then runs ERNIC setup. |
| `./scripts/ernic/setup.sh` | Requires an existing cluster and GPU Helm release. Installs/upgrades `amd-network`, then upgrades `amd-gpu-mock` to the pinned published chart with the ERNIC worker selectors, DRA enabled and GPU device plugin disabled. |
| Re-running ERNIC setup with an already joined worker | Repeats both Helm reconciliation steps without replacing the worker disk. |

For an existing demo cluster, use `./demo/setup.sh --skip-cluster --ernic` if
you want to reapply `demo/config.yaml` as well. That full setup resets prior
Helm values. The narrower ERNIC GPU upgrade uses `--reuse-values`, preserving
existing settings except the selectors and allocator settings it explicitly
changes. Its chart version includes the exporter readiness timeout fix.

The network release uses a chart copied from the pinned upstream source revision
in `scripts/ernic/versions.env`, with one device-plugin ConfigMap template override.
The operator and NIC plugin images are pinned there too. Updating only the local
GPU chart source does not change what setup installs: maintainers must publish
that chart version and update the release pin. Re-running setup reconciles
Kubernetes components; it does not rebuild or replace an existing VM image.

## What the audience sees

```bash
kubectl -n amd-demo-gpu-network get pods,resourceclaims
kubectl -n kube-amd-network get networkconfig,daemonsets
kubectl -n amd-demo-gpu-network logs tiny-llm-gpu-network
python3 demo/gpu-network/single-node/verify.py
```

`run.sh` dumps the actual application logs, sends an HTTP `/generate` request,
and prints the allocation evidence. You should see one Running Pod on
`amd-ernic-worker-1`, one allocated ResourceClaim from that worker's GPU pool,
and one operator-managed NIC resource. The output includes:

- `/dev/kfd` and exactly one `/dev/dri/renderD*` character device.
- `/dev/infiniband/uverbs0` and `/dev/infiniband/rdma_cm`.
- `PCIDEVICE_AMD_COM_NIC` and its discovered RDMA device metadata (`ionic_0` or a predictable
  name such as `rocep0s4`).
- The scripted text response with `simulation: true` and the worker name.

The verifier compares the claim's GPU identity with the injected render-device
minor and the matching advertised ResourceSlice. It also checks that the Pod
requests a NIC, runs on the selected worker, and reports the allocated NIC
metadata. A missing device or mismatched claim makes the demo fail.

The service is `tiny-llm.amd-demo-gpu-network.svc:8000`. The app listens on the
worker network because this initial demo uses `hostNetwork: true`. No new
secondary network attachment or port-forward is needed by the runner.
Grafana remains at localhost3000 (`admin` / `amdmock`); filter GPU metrics by
the worker/node and consumer namespace. NIC metrics are not part of this demo.

## What it proves

Real NFD discovery of an emulated PCI NIC -> Network Operator reconciliation
-> device-plugin/kubelet NIC allocation, alongside upstream AMD DRA discovery
of mock GPU sysfs -> ResourceClaim allocation -> CDI GPU injection. The
application sees both devices on the same worker and serves an HTTP response.

The text is scripted: no weights are loaded and no GPU inference is executed.
There is no RDMA transfer test, distributed inference, GPU-direct DMA, or
claim of NIC traffic isolation. Kubernetes allocation is exclusive, but the
host-network Pod shares the worker's network namespace.

## Captured run

[captured.log](captured.log) contains actual output from the 2026-10-08 run,
including the response, claim, ResourceSlice and injected GPU/NIC identities.
The final clean-worker evidence is:

| Check | Actual output |
| --- | --- |
| Published artifact, fresh disk, automatic worker setup | [clean-install.log](clean-install.log) |
| GPU/NIC allocation and HTTP response | [clean-demo.log](clean-demo.log) |
| Published chart 0.2.12 readiness correction | [published-chart-upgrade.log](published-chart-upgrade.log) |
| Allocation verified after chart upgrade | [published-chart-demo.log](published-chart-demo.log) |
| Actual metrics and cgroup enforcement | [runtime-checks.log](runtime-checks.log) |

The clean VM was initially validated with chart 0.2.11, then upgraded to published
0.2.12 to correct the exporter readiness timeout under TCG. Historical logs
retain their actual versions. [prepared-worker.log](prepared-worker.log) records
the earlier prepared-worker allocation check.

Names and UUIDs vary on another run. [provenance.json](provenance.json) records
image and source inputs. No example output is presented as a measured result.

## Cleanup and overrides

```bash
./demo/gpu-network/single-node/run.sh --cleanup  # remove only this workload
./scripts/ernic/cleanup.sh                     # remove the dedicated worker
```

The worker cleanup preserves cached VM disks/downloads and the Podman VM.
`KUBE_CONTEXT`, `ERNIC_NODE`, and `DEMO_NAMESPACE` select another deployment.
Provisioning also accepts `ERNIC_CONTAINER`, `ERNIC_SSH_PORT`,
`ERNIC_STATE_DIR`, and `ERNIC_CONTROL_PLANE`. Use separate values for a separate
lab. These scripts do not create a second Kubernetes control plane.
