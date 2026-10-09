# Fresh deployment record and walkthrough

On 2026-10-08, the previous Kind cluster and both ERNIC workers were removed.
A new Kind control plane and a new default ERNIC worker were created using the
published repository commands. The default Podman libkrun machine and cached
images were retained. This was a fresh Kubernetes installation and worker disk,
not a cold-cache download benchmark or a Podman-machine rebuild.

The run used upstream commit `d3dcba79ff4a727bfa711dc624770a4de1531957`, Kind node
image `0.2.2`, GPU chart `0.2.12`, and prepared worker/lab images `0.1.0`.
No local builds, source edits, manual guest changes or recovery flags were used.
Image digests are recorded in the [artifact inventory](../../../artifacts/ernic-worker/published-images.json).

## 1. Remove the previous demo environment

For the standard worker, the published cleanup command is:

```bash
./scripts/ernic/cleanup.sh
helm uninstall amd-gpu-mock --namespace amd-mock
kind delete cluster --name amd-mock
```

Worker cleanup deletes the application namespace, drains/deletes its Kubernetes
node, then shuts down/removes the lab container. Deleting Kind removes its
control plane and the Network Operator release inside that cluster. Stop any
additional ERNIC workers with their corresponding cleanup overrides first.
This run also removed a previous prepared-worker experiment; those lab-specific
overrides are recorded in the local session notes and are not needed for a
standard single-worker installation.

Cleanup preserves VM state. In this run the default `tmp/ernic/` directory did
not exist, so the next setup created a new writable disk and SSH identity.
If that directory exists and you want a fresh worker disk, archive it **after
stopping its worker**, before setup. For example:

```bash
# Only after cleanup has stopped the worker using this directory:
mv tmp/ernic "tmp/ernic-previous-$(date +%Y%m%d-%H%M%S)"
```

That conditional archive command describes how to repeat a fresh-disk run; it
was unnecessary in this captured run. Keeping the previous disk is useful for
inspection, but does not represent a fresh guest installation.

## 2. Run the published quick start

From the repository root:

```bash
export KIND_EXPERIMENTAL_PROVIDER=podman
kind create cluster --name amd-mock \
  --image docker.io/submod/amd-mock-kind-node:0.2.2 \
  --config deployments/kind-node/kind-config.yaml

helm install amd-gpu-mock oci://docker.io/submod/amd-gpu-mock \
  --version 0.2.12 --namespace amd-mock --create-namespace
```

The control plane is recreated, and the GPU mock/DRA and telemetry workloads
start. `helm install` without `--wait` can report `deployed` while Pods are still
starting. The dashboard and Grafana become accessible as their Pods become Ready.

## 3. Add the worker, then start the application

```bash
./scripts/ernic/setup.sh
./demo/gpu-network/single-node/run.sh
```

Setup creates the guest, verifies the NIC's RDMA interface, joins Kubernetes,
installs the Network Operator/NFD, waits for the NIC plugin, and upgrades the
GPU release with worker selectors. Its successful final marker is:

```text
Worker ready. Run ./demo/gpu-network/single-node/run.sh
```

**No Tiny LLM Pod exists until `run.sh` is invoked.** The runner creates the
namespace, ConfigMap, GPU claim template, Pod and Service. It waits up to five
minutes for Pod readiness, dumps logs and verifies the devices and HTTP response.

In this particular session, the runner was invoked while setup was finishing
its exporter readiness wait, after GPU/NIC resources were already advertised.
Both commands completed successfully. For repeatable normal use, follow the
sequential commands above; overlapping them is not a required setup step.

## 4. Understand the visible states

