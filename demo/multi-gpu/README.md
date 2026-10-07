# Multi-GPU and concurrent consumers

```bash
# One pod, two physical GPU card/render pairs.
python3 demo/run.py multi-gpu --count 2
kubectl -n amd-demo-multi-gpu get pods,resourceclaims
python3 demo/run.py cleanup

# Four independent pods, one physical GPU each.
python3 demo/run.py multi-gpu --count 1 --replicas 4
```

Both allocators are supported. Show each request's device nodes and, with
DRA, its claim allocation. Independent claims/requests consume separate
physical GPUs. The runner verifies the requested render-device count in each
consumer. It does not verify GPU execution or bandwidth scaling.

Cleanup before changing the count/replicas; existing pod resource requests
cannot be changed in place. Keep total requests within the free physical pool.
