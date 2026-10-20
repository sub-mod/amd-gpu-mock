# HAMi source remains unchanged. Native ARM64 build against the explicit test ABI.
FROM docker.io/submod/amd-gpu-mock-driver:v0.1.1@sha256:5dcc04c9a83db5a232c05c7c6adf632b337af4f5da1a94035b2f063380493524 AS backend
FROM docker.io/library/golang:1.27.2 AS build
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends libdrm-dev libhwloc-dev && rm -rf /var/lib/apt/lists/*
COPY --from=backend /opt/amd-gpu-mock/lib/ /opt/amd-driver-mock/lib/
COPY --from=backend /usr/lib64/libamd_smi.so /opt/amd-driver-mock/lib/libamd_smi.so.27
COPY pkg/mocksmi/exporter/amdsmi.h /opt/rocm/include/amd_smi/amdsmi.h
RUN mkdir -p /opt/rocm/lib && ln -s /opt/amd-driver-mock/lib/libamd_smi.so.27 /opt/rocm/lib/libamd_smi.so && ln -s libdrm_amdgpu.so.1 /opt/amd-driver-mock/lib/libdrm_amdgpu.so
COPY tmp/hami-main/amd-device-plugin/ /hami/
WORKDIR /hami
ENV CGO_LDFLAGS="-L/opt/amd-driver-mock/lib"
ENV LD_LIBRARY_PATH=/opt/amd-driver-mock/lib
RUN go build -ldflags="-X main.gitDescribe=35c84ab2b224f7f43c74bb68e307dfd244c71bae" -o /hami-device-plugin ./cmd/k8s-device-plugin
RUN cc -shared -fPIC -D_GNU_SOURCE -O2 -fvisibility=hidden -Iamd-hami-core/src/include -Iamd-hami-core/src/multiprocess \
    amd-hami-core/src/hip/libamvgpu_audit.c amd-hami-core/src/multiprocess/hip_multiprocess_memory_limit.c \
    -ldl -pthread -o /libamvgpu.so
FROM backend
RUN apt-get update && apt-get install -y --no-install-recommends libhwloc15 && rm -rf /var/lib/apt/lists/*
COPY --from=build /hami-device-plugin /opt/amd-driver-mock/bin/hami-device-plugin
COPY --from=build /libamvgpu.so /opt/hami/lib/amd/libamvgpu.so
ENTRYPOINT ["/opt/amd-driver-mock/bin/hami-device-plugin"]
