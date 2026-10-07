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
