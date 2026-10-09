# RDMA demo application image

`docker.io/submod/amd-rdma-demo:0.1.0` is a Linux ARM64 demo image. It contains:

- Ubuntu 26.04 userspace, Python 3 and the stock rdma-core libibverbs/ionic provider.
- `rdma-transfer`, built from [transfer.c](transfer.c), linked with libibverbs and OpenSSL.
- No emulator, kernel, AMD GPU driver, model weights or compiler in the final stage.

The existing single-node HTTP app is mounted through a ConfigMap at runtime;
it is not baked into this image. This image changes no upstream provider code.
The [Containerfile](Containerfile) records package installation and build inputs.
Maintainers rebuild and publish with:

```bash
./demo/gpu-network/two-node/image/build.sh --push
```

Users run the demo against the published image; no local build is required.
The demo uses CPU registered memory, RC queue pairs, SEND/RECV and
RDMA WRITE WITH IMMEDIATE. TCP between application Pods carries queue-pair
metadata, SHA-256 digests and synchronization. It never carries the payload.
ERNIC's upstream TCP mesh transports the emulated RDMA operations between labs;
this is not physical RoCE performance or GPU-direct DMA.

The receiver's opt-in `RDMA_CORRUPT=1` flag changes a byte after receiving it,
so the runner can demonstrate that its checksum validation fails. It is a
validation control in the demo application, not a NIC fault-injection interface.
