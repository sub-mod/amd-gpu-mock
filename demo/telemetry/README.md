# Real AMD telemetry and workload attribution

Grafana starts with the demo setup at http://localhost:3000, with the dashboard
**AMD GPU Fleet — Device Metrics Exporter** already provisioned.

```bash
python3 demo/run.py llm
python3 demo/run.py telemetry
```

Show temperature, power, activity, VRAM, clocks and ECC. The runner queries
AMD metrics through Grafana's Prometheus datasource. Its output includes
metric labels; find `pod`, `namespace` and `container` for allocated GPUs.
Then inject a fault from the [fault demo](../faults/README.md).

The stack uses real Prometheus and Grafana, and unmodified AMD GPU Agent /
exporter binaries. The mock is at AMD SMI's device API layer. AMD's x86
collector is explicitly emulated on ARM64. This is different from scraping
the node agent's separate diagnostic `/metrics` endpoint. See the
[telemetry guide](../../docs/guides/telemetry.md) for provenance and limits.

## What to watch and what the logs prove

The runner prints metrics obtained by calling Grafana's Prometheus datasource.
For each value, correlate `gpu_id` with the mock inventory and check the
optional `namespace/pod/container` label. These labels come from kubelet's
pod-resources association in the AMD exporter; DRA or the device plugin first
allocates the device. DRA does not transport the metric itself.

The query output proves that data is available through Grafana. To prove the
entire path, follow [EVIDENCE.md](../EVIDENCE.md), hold one injected condition,
and compare the mock snapshot, real exporter's endpoint and Prometheus.
Readings can differ slightly because dynamic simulation continues between
samples. ECC or fixed overheating is easier to correlate than changing activity.

Grafana refreshes every 5 seconds. Allow collection/scraping delay; reload an
already-open page after a dashboard upgrade. The default Grafana memory limit
is 1 GiB; inspect pod restarts and `lastState` if the UI stops updating.
A successfully rendered graph is not proof of real GPU execution or an alert
reaction. ARM64 runs AMD's unchanged x86 collector binaries through QEMU.

See the [shared evidence checklist](../EVIDENCE.md) for commands, provenance,
and how to distinguish direct observations from inferred intermediate steps.
