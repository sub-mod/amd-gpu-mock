# How to prove a demo's path

Run commands from the checkout. These examples assume the quick-start release
`amd-gpu-mock` in namespace `amd-mock` and context `kind-amd-mock`:

```bash
kubectl config use-context kind-amd-mock
kubectl get pods -A
kubectl get resourceclaims -A
```

Workloads live in `amd-demo-*` namespaces and remain after individual demo
commands. The automated presenter suite cleans them at the end. Profiles,
faults, telemetry and virtual partitioning create no workload pods. Use
`python3 demo/run.py cleanup` when finished; it deletes demo-labelled namespaces
and resets faults/SPX. Do not clean up during a presentation you want to inspect.
Run GPU-changing demos without other users changing the state concurrently.

## Two real consumer paths from mocked devices

```text
Allocation:
mock profile -> rendered AMD sysfs/KFD + device nodes
             -> real AMD DRA discovery -> ResourceSlice
             -> scheduler/claim -> kubelet/AMD NodePrepareResources
             -> CDI/container runtime -> selected workload device nodes

Alternative allocation:
mock topology -> real AMD device plugin -> amd.com/gpu resource
              -> scheduler -> kubelet Allocate -> workload device nodes

Telemetry:
dashboard action -> mock state -> shared SMI snapshot -> mock AMD SMI ABI
                 -> real AMD GPU Agent -> real AMD Device Metrics Exporter
                 -> Prometheus scrape -> Grafana query/display

Attribution:
allocated workload -> kubelet pod-resources -> AMD exporter consumer labels
```

DRA is not a hop in the telemetry pipeline. The scheduler allocates the devices
advertised by the driver; it does not read Grafana or react to these faults.

## Record provenance before presenting

```bash
helm list -n amd-mock
kubectl -n amd-mock get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{range .status.containerStatuses[*]}{.name}{" "}{.image}{" "}{.imageID}{"\n"}{end}{end}'
kubectl -n amd-mock get ds/amd-gpu-mock-metrics-exporter -o yaml
```

Record the deployed image digests, not only a tag. The exporter manifest shows
the shared SMI state mount and kubelet pod-resources mount. The published runtime
contains unchanged AMD v1.5.2 GPU Agent/exporter binaries with a replacement
AMD SMI device library. Image names alone do not establish binary provenance;
see the pinned inputs and build recipe in the
[telemetry guide](../docs/guides/telemetry.md) and
[exporter image source](../deployments/metrics-exporter/). ARM64 explicitly
emulates the x86 AMD collectors with QEMU.

## Allocation evidence, from host mock to container

```bash
kubectl -n amd-mock exec ds/amd-gpu-mock -- ls /var/lib/amd-gpu-mock/sys/class/kfd/kfd/topology/nodes
kubectl get resourceslices -o yaml
kubectl -n amd-demo-dra get resourceclaims -o yaml
kubectl -n amd-demo-dra get pod dra-gpu-demo -o yaml
kubectl -n amd-demo-dra logs dra-gpu-demo
kubectl -n amd-demo-dra exec dra-gpu-demo -- ls -l /dev/kfd /dev/dri
kubectl -n amd-demo-dra describe pod dra-gpu-demo
kubectl -n amd-mock logs ds/amd-gpu-mock-dra-kubeletplugin --tail=80
```

Compare the claim's `status.allocation.devices.results` driver/pool/device
with the ResourceSlice and its full-device capacity. Compare the selected node
with the pod's `spec.nodeName`. For this pinned AMD driver, `gpu-0-128` names
card0/renderD128. The runner checks advertised device membership, allocation
count and matching injected render nodes; `/dev/kfd` must be a character device.

To inspect the CDI files on the kind node, use your runtime:

```bash
podman exec amd-mock-control-plane ls -l /var/run/cdi
# Docker users: replace podman with docker.
```

