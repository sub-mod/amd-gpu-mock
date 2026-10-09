# Spur batch scheduling with mock AMD GPUs

Run **unchanged Spur 0.14.0** against mock MI300X GPUs. A job occupies the
whole GPU pool; a second job waits in Spur's queue, then starts when the first
job completes. The payload checks injected character devices and exits when
the presenter releases it. No GPU computation or RocJITsu backend is needed.

This demo creates a separate `amd-spur` Kind cluster with its own kubeconfig.
It does not switch the allocator or workloads in your normal `amd-mock` cluster.
The demo cluster uses the device plugin because the pinned upstream Spur
Kubernetes operator creates Pods requesting `amd.com/gpu`; it does not create
DRA ResourceClaims.

## Allocation flow

```text
(1) Published mock node image + chart: eight synthetic MI300X GPUs
                   |
                   v
(2) Real AMD device plugin discovers devices -> kubelet: amd.com/gpu: 8
                   |
                   v
(3) Unchanged Spur Kubernetes operator watches node capacity and labels
                   | registers one virtual compute node
                   v
(4) spurctld receives two SpurJobs and schedules the first for eight GPUs
                   | controller-signed launch credential
                   v
(5) Spur operator creates an ordinary Pod requesting amd.com/gpu: 8
                   |
                   v
(6) Kubernetes + kubelet + AMD device plugin inject the allocated devices
                   | workload prints actual character-device identities
                   v
(7) Second job remains in Spur queue: Pending / Resources; no Pod yet
                   | presenter releases the first workload; completion reported
                   v
(8) Spur dispatches waiting job -> Pod requests one GPU -> checks devices
                   | presenter releases second workload
                   v
(9) Both SpurJobs Completed; workload Pod logs remain available
```

The controller and operator are real upstream binaries from the published
`rocm/spur:0.14.0` image, pinned to the AMD64 manifest digest in
[versions.env](versions.env). Upstream source commit:
[`bd28e6395547377cb47c7d911390f99432a5fc73`](https://github.com/ROCm/spur/tree/bd28e6395547377cb47c7d911390f99432a5fc73).
No source patch, custom image, native agent, or compute simulator is added.
The operator is the virtual agent in this Kubernetes deployment; `spurd` is
not required for this path.

## Set up and run

Requires kind v0.33.0+, kubectl, Helm, Python 3, curl and Docker or Podman.
Run from the repository checkout:

```bash
# Podman users:
export KIND_EXPERIMENTAL_PROVIDER=podman

demo/spur/setup.sh
python3 -u demo/spur/run.py
```

The script uses the published mock node `0.2.2` and chart `0.2.13`, then installs
Spur's upstream CRD and this demo's controller/operator configuration. It
uses a private kubeconfig at `tmp/spur/kubeconfig`. Set `SPUR_CLUSTER` and
`SPUR_KUBECONFIG` to override the cluster name and kubeconfig location.

The upstream Spur image is **Linux AMD64 only**. This demo was validated on
an ARM64 Kind node inside this Mac's Podman VM with its existing AMD64 binary
translation support. That is a prerequisite on ARM64 hosts; the setup does
not install or reconfigure emulators. Linux AMD64 needs no CPU translation.
No ARM64-native Spur image is claimed.

This small demo disables telemetry and dashboard Services in its separate
cluster to reduce resource use and avoid competing with your existing demo.
The normal README quick start retains its dashboard/Grafana behavior.

## Actual output and what it proves

[Captured run](captured.log) contains real output from the validated run,
including the upstream version, generated Pod names, device identities,
Spur queue, completion transitions and final object listing. The script
prints these directly; it does not insert expected output into runtime logs.

| Check | Evidence |
| --- | --- |
| Upstream binary | `spur 0.14.0 (bd28e639)` |
| Whole pool allocated | Operator-created Pod has `amd.com/gpu: 8`; workload sees eight render character devices and KFD |
| Queueing belongs to Spur | Second job shows `PD` / `Resources`, with no corresponding Pod while the pool is held |
| Resource release | First workload exits; SpurJob becomes `Completed`; waiting job then receives one GPU |
| Device-plugin injection | Workload checks character devices; generated Pod is unprivileged and has no direct `/dev` hostPath mounts |
| End-to-end completion | Both jobs reach `Completed` through the unchanged controller/operator flow |

The mock supplies discovery/device surfaces. The real device plugin allocates
and injects devices, Kubernetes starts containers, and Spur controls the queue
and dispatch. This proves orchestration over fake devices; it does not prove
HIP execution, GPU performance, hardware isolation, or DRA integration.
Node GPU type and memory labels are declared demo inventory, not measurements.

The controller uses one replica and ephemeral state. It is a disposable demo,
not a high-availability or production deployment. The operator launch endpoint
requires signed controller credentials, supplied through a generated Kubernetes
Secret; keys are not included in captured output. The controller's submission
API uses upstream unauthenticated mode inside this dedicated local cluster.
No Spur Service is exposed through a host port or NodePort. Do not use this
configuration as a shared production service.

## Inspect, repeat and clean up

```bash
export KUBECONFIG="$PWD/tmp/spur/kubeconfig"
kubectl -n amd-demo-spur get spurjobs,pods -o wide
kubectl -n amd-demo-spur logs -l spur.amd.com/managed-by=spur-k8s-operator --prefix
kubectl -n amd-demo-spur logs deployment/spur-k8s-operator

# Completed objects are retained. Delete only these demo jobs before repeating:
kubectl -n amd-demo-spur delete spurjob hold-pool queued-gpu
python3 -u demo/spur/run.py

# Remove this demo's entire dedicated cluster:
demo/spur/cleanup.sh
```

The run script refuses existing SpurJobs so it does not silently overwrite
work. If interrupted while a job is holding GPUs, delete its SpurJob to cancel
it, or use the cleanup script. Setup can be rerun to reconcile the same demo
cluster. It does not validate coexistence with independently submitted jobs.

The optional `spur-demo` GitHub Actions workflow runs the same setup and script
on Linux AMD64. A local PASS is not a claim that a remote workflow has run.
See [upstream Kubernetes deployment](https://github.com/ROCm/spur/blob/v0.14.0/docs/deployment/kubernetes.rst)
for the full deployment model.
