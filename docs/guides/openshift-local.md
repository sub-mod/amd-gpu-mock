# Tiny LLM on OpenShift Local with restricted-v2 SCC

**The Tiny LLM application explicitly requires OpenShift’s `restricted-v2` SCC.**
The verifier checks the admitted Pod’s `openshift.io/scc` annotation. Only the
mock agent and AMD device plugin receive namespace-scoped permission to use the
existing `privileged` SCC; the application receives no privileged grant.

Status: live deployment and clean namespace reinstall passed on October 14, 2026.
Validated on Apple Silicon: CRC 2.64.0, OpenShift 4.22.14, Kubernetes 1.35.6,
ARM64 and CRI-O. See [captured live output](../../demo/openshift/tiny-llm/captured.log).

This separate demo deploys eight mock MI300X GPUs and a scripted Tiny LLM service
using published images. It starts with the real AMD device plugin, rather than
DRA or the GPU Operator. No model weights, ROCm computation, or NIC is involved.

On macOS, OpenShift Local (CRC) runs its own VM through vfkit. It is not a Kind
cluster inside the Podman machine. Podman can remain installed alongside CRC;
OpenShift uses CRI-O inside its VM. CRC does not support nested virtualization.
See the [CRC installation](https://crc.dev/docs/installing/) and
[usage](https://crc.dev/docs/using/) documentation.

```text
macOS Apple Silicon
 |
 +-- Podman machine (separate; not used to host this cluster)
 |
 +-- [1] CRC / vfkit -> ARM64 OpenShift VM
       |
       +-- [2] Mock node agent creates synthetic GPU discovery and device files
       +-- [3] AMD device plugin discovers them and advertises amd.com/gpu: 8
       +-- [4] OpenShift scheduler places Tiny LLM Pod requesting one GPU
       +-- [5] Kubelet / CRI-O inject allocated KFD + one render device
       +-- [6] App verifies character devices and returns scripted HTTP response
```

See the [OpenShift demo sequence](openshift-demos.md) for additional scenarios
and their captured evidence.

## Start CRC

Install CRC with the official macOS installer, plus Helm and Python 3. Use
CRC's bundled oc CLI. Download the Red Hat pull secret to a private local file;
do not paste it into logs or commit it.

```bash
./demo/openshift/tiny-llm/setup.sh
# Override for another local folder or a CI-provided protected file:
# PULL_SECRET_FILE=/absolute/path/to/pull-secret.json ./demo/openshift/tiny-llm/setup.sh
eval "$(crc oc-env --shell bash)"
# Follow CRC's login instructions, with the kubeadmin user.
# Use the kubeadmin login instruction printed by crc start.
# Confirm the selected API is https://api.crc.testing:6443.
oc get nodes
oc get clusteroperators
```

The default pull-secret path is `../crc/pull-secret.txt` relative to the repository
root (the local development CRC folder). `PULL_SECRET_FILE` overrides it for
local development or CI. Never add the secret to source control or artifacts.
The setup script uses the existing CRC configuration; it does not create a
hosted CI deployment.

The existing local CRC configuration uses 8 CPUs, 32 GiB RAM and a 100 GiB disk.
It is not necessary to resize or recreate the Podman machine for this demo.

## Install and show the response

From the repository root, after CRC is running and admin login is established:

```bash
python3 -m venv /tmp/amd-crc-demo-venv
/tmp/amd-crc-demo-venv/bin/pip install PyYAML
/tmp/amd-crc-demo-venv/bin/python demo/openshift/tiny-llm/run.py render
/tmp/amd-crc-demo-venv/bin/python demo/openshift/tiny-llm/run.py install
/tmp/amd-crc-demo-venv/bin/python demo/openshift/tiny-llm/run.py verify
oc -n amd-mock-crc-llm get pods -o wide
oc -n amd-mock-crc-llm logs tiny-llm
```

The adapter renders published chart 0.2.13 and changes only namespace and
OpenShift service-account/SCC settings and the plugin’s `/dev` host mount.
CRI-O requires normal `/dev/null`; the mock agent already stages GPU device files
on host `/dev`. The plugin retains the synthetic sysfs discovery mount. The mock and plugin use a dedicated
service account with namespace-scoped access to the existing privileged SCC.
The application uses the namespace's default service account and requests GPU
resources normally. No global SCC or default service-account grants are added.
SCC admission, ARM64 image execution and CRI-O device injection passed in the
recorded run. The application explicitly requires `restricted-v2` through
`openshift.io/required-scc`, runs non-root, drops capabilities and disables
privilege escalation. It received no
privileged SCC grant. No cluster-wide SELinux policy change was needed.

`DEVICE_EVIDENCE` must show `/dev/kfd` and exactly one `/dev/dri/renderD*`, each
as a character device. `SIMULATED_RESPONSE` shows the prompt, scripted output,
node and allocation evidence. A passing verify command establishes scheduling,
device injection and application response; it does not establish GPU computation.
The captured output includes the actual clean namespace reinstall and HTTP
response, plus upstream plugin discovery logs.

## Clean up

```bash
/tmp/amd-crc-demo-venv/bin/python demo/openshift/tiny-llm/run.py cleanup
crc stop
```

Namespace cleanup removes the demo workloads, not files staged on the VM host.
For a complete reset, `crc delete` deletes the whole CRC VM and all its cluster
data; use it only when you intend to remove the entire local cluster.

During the automated validation session, CRC’s vfkit process stopped when the
startup command session ended. A persistent terminal session kept it running
for the successful reinstall. If the VM unexpectedly stops, check `crc status`
and restart CRC before running the demo; this is separate from GPU allocation.
The recorded reinstall resets the demo namespace, not the whole CRC VM.

The first run also worked under CRC admin’s `anyuid` SCC. Pinning `restricted-v2`
is an application security/portability check, not a GPU-allocation mechanism.
The dedicated mock/node-plugin account still needs the privileged SCC. See
[OpenShift SCC configuration](https://docs.redhat.com/en/documentation/openshift_container_platform/4.22/html/authentication_and_authorization/managing-pod-security-policies).
