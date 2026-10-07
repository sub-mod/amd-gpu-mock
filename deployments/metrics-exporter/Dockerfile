# The collector binaries are copied unchanged from AMD's published release.
FROM --platform=linux/amd64 docker.io/rocm/device-metrics-exporter@sha256:d4f2706cc42a526aeba36da082f07bbdd74be9b4d6988ae16d914fb474de9f75 AS upstream
# Keep only the standard x86 runtime needed by the unchanged collector.
RUN mkdir -p /minimal/lib64 && cp -L /lib64/libz.so.1 /lib64/libstdc++.so.6 /lib64/libm.so.6 /lib64/libgcc_s.so.1 /lib64/libc.so.6 /lib64/ld-linux-x86-64.so.2 /lib64/librt.so.1 /lib64/libdl.so.2 /lib64/libpthread.so.0 /minimal/lib64/
FROM --platform=linux/amd64 docker.io/library/gcc:14 AS backend
COPY pkg/mocksmi/exporter /src
RUN gcc -shared -fPIC -Wl,-soname,libamd_smi.so.27 -Wl,--version-script=/src/version.map -o /libamd_smi.so.27 /src/mock.c /src/unsupported.c
FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends qemu-user-static libstdc++6 ca-certificates && rm -rf /var/lib/apt/lists/* && find /usr/bin -name 'qemu-*-static' ! -name qemu-x86_64-static -delete && mkdir -p /var/log /var/lib/amd-metrics-exporter /etc/metrics /mock
COPY --from=upstream /home/amd/bin/gpuagent /home/amd/bin/gpuagent
COPY --from=upstream /home/amd/bin/server /home/amd/bin/server
COPY --from=upstream /minimal/lib64 /opt/amd64/lib64
COPY --from=backend /libamd_smi.so.27 /mock/libamd_smi.so.27
COPY deployments/metrics-exporter/entrypoint.sh /entrypoint.sh
COPY deployments/metrics-exporter/config.json /etc/metrics/config.json
ENV MOCK_AMDSMI_STATE_DIR=/var/lib/amd-gpu-mock/smi
ENTRYPOINT ["/entrypoint.sh"]
