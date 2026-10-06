# Automated validation

Release 0.2.2 targets Kubernetes 1.37. Use kind v0.33.0 or newer and kubectl
v1.37. Older kind versions can generate kubeadm APIs that Kubernetes 1.37
rejects before any GPU test runs.

## Contracts without a cluster

```bash
go test ./...
tests/dra/chart-validation.sh
tests/dra/discovery-check.sh
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

Partition tests cover the API's virtual state, not schedulable hardware
partitions. The API does not increase Kubernetes capacity when CPX is selected.
Fault tests use an explicit device-plugin restart; they do not promise
continuous device-health detection without rediscovery.

The `operator-e2e` smoke job separately tests the published SIM_ENABLE
controller, device-plugin and node-labeller readiness, eight-GPU capacity,
and one-GPU workload injection. It disables DME, KMM and NFD to isolate
Operator reconciliation and scheduling; it does not claim their validation.

These suites do not validate the real AMD metrics exporter,
full amd-smi CLI, CVS/RVS, node reboot/failure, or multi-node placement.
Those remain separate consumer-validation tasks. GPU computation is outside
the mock's control-plane scope.

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
Chart 0.2.3 exposes the dashboard while reusing the published 0.2.2 mock/node
images; the node image still runs Kubernetes 1.37.
