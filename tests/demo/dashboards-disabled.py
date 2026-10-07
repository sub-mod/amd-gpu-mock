#!/usr/bin/env python3
"""Ensure disabled dashboards have no host exposure or Grafana workload."""
import json
import os
import subprocess
import time
import urllib.request

ctx = os.environ.get("DEMO_CONTEXT", "kind-amd-mock")
cmd = ["kubectl", "--context", ctx, "-n", "amd-mock"]
service = json.loads(subprocess.check_output(cmd + ["get", "svc/amd-gpu-mock-metrics", "-o", "json"]))
assert service["spec"]["type"] == "ClusterIP"
assert all("nodePort" not in p for p in service["spec"]["ports"])
assert not subprocess.check_output(cmd + ["get", "deploy/amd-gpu-mock-grafana", "--ignore-not-found"]).strip()
for url in [os.environ.get("MOCK_URL", "http://localhost:8080") + "/api/gpus",
            os.environ.get("GRAFANA_URL", "http://localhost:3000") + "/api/health"]:
    deadline = time.monotonic() + 60
    while True:
        try:
            with urllib.request.urlopen(url, timeout=3) as response:
                response.read()
        except OSError:
            print("PASS disabled host dashboard: " + url, flush=True)
            break
        if time.monotonic() >= deadline:
            raise AssertionError("Dashboard remains exposed: " + url)
        time.sleep(2)
