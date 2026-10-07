# Automated validation

Release 0.2.2 targets Kubernetes 1.37. Use kind v0.33.0 or newer and kubectl
v1.37. Older kind versions can generate kubeadm APIs that Kubernetes 1.37
rejects before any GPU test runs.

## Contracts without a cluster

```bash
go test ./...
tests/dra/chart-validation.sh
tests/dra/discovery-check.sh
PARTITION_MODE=DPX tests/dra/discovery-check.sh mi300x
```

The Go tests compare all seven YAML profiles with rendered KFD names,
SIMD counts, GFX targets, vendor/device IDs, render minors, and memory sizes.
They verify the DMI UUID mount destination survives profile switches;
native AMD64 kind needs this path when a consumer mounts the mock over `/sys`.
They also exercise API fault/recovery operations and repeated MI300X
DPX/CPX/QPX/SPX transitions, checking unique identities, physical PCI
addresses, memory division, restoration, and rejection of invalid modes.

The chart tests reject configurations that enable two allocators, point at
the wrong sysfs root, or place the mock and driver on different nodes.
AMD's unchanged discovery package validates all seven profiles / 60 GPUs.

## Physical GPU device-plugin tests

On a dedicated single-node Kubernetes 1.37 cluster, install the mock chart
with its device plugin enabled and DRA disabled. Set the profile at install
time (`--set gpu.profile=mi250x`, for example), then run:

```bash
PROFILE=mi250x python3 tests/profile-e2e.py
```

The script requires kubectl and Python 3, creates an unused test namespace,
and deletes its workloads unless `KEEP=1` is set. It mutates GPU 0's mock
health and restarts the device plugin for explicit rediscovery. Run it only
on a dedicated test cluster without other GPU consumers.

Each profile checks:

1. API model, memory, physical identities, and exact allocatable count.
2. One-GPU scheduling and exactly one render character device in the consumer.
3. Full-pool exhaustion: an additional request remains pending.
4. Release: the pending consumer starts after capacity becomes available.
5. Crash: RAS state and driver bindings change; rediscovery reduces capacity.
6. Recovery: rediscovery restores capacity.
7. Overheat reaches the sysfs temperature sensor.
8. ECC injection and recovery reach the sysfs error counter.

`profile-e2e` runs these checks independently for MI210, MI250X, MI300A,
MI300X, MI325X, MI350X, and MI355X on native AMD64 GitHub runners. Each
profile gets a fresh cluster; the suite does not assume live profile changes
recreate device nodes. Failure artifacts include events, pod status,
allocatable resources, agent/device-plugin logs, and kind logs.

## DRA tests

