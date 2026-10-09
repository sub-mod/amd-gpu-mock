# Choose a demo

Install the [quick start](getting-started.md) first. Use the
[presenter guide](../../demo/README.md) for commands, cleanup, and captured logs.

| Demo | Setup | What to show |
| --- | --- | --- |
| [Tiny LLM](../../demo/llm/README.md) | DRA or device plugin | Application response, allocated devices and logs |
| [DRA](../../demo/dra/README.md) | Default | Published devices and claim allocation |
| [Allocation lifecycle](../../demo/allocation/README.md) | Default | Allocation, release and subsequent reuse |
| [Multi-GPU](../../demo/multi-gpu/README.md) | See demo allocator requirements | Multiple distinct devices in a workload |
| [Same-GPU slices](../../demo/partition-allocation/README.md) | Fresh DPX/NPS2 installation | Two containers receive different partitions of one physical parent |
| [Virtual partition controls](../../demo/partitioning/README.md) | Default SPX | Dashboard representation; does not create schedulable slices |
| [Profiles](../../demo/profiles/README.md) | See demo | GPU model inventory and topology |
| [Fault injection](../../demo/faults/README.md) | Default | ECC, overheating and recovery visibility |
| [Telemetry](../../demo/telemetry/README.md) | Default | Real exporter, Prometheus and Grafana |
| [GPU + NIC](../../demo/gpu-network/single-node/README.md) | Optional prepared ERNIC worker | Real GPU and NIC allocation paths for one application |
| [Two-worker RDMA](../../demo/gpu-network/two-node/README.md) | In development | CPU-buffer transfer and checksums; no validated payload PASS yet |
