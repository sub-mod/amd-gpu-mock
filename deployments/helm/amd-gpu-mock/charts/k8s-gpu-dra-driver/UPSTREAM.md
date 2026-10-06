Vendored from ROCm/k8s-gpu-dra-driver v1.0.0 at
7bf0efa6704371a928b533fce8b33993631bdb8a, under its Apache-2.0 license.

Packaging changes: normalize chart version, set appVersion to v1.0.0, and
make the sys hostPath configurable as mockSysPath. The parent chart supplies
the published multiarch image. No AMD driver Go source is modified.
