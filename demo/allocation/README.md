# Allocation, deletion and reuse

For partition-specific exhaustion, exact sibling-preserving reuse and CDI
cleanup, use [same-GPU partition allocation](../partition-allocation/README.md).
The whole-GPU reuse capture below remains historical SPX evidence.

```bash
python3 demo/run.py allocation
```

The runner starts a one-GPU consumer, shows its devices, deletes it and waits
for generated DRA claim cleanup, then starts a second consumer. Both DRA and
the device plugin are supported. This shows capacity is reusable after release;
it does not promise selection of the same GPU while other capacity is free.

The second consumer remains available for inspection. For stronger full-pool,
same-GPU and explicit/shared-claim checks, use the
[DRA lifecycle tests](../../docs/guides/dra.md#tests-and-evidence).

## Recorded run output

Captured on 2026-10-06 using Kubernetes v1.37.0, chart 0.2.9 and the
ARM64 default Podman VM. Names, IDs and readings are specific to this run.
[Full captured output](captured.log); [capture sources and complete suites](../logs/README.md).

Actual captured output:

```text
crw-r-----    1 root     root      234,   0 Oct  7 02:11 /dev/kfd

/dev/dri:
total 0
crw-r-----    1 root     root      226,   3 Oct  7 02:11 card3
crw-r-----    1 root     root      226, 131 Oct  7 02:11 renderD131

NAME              STATE                AGE
first-gpu-mc85q   allocated,reserved   1s

Deleting first consumer; returning allocation to the pool...
crw-r-----    1 root     root      234,   0 Oct  7 02:11 /dev/kfd

/dev/dri:
total 0
crw-r-----    1 root     root      226,   3 Oct  7 02:11 card3
crw-r-----    1 root     root      226, 131 Oct  7 02:11 renderD131

NAME               STATE                AGE
second-gpu-8ctsj   allocated,reserved   1s

PASS: allocation works after release (not a promise of the same GPU).
```

Both consumers received card3/renderD131 in this run, with different claim names. The first was deleted before the second was created. Exact-device reuse happened in this capture but is not guaranteed when other devices are free.

## Reading this run

The first consumer prints its claim/device evidence. The runner deletes that
pod, waits for generated DRA claims to disappear, then creates `second` and
checks its devices. In device-plugin mode there is no generated claim to wait
for; successful scheduling of `second` is the observed reuse evidence.

```bash
kubectl -n amd-demo-allocation get pods,resourceclaims
kubectl -n amd-demo-allocation logs second
kubectl -n amd-demo-allocation get resourceclaims -o yaml
```

The final `PASS` means a new request works after deletion and cleanup.
Because other GPUs may be free, this demo alone does not prove that the exact
released GPU was selected or that the entire pool was exhausted. The lifecycle
tests linked above cover stronger cases. Claim garbage collection is visible
API evidence; kubelet unprepare and AMD driver's cleanup are intermediate
operations to inspect via the [shared evidence guide](../EVIDENCE.md).
The runner leaves `second` Running so you can inspect it.

See the [shared evidence checklist](../EVIDENCE.md) for commands, provenance,
and how to distinguish direct observations from inferred intermediate steps.
