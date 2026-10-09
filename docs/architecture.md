# Architecture

The mock supplies device contracts read by AMD software. It does not execute
HIP kernels, emulate GPU memory or implement KFD ioctls.

## System overview

```text
 HOST: Docker / Podman Linux VM
 +-----------------------------------------------------------------------------------------+
 | KIND NODE: Kubernetes 1.37 / containerd / AMD container runtime / CDI                   |
 |                                                                                         |
 |  Profile YAML -----+                  Browser: http://localhost:8080                    |
 |                    |                              |                                     |
 |                    v                              | dashboard actions + state polling   |
 |            +----------------------+               v                                     |
 |            | Mock node agent      |<--- NodePort 30080 <--- kind host-port mapping      |
 |            | API + runtime state  |                                                     |
 |            | dynamic simulator    |                                                     |
 |            +----------------------+                                                     |
 |                    | renders / synchronizes                                             |
 |          +---------+---------------------------+                                        |
 |          v                                     v                                        |
 |  +--------------------------+          +----------------------------+                   |
 |  | Mock device surfaces     |          | Atomic SMI device state    |                   |
 |  | KFD / PCI / DRM sysfs    |          | /var/lib/amd-gpu-mock/smi  |                   |
 |  | driver bindings + RAS    |          | per-GPU sensor snapshots   |                   |
 |  | /dev/kfd + card/render   |          +----------------------------+                   |
 |  +--------------------------+                      | read through vendor ABI            |
 |          | discovery                                v                                   |
 |          v                             +----------------------------+                   |
 |  +--------------------------+          | Mock libamd_smi.so.27      |                   |
 |  | AMD DRA driver (default) |          | identity / sensors / ECC   |                   |
 |  | publishes ResourceSlices |          +----------------------------+                   |
 |  | prepares/unprepares CDI  |                       | AMD SMI results                   |
 |  +--------------------------+                       v                                   |
 |          |                             +----------------------------+                   |
 |          | Kubernetes API              | Real AMD GPU Agent         |                   |
 |          v                             +----------------------------+                   |
 |  +--------------------------+                       | GPU Agent RPC                     |
 |  | API server               |                       v                                   |
 |  | Pods / claims / slices   |          +----------------------------+                   |
 |  +--------------------------+          | Real AMD metrics exporter  |                   |
 |       ^               |                +----------------------------+                   |
 |       | reads/writes  | bound Pod                    ^                  | /metrics      |
 |  +-----------+        v                             |                  v                |
 |  | Scheduler |  +-----------+   real pod-resources --+          +------------+          |
 |  | DRA plugin|  | Kubelet   |                                  | Prometheus |           |
 |  +-----------+  +-----------+                                  +------------+           |
 |                       | prepare claim via DRA driver                  | queries         |
 |                       v                                              v                  |
 |                +-------------------------+                     +------------+           |
 |                | containerd + AMD runtime |                     | Grafana    |          |
 |                | inject allocated nodes  |                     +------------+           |
 |                +-------------------------+                                              |
 |                       |                                                                 |
 |                       v                                                                 |
 |                +-------------------------+                                              |
 |                | Workload container      |                                              |
 |                | /dev/kfd + selected GPU |                                              |
 |                | no GPU compute backend  |                                              |
 |                +-------------------------+                                              |
 +-----------------------------------------------------------------------------------------+

 ALTERNATIVE ALLOCATOR (instead of DRA):
   Mock sysfs --> AMD device plugin --> kubelet device manager
                         |                       |
                         | capacity/health       +--> Allocate --> device injection
                         v
                    Node amd.com/gpu --> scheduler --> bound workload

 OPTIONAL OPERATOR SMOKE (both bundled allocators disabled):
   SIM_ENABLE controller --> its device plugin + node labeller --> mock sysfs
   Operator-owned DRA / exporter / remediation are not validated by this smoke.
```

The diagram shows data and control flow, not network isolation. API objects
live in Kubernetes; the scheduler reads and updates them. Allocation details
and the fault boundary are expanded below. Bundled Prometheus uses DNS endpoint discovery; the optional external stack
uses a ServiceMonitor. Grafana's provisioned dashboard queries the real AMD metrics.

DRA and the device plugin are mutually exclusive. Telemetry works alongside
either allocator and reads kubelet's real pod-resources socket for workload
labels. The optional Operator smoke path uses its own device plugin and node
labeller; disable both bundled allocators before using it.

## DRA: discovery, scheduling and workload lifetime

