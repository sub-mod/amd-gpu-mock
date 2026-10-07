#!/usr/bin/env python3
"""Exercise presenter commands on a dedicated freshly installed demo cluster."""
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[2]
CTX = os.environ.get("DEMO_CONTEXT", "kind-amd-mock")
CONFIG = os.environ.get("DEMO_CONFIG", str(ROOT / "demo/config.yaml"))
MODE = os.environ.get("ALLOCATOR", "dra")
MOCK = os.environ.get("MOCK_URL", "http://localhost:8080")
GRAFANA = os.environ.get("GRAFANA_URL", "http://localhost:3000")
AUTH = "Basic " + base64.b64encode(("admin:" + os.environ.get("GRAFANA_ADMIN_PASSWORD", "amdmock")).encode()).decode()


def run(command, *args):
    result = subprocess.check_output([sys.executable, str(ROOT / "demo/run.py"), command,
                                      "--context", CTX, "--config", CONFIG, *args], text=True)
    print(result, flush=True)
    print("PASS presenter command: " + command, flush=True)


def k(*args):
    return subprocess.check_output(["kubectl", "--context", CTX, *args], text=True)


def get(path):
    with urllib.request.urlopen(MOCK + path, timeout=10) as response:
        return json.load(response)


def values(expr):
    payload = {"from": "now-5m", "to": "now", "queries": [{"refId": "A", "expr": expr,
               "instant": True, "format": "table", "datasource": {"type": "prometheus", "uid": "prometheus"},
               "intervalMs": 1000, "maxDataPoints": 1000}]}
    req = urllib.request.Request(GRAFANA + "/api/ds/query", json.dumps(payload).encode(),
                                 {"Authorization": AUTH, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=15) as response:
        result = json.load(response)["results"]["A"]
    assert not result.get("error"), result
    return [v for f in result.get("frames", []) for field, vs in zip(f["schema"]["fields"], f["data"]["values"])
            if field["type"] == "number" for v in vs]


def wait(check, label):
    end = time.monotonic() + 180
    while time.monotonic() < end:
        if check():
            print("PASS " + label, flush=True)
            return
        time.sleep(2)
    raise AssertionError(label)


try:
    run("cleanup")
    run("llm")
    if MODE == "dra":
        run("dra")
    run("multi-gpu", "--count", "2")
    run("allocation")
    run("profiles")
    run("telemetry")
    run("faults", "--action", "overheat")
    assert get("/api/gpus")["gpus"][0]["temperature_c"] == 105
    wait(lambda: 105 in values('amd_gpu_edge_temperature{gpu_id="0"}'), "presenter overheat reaches Grafana")
    run("faults", "--action", "recover")
    run("faults", "--action", "ecc-error")
    wait(lambda: 1 in values('amd_gpu_ecc_uncorrect_total{gpu_id="0"}'), "presenter ECC reaches Grafana")
    run("faults", "--action", "recover")
    wait(lambda: 0 in values('amd_gpu_ecc_uncorrect_total{gpu_id="0"}'), "presenter recovery reaches Grafana")
    run("cleanup")
    run("partitioning", "--mode", "CPX")
    assert len(get("/api/gpus")["gpus"]) == 64
    if MODE == "device-plugin":
        nodes = json.loads(k("get", "nodes", "-o", "json"))["items"]
        assert sum(int(n["status"]["allocatable"]["amd.com/gpu"]) for n in nodes) == 8
    run("partitioning", "--mode", "SPX")
    assert len(get("/api/gpus")["gpus"]) == 8
    run("multi-gpu", "--count", "1", "--replicas", "4")
    devices = [k("exec", "consumer-%d" % i, "-n", "amd-demo-multi-gpu", "--", "sh", "-c", "ls /dev/dri/renderD*").strip()
               for i in range(4)]
    assert len(set(devices)) == 4, devices
    print("PASS four independent physical GPU allocations", flush=True)
finally:
    run("cleanup")
