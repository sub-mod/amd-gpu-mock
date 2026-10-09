#!/usr/bin/env python3
"""Assert GPU DRA provenance and NIC allocation on the same worker."""
import json
import os
import subprocess

CONTEXT = os.environ.get("KUBE_CONTEXT", "kind-amd-mock")
NODE = os.environ.get("ERNIC_NODE", "amd-ernic-worker-1")
NS = os.environ.get("DEMO_NAMESPACE", "amd-demo-gpu-network")
POD = os.environ.get("DEMO_POD", "tiny-llm-gpu-network")
BASE = ["kubectl", "--context", CONTEXT]


def get(kind, name):
    return json.loads(subprocess.check_output(BASE + ["-n", NS, "get", kind, name, "-o", "json"]))


pod = get("pod", POD)
assert pod["spec"]["nodeName"] == NODE
assert pod["status"]["phase"] == "Running"
assert pod["spec"]["containers"][0]["resources"]["limits"]["amd.com/nic"] == "1"
claim_name = next(c["resourceClaimName"] for c in pod["status"]["resourceClaimStatuses"] if c["name"] == "gpu")
claim = get("resourceclaim", claim_name)
allocations = claim["status"]["allocation"]["devices"]["results"]
assert len(allocations) == 1
allocation = allocations[0]
assert allocation["driver"] == "gpu.amd.com"
assert allocation["pool"] == NODE
code = '''import json,urllib.request
request=urllib.request.Request("http://127.0.0.1:8000/generate",data=json.dumps({"prompt":"The future of AI is"}).encode(),headers={"Content-Type":"application/json"})
print(urllib.request.urlopen(request,timeout=10).read().decode())'''
response = json.loads(subprocess.check_output(BASE + ["-n", NS, "exec", POD, "--", "python3", "-c", code]))
evidence = response["allocation"]
assert response["simulation"] is True
assert evidence["node"] == NODE
render = f'/dev/dri/renderD{allocation["device"].rsplit("-", 1)[1]}'
assert render in evidence["devices"], (render, evidence)
assert evidence["devices"][render]["major"] == 226
assert evidence["devices"][render]["minor"] == int(render.split("renderD")[1])
assert "/dev/kfd" in evidence["devices"]
nic = evidence["nic_pci"]
assert len(nic.split(",")) == 1
assert evidence["nic_info"][nic]["rdma"]["rdma_dev"] in evidence["rdma_devices"]
assert "/dev/infiniband/uverbs0" in evidence["devices"]
assert "/dev/infiniband/rdma_cm" in evidence["devices"]
slices = json.loads(subprocess.check_output(BASE + ["get", "resourceslices", "-o", "json"]))
matched = [d for s in slices["items"] if s["spec"]["pool"]["name"] == NODE
           for d in s["spec"].get("devices", []) if d["name"] == allocation["device"]]
assert len(matched) == 1
print(json.dumps({"pod": POD, "node": NODE, "claim": claim_name,
                  "gpu_allocation": allocation, "advertised_gpu": matched[0],
                  "response": response}, indent=2))
print("PASS: same worker, AMD DRA claim -> matching injected GPU, Network Operator NIC -> discovered RDMA device, HTTP simulated response")
print("No RDMA transfer, real GPU compute, or GPU-direct DMA was tested.")
