# OpenShift Local demo scenarios

All OpenShift-specific runners live in **`demo/openshift/`**. Start with the
[Tiny LLM setup](openshift-local.md), then use the sequence below on the same
CRC cluster. These demos do not create a Kind cluster or use Podman to host
OpenShift: CRC uses vfkit on macOS and CRI-O inside its VM.

## Validated scenarios

The additional live runs used Apple Silicon, OpenShift 4.22.14, Kubernetes
1.35.6, published chart 0.2.13 and mock image v0.2.7. Logs are actual run output,
not example responses. Each stage checks its claimed behavior before printing
`PASS`; these are control-plane/device-injection demonstrations, not GPU compute.

| Order | Demo | What the captured output proves |
| --- | --- | --- |
| 1 | [Tiny LLM](../../demo/openshift/tiny-llm/captured.log) | GPU request, one allocated render device, scripted HTTP response |
| 2 | [Multi-GPU](../../demo/openshift/multi-gpu/captured.log) | One Pod gets two GPUs; two concurrent Pods get different GPUs |
| 3 | [Allocation and release](../../demo/openshift/allocation/captured.log) | Genuine `Insufficient amd.com/gpu` Pending condition, then reuse of a released device |
| 4 | [Fault injection](../../demo/openshift/faults/captured.log) | Overheat reaches hwmon; ECC reaches KFD RAS; busy/idle/recovery change mock state |
| 5 | [Profiles](../../demo/openshift/profiles/captured.log) | Eight physical MI300X entries and the published profile catalog |
| 6 | [Partition controls](../../demo/openshift/partitioning/captured.log) | CPX dashboard state changes while schedulable capacity stays unchanged |
| 7 | [AMD DRA](../../demo/openshift/dra/captured.log) | Stable claims, real driver preparation, CRI-O/CDI injection, occupied-device rejection and same-device release/reuse |
| 8 | [Telemetry](../../demo/openshift/telemetry/captured.log) | Real AMD exporter reports eight GPUs; injected ECC and recovery reach Prometheus; Grafana is provisioned |
| 9 | [Same-GPU partition allocation](../../demo/openshift/partition-allocation/captured.log) | Two containers receive distinct 96 GiB DPX slice descriptors with the same physical PCI parent |

**Application consumers explicitly require `restricted-v2`.** The runners
verify the admitted SCC, non-root UID and allocated character devices.
Prometheus and Grafana also require `restricted-v2`. The mock node agent,
DRA node plugin and metrics exporter need host/device access and have separately
scoped privileged service accounts. Namespace Pod Security settings permitting
those operands do not grant privileged SCC access to application accounts.

## Run the sequence

Use the CRC administrative context, Helm and the Python environment from the
Tiny LLM guide. It needs PyYAML. `PULL_SECRET_FILE` remains configurable in
`demo/openshift/tiny-llm/setup.sh`, defaulting to the local sibling CRC folder.
The runtime scripts reject a selected API other than `api.crc.testing`.

From the repository root:

```bash
source /tmp/amd-crc-demo-venv/bin/activate
python demo/openshift/run.py list
# On the initial device-plugin/SPX setup:
python demo/openshift/run.py tiny-llm
python demo/openshift/run.py multi-gpu
python demo/openshift/run.py allocation
python demo/openshift/run.py faults
python demo/openshift/run.py profiles
python demo/openshift/run.py partitioning
# Switch this dedicated demo installation to DRA:
python demo/openshift/run.py dra
python demo/openshift/run.py telemetry
# Drain this suite's full-GPU DRA consumer and switch to fixed DPX:
python demo/openshift/run.py partition-allocation
# Return to the initial device-plugin/SPX Tiny LLM presentation:
python demo/openshift/run.py restore
```

Each consumer demo retains its last successful Pod for inspection. Clean its
namespace before repeating it; Pod resource requests and claim selectors are
immutable. DRA setup removes only the suite's known device-plugin consumers and
stops that plugin before deploying DRA. It refuses unrelated GPU consumers.
Do not advertise the same mock devices through both allocators concurrently.

The partition-allocation runner refuses outstanding claims before restarting
the mock in fixed DPX/NPS2 mode. The real driver then publishes 16 logical devices
from eight physical GPUs. Its one claim contains two requests constrained with
`matchAttribute: resource.kubernetes.io/pciBusID`; each container consumes its
own request. The logs prove same-parent allocation and separate device-node
injection, not physical memory enforcement or real hardware partition commands.
Restore drains the known DRA presentations, restores SPX and restarts the
exporter so its enumeration matches the new inventory.

