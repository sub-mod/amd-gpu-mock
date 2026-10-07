#!/usr/bin/env python3
"""Presenter-friendly demos using the installed mock, with isolated namespaces."""
import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parent.parent
COMMANDS = {
    "llm": "Scripted Tiny LLM: GPU scheduling and device injection (both allocators)",
    "partitioning": "SPX/DPX/QPX/CPX dashboard state; physical allocation stays unchanged",
    "dra": "ResourceSlice -> claim -> CDI -> one-GPU consumer",
    "faults": "Overheat, ECC, crash, busy, idle and recover from the dashboard API",
    "multi-gpu": "One container with two GPUs, or concurrent independent consumers",
    "allocation": "Delete a consumer, release its generated claim, then allocate again",
    "telemetry": "Real AMD exporter metrics queried through the provisioned Grafana",
    "profiles": "Show the GPU profile catalog and installed physical inventory",
    "cleanup": "Delete only namespaces owned by these demos and recover mock state",
}
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("command", choices=["list", *COMMANDS])
parser.add_argument("--config", default=str(ROOT / "demo/config.yaml"))
parser.add_argument("--context", default=os.environ.get("DEMO_CONTEXT", "kind-" + os.environ.get("CLUSTER_NAME", "amd-mock")))
parser.add_argument("--allocator", choices=["auto", "dra", "device-plugin"], default="auto")
parser.add_argument("--gpu", type=int, default=0)
parser.add_argument("--action", choices=["overheat", "ecc-error", "crash", "busy", "idle", "recover"], default="overheat")
parser.add_argument("--mode", choices=["SPX", "DPX", "QPX", "CPX"], default="CPX")
parser.add_argument("--count", type=int, default=2)
parser.add_argument("--replicas", type=int, default=1)
args = parser.parse_args()


def k(*cmd, obj=None, check=True):
    result = subprocess.run(["kubectl", "--context", args.context, *cmd],
                            input=None if obj is None else json.dumps(obj), text=True,
                            capture_output=True)
    if check and result.returncode:
        raise RuntimeError(result.stderr.strip())
    return result.stdout


def apply(obj):
    return k("apply", "-f", "-", obj=obj)


def ns(name):
    name = "amd-demo-" + name
    apply({"apiVersion": "v1", "kind": "Namespace", "metadata": {"name": name,
           "labels": {"amd-gpu-mock/demo": "true"}}})
    return name


def allocator():
    if args.allocator != "auto":
        return args.allocator
    if k("get", "ds/amd-gpu-mock-dra-kubeletplugin", "-n", "amd-mock", "--ignore-not-found").strip():
        return "dra"
    nodes = json.loads(k("get", "nodes", "-o", "json"))["items"]
    if any(int(n["status"].get("allocatable", {}).get("amd.com/gpu", "0")) for n in nodes):
        return "device-plugin"
    raise RuntimeError("No allocator detected. Run demo/setup.sh first.")


def settings():
    rendered = subprocess.check_output(["helm", "template", "kind", str(ROOT / "deployments/kind-node/config-chart"),
                                       "-f", args.config, "--show-only", "templates/runtime.json"], text=True)
    return json.loads(rendered[rendered.index("{"):])


def request(url, path, method=None, data=None, password=None):
    headers = {"Content-Type": "application/json"}
    if password is not None:
        headers["Authorization"] = "Basic " + base64.b64encode(("admin:" + password).encode()).decode()
    req = urllib.request.Request(url + path, None if data is None else json.dumps(data).encode(), headers, method=method)
    with urllib.request.urlopen(req, timeout=20) as response:
        return json.load(response)


def mock(path, method=None):
    cfg = settings()
    if not cfg["mockDashboardEnabled"]:
        raise RuntimeError("The mock host dashboard/API is disabled in this config.")
    return request(os.environ.get("MOCK_URL", cfg["mockURL"]), path, method)


