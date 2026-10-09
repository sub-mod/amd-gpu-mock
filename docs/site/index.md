# AMD GPU Mock

Explore AMD GPU allocation, operators, telemetry, and fault injection on CPU-only
Kubernetes nodes. Real Kubernetes components work against synthetic GPU discovery
and management interfaces.

Start with the [quick start](getting-started.md), then
[choose a demo](demos.md). The mock dashboard and Grafana are available through
the quick start's port mappings.

## What you can demonstrate

| Scenario | What it establishes |
| --- | --- |
| DRA | ResourceSlices, selectors, ResourceClaims, CDI injection and claim lifecycle |
| Same-GPU partition allocation | Fixed MI300X DPX/NPS2 siblings allocated through the real AMD DRA driver |
| Device plugin | Whole-GPU allocation through `amd.com/gpu` |
| Telemetry and faults | Dashboard state flowing through mock AMD SMI, the real exporter, Prometheus and Grafana |
| GPU and NIC worker | One application receiving a DRA GPU and an AMD Network Operator NIC |

The GPU mock does not execute HIP kernels, implement DMA, or establish hardware
memory isolation or performance. The Tiny LLM presentation demonstrates application
and allocation integration; it does not prove GPU inference.

## Understand the layers

Read the [architecture diagrams](../architecture.md) and
[mock interface responsibilities](../how-it-works.md) to follow discovery,
allocation, device injection and telemetry. Each demo explains its assertions
and links to recorded output. Historical captures retain their original versions.

## Current scope

The default setup uses Kubernetes 1.37 and DRA. Device-plugin allocation is an
alternative installation mode; the two allocators must not hand out the same
GPU pool simultaneously. Schedulable partitioning uses a fixed startup topology.
The optional two-worker RDMA demo remains in development.

See [testing](../guides/testing.md) for executable checks and validation limits.
This project was inspired by [NVIDIA Mokka](https://github.com/NVIDIA/k8s-test-infra).
