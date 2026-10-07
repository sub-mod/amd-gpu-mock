# AMD GPU mock demo room

Open this folder when presenting. Every demo uses published images and a
CPU-only kind cluster; no AMD source checkout, compiler or custom image build
is needed. The workload demos prove scheduling and device injection, not
GPU inference or hardware isolation.

## Start once

Requires kind v0.33.0+, kubectl, Helm, Python 3 and running Docker/Podman.

```bash
./demo/setup.sh
```

The default setup installs DRA, the mock node agent, the real AMD exporter,
Prometheus and a provisioned Grafana dashboard. Open:

- Mock dashboard: http://localhost:8080
- Grafana: http://localhost:3000 (`admin` / `amdmock`)

No port-forward processes are needed. These endpoints survive closing the
terminal while the container runtime and cluster keep running.

`demo/setup.sh` refuses to delete an existing cluster. Use `--skip-cluster`
to upgrade an existing compatible kind cluster, or `--teardown` explicitly.
`CONTAINER_RUNTIME=docker` or `CONTAINER_RUNTIME=podman` overrides runtime
autodetection.
An older cluster without the Grafana port mapping needs recreation to expose
Grafana on a host port. The built-in Prometheus and Grafana use ephemeral
storage; this is a local demonstration environment.

## One config for ports and enable switches

Edit [config.yaml](config.yaml) **before** creating the cluster:

```yaml
kind:
  mockDashboardPort: 8080  # Host port; change freely before cluster creation.
  grafanaPort: 3000

dashboard:
  enabled: true           # false removes mock dashboard host exposure.
  nodePort: 30080

monitoring:
  enabled: true           # false disables bundled Prometheus and Grafana.
  grafana:
    enabled: true         # false disables Grafana only.
    nodePort: 30300
    adminPassword: amdmock
```

Keep the other fields in the supplied config, including the allocator and
exporter settings. The setup script renders kind mappings and installs Helm
with the same values file. This avoids mapping one port while serving another.
The node agent's internal API still runs when its host dashboard is disabled.
Fault/partition/profile demos require that API's host exposure. DRA and workload
demos work without either dashboard.

```bash
cp demo/config.yaml /tmp/my-demo.yaml
# Edit /tmp/my-demo.yaml, then:
./demo/setup.sh --config /tmp/my-demo.yaml
python3 demo/run.py telemetry --config /tmp/my-demo.yaml
```

Use `CLUSTER_NAME=my-demo` for another cluster and `--context kind-my-demo`
with the demo runner. Use a separate `KUBECONFIG` if you want to keep your
current kubectl context untouched. `--skip-cluster` changes Helm workloads,
but cannot change existing kind host-port mappings.

For device-plugin demonstrations, edit both allocator flags:

```yaml
dra:
  enabled: false
devicePlugin:
  enabled: true
```

Delete demo consumers before switching allocator. Workload demos automatically
detect DRA versus device-plugin capacity. Do not enable both.

## Pick a demo

```bash
python3 demo/run.py list
```

| Folder | What to show | Command |
| --- | --- | --- |
| [llm](llm/README.md) | Tiny LLM scheduling and scripted output with one GPU | `python3 demo/run.py llm` |
| [partitioning](partitioning/README.md) | SPX/DPX/QPX/CPX virtual dashboard state | `python3 demo/run.py partitioning --mode CPX` |
| [dra](dra/README.md) | ResourceSlice, ResourceClaim allocation and CDI devices | `python3 demo/run.py dra` |
| [faults](faults/README.md) | Overheat, ECC, crash and recovery across real telemetry | `python3 demo/run.py faults --action overheat` |
| [multi-gpu](multi-gpu/README.md) | Two GPUs in one pod, or multiple independent consumers | `python3 demo/run.py multi-gpu --count 2` |
| [allocation](allocation/README.md) | Delete a consumer, observe release, allocate again | `python3 demo/run.py allocation` |
| [telemetry](telemetry/README.md) | Real AMD metrics and consumer labels in Grafana | `python3 demo/run.py telemetry` |
| [profiles](profiles/README.md) | Model catalog and physical GPU inventory | `python3 demo/run.py profiles` |

Run on a dedicated demonstration cluster. Workloads remain running so you can
inspect them; they consume GPUs until cleanup. Each demo uses a namespace
labelled `amd-gpu-mock/demo=true`, with names such as `amd-demo-llm`.

## Recorded output from real runs

Each demo guide includes actual captured output and a link to its full log.
See [the capture index](logs/README.md) for provenance and complete DRA and
device-plugin runs. These are recorded results, not invented sample output.
Print any recorded demo directly from the runner without changing the cluster:

```bash
python3 demo/run.py llm --show-captured
python3 demo/run.py multi-gpu --show-captured
python3 demo/run.py faults --show-captured
```

Omit `--show-captured` to execute the live demo.

## How to read the evidence

Every demo guide explains what to watch, how to read the logs, the layers
exercised, and the limits of the evidence. Start with [EVIDENCE.md](EVIDENCE.md)
for provenance, allocation/CDI checks and a controlled fault traced through
AMD SMI, the real GPU Agent/exporter, Prometheus and Grafana. Workload runners
print `EVIDENCE` and `PASS` only for the checks they actually perform.

Use `kubectl get pods -A` to see demo namespaces. Individual commands leave
workloads running; the automated presenter suite removes them. Several demos
only inspect or change state and create no pods.

## Suggested ten-minute presentation

1. Open both dashboards; point out eight physical MI300X devices.
2. Run the LLM demo and show the injected card/render nodes and scripted logs.
3. Run the DRA demo; show the allocated device names in its claim.
4. Open Grafana and show pod/namespace/container attribution.
5. Trigger Overheat or ECC; watch the mock dashboard change immediately and
   Grafana follow after collection/scraping. Recover GPU 0.
6. Clean up workloads before demonstrating virtual CPX state; reset to SPX.
7. Show multi-GPU allocation or allocation/release if the audience asks.

Faults do not automatically revoke claims, evict pods or restart workloads.
CPX entries are not independently schedulable hardware slices. Use the
[ASCII architecture diagrams](../docs/architecture.md) to explain these boundaries.

## Clean up

```bash
python3 demo/run.py cleanup
# Or remove the whole dedicated demo cluster:
./demo/setup.sh --teardown
```

Cleanup removes only demo-labelled namespaces, resets SPX and recovers the
mock GPUs when the host API is enabled. Supply the same `--config` and context
used during setup. It does not remove the Helm release unless the whole
cluster is deleted.

## Compatible published inputs

| Component | Version |
| --- | --- |
| Chart (default dashboards) | 0.2.11 |
| kind node / Kubernetes | 0.2.2 / v1.37.0 |
| Mock node-agent image | v0.2.4 |
| AMD exporter runtime | v1.5.2-mock.2 |

These versions are independent: changing chart configuration does not require
rebuilding an unchanged node image. The build pins are in
[`scripts/release.env`](../scripts/release.env). The setup uses those pins.

See [demo validation](../docs/guides/testing.md#presenter-demos-and-default-dashboards)
and [telemetry details](../docs/guides/telemetry.md) for tests and limitations.

## Same-GPU allocation

[Partition allocation](partition-allocation/README.md) uses the fixed DPX/NPS2
startup topology and proves two containers receive different slices of one
physical GPU. This is separate from the virtual partition display demo.
