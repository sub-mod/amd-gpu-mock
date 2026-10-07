# Allocation, deletion and reuse

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

## What to watch and what the logs prove

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
