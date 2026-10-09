# Troubleshooting

Start with the resources that correspond to the failing layer:

```bash
kubectl get nodes
kubectl -n amd-mock get pods -o wide
kubectl get resourceslices
kubectl get resourceclaims -A
kubectl get events -A --sort-by=.lastTimestamp
```

A missing ResourceSlice points to mock or driver discovery. An unallocated claim
points to selectors, constraints or available capacity. An allocated claim with
a container creation error points to driver preparation or CDI injection.

| Symptom | Guide |
| --- | --- |
| Pending DRA workload or missing devices | [DRA troubleshooting](../guides/dra.md#limits-and-troubleshooting) |
| `amd.com/gpu` unavailable | [Device-plugin installation](../guides/device-plugin.md) |
| Dashboard or Grafana inaccessible | [Quick start](getting-started.md) and [telemetry](../guides/telemetry.md) |
| Partition workload cannot allocate | [Fixed partition topology](../guides/partition-allocation.md) |
| GPU agent fails opening `dev/kfd` after restart | Upgrade to chart **0.2.13** / mock image **v0.2.7**, which preserves existing mock character devices during rendering. |
| ERNIC VM or NIC discovery fails | [GPU/network guide](../guides/gpu-network.md) |

Fault controls change simulated management state. They do not promise automatic
DRA claim revocation, workload restart, or hardware recovery.