The [numbered architecture flow](../../../docs/guides/gpu-network.md#how-the-application-gets-its-devices)
explains stages 1–8, including the distinction between hardware visibility,
resource advertisement, scheduling and container device allocation.

| What you see | Meaning and next action |
| --- | --- |
| `Booting guest; waiting for SSH` | QEMU TCG is booting the prepared disk and initializing a new guest identity. Monitor setup; no application Pod exists yet. |
| `hca_id: rocep0s4`, `PORT_ACTIVE` | Guest drivers can see one active emulated RDMA port. This is before Pod allocation. |
| Worker `NotReady`, then `Ready` | The node registered; initial CNI Pods and configuration must finish. |
| `amd-nic=true`, but no `amd.com/nic` | PCI discovery succeeded; the operator/plugin still needs to advertise the resource. |
| `amd.com/nic: 1` plus worker ResourceSlice | NIC and GPU resources are advertised to Kubernetes. No application is created by this state alone. |
| App `Pending` | Inspect scheduling events and resource availability. Another consumer of the only NIC can prevent scheduling. |
| App `ContainerCreating` with allocated claim | The Pod has been assigned; image pulls and container preparation may still be running. |
| App `1/1 Running`, `DEVICE_EVIDENCE`, verifier `PASS` | Both device paths and the scripted HTTP response have been checked. |

At container preparation, kubelet calls the NIC plugin's `Allocate` method;
the operator itself does not allocate the NIC to the application. Seeing a NIC
in guest or host-network Pod sysfs alone is not proof of this allocation.
Node Allocatable remains `1` even while the Pod consumes the only NIC; scheduling
accounts for requests separately.

## 5. Inspect the demo without changing the environment

These are diagnostic commands, not additional installation steps. During the
session they were repeated to observe progress; polling is not necessary to
provision the environment.

```bash
kubectl get nodes
helm list -A
kubectl -n kube-amd-network get networkconfig,daemonsets,pods
kubectl get resourceslices
kubectl describe node amd-ernic-worker-1
kubectl -n amd-demo-gpu-network get pods,resourceclaims -o wide
kubectl -n amd-demo-gpu-network get events --sort-by=.lastTimestamp
kubectl -n amd-demo-gpu-network logs tiny-llm-gpu-network
```

To repeat the allocation/HTTP verification on the running Pod:

```bash
python3 demo/gpu-network/single-node/verify.py
```

For setup progress, inspect `tmp/ernic/worker-console.log`, `guest-setup.log`,
`join.log`, `ernic.log` and `qemu.log`. Kubernetes events and containerd logs were
also inspected during this run. No configuration was changed through those
checks. Keep private SSH keys and bootstrap files out of published logs.

## Actual results and startup observations

| Result | Captured evidence |
| --- | --- |
| Prepared artifact, guest RDMA discovery, cluster join, network installation and GPU Helm upgrade | [fresh-cluster-setup.log](fresh-cluster-setup.log) |
| Pod creation, claim/ResourceSlice/render-device identity, NIC metadata and HTTP response | [fresh-cluster-demo.log](fresh-cluster-demo.log) |

The captures are actual command output, not reconstructed examples. They cover
the ERNIC setup and demo runner; the earlier cleanup/Kind/initial Helm output
was observed in the session and is summarized here, not claimed as a saved
complete terminal transcript. Guest/application timestamps use UTC; Helm output
uses the Mac's local time (America/New_York).

During first control-plane startup, DRA initialization briefly failed in a
runtime hook while the mock agent was still preparing its sysfs view. It cleared
on retry without intervention. An early 50-second readiness observation timed
out; all quick-start Pods subsequently became Ready. That diagnostic timeout did
not terminate or repair setup. On the fresh worker, image pulls and mock sysfs
initialization also caused temporary `ContainerCreating`/mount-wait states.
The application's Python image pull took 51.52 seconds in this run. These are
observations from this run, not guaranteed timings or reasons to ignore a
persistent failure. If a script reaches its timeout, retain its logs and inspect
the failing Pod's events before retrying.

The final application ran on `amd-ernic-worker-1`, with GPU `gpu-0-128` mapped
to `/dev/dri/renderD128`, NIC PCI `0000:00:04.0` mapped to RDMA device `rocep0s4`,
and both RDMA character devices present. Its HTTP response was:

```text
The future of AI is bright and full of possibilities
```

The verifier reported `PASS`. All cluster Pods were Ready at final inspection.
Dashboard `http://localhost:8080` and Grafana `http://localhost:3000/login`
returned HTTP 200; Grafana login is `admin` / `amdmock`. This confirms allocation
and a scripted application response, not GPU computation or RDMA data transfer.
The environment was left running for inspection.
