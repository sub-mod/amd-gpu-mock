# GPU models and physical inventory

```bash
python3 demo/run.py profiles
```

Show seven profile models and the installed fleet's identities, PCI BDFs,
NUMA nodes and memory. To present another model, choose `gpu.profile` in a
copy of `demo/config.yaml` before installing a new dedicated cluster.

MI250X models 16 GCD devices at 64 GiB each; MI300A has four devices; other
profiles have eight. Do not change profile while consumers hold allocations.
Live profile/count changes require consumer rediscovery and matching device
nodes. Per-tray switching lacks immediate renderer synchronization. The
real exporter's ASIC/PCIe/clock-limit metadata still contains MI300X constants;
this demo does not claim all-profile telemetry fidelity.
