# HAMi sharing with the AMD GPU mock

HAMi is an optional allocator for the same mock node agent used by the default
DRA demo. Use the dedicated [HAMi demo](../../demo/hami/README.md); it creates its
own Kind cluster and kubeconfig. DRA and the ordinary AMD device plugin are
disabled in this cluster so only HAMi manages its GPUs.

The initial supported configuration is one simulated MI300X in SPX, 304 CUs,
192 GiB VRAM, and four advertised share slots, on Linux AMD64 or ARM64.
Chart `0.2.16` adds the bounded `gpu.count` inventory selection; the ordinary
quick start keeps its original eight-GPU inventory. The
host kernel must provide CUSE. On macOS, this means the container runtime's
Linux VM; macOS itself does not provide CUSE. Windows and OpenShift are outside
this demo's validation scope.

## Architecture and execution order

```text
(1) demo/hami/setup.sh creates a dedicated Kind node
                     |
(2) Published mock Helm chart: gpu.count=1, driverMock.enabled=true
    DRA=false, devicePlugin=false
                     |
(3) Main node agent: original MI300X profile + simulator + dashboard
         |                     |                      |
         v                     v                      v
    mock sysfs            AMD SMI state         CUSE KFD/card/render
         |                     |                      |
         +---- staged libdrm + AMD SMI libraries ------+
                               |
(4) Unchanged HAMi AMD plugin discovers 304 CUs / 192 GiB / one UUID
    -> node annotation + kubelet advertises four amd.com/gpu share slots
                               |
(5) HAMi webhook + scheduler admit two Pods requesting, each:
    amd.com/gpu=1, amd.com/gpucores=50, amd.com/gpumem=98304
                               |
(6) Kubelet -> HAMi Allocate -> same GPU device endpoints in both Pods
    distinct 152-CU masks + 98304m memory-limit settings + upstream hook
                               |
(7) Each consumer opens the allocated CUSE character devices and logs evidence
    Third Pod waits -> delete one consumer -> HAMi reuses released budget
                               |
(8) Dashboard crash -> main RAS state -> libdrm failure -> HAMi health pulse
    -> kubelet advertises zero healthy slots; recovery restores four
```

HAMi's real plugin, webhook and scheduler make allocation decisions. The setup
adapts upstream chart mounts, image references and environment to select the
mock libraries. It does not patch HAMi source or fabricate allocation annotations.
The main node agent owns all simulated inventory, state and device endpoints;
there is no external experiment provider, alternate renderer or RocJITsu daemon.
The hook is staged by a plugin init container, separately from the mock libraries.

## Run and inspect

```bash
./demo/hami/setup.sh
python3 -u demo/hami/verify.py
python3 -u tests/hami/lifecycle.py

kubectl --kubeconfig tmp/hami-main/kubeconfig -n amd-hami-demo get pods
kubectl --kubeconfig tmp/hami-main/kubeconfig -n amd-hami-demo logs right
```

Each workload requests a software share through HAMi's resources:

```yaml
resources:
  limits:
    amd.com/gpu: 1
    amd.com/gpucores: 50   # Percent of the physical GPU's CUs
    amd.com/gpumem: 98304 # MiB (96 GiB)
```

The mock dashboard starts at `http://localhost:8081`; Grafana starts at
`http://localhost:3001` (`admin` / `amdmock`). Ports differ from the default demo
so the clusters can coexist. Set `HAMI_DASHBOARD_PORT` and `HAMI_GRAFANA_PORT`
before setup to change them. `CONTAINER_RUNTIME=docker` or `podman` overrides
runtime detection. Setup refuses an existing `amd-hami-main` cluster.

No local compilation is required: setup pulls published images and fetches
pinned upstream chart sources. It stores its kubeconfig under `tmp/hami-main`
and leaves the default context unchanged. Keep this fixed one-GPU inventory
while HAMi consumers exist; switching dashboard profiles changes capacity and
is outside this sharing demo's lifecycle contract.

## What the checks establish

- Discovery: one physical UUID, 304 CUs, 196608 MiB VRAM and four share slots.
- Two consumers: same UUID, native character-device opens, disjoint 152-CU masks
  and 98304m memory-limit settings supplied by the actual HAMi Allocate response.
- Exhaustion/reuse: a third Pod stays unbound until a consumer releases budget.
- Plugin restart: the remaining consumer Pod UIDs survive and slots return.
- Dashboard crash/recovery: shared state flows through libdrm and HAMi health
  reporting to kubelet. Existing workloads are not claimed to be evicted.
- Agent restart: mounted directories survive SIGTERM, followed by Grafana checks
  against the real AMD exporter.

This demonstrates software sharing and configured limits, not physical GPU
partitions, GPU-memory enforcement, compute throttling or HIP execution. The
upstream HAMi hook is installed, but these inspection workloads do not exercise
its HIP allocation hooks. The kernel dmem backend is disabled. Use real AMD
hardware for compute/isolation claims. RocJITsu remains a separate experiment.

See [CUSE/library fidelity](driver-mock.md), [build recipes and pins](../../deployments/hami/README.md),
and [demo evidence](../../demo/hami/README.md#captured-validation).

## Cleanup

```bash
./demo/hami/cleanup.sh
```

Only the dedicated `amd-hami-main` release/cluster is removed. The default
quick-start cluster and the earlier experiment environment are left alone.