```text
[1] CRC VM / OpenShift API / scheduler
        |
[2] Mock agent -> synthetic sysfs + host GPU device files
        |
        +-- Device-plugin stages
        |   [3] AMD plugin -> amd.com/gpu capacity
        |   [4] Pod request -> scheduler -> Allocate -> CRI-O devices
        |
        +-- DRA stages (device plugin stopped)
            [3] AMD DRA discovery -> ResourceSlice / DeviceClass
            [4] ResourceClaim -> scheduler selects device(s)
            [5] NodePrepareResources -> CDI spec -> CRI-O devices
                         |
            [6] restricted-v2 consumer checks KFD + render nodes
                         |
            [7] Delete consumer + claim -> unprepare -> device reuse

Fault path:
[1] Dashboard API action -> [2] mock state/sysfs/AMD SMI snapshot
    -> [3] real AMD GPU Agent/exporter -> [4] Prometheus -> [5] Grafana
```

## Dashboard and Grafana

Telemetry setup creates edge-terminated OpenShift Routes:

```bash
oc -n amd-mock-crc-llm get routes
```

The captured local hosts are:

- `https://amd-mock-dashboard-amd-mock-crc-llm.apps-crc.testing`
- `https://amd-mock-grafana-amd-mock-crc-llm.apps-crc.testing`

Grafana's demo login is `admin` / `amdmock`; change the chart-provided credential
before using this outside a local demo. Route certificates may require trusting
CRC's local certificate authority. The fault test invokes the same API endpoints
as dashboard buttons; it does not automate browser clicks. The telemetry test
verifies Prometheus values and Grafana provisioning, not browser rendering. Both Route endpoints were also
queried successfully from the macOS host after restoring SPX.

## ERNIC and Network Operator: prerequisite gap

Run the real host inspection:

```bash
python demo/openshift/run.py network-preflight
```

[Captured inspection](../../demo/openshift/gpu-network/captured-preflight.log)
returns a nonzero exit code deliberately because this CRC VM has no Pensando
PCI device and no `ionic_rdma` module or RDMA device. Its Ethernet `ionic` module
is available. Nothing fabricates PCI sysfs entries or advertises `amd.com/nic`.
The Network Operator has not been installed or validated in this lane.

The existing ERNIC implementation attaches a userspace PCI device through
QEMU's VFIO-user interface. CRC's vfkit uses VirtIO devices and does not provide
that existing attachment path. CRC also does not support nested virtualization.
An OpenShift ERNIC demo needs a compatible VM backend/device attachment plus an
RHCOS-compatible RDMA driver and real discovery by NFD/Network Operator. The
Ubuntu kubeadm worker cannot simply join OpenShift unchanged. Single-node and
two-node transfer demonstrations remain blocked on that infrastructure work.
See [vfkit device configuration](https://github.com/crc-org/vfkit/blob/main/doc/usage.md)
and [CRC requirements](https://crc.dev/docs/installing/).

## Spur: architecture prerequisite

```bash
python demo/openshift/run.py spur-preflight
```

[Captured image inspection](../../demo/openshift/spur/captured-preflight.log)
shows the current pinned upstream Spur image is AMD64 and this node is ARM64.
The probe exits nonzero on that mismatch; it does not claim a running Spur
scheduler. Next work is an upstream ARM64 image or a separately built, published
and validated ARM64 artifact, followed by OpenShift admission and queueing tests.
No new image was built or published for the demos above.

## Cleanup and limits

Restore before leaving partition mode. Then remove the optional consumer
namespaces using their exact names:

```bash
oc delete namespace amd-crc-multi-gpu amd-crc-allocation --ignore-not-found
# Complete local stack removal also removes the retained Tiny LLM/monitoring:
python demo/openshift/tiny-llm/run.py cleanup
```

The suite creates cluster-scoped DRA/RBAC resources as well as namespace objects.
Namespace deletion alone does not remove all of them or mock files on the VM.
Use `crc delete` only when you intend to delete the entire dedicated cluster.
The suite does not claim AMD GPU Operator/OLM parity, actual ROCm execution,
NIC allocation, GPU-direct DMA, fault-driven eviction or automatic remediation.
