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

## Recorded run output

Captured on 2026-10-06 using Kubernetes v1.37.0, chart 0.2.9 and the
ARM64 default Podman VM. Names, IDs and readings are specific to this run.
[Full captured output](captured.log); [capture sources and complete suites](../logs/README.md).

Actual output excerpt:

```text
DEMO: Real AMD exporter metrics queried through the provisioned Grafana
Guide: demo/telemetry/README.md; inspect pods across namespaces with kubectl get pods -A
Dashboard: AMD GPU Fleet — Device Metrics Exporter
PATH: mocked AMD SMI -> real AMD GPU Agent -> real AMD exporter -> Prometheus -> Grafana
These queries prove Grafana datasource results; use the guide's snapshot/exporter checks
to correlate a controlled change across every layer. DRA is the allocation path, not a metric hop.
amd_gpu_edge_temperature
  GPU 5: 50
  GPU 2: 34  consumer=amd-demo-multi-gpu/consumer-0/consumer
  GPU 7: 56
  GPU 1: 36  consumer=amd-demo-multi-gpu/consumer-0/consumer
  GPU 3: 38  consumer=amd-demo-allocation/second/consumer
  GPU 6: 57  consumer=amd-demo-llm/tiny-llm-dra-demo-69b9bb8dfd-g9rb8/llm-service
  GPU 0: 44  consumer=amd-demo-dra/dra-gpu-demo/demo
  GPU 4: 41  consumer=default/tiny-llm-dra-demo-69b9bb8dfd-zt99m/llm-service
amd_gpu_ecc_uncorrect_total
  GPU 5: 0
  GPU 2: 0  consumer=amd-demo-multi-gpu/consumer-0/consumer
  GPU 7: 0
  GPU 1: 0  consumer=amd-demo-multi-gpu/consumer-0/consumer
  GPU 3: 0  consumer=amd-demo-allocation/second/consumer
  GPU 6: 0  consumer=amd-demo-llm/tiny-llm-dra-demo-69b9bb8dfd-g9rb8/llm-service
  GPU 0: 0  consumer=amd-demo-dra/dra-gpu-demo/demo
  GPU 4: 0  consumer=default/tiny-llm-dra-demo-69b9bb8dfd-zt99m/llm-service
```

The recorded Grafana datasource results associate GPUs 1 and 2 with the two-GPU consumer, GPU 0 with the DRA pod, and GPU 6 with the LLM pod. These are real exporter consumer labels attached to simulated device measurements.

## Reading this run

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
