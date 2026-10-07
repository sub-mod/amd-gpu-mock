# GPU partitioning: virtual state versus physical allocation

```bash
python3 demo/run.py partitioning --mode CPX
# Show 64 virtual entries for eight MI300X physical GPUs.
python3 demo/run.py partitioning --mode DPX
python3 demo/run.py partitioning --mode QPX
python3 demo/run.py partitioning --mode SPX
```

Clean up GPU consumers before changing partition state. Show the division of
reported memory and the restoration to SPX. The allocator still has eight
physical GPUs; this API does not implement AMD hardware partitions, MxGPU,
SR-IOV or independent slice scheduling.

For four simultaneously scheduled physical GPU consumers:

```bash
python3 demo/run.py multi-gpu --count 1 --replicas 4
```

With the device plugin, [physical-workloads.yaml](physical-workloads.yaml)
is also available for the original two-service/four-replica presentation:

```bash
kubectl create namespace amd-demo-partitioning
kubectl label namespace amd-demo-partitioning amd-gpu-mock/demo=true
kubectl -n amd-demo-partitioning apply -f demo/partitioning/physical-workloads.yaml
kubectl -n amd-demo-partitioning get pods
```

Those replicas request full physical GPUs, not CPX partitions.
