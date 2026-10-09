# Scenarios

Choose a walkthrough for the component or workload you want to demonstrate.
Each uses the real Kubernetes allocation path over mocked hardware interfaces.
Run commands from the repository checkout; the linked demo pages include actual
captured logs, inspection commands and the boundaries of each proof.

## Prerequisites

Install kind v0.33.0+, kubectl, Helm and Docker or Podman. Complete the
[quick start](getting-started.md) for the default DRA scenarios. Device-plugin,
fixed-partition, GPU/network and Spur scenarios describe their additional setup.
Keep different allocator configurations in separate clusters.

## Component scenarios

| Scenario | Setup | Result |
| --- | --- | --- |
| [AMD device plugin](../guides/device-plugin.md) | Alternative allocator | A Pod requesting `amd.com/gpu` receives allocated devices |
| [AMD DRA](../guides/dra.md) | Default quick start | ResourceSlices, ResourceClaims, scheduler selection and CDI injection |
| [AMD GPU Operator](../guides/gpu-operator.md) | Operator guide | Tested Operator reconciliation and operand discovery |
| [GPU and NIC worker](../../demo/gpu-network/single-node/README.md) | Prepared ERNIC VM | One application receives a DRA GPU and device-plugin NIC |
| [Spur batch scheduling](../../demo/spur/README.md) | Separate device-plugin cluster | Queueing, GPU allocation, completion and resource reuse |

## Workload scenarios

| Scenario | Run | What to inspect |
| --- | --- | --- |
| [Tiny LLM](../../demo/llm/README.md) | `python3 demo/run.py llm` | Application logs and allocated devices; no real inference |
| [DRA allocation](../../demo/dra/README.md) | `python3 demo/run.py dra` | Claim status, advertised device and matching injected render node |
| [Multiple GPUs](../../demo/multi-gpu/README.md) | `python3 demo/run.py multi-gpu` | Distinct GPU allocations and per-container device visibility |
| [Same-GPU partitions](../../demo/partition-allocation/README.md) | `demo/partition-allocation/run.sh` | Two containers with different DPX/NPS2 slices of one physical parent |

## Related tasks

- [Allocation and release](../../demo/allocation/README.md): follow a claim through release and reuse.
- [Fault injection](../../demo/faults/README.md): trigger overheating, ECC errors and recovery.
- [Telemetry](../../demo/telemetry/README.md): follow state through AMD SMI, the exporter, Prometheus and Grafana.
- [Virtual partition controls](../../demo/partitioning/README.md): display-only partition changes.
- [GPU profiles](../../demo/profiles/README.md): inspect model inventory and topology.

The [two-worker RDMA scenario](../../demo/gpu-network/two-node/README.md) remains
in development. Do not present it as a validated cross-node payload transfer.
Use the [presenter guide](../../demo/README.md) for full presentation setup and cleanup.
