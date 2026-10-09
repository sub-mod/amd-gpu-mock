# Two-node RDMA payload transfer

Two dedicated Ubuntu VM workers each receive a simulated AMD MI300X GPU through
DRA and an emulated Pensando NIC through the AMD Network Operator's NIC device
plugin. Two application Pods exchange randomized CPU-buffer payloads using
libibverbs. The receiver computes SHA-256 over the received bytes.

This is separate from the [single-node demo](../single-node/README.md). It does
not require an LLM framework: each Pod keeps the existing scripted Tiny LLM HTTP
app running for inspection, while the transfer executable proves the RDMA path.
No GPU computation or GPU-direct DMA is involved.

## Architecture and sequence

```text
[1] README quick start: Kind API + scheduler + published GPU Helm chart
                          |
[2] setup.sh starts two ERNIC labs and QEMU guests, then joins both workers
    Lab A: TCP manager <--------- ERNIC mesh ---------> Lab B: TCP worker
              | VFIO-user                                  | VFIO-user
              v                                            v
    Worker amd-ernic-rdma-a                       Worker amd-ernic-rdma-b
    ionic + ionic_rdma kernel drivers             ionic + ionic_rdma drivers
              |                                            |
[3] Discovery on EACH worker (may run concurrently):
    GPU mock sysfs -> AMD DRA -> ResourceSlices (available GPUs)
    ERNIC PCI -> NFD -> Network Operator -> NIC plugin -> amd.com/nic: 1
                          |
[4] run.sh waits for Nodes, allocator DaemonSets and NIC advertisement
    Creates ONE namespace: amd-demo-rdma
    tiny-llm-rdma-a -> worker A     tiny-llm-rdma-b -> worker B
    Each Pod requests its own GPU claim + amd.com/nic: 1
                          |
[5] Scheduler places Pods and allocates GPU claims; kubelet prepares devices
    AMD DRA NodePrepare -> GPU CDI edits -> /dev/kfd + allocated render node
    NIC plugin Allocate -> PCI metadata + /dev/infiniband device mappings
    containerd starts both Pods; allocation verifier + HTTP preflight pass
                          |
[6] Sender B <--- TCP: QP metadata, hashes and synchronization ---> Receiver A
    (This control connection does not carry the randomized payload.)
                          |
[7] Sender B registered CPU memory -> libibverbs/ionic -> emulated PCI NIC B
    -> ERNIC TCP mesh -> emulated PCI NIC A -> receiver registered CPU memory
    SEND/RECV, then RDMA WRITE WITH IMMEDIATE; check completion + SHA-256
                          |
[8] Repeat with deliberate receiver byte corruption -> checksum must reject
    Logs retained; both Tiny LLM simulation Pods remain running for inspection
```

Numbers describe dependencies, not an exact serial order of all controller Pods.
The NIC becomes visible to the guest at step 2, advertised to Kubernetes at
step 3, requested at step 4, and prepared for the container at step 5.
No payload transfer is claimed until step 7 succeeds. GPU allocation is checked
alongside the transfer; the GPU mock does not back the registered CPU buffers.


Each worker retains the default eight-GPU MI300X mock profile; each demo Pod
requests one GPU. Each worker has one emulated Pensando NIC with one RDMA port, plus a separate
virtio SSH management NIC. The emulated NIC also carries its Kubernetes network
connection. The Pods use host networking, not isolated secondary networks.

## Set up and run