```text
 DISCOVERY                      SCHEDULING / ALLOCATION              EXECUTION SETUP

 Profile YAML
      |
      v
 Mock sysfs --> AMD DRA driver --> ResourceSlices -----+
                                                      |
 Pod + ResourceClaimTemplate                          v
      |                                  +-------------------------+
      +--> generated ResourceClaim ----->| Kubernetes scheduler     |
                                         | DRA allocation logic    |
                                         | match class + selectors |
                                         | choose devices + node   |
                                         +-------------------------+
                                                      |
                              +-----------------------+--------------------+
                              v                                            v
                    Claim allocation in API                       Pod bound to node
                              |                                            |
                              +-----------------------+--------------------+
                                                      v
                                                  Kubelet
                                                      |
                                            prepare allocated claim
                                                      v
                                               AMD DRA driver
                                                      |
                                    write per-claim CDI spec on host
                                    return allocated CDI device IDs
                                                      v
                                         containerd + AMD runtime
                                                      |
                                      inject shared /dev/kfd plus
                                      allocated cardN / renderDN
                                                      v
                                             Workload container
                                             (scripted Tiny LLM,
                                              scheduling tests)
                                                      |
                                               delete consumer
                                                      v
                           kubelet --> DRA unprepare --> remove claim CDI spec
                                         |
                                         +--> release/deallocation + claim lifecycle
                                              --> GPU reusable by another request
```

