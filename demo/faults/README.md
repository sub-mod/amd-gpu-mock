# Dashboard failure injection

Open the mock dashboard and Grafana side by side. Use the buttons directly,
or run the equivalent actions:

```bash
python3 demo/run.py faults --gpu 0 --action overheat
python3 demo/run.py faults --gpu 0 --action recover
python3 demo/run.py faults --gpu 0 --action ecc-error
python3 demo/run.py faults --gpu 0 --action recover
python3 demo/run.py faults --gpu 0 --action busy
python3 demo/run.py faults --gpu 0 --action idle
python3 demo/run.py faults --gpu 0 --action crash
python3 demo/run.py faults --gpu 0 --action recover
```

Overheat and ECC buttons toggle; Recover explicitly resets healthy state.
Dashboard changes reach the same device state read by mock AMD SMI, real AMD
GPU Agent and real exporter. Grafana follows the collection/scrape interval.
Busy/idle also change activity, clocks, power and used VRAM.

Crash removes mock discovery bindings and host card/render nodes and zeroes
power/activity/clocks. It does not simulate an AMD SMI device-lost return or
kill an existing workload. DRA does not promise live health propagation or
claim revocation; device-plugin fault tests use explicit restart/rediscovery.
No automatic alert rules or remediation are installed. See the
[ASCII fault path](../../docs/architecture.md#dashboard-failures-two-paths-different-consequences).
