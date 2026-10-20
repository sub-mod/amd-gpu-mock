# Captured experiment evidence

These are actual outputs from this branch on an ARM64 Mac's default Podman VM
(Fedora kernel 7.1.3-200.fc44.aarch64) and a dedicated Kind Kubernetes v1.37.0
cluster. Image/source provenance is in ../published-images.json and ../versions.env.
No captured output is printed as a substitute for executing the live test.

| File | Meaning |
| --- | --- |
| native-probe.log | Native open, original-profile capacity and negative ABI cases |
| raw-ioctl.log | Genuine CUSE device rejects unsupported raw ioctl |
| smi-abi.log | Original full C ABI regression suite with BDF lookup coverage |
| identity-before.log | New KFD decimal-ID regression fails on untouched original main |
| smi-before.log | BDF identity regression fails against original NOT_SUPPORTED backend |
| go-regression.log | go test ./... after the shared corrections |
| fresh-setup.log | Clean dedicated-cluster/volume setup using published images, no build |
| fresh-e2e.log | Two same-GPU shares, budget exhaustion and reuse |
| fresh-lifecycle.log | Plugin replacement and fault -> allocatable zero -> recovery |

The two "before" failures are deliberate executions of the new compatibility
checks against the original unchanged source, not regressions injected into
HAMi or the mock. They document the gap addressed by the shared commits.

The images were also queried through anonymous Docker Hub registry access and
confirmed ARM64 at the published digests. This does not establish AMD64 support,
CRC compatibility, real VRAM isolation, compute throttling or GPU execution.

The development pass exposed and corrected a setup adapter assumption: kubectl
client-side conversion emits concatenated JSON objects for multiple YAML
documents. The final adapter decodes that stream instead of assuming one List.
Only a completed final clean-install log is labeled fresh-setup here.
