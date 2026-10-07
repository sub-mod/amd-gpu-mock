# AMD SMI ABI provenance

`amdsmi.h` is copied without modification from ROCm/gpu-agent release-v1.5.2, commit `4ce653089c09ae9be2503425d63d3e4452992813`, path `sw/nic/third-party/rocm/amd_smi_lib/include/amd_smi/amdsmi.h`. Its MIT notice remains intact. It defines AMD SMI ABI 27.0.

The real collector binaries come unchanged from `docker.io/rocm/device-metrics-exporter:v1.5.2`, pinned to digest `sha256:d4f2706cc42a526aeba36da082f07bbdd74be9b4d6988ae16d914fb474de9f75`. GPU Agent requires `libamd_smi.so.27` with GNU symbol version `AMDSMI_1`; both are supplied by the replacement.

`unsupported.c` is generated from the GPU-only preprocessed header. To refresh it:

```bash
cc -E -P amdsmi.h > /tmp/amdsmi-preprocessed.h
python3 generate-stubs.py /tmp/amdsmi-preprocessed.h
clang-format -i unsupported.c
```

The mock implements the telemetry and identity calls needed by the pinned collector. Unsupported control, event, profiler and other device capabilities return `AMDSMI_STATUS_NOT_SUPPORTED` rather than succeeding without doing work. The older handwritten mock in the parent directory is not used by this exporter.

AMD exporter v1.4.1 was tested during development, but its bundled GPU Agent does not read ECC counters. It cannot validate the dashboard ECC pathway and is not the supported telemetry image.
