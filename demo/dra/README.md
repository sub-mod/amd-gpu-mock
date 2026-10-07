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

## What to watch and what the logs prove

Read the output in this order: ResourceSlice inventory, claim allocation,
workload device listing, then the runner's `EVIDENCE`/`PASS` lines. The runner
checks that the claim's driver/pool/device exists in the advertised inventory
and that its render device appears inside the scheduled container.

The device names in this pinned AMD driver encode card and render indices:
`gpu-0-128` corresponds to card 0/renderD128. The claim's node selector and the
pod's scheduled node should agree. `/dev/kfd` is shared infrastructure;
its presence alone does not identify the selected GPU. The allocated render
node provides that correlation.

This demonstrates mocked AMD topology -> real AMD DRA discovery -> scheduler
allocation -> kubelet NodePrepareResources -> CDI/runtime device injection.
It does not prove successful GPU computation. ResourceSlice/claim/device
agreement is observed evidence; inspect the driver logs and CDI files in the
[shared evidence guide](../EVIDENCE.md) when explaining the intermediate hops.
Do not present the unused MI300X selector template as a selector test.

See the [shared evidence checklist](../EVIDENCE.md) for commands, provenance,
and how to distinguish direct observations from inferred intermediate steps.
