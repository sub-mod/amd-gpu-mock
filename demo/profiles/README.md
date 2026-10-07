# GPU models and physical inventory

This catalog presentation uses an SPX startup fleet. Fixed DPX/NPS2 mode
blocks runtime profile/tray changes; see [partition allocation](../partition-allocation/README.md).

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

## Recorded run output

Captured on 2026-10-06 using Kubernetes v1.37.0, chart 0.2.9 and the
ARM64 default Podman VM. Names, IDs and readings are specific to this run.
[Full captured output](captured.log); [capture sources and complete suites](../logs/README.md).

Actual captured output:

```text
DEMO: Show the GPU profile catalog and installed physical inventory
Guide: demo/profiles/README.md; inspect pods across namespaces with kubectl get pods -A
PROFILE    MODEL                     DEVICES  GiB/DEVICE  TDP/W
mi210      AMD Instinct MI210              8          64    300
mi250x     AMD Instinct MI250X            16          64    500
mi300a     AMD Instinct MI300A             4         128    550
mi300x     AMD Instinct MI300X             8         192    750
mi325x     AMD Instinct MI325X             8         256   1000
mi350x     AMD Instinct MI350X             8         288   1000
mi355x     AMD Instinct MI355X             8         288   1400

Installed inventory:
GPU 0  0000:05:00.0  NUMA=0 AMD Instinct MI300X       VRAM=196608 MiB status=healthy
GPU 1  0000:26:00.0  NUMA=0 AMD Instinct MI300X       VRAM=196608 MiB status=healthy
GPU 2  0000:46:00.0  NUMA=0 AMD Instinct MI300X       VRAM=196608 MiB status=healthy
GPU 3  0000:65:00.0  NUMA=0 AMD Instinct MI300X       VRAM=196608 MiB status=healthy
GPU 4  0000:85:00.0  NUMA=1 AMD Instinct MI300X       VRAM=196608 MiB status=healthy
GPU 5  0000:a6:00.0  NUMA=1 AMD Instinct MI300X       VRAM=196608 MiB status=healthy
GPU 6  0000:c6:00.0  NUMA=1 AMD Instinct MI300X       VRAM=196608 MiB status=healthy
GPU 7  0000:e5:00.0  NUMA=1 AMD Instinct MI300X       VRAM=196608 MiB status=healthy
Select a different profile at installation; avoid live switches with active consumers.
```

The installed fleet contains eight MI300X devices with 196608 MiB each. The preceding seven-model table is the available catalog, not seven installed fleets.

## Reading this run

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
