#!/bin/bash
# Stage mock AMD GPU sysfs paths at boot.
# Runs as a systemd oneshot before containerd/kubelet.
#
# Creates tmpfs-backed directories and bind-mounts them into /sys
# so the AMD GPU Operator's init containers find:
#   /sys/class/kfd        — KFD class directory
#   /sys/module/amdgpu    — amdgpu kernel module

set -e

MOCK=/tmp/mock-sys

echo "[amd-gpu-mock] Staging mock sysfs paths..."

# Create the mock tree in tmpfs
mkdir -p "${MOCK}/class/kfd/kfd/topology/nodes"
MODDIR="${MOCK}/module/amdgpu"
mkdir -p "${MODDIR}/drivers/pci:amdgpu"
echo "live"   > "${MODDIR}/initstate"
echo "6.19.4" > "${MODDIR}/version"
echo "1"      > "${MODDIR}/refcnt"

# Bind-mount into real /sys
# KIND nodes run in a container with their own mount namespace.
# /sys is mounted rw, so mkdir works.
mkdir -p /sys/class/kfd    2>/dev/null || true
mkdir -p /sys/module/amdgpu 2>/dev/null || true

mount --bind "${MOCK}/class/kfd"     /sys/class/kfd     2>/dev/null || true
mount --bind "${MOCK}/module/amdgpu" /sys/module/amdgpu 2>/dev/null || true

# Verify
if [ -d /sys/class/kfd ] && [ -f /sys/module/amdgpu/initstate ]; then
    echo "[amd-gpu-mock] OK: /sys/class/kfd and /sys/module/amdgpu staged"
else
    echo "[amd-gpu-mock] WARNING: sysfs staging incomplete"
fi