Inspect the listed AMD claim CDI file with the runtime's `exec ... cat <file>`;
match its device edits to the container listing. A successful claim plus
matching device nodes establishes the allocation/injection contract. Driver
logs, CDI files and pod Events explain the intermediate preparation steps;
ordinary success logs are not a trace of every function call. A Running pod
alone, a claim alone or scripted inference text does not prove GPU access.

For device-plugin mode, inspect the node's `amd.com/gpu` capacity, the pod's
container limits, then its injected nodes. ResourceClaims are absent. The real
AMD device plugin runs within the mock DaemonSet; inspect its container logs
and the device-plugin guide for that alternate path.

## Telemetry evidence, one held condition across each layer

Prefer ECC or fixed overheating for a clear correlation. Recover GPU 0 first,
then inject ECC once and leave it in place while checking each stage:

```bash
python3 demo/run.py faults --gpu 0 --action recover
python3 demo/run.py faults --gpu 0 --action ecc-error
curl -fsS http://localhost:8080/api/gpus
kubectl -n amd-mock exec ds/amd-gpu-mock -- cat /var/lib/amd-gpu-mock/smi/gpu0
kubectl get --raw /api/v1/namespaces/amd-mock/services/amd-gpu-mock-metrics-exporter:5000/proxy/metrics
kubectl get --raw '/api/v1/namespaces/amd-mock/services/amd-gpu-mock-prometheus:9090/proxy/api/v1/query?query=amd_gpu_ecc_uncorrect_total'
python3 demo/run.py telemetry
```

The snapshot's first line fields are temperature C, power W, power cap W,
activity %, used memory MiB, total memory MiB, ECC count, graphics MHz and
memory MHz. The next lines contain model, canonical SMI UUID and PCI BDF.
The snapshot is the input read by the mock AMD SMI library, not a fabricated
Prometheus response. See [snapshot writer](../pkg/gpu/kfd/smi.go) and
[AMD SMI implementation](../pkg/mocksmi/exporter/) for that boundary.

At the export endpoint find `amd_gpu_ecc_uncorrect_total` with `gpu_id="0"`.
At Prometheus find the same GPU/value. The telemetry runner queries Grafana's
Prometheus datasource; the ECC panel should show that sample. This is the real
AMD exporter's `/metrics`, not the mock node agent's diagnostic endpoint.
An increase at all stages is propagation evidence. Small differences in busy
readings are expected because each stage samples a changing simulation.

Grafana refreshes every 5 seconds; collection/scraping adds delay. Refresh an
already-open page after provisioning changes. If data stops updating, inspect:

```bash
kubectl -n amd-mock get pods
kubectl -n amd-mock describe deployment/amd-gpu-mock-grafana
kubectl -n amd-mock logs deployment/amd-gpu-mock-grafana --tail=40
kubectl -n amd-mock logs ds/amd-gpu-mock-metrics-exporter --tail=40
```

Pod restarts/OOMKilled are failures, not evidence that a fault was ignored by
AMD SMI. Restore GPU health after the observation:

```bash
python3 demo/run.py faults --gpu 0 --action recover
```

## Boundaries to state to the audience

These demos establish discovery, scheduling, allocation, preparation, device
injection and telemetry against mock device interfaces. They do not establish
real GPU computation, performance, hardware isolation, AMD hardware partition
management, automatic alerts/eviction, or independently schedulable CPX slices.
The [same-GPU allocation demo](partition-allocation/README.md) verifies fixed
MI300X DPX/NPS2 partitions through unchanged AMD DRA, the scheduler, kubelet
and CDI runtime. Its [layer responsibilities](../docs/guides/partition-allocation.md#responsibilities-of-each-layer)
and separate captured log describe allocation visibility, not hardware isolation.
Individual guides identify what each command directly checks.

## Fixed partition demo lifecycle

The standalone partition runner leaves `amd-demo-partition-allocation` for
inspection. Delete that namespace explicitly to release its claims. It is not
labelled for the generic runner cleanup, and fixed DPX startup rejects virtual
SPX reset/profile changes. See the [presentation setup](README.md#same-gpu-allocation-presentation).