def consumer(namespace, name, mode, count=1):
    container = {"name": "consumer", "image": "docker.io/library/busybox:1.36",
                 "command": ["sh", "-c", "test -c /dev/kfd; ls -l /dev/kfd /dev/dri; sleep 3600"]}
    spec = {"restartPolicy": "Never", "terminationGracePeriodSeconds": 0, "containers": [container]}
    if mode == "dra":
        apply({"apiVersion": "resource.k8s.io/v1", "kind": "ResourceClaimTemplate",
               "metadata": {"name": name, "namespace": namespace},
               "spec": {"spec": {"devices": {"requests": [{"name": "gpu", "exactly": {
                   "deviceClassName": "gpu.amd.com", "count": count}}]}}}})
        spec["resourceClaims"] = [{"name": "gpu", "resourceClaimTemplateName": name}]
        container["resources"] = {"claims": [{"name": "gpu"}]}
    else:
        container["resources"] = {"limits": {"amd.com/gpu": count}}
    apply({"apiVersion": "v1", "kind": "Pod", "metadata": {"name": name, "namespace": namespace}, "spec": spec})
    k("wait", "pod/" + name, "-n", namespace, "--for=condition=Ready", "--timeout=180s")
    devices = k("exec", name, "-n", namespace, "--", "sh", "-c", "test -c /dev/kfd && ls /dev/dri/renderD*").splitlines()
    if len(devices) != count:
        raise RuntimeError("Expected %d render devices, got %r" % (count, devices))
    print(k("logs", name, "-n", namespace))
    if mode == "dra":
        print(k("get", "resourceclaims", "-n", namespace, "-o", "wide"))
    return devices