See the [DRA guide](dra.md#tests-and-evidence). CI runs the basic and
lifecycle suites against both the source mock with AMD's official driver
and the published chart/images. These allocators run in separate clusters.

## Scope

The virtual-partition tests cover the dashboard API's display state. The
same-GPU allocation suite separately covers fixed MI300X DPX/NPS2 topology.
The API does not increase Kubernetes capacity when CPX is selected.
Fault tests use an explicit device-plugin restart; they do not promise
continuous device-health detection without rediscovery.

The `operator-e2e` smoke job separately tests the published SIM_ENABLE
controller, device-plugin and node-labeller readiness, eight-GPU capacity,
and one-GPU workload injection. It disables DME, KMM and NFD to isolate
Operator reconciliation and scheduling; it does not claim their validation.

The separate telemetry suite below validates the real AMD exporter. Full
amd-smi CLI, CVS/RVS, node reboot/failure and multi-node placement remain
separate consumer-validation tasks. GPU computation is outside the mock's
control-plane scope.

## Tiny LLM and virtual partition demos

On the default published quick start, run:

```bash
MODE=dra python3 tests/demo-e2e.py
```

For the alternative device-plugin installation (DRA disabled), run:

```bash
MODE=device-plugin python3 tests/demo-e2e.py
```

Run on a dedicated MI300X cluster with no other GPU consumers. The script
creates and deletes the named default-namespace demo deployments and restores
SPX mode. Both paths check one-GPU injection and scripted LLM output, then
DPX/CPX/QPX/SPX transitions, virtual identity/memory, and unchanged physical
allocator capacity. The device-plugin path also checks four simultaneous
replicas receive four distinct physical GPUs. DRA multi-GPU requests and
shared explicit claims are covered by the basic/lifecycle suites.

These demos execute scripted Python output; they do not download model weights
or perform LLM inference. Virtual partition entries are not independently
schedulable slices. AMD compute partitions and NVIDIA MIG hardware isolation
are not implemented by this mock.

## Automatic dashboard access

The quick-start kind configuration maps host port 8080 to the chart's
NodePort 30080. After Helm installation, no port-forward process is needed:

```bash
python3 tests/dashboard-e2e.py
```

This checks dashboard HTML, GPU identity/count, profile API, and metrics through
the host URL. Use `DASHBOARD_URL=http://127.0.0.1:9090` when testing a custom
kind host port. Change that mapping before creating the cluster; container
port mappings cannot be added to an existing kind node by a Helm upgrade.
The DRA and Operator CI jobs run this check with the same kind configuration.
Chart 0.2.11 uses mock image v0.2.6 and node image 0.2.2; the node image
still runs Kubernetes 1.37.

## Real AMD exporter telemetry

See the [telemetry guide](telemetry.md) for monitoring installation and ports.
With Prometheus on localhost:9090, Grafana on localhost:3000 and the mock
on localhost:8080:

```bash
./tests/telemetry/abi.sh # Podman; CONTAINER_RUNTIME=docker also supported
python3 tests/telemetry/e2e.py
ALLOCATOR=dra python3 tests/telemetry/attribution.py
# Or ALLOCATOR=device-plugin on that installation.
```

The ABI suite checks enumeration, buffers, units, ECC, graphics clocks,
unsupported APIs and concurrent readers. The live suite checks GPU identity,
VRAM units, ServiceMonitor health, every per-GPU dashboard action (Overheat,
Busy, Idle, Crash, Recover and ECC), and every Grafana panel query. It restores
GPU 0 after fault testing. Run on a dedicated cluster with GPU 0 healthy and
no concurrent fault actions. Healthy readings fluctuate under dynamic simulation.

The attribution suite creates and cleans up a GPU consumer and checks its
pod/namespace/container labels from the real kubelet pod-resources socket.
`telemetry-e2e` CI covers AMD64 and ARM64 runners with both allocators and
repeats telemetry tests after exporter restart. ARM64 runs AMD's unchanged
x86 collector under QEMU; the surrounding cluster and node agent run natively.
Local validation passed on ARM64 Podman; CI results are the evidence for the
native AMD64 path. The tests invoke dashboard endpoints, not browser clicks.

## Presenter demos and default dashboards

`demo/` contains runnable LLM, DRA, virtual partitioning, fault injection,
multi-GPU, allocation/release, telemetry, profile and fixed same-GPU partition
presentations. See its
[presenter guide](../../demo/README.md). Chart 0.2.11 installs built-in
Prometheus/Grafana and the real exporter by default; the shared kind config
exposes Grafana at localhost:3000 and the mock dashboard at localhost:8080.

```bash
tests/demo/chart-validation.sh
python3 tests/demo/grafana-e2e.py
```

The chart checks cover default/custom host ports, both dashboard switches,
external-monitoring mode, invalid configuration rejection, and consistency
between demo manifests and existing tested assets. The Grafana check verifies
host access without forwarding, dashboard provisioning, real AMD GPU count
and every panel query. The published DRA CI path runs it from a fresh cluster.

`demo-e2e` CI runs the new presenter scripts on fresh published-image clusters
with both allocators. It covers the LLM, multi-GPU consumers, claim release,
fault recovery and Grafana, and verifies disabling/re-enabling both dashboards.
Do not run competing fault-injection suites simultaneously. The demos leave
workloads for inspection; `demo/run.py cleanup` removes labelled namespaces.

## Same-GPU partition allocation tests

On a dedicated fixed MI300X DPX/NPS2 cluster, run:

```bash
python3 tests/dra/partition-allocation.py
```

The `same-gpu-partition-allocation` workflow runs source and published-image
paths. It checks sixteen partition devices across eight parents, capacities,
same-parent allocations, per-container device visibility, exhaustion, CDI
cleanup, released-device reuse, sibling continuity, and driver pod replacement.
The final two-container pod remains Running; delete its namespace explicitly.
See the [allocation guide](partition-allocation.md) and
[captured presentation](../../demo/partition-allocation/README.md).

The low-level discovery script passes the selected mode explicitly into the
probe inside its private mount namespace, including the Linux `sudo` fallback.
Rendering and comparison therefore use the same partition configuration.
This suite proves allocation/injection through real layers, not hardware
compute or memory isolation. Per-partition exporter attribution and physical
fault propagation remain outside this allocation test.
