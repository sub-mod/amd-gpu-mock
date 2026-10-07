# AMD device plugin

The default quick start installs DRA. To use workloads requesting the
extended resource `amd.com/gpu`, select the device plugin instead:

```bash
kind create cluster --name amd-mock \
    --image docker.io/submod/amd-mock-kind-node:0.2.2 \
    --config deployments/kind-node/kind-config.yaml
helm install amd-gpu-mock oci://docker.io/submod/amd-gpu-mock \
    --version 0.2.4 --namespace amd-mock --create-namespace \
    --set dra.enabled=false --set devicePlugin.enabled=true
kubectl -n kube-system rollout status ds/amd-gpu-mock-device-plugin --timeout=180s
kubectl get node -o jsonpath='{.items[0].status.allocatable.amd\.com/gpu}'
# 8
```

Use the same published node image for both allocators. Kubernetes 1.37 and
kind v0.33.0 or newer are required for this release. Podman users should set
`KIND_EXPERIMENTAL_PROVIDER=podman` before creating the cluster.

A container requests a physical GPU with:

```yaml
resources:
  limits:
    amd.com/gpu: 1
```

Change the initial profile with `--set gpu.profile=mi250x`, for example.
The chart rejects enabling the device plugin and DRA together because both
would independently allocate the same GPU pool.

To switch an existing release, delete GPU-consuming workloads first, then
run `helm upgrade` with the two allocator flags above. Existing ResourceClaim
workloads do not automatically become device-plugin workloads.

See the [testing guide](testing.md) for per-profile scheduling, exhaustion,
release, and fault propagation tests.

The same dashboard and optional [real AMD telemetry pipeline](telemetry.md)
work with either allocator. The kind configuration exposes localhost:8080.