def main():
    if args.command == "list":
        for name, description in COMMANDS.items():
            print("%-14s %s" % (name, description))
        return
    if args.command == "llm":
        mode = allocator()
        namespace = ns("llm")
        k("apply", "-n", namespace, "-f", str(ROOT / "demo/llm" / (mode + ".yaml")))
        deployment = "tiny-llm-dra-demo" if mode == "dra" else "tiny-llm-demo"
        k("rollout", "status", "deployment/" + deployment, "-n", namespace, "--timeout=180s")
        time.sleep(5)  # Let scripted model-loading messages appear.
        print(k("logs", "deployment/" + deployment, "-n", namespace, "--tail=70"))
        print("Scripted output only: no model weights or GPU inference.")
    elif args.command == "dra":
        if allocator() != "dra":
            raise RuntimeError("This demo requires the DRA installation.")
        namespace = ns("dra")
        k("apply", "-n", namespace, "-f", str(ROOT / "demo/dra/claim.yaml"))
        k("wait", "pod/dra-gpu-demo", "-n", namespace, "--for=condition=Ready", "--timeout=180s")
        print(k("get", "resourceslices"))
        print(k("get", "resourceclaims", "-n", namespace, "-o", "yaml"))
        print(k("logs", "dra-gpu-demo", "-n", namespace))
    elif args.command == "multi-gpu":
        if args.count < 1 or args.replicas < 1:
            raise RuntimeError("--count and --replicas must be positive")
        mode = allocator()
        namespace = ns("multi-gpu")
        for index in range(args.replicas):
            consumer(namespace, "consumer-%d" % index, mode, args.count)
        print("Each independent request receives its own physical GPU allocation.")
    elif args.command == "allocation":
        mode = allocator()
        namespace = ns("allocation")
        consumer(namespace, "first", mode)
        print("Deleting first consumer; returning allocation to the pool...")
        k("delete", "pod/first", "-n", namespace, "--wait=true", "--timeout=120s")
        if mode == "dra":
            # Wait for the generated claim's owner-based garbage collection.
            deadline = time.monotonic() + 120
            while json.loads(k("get", "resourceclaims", "-n", namespace, "-o", "json"))["items"]:
                if time.monotonic() > deadline:
                    raise RuntimeError("Generated claim cleanup timed out")
                time.sleep(2)
        consumer(namespace, "second", mode)
        print("PASS: allocation works after release (not a promise of the same GPU).")
    elif args.command == "partitioning":
        print(json.dumps(mock("/api/partitions/set?mode=" + args.mode, "POST"), indent=2))
        print("Virtual dashboard entries only; allocator capacity remains physical. Reset with --mode SPX.")
    elif args.command == "faults":
        print(json.dumps(mock("/api/actions/" + args.action + "?gpu=" + str(args.gpu), "POST"), indent=2))
        print("Watch the mock dashboard and Grafana. Recover with --action recover.")
        print("Fault injection does not automatically revoke claims or restart workloads.")
    elif args.command == "profiles":
        print("PROFILE    MODEL                     DEVICES  GiB/DEVICE  TDP/W")
        for profile in mock("/api/profiles"):
            print("%-10s %-25s %7d %11d %6d" % (profile["slug"], profile["name"],
                  profile["gpu_count"], profile["memory_gb"], profile["tdp_w"]))
        print("\nInstalled inventory:")
        for gpu in mock("/api/gpus")["gpus"]:
            print("GPU %-2d %-13s NUMA=%d %-25s VRAM=%d MiB status=%s" % (
                gpu["index"], gpu["pci_bdf"], gpu["numa_node"], gpu["name"], gpu["memory_total_mb"], gpu["status"]))
        print("Select a different profile at installation; avoid live switches with active consumers.")
    elif args.command == "telemetry":
        cfg = settings()
        if not cfg["grafanaEnabled"]:
            raise RuntimeError("Grafana is disabled in this config.")
        url = os.environ.get("GRAFANA_URL", cfg["grafanaURL"])
        password = os.environ.get("GRAFANA_ADMIN_PASSWORD", cfg["grafanaPassword"])
        dashboard = request(url, "/api/dashboards/uid/amd-real-exporter", password=password)
        print("Dashboard:", dashboard["dashboard"]["title"])
        for metric in ["amd_gpu_edge_temperature", "amd_gpu_ecc_uncorrect_total", "amd_gpu_gfx_activity", "amd_gpu_used_vram"]:
            result = request(url, "/api/ds/query", data={"from": "now-5m", "to": "now", "queries": [{
                "refId": "A", "expr": metric, "instant": True, "format": "table",
                "datasource": {"type": "prometheus", "uid": "prometheus"}, "intervalMs": 1000,
                "maxDataPoints": 1000}]}, password=password)
            if result["results"]["A"].get("error"):
                raise RuntimeError(result)
            print(metric)
            frames = result["results"]["A"].get("frames", [])
            if not frames:
                raise RuntimeError("Metrics not collected yet; retry after the next scrape.")
            for frame in frames:
                for field, values in zip(frame["schema"]["fields"], frame["data"]["values"]):
                    if field["type"] != "number" or not values:
                        continue
                    labels = field.get("labels", {})
                    owner = "/".join(labels.get(key, "") for key in ("namespace", "pod", "container"))
                    print("  GPU %s: %s%s" % (labels.get("gpu_id", "?"), values[-1],
                          "  consumer=" + owner if owner != "//" else ""))
    elif args.command == "cleanup":
        print(k("delete", "namespaces", "-l", "amd-gpu-mock/demo=true", "--wait=true", "--timeout=120s"))
        cfg = settings()
        if cfg["mockDashboardEnabled"]:
            mock("/api/partitions/set?mode=SPX", "POST")
            gpus = mock("/api/gpus")["gpus"]
            for gpu in gpus:
                mock("/api/actions/recover?gpu=" + str(gpu["index"]), "POST")
        print("Demo workloads removed. Mock faults/partition state reset when API is enabled.")


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, OSError, subprocess.CalledProcessError) as error:
        parser.exit(1, "Demo failed: " + str(error) + "\n")
