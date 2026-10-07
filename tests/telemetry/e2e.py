#!/usr/bin/env python3
"""Exercise real AMD exporter -> Prometheus -> Grafana and the SMI state bridge."""
import base64
import json
import os
import time
import urllib.parse
import urllib.request

PROM = os.environ.get("PROMETHEUS_URL", "http://localhost:9090")
GRAFANA = os.environ.get("GRAFANA_URL", "http://localhost:3000")
MOCK = os.environ.get("MOCK_URL", "http://localhost:8080")
PASSWORD = os.environ.get("GRAFANA_ADMIN_PASSWORD", "amdmock")
AUTH = "Basic " + base64.b64encode(("admin:" + PASSWORD).encode()).decode()


def request(base, path, data=None, method=None, auth=False):
    headers = {"Content-Type": "application/json"}
    if auth:
        headers["Authorization"] = AUTH
    req = urllib.request.Request(base + path, None if data is None else json.dumps(data).encode(), headers, method=method)
    with urllib.request.urlopen(req, timeout=15) as response:
        return json.load(response)


def query(expr):
    response = request(PROM, "/api/v1/query?" + urllib.parse.urlencode({"query": expr}))
    assert response["status"] == "success", response
    return response["data"]["result"]


def wait(check, label, timeout=120):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            result = check()
            if result:
                print("PASS " + label, flush=True)
                return result
        except (AssertionError, OSError, KeyError) as error:
            last = str(error)
        time.sleep(2)
    raise AssertionError(label + " timed out: " + str(last))


def main():
    gpus = request(MOCK, "/api/gpus")["gpus"]
    assert gpus, "mock fleet is empty"
    count = len(gpus)
    temperatures = wait(lambda: (r if len(r := query("amd_gpu_edge_temperature")) == count else None), "real AMD exporter GPU count")
    ids = {r["metric"]["gpu_id"] for r in temperatures}
    assert ids == {str(g["index"]) for g in gpus}, ids
    assert all(r["metric"]["card_model"] == gpus[0]["name"] for r in temperatures)
    assert len({r["metric"]["serial_number"] for r in temperatures}) == count
    assert all(0 < float(r["value"][1]) < 120 for r in temperatures)
    print("PASS GPU identities, model, serials and temperature units")
    for metric in ["amd_gpu_package_power", "amd_gpu_gfx_activity", "amd_gpu_used_vram", "amd_gpu_ecc_uncorrect_total"]:
        assert len(query(metric)) == count, metric
    total = query("amd_gpu_total_vram")
    assert len(total) == count
    assert all(float(r["value"][1]) == gpus[int(r["metric"]["gpu_id"])]["memory_total_mb"] for r in total)
    clocks = query('avg by (gpu_id) (amd_gpu_clock{clock_type="system"})')
    assert len(clocks) == count and all(float(r["value"][1]) > 0 for r in clocks), clocks
    print("PASS power, utilization, ECC, clocks and VRAM values/units")
    def healthy_targets():
        targets = request(PROM, "/api/v1/targets")["data"]["activeTargets"]
        targets = [t for t in targets if "metrics-exporter" in t["labels"].get("service", "")]
        return targets if targets and all(t["health"] == "up" for t in targets) else None
    wait(healthy_targets, "exporter ServiceMonitor target is UP")
    original = gpus[0]["ecc_errors"]
    assert gpus[0]["status"] == "healthy", "run fault test with GPU 0 healthy"
    try:
        request(MOCK, "/api/actions/ecc-error?gpu=0", method="POST")
        wait(lambda: any(float(r["value"][1]) == original + 1 for r in query('amd_gpu_ecc_uncorrect_total{gpu_id="0"}')), "dashboard ECC action reaches Prometheus through AMD SMI")
    finally:
        request(MOCK, "/api/actions/ecc-error?gpu=0", method="POST")
    wait(lambda: any(float(r["value"][1]) == original for r in query('amd_gpu_ecc_uncorrect_total{gpu_id="0"}')), "ECC recovery reaches Prometheus")
    def matches(metric, check):
        return any(check(float(r["value"][1])) for r in query(metric))

    # Exercise the exact dashboard endpoints, with recovery even on failure.
    actions = [
        ("overheat", [("amd_gpu_edge_temperature", lambda v: v == 105)]),
        ("busy", [("amd_gpu_gfx_activity", lambda v: v >= 40), ("amd_gpu_package_power", lambda v: v > 0), ("amd_gpu_used_vram", lambda v: v == gpus[0]["memory_total_mb"] * 70 // 100)]),
        ("idle", [("amd_gpu_gfx_activity", lambda v: 0 <= v <= 7), ("amd_gpu_used_vram", lambda v: v == gpus[0]["memory_used_mb"])]),
        ("crash", [("amd_gpu_package_power", lambda v: v == 0), ("amd_gpu_gfx_activity", lambda v: v == 0)]),
        ("recover", [("amd_gpu_edge_temperature", lambda v: 0 < v < 95), ("amd_gpu_package_power", lambda v: v > 0)]),
    ]
    try:
        for action, fields in actions:
            request(MOCK, "/api/actions/" + action + "?gpu=0", method="POST")
            wait(lambda: all(matches(metric + '{gpu_id="0"}', check) for metric, check in fields), "dashboard " + action + " reaches Prometheus through AMD SMI")
    finally:
        request(MOCK, "/api/actions/recover?gpu=0", method="POST")
    dashboard = wait(lambda: request(GRAFANA, "/api/dashboards/uid/amd-real-exporter", auth=True), "Grafana dashboard provisioned")["dashboard"]
    datasource = request(GRAFANA, "/api/datasources/name/Prometheus", auth=True)
    for panel in dashboard["panels"]:
        for target in panel.get("targets", []):
            expr = target["expr"]
            assert "amd_gpu_" in expr, expr
            response = request(GRAFANA, "/api/ds/query", {"from": "now-5m", "to": "now", "queries": [{"refId": "A", "expr": expr, "instant": True, "format": "table", "datasource": {"type": "prometheus", "uid": datasource["uid"]}, "intervalMs": 1000, "maxDataPoints": 1000}]}, auth=True)
            result = response["results"]["A"]
            assert not result.get("error"), result
            assert any(frame.get("data", {}).get("values") and any(frame["data"]["values"]) for frame in result.get("frames", [])), (panel["title"], result)
    print("PASS every Grafana panel obtains real exporter data through its Prometheus datasource")


if __name__ == "__main__":
    main()
