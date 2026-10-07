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
