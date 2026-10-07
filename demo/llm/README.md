# Tiny LLM: GPU scheduling

```bash
python3 demo/run.py llm
kubectl -n amd-demo-llm get pods,resourceclaims
```

Show the scheduled container, `/dev/kfd`, its selected render device and the
scripted model-loading/inference text. [dra.yaml](dra.yaml) is the default
ResourceClaim variant; [device-plugin.yaml](device-plugin.yaml) requests
`amd.com/gpu: 1`. The runner selects the installed allocator automatically.

No model weights are downloaded and no inference runs. Watch Grafana for the
consumer labels. The workload remains running until `python3 demo/run.py cleanup`.

## What to watch and what the logs prove

The runner prints the selected allocator's evidence after the model-loading
text. For DRA, compare the ResourceSlice device, the claim's allocated device,
and the container's matching `renderD` node. `/dev/kfd` must be a character
device. These checks establish the path from mocked sysfs/KFD topology through
the real AMD DRA driver, scheduler, kubelet preparation and runtime injection.
For the device plugin, the request is `amd.com/gpu: 1`; no DRA claim is involved.

```bash
kubectl -n amd-demo-llm logs deployment/tiny-llm-dra-demo
kubectl -n amd-demo-llm get resourceclaims -o yaml
kubectl -n amd-demo-llm exec deployment/tiny-llm-dra-demo -- ls -l /dev/kfd /dev/dri
# Device-plugin mode: use deployment/tiny-llm-demo instead.
```

`GPU device ... True` and the device listing confirm injection. The progress
bar and generated tokens are scripted Python text; they do not demonstrate
ROCm/HIP execution, model loading, inference accuracy or throughput. A Running
pod alone is insufficient evidence of GPU access. Use the telemetry demo to
find this pod's labels; its displayed utilization is simulated device state,
not utilization measured from the scripted model.

See the [shared evidence checklist](../EVIDENCE.md) for commands, provenance,
and how to distinguish direct observations from inferred intermediate steps.
