# Hosted libvirt experiment

The x86-64 `ubuntu-24.04` GitHub runner successfully booted Linux userspace
through libvirt with KVM acceleration on October 14, 2026.

- [Passing run and artifacts](https://github.com/sub-mod/amd-gpu-mock/actions/runs/38637725858)
- Tested source: `9103da1` on `experiment/openshift-libvirt-ci`.
- Probe: `probe-libvirt.sh`; workflow: `.github/workflows/openshift-libvirt-probe.yaml`.
- Transient guest: 1 vCPU, 256 MiB, minimal initramfs, no network or disk.
- Cleanup removed the transient guest and its files.

Captured resource report:

```json
{
  "logical_cpus": 4,
  "host_ram_gib": 15.61,
  "available_disk_gib": 85.78,
  "kvm_device_present": true,
  "sno_planning_budget_met": false,
  "scope": "Host resources only; guest boot is reported separately; OpenShift not tested"
}
```

Captured guest output:

```text
Linux (none) 6.8.0-147-generic #147-Ubuntu SMP PREEMPT_DYNAMIC Thu Sep 24 11:33:16 UTC 2026 x86_64 GNU/Linux
AMD_MOCK_KVM_GUEST_BOOT_OK
PASS: libvirt booted Linux userspace with KVM acceleration
```

## What this establishes

The tested hosted runner exposed `/dev/kvm` and could execute a real Linux VM.
This is not evidence of a running OpenShift cluster, working guest networking,
CRI-O GPU device injection, or parity with AMD CI. Future runner allocations
may differ; retain the probe as a preflight.

## Next deployment requirements

[AMD CI](https://github.com/rh-ecosystem-edge/amd-ci) provisions SNO through kcli
on existing local or remote libvirt hosts. Its default control-plane VM requests
6 vCPUs, 18432 MiB memory and a 120 GB disk. The tested standard runner has less
physical memory than that VM request; a thin disk does not resolve the memory
constraint. The reported 8 CPU/30 GiB/200 GiB planning budget is a conservative
host estimate, not an official OpenShift minimum.

Use a sufficiently sized dedicated Linux/KVM host or configured larger runner
for the next experiment, plus a Red Hat pull secret supplied securely. No
larger paid runner or external host was provisioned by this experiment.

Execution order:

```text
[1] Hosted runner -> libvirt/KVM -> Linux userspace marker       PASS
[2] Sized host + pull secret -> AMD CI/kcli -> Ready SNO        NOT RUN
[3] Mock agent -> AMD device plugin -> kubelet/CRI-O -> Pod     NOT RUN
[4] GPU Operator, DRA, telemetry and NIC integration            NOT RUN
```

Start with the device-plugin allocation baseline in the existing local
OpenShift adapter, then validate each additional layer. OpenShift SCC/SELinux,
CRI-O/CDI, Kubernetes/DRA API versions and ERNIC guest integration need explicit
compatibility checks. Do not run the real-hardware driver installer against the
CPU-only mock host or claim the entire Kind stack transfers unchanged.
