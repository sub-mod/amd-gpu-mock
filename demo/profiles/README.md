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

## What to watch and what the logs prove

The first table is the available profile catalog; the second is the currently
installed fleet. Read GPU index, model, BDF, NUMA node and memory together.
This command reads the mock API and creates no pods. It does not install all
seven profiles, call real AMD hardware, or validate every profile's exporter.

Compare the installed inventory against `kubectl get resourceslices -o yaml`
in DRA mode, and the rendered topology described in the
[shared evidence guide](../EVIDENCE.md). That comparison can establish that
the active profile reached the real AMD driver's discovery path. Catalog
output alone cannot establish that. GPU identifiers can use different formats
between the dashboard, DRA and AMD SMI; correlate BDF and card/render indices.
Avoid live profile changes while the demo consumers are allocated.

See the [shared evidence checklist](../EVIDENCE.md) for commands, provenance,
and how to distinguish direct observations from inferred intermediate steps.
