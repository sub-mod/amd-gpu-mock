# Tiny LLM: GPU scheduling

This is the SPX one-GPU workload presentation. For per-container same-parent
slice allocation, use [partition allocation](../partition-allocation/README.md);
neither demo executes real GPU inference.

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

## Recorded run output

Captured on 2026-10-06 using Kubernetes v1.37.0, chart 0.2.9 and the
ARM64 default Podman VM. Names, IDs and readings are specific to this run.
[Full captured output](captured.log); [capture sources and complete suites](../logs/README.md).

Actual captured output:

```text
DEMO: Scripted Tiny LLM: GPU scheduling and device injection (both allocators)
Guide: demo/llm/README.md; inspect pods across namespaces with kubectl get pods -A
============================================================
  AMD GPU Mock — LLM Inference Demo
============================================================

Pod scheduled with a DRA ResourceClaim.
GPU device: /dev/kfd = True
DRI device: /dev/dri = True

Simulating model loading: HuggingFaceTB/SmolLM-135M
  [--------------------] 0%
  [#####---------------] 25%
  [##########----------] 50%
  [###############-----] 75%
  [####################] 100%
Simulated model ready (no weights loaded)

Prompt: "The future of AI is"
Generating 5 tokens...
  Token 1: bright
  Token 2: and
  Token 3: full
  Token 4: of
  Token 5: possibilities

Generated: "The future of AI is bright and full of possibilities"

In a real deployment, this would use ROCm/HIP on the MI300X.
The mock proves Kubernetes GPU scheduling works end-to-end.

LLM service ready. Listening for requests...

EVIDENCE pod amd-demo-llm/tiny-llm-dra-demo-69b9bb8dfd-g9rb8 scheduled on amd-mock-control-plane; /dev/kfd is a character device; render devices: /dev/dri/renderD134
EVIDENCE claim tiny-llm-dra-demo-69b9bb8dfd-g9rb8-gpu-dkt64 -> driver=gpu.amd.com pool=amd-mock-control-plane device=gpu-6-134; advertised capacity={'computeUnits': {'value': '304'}, 'memory': {'value': '192Gi'}, 'simdUnits': {'value': '1216'}}
PASS AMD DRA advertised device -> allocated claim -> matching injected render device
This proves mock device allocation and injection, not GPU execution or hardware isolation.
Scripted output only: no model weights or GPU inference.
```

The recorded claim selected `gpu-6-134`, and the container received `renderD134`. The final checked result confirms allocation/injection; the generated text remains a simulation.

## Reading this run

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
