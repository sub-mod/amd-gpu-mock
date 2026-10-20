FROM docker.io/library/ubuntu:24.04
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg python3 && \
 curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | gpg --dearmor -o /usr/share/keyrings/rocm.gpg && \
 echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 noble main' > /etc/apt/sources.list.d/rocm.list && \
 printf 'Package: *\nPin: origin repo.radeon.com\nPin-Priority: 600\n' > /etc/apt/preferences.d/rocm && \
 apt-get update && apt-get install -y --no-install-recommends hip-runtime-amd=7.2.26015.70200-43~24.04 hsa-rocr=1.18.0.70200-43~24.04 && rm -rf /var/lib/apt/lists/*
COPY tmp/rocjitsu-results/artifacts/bin/rocjitsu tmp/rocjitsu-results/artifacts/bin/hip_vector_add_test tmp/rocjitsu-results/artifacts/bin/limits /opt/compute/bin/
COPY tmp/rocjitsu-results/artifacts/lib/librocjitsu.so tmp/rocjitsu-results/artifacts/lib/libmask-audit.so /opt/compute/lib/
COPY tmp/rocjitsu-results/artifacts/lib/libamvgpu.so /opt/compute/hook/libamvgpu.so
ENV LD_LIBRARY_PATH=/opt/rocm/lib
CMD ["sleep", "infinity"]
