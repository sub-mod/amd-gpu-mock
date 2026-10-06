FROM registry.access.redhat.com/ubi9/ubi-minimal:9.8
ARG UPSTREAM_COMMIT
LABEL org.opencontainers.image.source="https://github.com/ROCm/k8s-gpu-dra-driver" \
      org.opencontainers.image.revision=$UPSTREAM_COMMIT
COPY gpu-kubeletplugin /usr/bin/gpu-kubeletplugin
COPY webhook /usr/bin/webhook
COPY LICENSE /licenses/AMD-DRA-LICENSE
