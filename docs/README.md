# Documentation guide

A searchable Material for MkDocs site now brings these guides and demo READMEs
together. See [building and publishing the site](site/maintaining.md) for local
preview and GitHub Pages setup.

The current published setup uses chart **0.2.12**, mock image **v0.2.6**,
node image **0.2.2 / Kubernetes v1.37.0**, AMD DRA **v1.0.0-mock.3** and
exporter **v1.5.2-mock.2**. These components have independent versions.
The root README contains the short installation path; these guides explain
behavior, validation and limits.

| Guide | What it covers |
| --- | --- |
| [How it works](how-it-works.md) | Mock interfaces, allocation and telemetry paths |
| [Architecture](architecture.md) | ASCII component diagrams and fault flow |
| [GPU profiles](profiles.md) | Model inventory, capacities and fidelity limits |
| [DRA](guides/dra.md) | ResourceClaims, allocation, CDI and lifecycle checks |
| [Same-GPU partition allocation](guides/partition-allocation.md) | Fixed MI300X DPX/NPS2, two containers sharing a physical parent, each layer's responsibilities |
| [Device plugin](guides/device-plugin.md) | Alternative whole-GPU allocator setup |
| [Telemetry](guides/telemetry.md) | Mock AMD SMI, real exporter, Prometheus and Grafana |
| [AMD GPU Operator](guides/gpu-operator.md) | Tested Operator components and remaining integration work |
| [GPU/network worker](guides/gpu-network.md) | Prepared ERNIC VM worker, real operator NIC discovery and DRA GPU allocation |
| [Prepared worker artifact](../artifacts/ernic-worker/README.md) | Image contents, pinned inputs, rebuilding and validation |
| [Testing](guides/testing.md) | Local contracts and complete CI suites |
| [Demo room](../demo/README.md) | Presentations, commands, actual captured logs and cleanup |

Default SPX supports the original eight presentations. Fixed DPX/NPS2 requires
a separate fresh startup configuration and provides the ninth, same-GPU
partition-allocation presentation. Virtual dashboard partition changes do not
create schedulable slices. Recorded logs retain the versions used when they
were captured; older chart 0.2.9 captures remain historical evidence.

The optional GPU/network presentation adds a prepared VM worker to Kind. Its
single-node allocation demo is validated; the two-node RDMA transfer demo is
planned separately.
