# Dashboard failure injection

The captured fault/telemetry evidence below is for the SPX whole-GPU setup.
Physical fault propagation across sibling partitions is outside the
[same-GPU allocation proof](../partition-allocation/README.md).

Open the mock dashboard and Grafana side by side. Use the buttons directly,
or run the equivalent actions:

```bash
python3 demo/run.py faults --gpu 0 --action overheat
python3 demo/run.py faults --gpu 0 --action recover
python3 demo/run.py faults --gpu 0 --action ecc-error
python3 demo/run.py faults --gpu 0 --action recover
python3 demo/run.py faults --gpu 0 --action busy
python3 demo/run.py faults --gpu 0 --action idle
python3 demo/run.py faults --gpu 0 --action crash
python3 demo/run.py faults --gpu 0 --action recover
```

Overheat and ECC buttons toggle; Recover explicitly resets healthy state.
Dashboard changes reach the same device state read by mock AMD SMI, real AMD
GPU Agent and real exporter. Grafana follows the collection/scrape interval.
Busy/idle also change activity, clocks, power and used VRAM.

Crash removes mock discovery bindings and host card/render nodes and zeroes
power/activity/clocks. It does not simulate an AMD SMI device-lost return or
kill an existing workload. DRA does not promise live health propagation or
claim revocation; device-plugin fault tests use explicit restart/rediscovery.
No automatic alert rules or remediation are installed. See the
[ASCII fault path](../../docs/architecture.md#dashboard-failures-two-paths-different-consequences).

## Recorded run output

Captured on 2026-10-06 using Kubernetes v1.37.0, chart 0.2.9 and the
ARM64 default Podman VM. Names, IDs and readings are specific to this run.
[Full captured output](captured.log); [capture sources and complete suites](../logs/README.md).

Selected lines from the actual capture (intermediate JSON fields omitted):

```text
  "status": "overheating",
  "temperature_c": 105,
  "ecc_errors": 0,
PASS presenter command: faults
PASS presenter overheat reaches Grafana
  "status": "healthy",
  "temperature_c": 49,
  "ecc_errors": 0,
PASS presenter command: faults
  "status": "ecc_error",
  "temperature_c": 49,
  "ecc_errors": 1,
PASS presenter command: faults
PASS presenter ECC reaches Grafana
  "status": "healthy",
  "temperature_c": 49,
  "ecc_errors": 0,
PASS presenter command: faults
PASS presenter recovery reaches Grafana
```

The ordered excerpts show overheating at 105 C, recovery, ECC count 1, then recovery to 0. The `PASS ... reaches Grafana` lines came from actual polling assertions in the presenter suite, not from the injection API response.

## Reading this run

The action prints the changed GPU JSON immediately. Then inspect the same GPU
through the [layer-by-layer evidence commands](../EVIDENCE.md): mock snapshot,
real exporter output, Prometheus value, and Grafana graph. Keep one controlled
state until the next collection/scrape; toggling and recovering immediately
may remove the condition before Prometheus samples it.

| Action | Immediate mock evidence | Downstream AMD metric to watch |
| --- | --- | --- |
| Overheat | `temperature_c: 105` | `amd_gpu_edge_temperature` reaches 105 |
| ECC | `ecc_errors` increases | `amd_gpu_ecc_uncorrect_total` increases |
| Busy | Activity/VRAM/power increase | `amd_gpu_gfx_activity`, `amd_gpu_used_vram`, `amd_gpu_package_power` |
| Idle | Low/background activity | Activity falls; simulated noise may remain |
| Crash | Status crashed, device nodes removed | Activity/power/clocks reach zero |
| Recover | Healthy defaults, ECC zero | ECC returns to zero and baseline readings resume |

An API response alone proves only injection into the mock. A matching change
at each stage establishes mocked AMD SMI -> real GPU Agent -> real exporter
-> Prometheus -> Grafana propagation. DRA is a separate allocation path,
not an intermediate telemetry stage. Recovery deliberately resets simulated
ECC counters; do not describe them as durable real-hardware counters.

```bash
kubectl -n amd-mock logs ds/amd-gpu-mock --tail=30
kubectl -n amd-mock logs ds/amd-gpu-mock-dra-kubeletplugin --tail=30
kubectl get pods -A
```

The mock log records actions such as `set BUSY` or `ECC ERROR`; it does not
prove scraping. Existing consumers need not exit on crash. A newly prepared
consumer can fail when its selected device node is absent, then retry after
recovery. That demonstrates a preparation failure, not automatic scheduler
health filtering. Read pod Events with `kubectl describe pod` to distinguish
these cases. Always finish with Recover before running other workloads.

See the [shared evidence checklist](../EVIDENCE.md) for commands, provenance,
and how to distinguish direct observations from inferred intermediate steps.
