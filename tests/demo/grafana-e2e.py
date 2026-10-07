#!/usr/bin/env python3
"""Check the default host-exposed Grafana and its real AMD metric queries."""
import base64
import json
import os
import time
import urllib.request

BASE = os.environ.get("GRAFANA_URL", "http://localhost:3000")
PASSWORD = os.environ.get("GRAFANA_ADMIN_PASSWORD", "amdmock")
COUNT = int(os.environ.get("EXPECTED_GPU_COUNT", "8"))
AUTH = "Basic " + base64.b64encode(("admin:" + PASSWORD).encode()).decode()


def get(path, payload=None):
    req = urllib.request.Request(BASE + path, None if payload is None else json.dumps(payload).encode(),
                                 {"Authorization": AUTH, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as response:
        return json.load(response)


def wait(check, label):
    end = time.monotonic() + 180
    last = None
    while time.monotonic() < end:
        try:
            result = check()
            if result:
                print("PASS " + label, flush=True)
                return result
        except (OSError, KeyError, AssertionError) as error:
            last = str(error)
        time.sleep(2)
    raise AssertionError(label + ": " + str(last))


def query(expr):
    response = get("/api/ds/query", {"from": "now-5m", "to": "now", "queries": [{
        "refId": "A", "expr": expr, "instant": True, "format": "table",
        "datasource": {"type": "prometheus", "uid": "prometheus"},
        "intervalMs": 1000, "maxDataPoints": 1000}]})["results"]["A"]
    assert not response.get("error"), response
    return response.get("frames", [])


def gpu_count():
    for frame in query("count(amd_gpu_edge_temperature)"):
        for field, values in zip(frame["schema"]["fields"], frame["data"]["values"]):
            if field["type"] == "number" and COUNT in values:
                return True
    return False


wait(lambda: get("/api/health").get("database") == "ok", "Grafana host access without port-forward")
dashboard = wait(lambda: get("/api/dashboards/uid/amd-real-exporter"), "AMD dashboard provisioned by default")["dashboard"]
assert dashboard.get("refresh") == "5s", "GPU dashboard must refresh automatically"
print("PASS automatic 5-second dashboard refresh", flush=True)
wait(gpu_count, "real AMD exporter GPU count through built-in Prometheus")
for panel in dashboard["panels"]:
    for target in panel.get("targets", []):
        wait(lambda: any(any(values for values in frame["data"]["values"]) for frame in query(target["expr"])),
             "Grafana panel: " + panel["title"])
