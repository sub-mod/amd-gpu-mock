#!/usr/bin/env python3
"""Confirm the real AMD exporter attaches labels from kubelet GPU allocations."""
import json
import os
import subprocess
import time
import urllib.parse
import urllib.request

PROM = os.environ.get("PROMETHEUS_URL", "http://localhost:9090")
MODE = os.environ.get("ALLOCATOR", "dra")
assert MODE in ("dra", "device-plugin")
NS = "telemetry-test-" + str(os.getpid())


def kubectl(*args, data=None):
    return subprocess.check_output(["kubectl", *args], input=None if data is None else json.dumps(data).encode()).decode()


def apply(obj):
    kubectl("apply", "-f", "-", data=obj)


try:
    apply({"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": NS}})
    container = {"name": "consumer", "image": "docker.io/library/busybox:1.36", "command": ["sh", "-c", "test -c /dev/kfd && ls /dev/dri/renderD* && sleep 600"]}
    spec = {"terminationGracePeriodSeconds": 0, "restartPolicy": "Never", "containers": [container]}
    if MODE == "dra":
        apply({"apiVersion": "resource.k8s.io/v1", "kind": "ResourceClaimTemplate", "metadata": {"name": "gpu", "namespace": NS}, "spec": {"spec": {"devices": {"requests": [{"name": "gpu", "exactly": {"deviceClassName": "gpu.amd.com"}}]}}}})
        spec["resourceClaims"] = [{"name": "gpu", "resourceClaimTemplateName": "gpu"}]
        container["resources"] = {"claims": [{"name": "gpu"}]}
    else:
        container["resources"] = {"limits": {"amd.com/gpu": 1}}
    apply({"apiVersion": "v1", "kind": "Pod", "metadata": {"name": "gpu-consumer", "namespace": NS}, "spec": spec})
    kubectl("wait", "pod/gpu-consumer", "-n", NS, "--for=condition=Ready", "--timeout=120s")
    logs = kubectl("logs", "gpu-consumer", "-n", NS)
    assert "renderD" in logs, logs
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        expr = 'amd_gpu_edge_temperature{pod="gpu-consumer",namespace="' + NS + '",container="consumer"}'
        url = PROM + "/api/v1/query?" + urllib.parse.urlencode({"query": expr})
        with urllib.request.urlopen(url, timeout=15) as response:
            rows = json.load(response)["data"]["result"]
        if rows:
            assert len(rows) == 1, rows
            print("PASS " + MODE + " allocation -> kubelet pod-resources -> real AMD exporter workload labels", flush=True)
            break
        time.sleep(2)
    else:
        raise AssertionError("allocated GPU metrics lack consumer pod/namespace/container labels")
finally:
    kubectl("delete", "namespace", NS, "--wait=false", "--ignore-not-found")
