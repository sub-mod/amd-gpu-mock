# GPU partitioning: virtual state versus physical allocation

```bash
python3 demo/run.py partitioning --mode CPX
# Show 64 virtual entries for eight MI300X physical GPUs.
python3 demo/run.py partitioning --mode DPX
python3 demo/run.py partitioning --mode QPX
python3 demo/run.py partitioning --mode SPX
```

Clean up GPU consumers before changing partition state. Show the division of
reported memory and the restoration to SPX. The allocator still has eight
physical GPUs; this API does not implement AMD hardware partitions, MxGPU,
SR-IOV or independent slice scheduling.

For four simultaneously scheduled physical GPU consumers:

```bash
python3 demo/run.py multi-gpu --count 1 --replicas 4
```

With the device plugin, [physical-workloads.yaml](physical-workloads.yaml)
is also available for the original two-service/four-replica presentation:

```bash
kubectl create namespace amd-demo-partitioning
kubectl label namespace amd-demo-partitioning amd-gpu-mock/demo=true
kubectl -n amd-demo-partitioning apply -f demo/partitioning/physical-workloads.yaml
kubectl -n amd-demo-partitioning get pods
```

Those replicas request full physical GPUs, not CPX partitions.

## Recorded run output

Captured on 2026-10-06 using Kubernetes v1.37.0, chart 0.2.9 and the
ARM64 default Podman VM. Names, IDs and readings are specific to this run.
[Full captured output](captured.log); [capture sources and complete suites](../logs/README.md).

Selected lines from the actual capture (intermediate JSON fields omitted):

```text
  "mode": "CPX",
  "partitions": 8,
  "total_gpus": 64
Virtual dashboard entries only; allocator capacity remains physical. Reset with --mode SPX.
PASS presenter command: partitioning
  "mode": "DPX",
  "partitions": 2,
  "total_gpus": 16
Virtual dashboard entries only; allocator capacity remains physical. Reset with --mode SPX.
  "mode": "QPX",
  "partitions": 4,
  "total_gpus": 32
Virtual dashboard entries only; allocator capacity remains physical. Reset with --mode SPX.
  "mode": "SPX",
  "partitions": 1,
  "total_gpus": 8
Virtual dashboard entries only; allocator capacity remains physical. Reset with --mode SPX.
```

CPX displayed 64 virtual entries, DPX 16, QPX 32, and SPX 8. This output records the display simulation, not independent DRA slice allocation.

## Reading this run

Compare the API's entry count and per-entry memory before/after the command.
For the default eight-GPU MI300X fleet, SPX/DPX/QPX/CPX displays 8/16/32/64
entries. These counts describe the mock dashboard's virtual layout only.

```bash
kubectl get resourceslices -o yaml
kubectl get nodes -o jsonpath='{range .items[*]}{.metadata.name}{" "}{.status.allocatable.amd\.com/gpu}{"\n"}{end}'
```

With DRA, inspect the actual advertised devices and their full-device capacity;
with the device plugin, inspect the physical resource count. The scheduler's
inventory does not become 64 independent GPUs when the dashboard shows CPX.
The command creates no workload pods and emits API JSON, not AMD driver
partition-management logs. It proves only virtual state/display handling.

A separate same-physical-GPU partition-allocation demo is planned, but is not
implemented here. That demo must prove separate partition discovery, claims,
container-specific device injection and partition release before being called
hardware-slice allocation. This display demo is not a substitute.

See the [shared evidence checklist](../EVIDENCE.md) for commands, provenance,
and how to distinguish direct observations from inferred intermediate steps.
