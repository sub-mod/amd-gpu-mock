# Two containers with slices of one GPU

Install chart 0.2.11 with `--set gpu.partition=DPX` on a fresh quick-start
cluster. The same published node image, AMD DRA driver and normal dashboard
port mappings are used. See [installation and architecture](../../docs/guides/partition-allocation.md).

For a dedicated cluster with an isolated kubeconfig and custom ports, follow
the [demo-room setup](../README.md#same-gpu-allocation-presentation). This runner
uses the current kubeconfig, so select the DPX cluster explicitly.

```bash
./demo/partition-allocation/run.sh
```

The script runs the checks, prints real pod logs and allocation evidence,
and leaves `amd-demo-partition-allocation/two-containers` Running. It does not
reuse or delete an existing demo namespace. Each container requests one named
partition from the shared ResourceClaim; the scheduler's same-parent constraint
ensures both slices come from one physical MI300X. Each gets 96 GiB of
advertised capacity and a different render device.

```bash
kubectl -n amd-demo-partition-allocation get pod two-containers
kubectl -n amd-demo-partition-allocation logs two-containers -c left
kubectl -n amd-demo-partition-allocation logs two-containers -c right
kubectl -n amd-demo-partition-allocation get resourceclaim two-slices -o yaml
```

The evidence comes from AMD's unchanged DRA driver publishing the mock's
DRM/KFD topology, Kubernetes allocating the claims, and AMD's NodePrepare
creating CDI edits which the container runtime applies. The test correlates
claim device names with ResourceSlice parent identity, profile and capacity,
and checks the actual character nodes inside each container. It also checks
exhaustion, reuse after NodeUnprepare removes the old claim CDI file, sibling
continuity, and a real driver pod replacement during restart.

This proves allocation and device visibility. The fake character devices do
not execute GPU kernels or prove hardware memory isolation. Per-partition
exporter workload attribution and physical fault propagation are outside
this allocation test.

The equivalent [two-container claim and pod](two-containers.json) can also
be applied in your own namespace. To replay the captured logs without a
cluster, run `./demo/partition-allocation/run.sh --show-captured`.

Clean up with `kubectl delete namespace amd-demo-partition-allocation`.
The raw [captured.log](captured.log) below records a real Podman run on the
published chart/image, Kubernetes v1.37.0 and unchanged AMD DRA v1.0.0.

## Actual captured output

```text
PASS: AMD driver advertises 16 partitions for 8 physical MI300X GPUs
EVIDENCE: first/consumer: claim=first request=gpu device=gpu-1-129 parent=0000:05:00.0 memory=96Gi render=renderD129
crw-r-----    1 root     root      234,   0 Oct  7 03:08 /dev/kfd

/dev/dri:
total 0
crw-r-----    1 root     root      226,   1 Oct  7 03:08 card1
crw-r-----    1 root     root      226, 129 Oct  7 03:08 renderD129
EVIDENCE: second/consumer: claim=second request=gpu device=gpu-0-128 parent=0000:05:00.0 memory=96Gi render=renderD128
crw-r-----    1 root     root      234,   0 Oct  7 03:08 /dev/kfd

/dev/dri:
total 0
crw-r-----    1 root     root      226,   0 Oct  7 03:08 card0
crw-r-----    1 root     root      226, 128 Oct  7 03:08 renderD128
PASS: third consumer stays Pending when the selected physical GPU has no free partitions
PASS: AMD NodeUnprepare removes the released claim CDI file
EVIDENCE: waiting/consumer: claim=waiting request=gpu device=gpu-1-129 parent=0000:05:00.0 memory=96Gi render=renderD129
crw-r-----    1 root     root      234,   0 Oct  7 03:09 /dev/kfd

/dev/dri:
total 0
crw-r-----    1 root     root      226,   1 Oct  7 03:09 card1
crw-r-----    1 root     root      226, 129 Oct  7 03:09 renderD129
EVIDENCE: second/consumer: claim=second request=gpu device=gpu-0-128 parent=0000:05:00.0 memory=96Gi render=renderD128
crw-r-----    1 root     root      234,   0 Oct  7 03:08 /dev/kfd

/dev/dri:
total 0
crw-r-----    1 root     root      226,   0 Oct  7 03:08 card0
crw-r-----    1 root     root      226, 128 Oct  7 03:08 renderD128
PASS: released partition is reused while the sibling consumer remains Ready
EVIDENCE: second/consumer: claim=second request=gpu device=gpu-0-128 parent=0000:05:00.0 memory=96Gi render=renderD128
crw-r-----    1 root     root      234,   0 Oct  7 03:08 /dev/kfd

/dev/dri:
total 0
crw-r-----    1 root     root      226,   0 Oct  7 03:08 card0
crw-r-----    1 root     root      226, 128 Oct  7 03:08 renderD128
EVIDENCE: waiting/consumer: claim=waiting request=gpu device=gpu-1-129 parent=0000:05:00.0 memory=96Gi render=renderD129
crw-r-----    1 root     root      234,   0 Oct  7 03:09 /dev/kfd

/dev/dri:
total 0
crw-r-----    1 root     root      226,   1 Oct  7 03:09 card1
crw-r-----    1 root     root      226, 129 Oct  7 03:09 renderD129
PASS: driver restart preserves both live allocations
EVIDENCE: two-containers/left: claim=two-slices request=left device=gpu-14-142 parent=0000:e5:00.0 memory=96Gi render=renderD142
crw-r-----    1 root     root      234,   0 Oct  7 03:09 /dev/kfd

/dev/dri:
total 0
crw-r-----    1 root     root      226,  14 Oct  7 03:09 card14
crw-r-----    1 root     root      226, 142 Oct  7 03:09 renderD142
EVIDENCE: two-containers/right: claim=two-slices request=right device=gpu-15-143 parent=0000:e5:00.0 memory=96Gi render=renderD143
crw-r-----    1 root     root      234,   0 Oct  7 03:09 /dev/kfd

/dev/dri:
total 0
crw-r-----    1 root     root      226,  15 Oct  7 03:09 card15
crw-r-----    1 root     root      226, 143 Oct  7 03:09 renderD143
PASS: two containers in one pod receive distinct partitions of the same physical GPU
Demo remains Running in namespace amd-demo-partition-allocation; delete that namespace to release its claims.
PASS: all 16 published partitions have DPX/NPS2, 96Gi and 152 CU; eight parents each have two devices
```

[Image IDs and capture provenance](provenance.json). Transcript SHA-256: `a9135f60b2ac02cdddf0a377630ab5845eb50debca387e3a5c240fa0a39e46a6`.