The scheduler acts on advertised devices and claim requests, not dashboard
telemetry. A generated claim follows its pod's lifetime; an explicit claim
can remain after its consumers leave. Shared explicit claims and restart
checkpoint behavior are covered in the [DRA lifecycle guide](guides/dra.md#release-explicit-claims-and-driver-restarts).
A prepared container has device nodes, but no real GPU execution backend.

## Dashboard failures: two paths, different consequences

```text
 USER: Overheat / ECC Error / Crash / Busy / Idle / Recover
                              |
                              | POST /api/actions/<action>?gpu=N
                              v
                    +-------------------------+
                    | Node-agent runtime state|
                    +-------------------------+
                              |
                +-------------+----------------------------+
                |                                          |
                v                                          v
      DEVICE / DISCOVERY PATH                     SENSOR / TELEMETRY PATH
      mock sysfs + host devices                   atomic per-GPU SMI snapshot
                |                                          |
                | crash: remove driver binding             | temperature / power /
                |        and card/render nodes             | activity / VRAM / ECC
                | ECC: update RAS counters                 v
                | overheat: update hwmon           mock AMD SMI ABI 27
                | recover: restore surfaces                |
                v                                          v
      AMD discovery consumers                      real AMD GPU Agent
                |                                          |
                | explicit rediscovery                     v
                | required by tested paths         real AMD metrics exporter
                v                                          |
      device plugin: reduced/restored capacity             v
      after restart in profile fault tests          Prometheus --> Grafana
                |                                          |
                v                                          +--> visible readings
      kubelet --> Node capacity --> scheduler               +--> workload labels via
      affects NEW scheduling decisions                          kubelet pod-resources

      DRA: no tested live device-health / hot-plug propagation
       X--> automatic ResourceSlice health update
       X--> automatic claim revocation or reallocation
       X--> automatic eviction / restart of an existing workload

      Telemetry:
       X--> scheduler decisions from temperature or ECC metrics
       X--> configured alerts / automatic remediation

      Dashboard state polling <--- node-agent runtime state (direct, fast)
      Prometheus / Grafana     <--- collector + scrape cycle (delayed)
```

`X-->` marks behavior the current setup does not implement or guarantee.
A dashboard crash changes discovery surfaces and zeroes exported power,
activity and clocks. It does not make AMD SMI report a lost device or force
an already-running pod to terminate. Removing a host device path is not
proof that existing container mounts disappear. DRA discovery occurs at
startup; do not treat an injected fault as guaranteed deallocation.
Recovery restores mock state; allocation consumers still require the
appropriate rediscovery. See [dashboard action coverage](guides/telemetry.md#other-dashboard-actions)
and [test scope](guides/testing.md).

## Node agent

The chart deploys a privileged DaemonSet. It stages mock sysfs under
`/var/lib/amd-gpu-mock/sys`, creates `/dev/kfd` and DRM character devices,
and writes CDI specs. KFD properties include vendor/device IDs, SIMD counts,
GFX targets and memory. PCI/DRM links supply physical identity and topology.
The staged driver module and bindings allow discovery without an AMD driver.

Profiles initialize runtime state. The simulator updates healthy temperature,
power, activity and clocks each second. Dashboard actions update that same
state and synchronize the staged sysfs and atomic AMD SMI snapshots. The
node agent also serves its own diagnostic `/metrics`; the real exporter
setup scrapes the separate AMD collector endpoint instead.

## Allocation and runtime

Chart 0.2.13 defaults to AMD's unchanged DRA v1.0.0 driver, republished for
AMD64 and ARM64. Its chart mounts mock sysfs at the driver's `/sys`. Kubernetes
allocates ResourceClaims; kubelet calls prepare/unprepare; the driver writes
per-claim CDI specs. Containerd injects only the allocated card/render devices
and shared `/dev/kfd`. See the [DRA guide](guides/dra.md).

The alternative device plugin reads the same sysfs and registers physical
GPU capacity as `amd.com/gpu`. See the [device-plugin guide](guides/device-plugin.md).

The published `amd-mock-kind-node:0.2.2` contains Kubernetes v1.37.0 and AMD's
container toolkit, with CDI enabled. Both allocation paths use this image.
Chart 0.2.13 uses node-agent image `amd-gpu-mock:v0.2.7`. The kind configuration
maps localhost:8080 to dashboard NodePort 30080 automatically.

## Telemetry

The default chart exporter DaemonSet contains unchanged AMD v1.5.2 collector
binaries and a dedicated AMD SMI replacement compiled against the matching
GPU Agent ABI 27 header. It reads node-agent snapshots through a read-only
host mount. This replacement is separate from the legacy handwritten library
staged for other consumers. Unsupported APIs return NOT_SUPPORTED.

AMD's published collector is x86-64. AMD64 executes it directly; ARM64 uses
explicit QEMU emulation. Prometheus, Grafana, Kubernetes and the node agent
run natively. Bundled Prometheus uses DNS discovery of a headless exporter Service and
preserves consumer labels. Grafana is provisioned and exposed at localhost:3000
by the kind mapping. The optional external Operator stack uses a ServiceMonitor.
The demo config coordinates ports and enable switches for both dashboards. See the [telemetry guide](guides/telemetry.md)
for setup, fault flows, tests, provenance and limitations.

## Operator scope

The published SIM_ENABLE controller fork bypasses driver init checks and
mounts mock sysfs for its plugin/labeller. The smoke test covers reconciliation,
readiness, capacity and device injection. This does not validate every
Operator operand. Operator-owned exporter, DRA and remediation remain separate
integration work; the tested real telemetry setup is the standalone chart
path. See the [Operator guide](guides/gpu-operator.md).

## Partitioning limits

SPX/DPX/QPX/CPX API transitions create virtual dashboard entries and divide
reported memory. They do not create independently schedulable partitions,
increase allocator capacity or implement AMD MxGPU/SR-IOV passthrough. Active
claims must not be combined with live profile changes. Profile/count changes
require consumer rediscovery and matching device nodes.

## Fixed DPX/NPS2 allocation

A fixed MI300X DPX/NPS2 startup uses partition-specific card/render/KFD nodes
and shared physical PCI/KFD identity. It exposes sixteen DRA devices across
eight physical GPUs. The scheduler matches the physical parent attribute;
AMD NodePrepare produces per-request CDI edits and the runtime applies them.
See [the partition architecture and responsibility table](guides/partition-allocation.md#allocation-path)
for the ASCII path, lifecycle, and verified boundaries. This startup topology
is separate from the virtual dashboard API transitions described above.

## Optional two-worker GPU and network path

```text
[1] Kind API/scheduler + GPU chart
 -> [2] Two ERNIC/QEMU workers join
 -> [3] AMD DRA publishes GPUs; Network Operator/NIC plugin advertises NICs
 -> [4] Two Pods in amd-demo-rdma request one GPU and one NIC each
 -> [5] Scheduler + kubelet/DRA + NIC plugin + containerd expose devices
 -> [6] Pods exchange queue-pair metadata over TCP
 -> [7] Verbs SEND/RECV and RDMA WRITE transfer CPU buffers through ERNIC mesh
 -> [8] SHA-256 checks prove delivery and reject intentional corruption
```

Each worker has its own emulated PCI NIC and GPU mock interfaces. GPU and NIC
allocation remain separate; the GPU is not in the CPU-buffer transfer path.
See the [GPU/network guide](guides/gpu-network.md#two-worker-allocation-and-transfer)
for the expanded diagram and the [two-worker demo](../demo/gpu-network/two-node/README.md)
for setup, captured evidence and cleanup. The single-node variant proves
allocation and HTTP access only.
