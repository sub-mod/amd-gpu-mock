# AMD device plugin

Advertise mock GPUs as `amd.com/gpu`, then schedule a workload that requests
one. The real AMD device plugin discovers the mock's staged GPU topology;
Kubernetes and kubelet handle scheduling and allocation normally.

## Prerequisites

Use kind v0.33.0+, kubectl, Helm, and Docker or Podman. Run from the repository
checkout. This scenario uses a fresh local cluster with the published node
image and chart; no custom image build is required. Kubernetes 1.37 is the
supported version. Podman users should first run:

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman
```

The default quick start uses DRA. Choose the device-plugin flags below when
installing this alternative allocator; the two allocators must not allocate
the same GPU pool simultaneously.

## Step 1: Create a cluster

```bash
kind create cluster --name amd-mock \
  --image docker.io/submod/amd-mock-kind-node:0.2.2 \
  --config deployments/kind-node/kind-config.yaml
```

The configuration maps the mock dashboard and Grafana ports to the host.
Use a fresh cluster rather than overwriting an existing DRA installation.

## Step 2: Install the mock and real device plugin

```bash
helm install amd-gpu-mock oci://docker.io/submod/amd-gpu-mock \
  --version 0.2.12 --namespace amd-mock --create-namespace \
  --set dra.enabled=false --set devicePlugin.enabled=true
kubectl -n amd-mock rollout status ds/amd-gpu-mock --timeout=180s
kubectl -n kube-system rollout status ds/amd-gpu-mock-device-plugin --timeout=180s
```

The chart stages the synthetic discovery tree and deploys AMD's device plugin.
The standard telemetry pipeline and dashboards use the same installation.

## Step 3: Wait for allocatable GPUs

```bash
kubectl wait nodes --all \
  --for='jsonpath={.status.allocatable.amd\.com/gpu}=8' --timeout=180s
kubectl get nodes \
  -o custom-columns='NODE:.metadata.name,GPUS:.status.allocatable.amd\.com/gpu'
```

The default MI300X profile exposes eight GPUs. Pod readiness can precede
kubelet registration and the node-status update, so wait for the resource
count before starting the workload.

## Step 4: Schedule a GPU workload

```bash
kubectl create namespace amd-device-plugin-demo
kubectl apply -n amd-device-plugin-demo -f - <<'YAML'
apiVersion: v1
kind: Pod
metadata:
  name: gpu-workload
spec:
  restartPolicy: Never
  containers:
  - name: app
    image: docker.io/busybox:1.36
    command: [sh, -c, 'ls -l /dev/kfd /dev/dri; sleep 3600']
    resources:
      limits:
        amd.com/gpu: 1
YAML
kubectl wait -n amd-device-plugin-demo pod/gpu-workload \
  --for=condition=Ready --timeout=180s
kubectl logs -n amd-device-plugin-demo gpu-workload
kubectl exec -n amd-device-plugin-demo gpu-workload -- test -c /dev/kfd
```

Expect KFD plus one allocated card/render pair inside the container. This
proves scheduling and device injection over mock character devices, not GPU
computation or hardware isolation. For actual captured device-plugin output,
see the [Tiny LLM presentation](../../demo/llm/README.md).

## Different GPU profiles

Set `--set gpu.profile=mi250x`, for example, on a fresh installation. The
expected resource count changes with the [profile](../profiles.md); the wait
above is specifically for the default eight-GPU MI300X setup.

## Troubleshooting

If allocatable capacity stays at zero, inspect discovery and registration:

```bash
kubectl -n amd-mock logs ds/amd-gpu-mock --tail=40
kubectl -n kube-system logs ds/amd-gpu-mock-device-plugin --tail=40
kubectl describe node
kubectl -n amd-device-plugin-demo describe pod gpu-workload
```

The chart rejects simultaneous DRA and device-plugin allocation. To switch an
existing release, delete its GPU consumers first, then upgrade with the two
allocator flags from Step 2. ResourceClaim workloads do not automatically
become device-plugin workloads.

## Clean up

```bash
kubectl delete namespace amd-device-plugin-demo
# Remove the cluster only when finished with all workloads in it:
kind delete cluster --name amd-mock
```

## Related

| Goal | Guide |
| --- | --- |
| Claim-based allocation | [AMD DRA](dra.md) |
| Batch queueing and GPU reuse | [Spur](../../demo/spur/README.md) |
| Fault injection and monitoring | [Telemetry](telemetry.md) |
| Automated allocation checks | [Testing](testing.md) |
| More presentations | [Scenarios](../site/scenarios.md) |
