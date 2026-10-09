#!/usr/bin/env bash
# Run inside the dedicated lab container, after its kind interface is attached.
set -euo pipefail
cd /opt/lab
NODE_IP="$(cat node-ip)"
MAC="$(python3 -c 'import ipaddress,sys; print(":".join(f"{b:02x}" for b in bytes([2,173])+ipaddress.ip_address(sys.argv[1]).packed))' "$NODE_IP")"
ip link show ernicbr0 >/dev/null 2>&1 || ip link add ernicbr0 type bridge
ip link set ernicbr0 up
ip tuntap show | grep -q '^ernic0:' || ip tuntap add dev ernic0 mode tap
ip addr flush dev eth1
ip addr flush dev ernic0
ip link set eth1 master ernicbr0
ip link set ernic0 master ernicbr0
ip link set eth1 up
ip link set ernic0 up
BACKEND="$(cat backend 2>/dev/null || printf loopback)"
if [[ "$BACKEND" == tcp:manager:self:* ]]; then
 BACKEND="tcp:manager:$(ip -4 -o addr show dev eth0 | awk '{print $4}' | cut -d/ -f1):${BACKEND##*:}"
fi
# Upstream TCP mesh requires each emulator to advertise its guest's own GIDs.
# The guest's link-local GID is derived from the same MAC used for the PCI NIC.
export ERNIC_TCP_GUEST_GIDS="$(python3 - "$MAC" "$NODE_IP" <<'PYGID'
import ipaddress,sys
mac=bytearray.fromhex(sys.argv[1].replace(':',''));mac[0]^=2
raw=bytes.fromhex('fe80000000000000')+mac[:3]+b'\xff\xfe'+mac[3:]
print(str(ipaddress.IPv6Address(raw))+','+sys.argv[2])
PYGID
)"
printf '%s\n' "$BACKEND" > backend-active
/usr/local/bin/rocm-ernic --socket /opt/lab/ernic.sock --backend "$BACKEND" --mac "$MAC" --tap ernic0 --log-level info --stats-file /opt/lab/ernic.stats > ernic.log 2>&1 &
SERVER_PID=$!
trap 'kill "$SERVER_PID" 2>/dev/null || true' EXIT
for attempt in $(seq 1 30); do [ ! -S ernic.sock ] || break; sleep 1; done
# Four CPUs are mandatory for ionic_rdma's four minimum event queues.
# Keep RAM below 4GiB: libvfio-user represents an individual DMA region with uint32 length.
/usr/local/bin/qemu-system-aarch64 -M virt -accel tcg,thread=multi -cpu cortex-a72 -smp 4 -m 3072 \
 -object memory-backend-memfd,id=mem,size=3072M,share=on -numa node,memdev=mem \
 -kernel /opt/lab/Image.raw -initrd /opt/lab/initrd \
 -append 'root=LABEL=cloudimg-rootfs rw console=ttyAMA0' \
 -drive file=/opt/lab/worker.qcow2,if=virtio,format=qcow2 \
 -drive file=/opt/lab/seed.img,if=virtio,format=raw \
 -netdev user,id=mgmt,hostfwd=tcp:0.0.0.0:2228-:22 \
 -device virtio-net-pci,netdev=mgmt,romfile= \
 -device '{"driver":"vfio-user-pci","socket":{"type":"unix","path":"/opt/lab/ernic.sock"}}' \
 -display none -serial file:/opt/lab/worker-console.log -monitor none > qemu.log 2>&1
