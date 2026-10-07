# Real AMD telemetry and workload attribution

Grafana starts with the demo setup at http://localhost:3000, with the dashboard
**AMD GPU Fleet — Device Metrics Exporter** already provisioned.

```bash
python3 demo/run.py llm
python3 demo/run.py telemetry
```

Show temperature, power, activity, VRAM, clocks and ECC. The runner queries
AMD metrics through Grafana's Prometheus datasource. Its output includes
metric labels; find `pod`, `namespace` and `container` for allocated GPUs.
Then inject a fault from the [fault demo](../faults/README.md).

The stack uses real Prometheus and Grafana, and unmodified AMD GPU Agent /
exporter binaries. The mock is at AMD SMI's device API layer. AMD's x86
collector is explicitly emulated on ARM64. This is different from scraping
the node agent's separate diagnostic `/metrics` endpoint. See the
[telemetry guide](../../docs/guides/telemetry.md) for provenance and limits.
