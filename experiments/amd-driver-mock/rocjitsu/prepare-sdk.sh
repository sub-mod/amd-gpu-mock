#!/bin/sh
# Run as root inside a disposable Ubuntu 24.04 AMD64 container.
set -eu
[ "$(dpkg --print-architecture)" = amd64 ] || { echo 'Requires AMD64 userspace' >&2; exit 1; }
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  ca-certificates curl gnupg cmake ninja-build g++ git python3
curl -fsSL https://repo.radeon.com/rocm/rocm.gpg.key | \
  gpg --dearmor --yes -o /usr/share/keyrings/rocm.gpg
cat > /etc/apt/sources.list.d/rocm.list <<'EOF'
deb [arch=amd64 signed-by=/usr/share/keyrings/rocm.gpg] https://repo.radeon.com/rocm/apt/7.2 noble main
EOF
# Ubuntu's hipcc 5.7 sorts above ROCm's hipcc 1.1. Use one SDK consistently.
cat > /etc/apt/preferences.d/rocjitsu-rocm <<'EOF'
Package: *
Pin: origin repo.radeon.com
Pin-Priority: 600
EOF
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  hip-dev=7.2.26015.70200-43~24.04 \
  hip-runtime-amd=7.2.26015.70200-43~24.04 \
  hipcc=1.1.1.70200-43~24.04 \
  hsa-rocr=1.18.0.70200-43~24.04 \
  hsa-rocr-dev=1.18.0.70200-43~24.04 \
  rocm-llvm=22.0.0.26014.70200-43~24.04 \
  rocm-device-libs=1.0.0.70200-43~24.04
dpkg-query -W hipcc hip-dev hip-runtime-amd hsa-rocr rocm-llvm rocm-device-libs
