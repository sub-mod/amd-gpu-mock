#!/usr/bin/env python3
"""GPU+ERNIC allocation, NIC exhaustion and release using the real project demo."""
import json
import os
import pathlib
import subprocess
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
CONTEXT = os.environ.get("KUBE_CONTEXT", "kind-amd-mock")
NS = os.environ.get("DEMO_NAMESPACE", "amd-demo-gpu-network")
K = ["kubectl", "--context", CONTEXT, "-n", NS]


def command(*args):
    return subprocess.check_output(K + list(args), text=True)


subprocess.run([str(ROOT / "demo/gpu-network/single-node/run.sh")], check=True)
pod = json.loads(command("get", "pod", "tiny-llm-gpu-network", "-o", "json"))
code = '''import os,pathlib
pci=os.environ["PCIDEVICE_AMD_COM_NIC"]
p=pathlib.Path("/sys/bus/pci/devices")/pci
assert (p/"vendor").read_text().strip()=="0x1dd8"
assert (p/"device").read_text().strip()=="0x1002"
assert (p/"driver").resolve().name=="ionic"
print(pci)
'''
first_nic = command("exec", "tiny-llm-gpu-network", "--", "python3", "-c", code).strip()
print("PASS: real ERNIC PCI device", first_nic, "bound to ionic", flush=True)
pod["metadata"] = {"name": "tiny-llm-network-second", "namespace": NS}
pod.pop("status", None)
pod["spec"].pop("nodeName", None)
for container in pod["spec"]["containers"]:
    container.pop("ports", None)  # Do not let host-port filtering mask NIC exhaustion.
    container["readinessProbe"]["httpGet"]["port"] = 8000
subprocess.run(K + ["create", "-f", "-"], input=json.dumps(pod), text=True, check=True)
for _ in range(60):
    events = json.loads(command("get", "events", "--field-selector",
                                "involvedObject.name=tiny-llm-network-second", "-o", "json"))
    if any("Insufficient amd.com/nic" in e.get("message", "") for e in events["items"]):
        break
    time.sleep(2)
else:
    raise AssertionError("No genuine NIC exhaustion scheduling event")
assert json.loads(command("get", "pod", "tiny-llm-network-second", "-o", "json"))["status"]["phase"] == "Pending"
print("PASS: second Pod Pending: Insufficient amd.com/nic", flush=True)
subprocess.run(K + ["delete", "pod", "tiny-llm-gpu-network", "--wait=true"], check=True)
subprocess.run(K + ["wait", "--for=condition=Ready", "pod/tiny-llm-network-second", "--timeout=300s"], check=True)
subprocess.run(["python3", str(ROOT / "demo/gpu-network/single-node/verify.py")],
               env=dict(os.environ, DEMO_POD="tiny-llm-network-second"), check=True)
second_nic = command("exec", "tiny-llm-network-second", "--", "python3", "-c", code).strip()
assert second_nic == first_nic
print("PASS: released ERNIC NIC reused by second GPU+DRA workload", flush=True)