Prerequisites are the [single-node setup requirements](../single-node/README.md#set-up-and-run)
and an existing README quick-start Kind cluster with its GPU Helm release.
Use chart **0.2.13** or later (mock image **v0.2.7**): it fixes agent restart
when mock character devices remain from an earlier process. The current implementation is ARM64/Podman. The machine must have at least
16 GiB RAM. The pair uses 6 GiB of guest RAM plus QEMU, ERNIC, control-plane and
telemetry overhead, and eight virtual CPUs. Use these two workers without other
ERNIC workers running; setup checks both lab containers and demo node registrations.
When transitioning from the single-node demo, remove its worker first:

```bash
./scripts/ernic/cleanup.sh
```

This removes its application/node/container and keeps Kind, Podman and cached
state. Merely stopping the container leaves an unavailable Kubernetes node that
can block Helm readiness. The initial attempt to retain three ERNIC workers on
the 16 GiB VM exhausted memory; that failed attempt is recorded in the notes.

```bash
./demo/gpu-network/two-node/setup.sh
./demo/gpu-network/two-node/run.sh
```

Setup creates dedicated containers/nodes `amd-ernic-rdma-a` and
`amd-ernic-rdma-b`, using state directories `tmp/ernic-rdma-a` and
`tmp/ernic-rdma-b`. SSH management ports are 2232 and 2233. It preserves the
Kind control plane and Podman machine; it replaces the single-node presentation
when that worker has been cleaned up. Both use the existing published
worker/lab images; no guest package installation or user image build is needed.
The runner pulls the published [RDMA application image](image/README.md).

The first ERNIC instance listens on its Podman network address at TCP port 6320;
the second connects to it. Setup advertises each guest's MAC-derived link-local
GID and IPv4-mapped GID through upstream `ERNIC_TCP_GUEST_GIDS`. Nothing is added
to a guest kernel/provider to make the mesh work. The application manually
exchanges queue-pair metadata because guest-to-guest `rdma_cm`/`rping` is not
supported by the pinned ERNIC revision. See the upstream
[ionic status](https://github.com/ROCm/rocm-ernic/blob/21f40e79c7f208d6e6013fac3c57f61b840db9ac/docs/ionic.rst)
and [TCP mesh/GID configuration](https://github.com/ROCm/rocm-ernic/blob/21f40e79c7f208d6e6013fac3c57f61b840db9ac/docs/service.rst).

The runner creates one GPU/NIC-consuming Pod per worker and runs the existing
allocation verifier on both. It then transfers a fresh random 64 KiB payload
with SEND/RECV and another with RDMA WRITE WITH IMMEDIATE. Both sides must
report successful completions and matching hashes. Next it deliberately corrupts
a received byte: both transfer processes must fail, and the runner must identify
the receiver checksum failure. An unrelated startup failure cannot pass this
negative check.

## What to inspect

```bash
kubectl get nodes
kubectl -n kube-amd-network get networkconfig,daemonsets,pods
kubectl -n amd-demo-rdma get pods,resourceclaims -o wide
kubectl -n amd-demo-rdma logs tiny-llm-rdma-a
kubectl -n amd-demo-rdma logs tiny-llm-rdma-b
```

`run.sh` dumps allocation/HTTP evidence and the transfer logs. Transfer subprocess
output is also saved under `tmp/rdma-demo/run/` (override with `RDMA_LOG_DIR`).
The HTTP app logs show the allocated devices; transfer logs show the separate
verbs executable. `ROLE`, `NODE`, `NIC`, `RDMA_DEVICE` and `QP_METADATA` identify
endpoints. `SENT_SHA256`/`RECEIVED_SHA256` and `PAYLOAD_PASS` establish byte
correctness, beyond merely observing completion events or interface counters.

The CPU-buffer payload goes through the guest's ionic verbs provider and kernel
interface, the emulated PCI NIC, and ERNIC's TCP mesh to the other guest's
registered memory. The underlying mesh is TCP software transport; throughput
under QEMU TCG is not a physical RDMA benchmark. Mock GPU allocation is verified
alongside the transfer; it is not part of its memory path.

## Check recovery after a guest reboot

With both demo workers running:

```bash
./demo/gpu-network/two-node/reboot-check.sh
```

This deliberately interrupts both applications. It reboots only the two QEMU
worker guests through their separate virtio management NICs, verifies changed
Kubernetes boot IDs and Ready status, then repeats allocation, SEND/RECV, RDMA
WRITE and corruption rejection. Each worker has a bounded ten-minute recovery
wait under TCG. It preserves Kind and the Podman machine. Logs default to
`tmp/rdma-demo/reboot-run/`.

## Cleanup

```bash
./demo/gpu-network/two-node/run.sh --cleanup  # only the application Pods/claims
./demo/gpu-network/two-node/cleanup.sh       # both dedicated workers as well
```

Cleanup releases both applications and drains both nodes before stopping either
emulator peer. This ordering matters: the NIC also carries Kubernetes traffic,
and peer teardown was observed to terminate the other ERNIC process in the
pinned revision. Cleanup preserves Kind, Podman and cached worker state.
Re-running setup reconciles Helm without replacing a joined worker's disk.
Changing an existing worker's ERNIC backend requires removing that worker first;
setup refuses to silently treat a loopback worker as a TCP-mesh worker.

## Recorded validation

The single-namespace demo passed both allocation checks, randomized
SEND/RECV, RDMA WRITE WITH IMMEDIATE, and deliberate corruption rejection.
See [the complete run](captured.log) and the [individual transfer logs](logs/positive-receiver.log).
The positive receiver log contains real completion events and matching hashes:

```text
PAYLOAD_PASS operation=SEND_RECV bytes=65536
PAYLOAD_PASS operation=RDMA_WRITE_WITH_IMM bytes=65536
TRANSFER_PASS role=receiver node=amd-ernic-rdma-a payload_path=libibverbs/ionic/ERNIC_TCP_mesh
```

The [negative receiver log](logs/corruption-receiver.log) records unequal expected
and received hashes followed by `operation=match` failure. The runner requires
that specific checksum failure; timeouts or allocation errors cannot satisfy it.
The `No RDMA transfer ... was tested` line earlier in the complete log belongs
to each allocation-only preflight. The transfer results follow both preflights.

A [fresh installation](fresh-install.log) passed using the earlier two-namespace
layout. The current single-namespace layout then passed both the complete
[demo run](captured.log) and an uninterrupted
[guest reboot check](reboot-validation.log). The reboot check confirmed changed
boot IDs for both guests, waited for GPU/DRA/NIC allocator readiness, recreated
terminal application Pods when needed, and repeated both allocation checks,
SEND/RECV, RDMA WRITE WITH IMMEDIATE and deliberate corruption rejection.
The initial post-reboot readiness race was corrected by waiting for allocator
DaemonSets and NIC advertisement after Node Ready. These results cover CPU
registered memory alongside DRA-allocated mock GPUs, not GPU-memory DMA.

Both worker Pods share the `amd-demo-rdma` namespace. Distinct Pod names and node selectors separate the allocations; separate namespaces are not required for RDMA. The script also removes the previous two-namespace demo layout before allocating NICs.
