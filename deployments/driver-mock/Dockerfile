# Optional CUSE/libdrm image. The ordinary mock image remains lightweight.
FROM docker.io/library/golang:1.26-bookworm AS go-builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY cmd/ cmd/
COPY pkg/ pkg/
RUN CGO_ENABLED=0 go build -o /out/node-agent ./cmd/node-agent && \
    CGO_ENABLED=0 go build -o /out/nri-plugin ./cmd/nri-plugin

FROM docker.io/library/debian:bookworm-slim AS native-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential libdrm-dev libfuse3-dev pkg-config && rm -rf /var/lib/apt/lists/*
WORKDIR /src
COPY pkg/mockdriver/native/ ./
COPY tests/driver-mock/probe.c ./
RUN mkdir -p /out && \
    cc -Wall -Wextra -Werror -fPIC -shared -Wl,-soname,libdrm_amdgpu.so.1 \
      $(pkg-config --cflags libdrm_amdgpu) drm.c -o /out/libdrm_amdgpu.so.1 && \
    cc -Wall -Wextra -Werror $(pkg-config --cflags fuse3) device.c \
      $(pkg-config --libs fuse3) -o /out/mock-device && \
    cc -Wall -Wextra -Werror $(pkg-config --cflags libdrm_amdgpu) probe.c \
      -L/out -l:libdrm_amdgpu.so.1 -Wl,-rpath,/opt/amd-gpu-mock/lib -o /out/driver-probe
COPY pkg/mocksmi/ /smi/
RUN cc -shared -fPIC -O2 -Wl,-soname,libamd_smi.so.27 \
    /smi/mock_amdsmi.c /smi/stubs.c -o /out/libamd_smi.so

FROM docker.io/library/debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends tini libfuse3-3 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=go-builder /out/ /usr/local/bin/
COPY --from=native-builder /out/mock-device /out/driver-probe /usr/local/bin/
COPY --from=native-builder /out/libdrm_amdgpu.so.1 /opt/amd-gpu-mock/lib/
COPY --from=native-builder /out/libamd_smi.so /usr/lib64/libamd_smi.so
RUN ln -s libamd_smi.so /usr/lib64/libamd_smi.so.27
COPY profiles/ /etc/amd-gpu-mock/profiles/
ENTRYPOINT ["tini", "--"]
CMD ["node-agent"]
