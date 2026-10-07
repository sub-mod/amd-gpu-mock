# Multi-GPU and concurrent consumers

```bash
# One pod, two physical GPU card/render pairs.
python3 demo/run.py multi-gpu --count 2
kubectl -n amd-demo-multi-gpu get pods,resourceclaims
python3 demo/run.py cleanup

# Four independent pods, one physical GPU each.
python3 demo/run.py multi-gpu --count 1 --replicas 4
```

Both allocators are supported. Show each request's device nodes and, with
DRA, its claim allocation. Independent claims/requests consume separate
physical GPUs. The runner verifies the requested render-device count in each
consumer. It does not verify GPU execution or bandwidth scaling.

Cleanup before changing the count/replicas; existing pod resource requests
cannot be changed in place. Keep total requests within the free physical pool.

## Recorded run output

Captured on 2026-10-06 using Kubernetes v1.37.0, chart 0.2.9 and the
ARM64 default Podman VM. Names, IDs and readings are specific to this run.
[Full captured output](captured.log); [capture sources and complete suites](../logs/README.md).

Actual captured output:

```text
crw-r-----    1 root     root      234,   0 Oct  7 02:11 /dev/kfd

/dev/dri:
total 0
crw-r-----    1 root     root      226,   1 Oct  7 02:11 card1
crw-r-----    1 root     root      226,   2 Oct  7 02:11 card2
crw-r-----    1 root     root      226, 129 Oct  7 02:11 renderD129
crw-r-----    1 root     root      226, 130 Oct  7 02:11 renderD130

NAME                   STATE                AGE
consumer-0-gpu-wpk52   allocated,reserved   1s

Each independent request receives its own physical GPU allocation.
```

This container received card1/renderD129 and card2/renderD130: two distinct full GPUs. It did not receive two slices of one GPU.

## Reading this run

`--count 2` creates **one pod with one container and two distinct full GPUs**.
The container's listing must contain two render nodes; in DRA mode the claim
must contain two allocation results. The runner checks both results against
ResourceSlices and the injected nodes. This is not two containers sharing a
GPU, and it is not two hardware partitions of the same GPU.

`--count 1 --replicas 4` creates four independent pods with one GPU each. Look
for four different render devices across the logs. The runner rejects overlap
on the single-node demo cluster. Claim names differ from device names: compare
the allocation results, not only the number of claims.

```bash
kubectl -n amd-demo-multi-gpu logs consumer-0
kubectl -n amd-demo-multi-gpu exec consumer-0 -- ls -l /dev/kfd /dev/dri
kubectl -n amd-demo-multi-gpu get resourceclaims -o yaml
```

The log's `ls` output and checked allocation results demonstrate scheduler
accounting and device injection through the selected real AMD allocator.
They do not demonstrate distributed inference, collective communication,
performance scaling, independent hardware slices or memory isolation.

See the [shared evidence checklist](../EVIDENCE.md) for commands, provenance,
and how to distinguish direct observations from inferred intermediate steps.
