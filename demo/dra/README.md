# DRA: request, allocation, prepare and injection

Requires the default DRA installation.

```bash
python3 demo/run.py dra
kubectl -n amd-demo-dra get resourceclaims -o yaml
kubectl get resourceslices
kubectl -n amd-demo-dra exec dra-gpu-demo -- ls -l /dev/kfd /dev/dri
```

[claim.yaml](claim.yaml) contains an unconstrained GPU template, a MI300X
product-selector template, and a pod using the unconstrained template.
Show a device advertised in ResourceSlices, the claim's allocation result,
and the single card/render pair injected into the pod by CDI. The selector
template is included as an example; it is not consumed by the default pod.

The [allocation demo](../allocation/README.md) shows release. The full
[DRA guide](../../docs/guides/dra.md) covers explicit/shared claims and restart
checkpoint behavior. These are allocation contracts, not compute execution.
