"""Tiny LLM presentation: scripted output, real Kubernetes device allocation."""
import glob
import json
import os
import stat
from http.server import BaseHTTPRequestHandler, HTTPServer


def evidence():
    paths = ["/dev/kfd", "/dev/infiniband/uverbs0", "/dev/infiniband/rdma_cm"]
    renders = sorted(glob.glob("/dev/dri/renderD*"))
    assert len(renders) == 1, f"Expected one allocated render node: {renders}"
    devices = {}
    for path in paths + renders:
        info = os.stat(path)
        assert stat.S_ISCHR(info.st_mode), f"Not a character device: {path}"
        devices[path] = {"major": os.major(info.st_rdev), "minor": os.minor(info.st_rdev)}
    nic = os.environ["PCIDEVICE_AMD_COM_NIC"]
    nic_info = json.loads(os.environ["PCIDEVICE_AMD_COM_NIC_INFO"])
    rdma_devices = sorted(os.path.basename(p) for p in glob.glob("/sys/class/infiniband/*"))
    assert nic_info[nic]["rdma"]["rdma_dev"] in rdma_devices, "Allocated RDMA device is missing from sysfs"
    return {"node": os.environ["NODE_NAME"], "devices": devices,
            "nic_pci": nic, "nic_info": nic_info, "rdma_devices": rdma_devices, "compute": "scripted simulation"}


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, body):
        encoded = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        self.end_headers()
        self.wfile.write(encoded)

    def do_GET(self):
        if self.path != "/healthz":
            self.reply(404, {"error": "unknown endpoint"})
            return
        self.reply(200, evidence())

    def do_POST(self):
        if self.path != "/generate":
            self.reply(404, {"error": "unknown endpoint"})
            return
        try:
            size = int(self.headers.get("Content-Length", "0"))
            if size < 1 or size > 4096:
                raise ValueError("request must contain 1–4096 bytes")
            payload = json.loads(self.rfile.read(size))
            prompt = payload["prompt"]
            if not isinstance(prompt, str):
                raise ValueError("prompt must be a string")
        except (ValueError, KeyError) as error:
            self.reply(400, {"error": str(error)})
            return
        response = {"prompt": prompt, "text": prompt + " bright and full of possibilities",
                    "simulation": True, "allocation": evidence()}
        print("SIMULATED_RESPONSE " + json.dumps(response), flush=True)
        self.reply(200, response)


if __name__ == "__main__":
    print("DEVICE_EVIDENCE " + json.dumps(evidence()), flush=True)
    print("Tiny LLM simulation: GPU allocated by AMD DRA; NIC allocated by AMD Network Operator.", flush=True)
    print("No model weights, GPU compute, or RDMA transfer is performed.", flush=True)
    HTTPServer(("0.0.0.0", 8000), Handler).serve_forever()
