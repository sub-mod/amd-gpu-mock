#!/usr/bin/env bash
# Disposable Ubuntu runner only. Boots a tiny Linux initramfs using libvirt/KVM.
set -euo pipefail
if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
  echo 'Requires an x86-64 Linux runner' >&2; exit 1
fi
OUT="${1:-${RUNNER_TEMP:-/tmp}/amd-libvirt-probe}"
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
python3 - "$OUT/resources.json" <<'PY'
import json, os, shutil, sys
mem = int(next(l.split()[1] for l in open('/proc/meminfo') if l.startswith('MemTotal:'))) * 1024
free = shutil.disk_usage(os.environ.get('RUNNER_TEMP', '/tmp')).free
report = {'logical_cpus': os.cpu_count(), 'host_ram_gib': round(mem / 2**30, 2),
          'available_disk_gib': round(free / 2**30, 2), 'kvm_device_present': os.path.exists('/dev/kvm'),
          'sno_planning_budget_met': os.cpu_count() >= 8 and mem >= 30 * 2**30 and free >= 200 * 2**30,
          'scope': 'Host resources only; guest boot is reported separately; OpenShift not tested'}
open(sys.argv[1], 'w').write(json.dumps(report, indent=2) + '\n')
print(json.dumps(report, indent=2))
PY
if [[ ! -c /dev/kvm ]]; then
  echo 'FAIL: no KVM device; refusing software emulation' >&2; exit 1
fi
sudo apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
  qemu-system-x86 libvirt-daemon-system libvirt-clients busybox-static cpio linux-image-generic
sudo systemctl start libvirtd
sudo virsh -c qemu:///system capabilities > "$OUT/capabilities.xml"
sudo virsh -c qemu:///system domcapabilities --virttype kvm > "$OUT/domain-capabilities.xml"
NAME="amd-mock-probe-${GITHUB_RUN_ID:-$$}"
VM_DIR="/var/lib/libvirt/images/$NAME"
LOG="/var/log/libvirt/qemu/$NAME-serial.log"
WORK="$(mktemp -d)"
cleanup() {
  sudo virsh -c qemu:///system destroy "$NAME" >/dev/null 2>&1 || true
  sudo cat "$LOG" > "$OUT/guest-console.log" 2>/dev/null || true
  # Only files created for this unique transient probe.
  sudo rm -rf "$VM_DIR"
  sudo rm -f "$LOG"
  rm -rf "$WORK"
}
trap cleanup EXIT
mkdir -p "$WORK/root/bin" "$WORK/root/proc" "$WORK/root/sys" "$WORK/root/dev"
cp /bin/busybox "$WORK/root/bin/busybox"
cat > "$WORK/root/init" <<'INIT'
#!/bin/busybox sh
/bin/busybox mount -t proc proc /proc
/bin/busybox mount -t sysfs sysfs /sys
/bin/busybox mount -t devtmpfs devtmpfs /dev
# Reach userspace and run commands, rather than merely create a KVM domain.
/bin/busybox uname -a
/bin/busybox echo AMD_MOCK_KVM_GUEST_BOOT_OK
/bin/busybox sync
/bin/busybox poweroff -f
INIT
chmod +x "$WORK/root/init"
(cd "$WORK/root" && find . -print0 | cpio --null -o --format=newc 2>/dev/null | gzip -1) > "$WORK/initrd.gz"
KERNEL="$(find /boot -maxdepth 1 -name 'vmlinuz-*-generic' | sort -V | tail -1)"
test -n "$KERNEL"
sudo install -d -m 755 "$VM_DIR"
sudo install -m 644 "$KERNEL" "$VM_DIR/kernel"
sudo install -m 644 "$WORK/initrd.gz" "$VM_DIR/initrd.gz"
cat > "$OUT/domain.xml" <<XML
<domain type='kvm'>
  <name>$NAME</name>
  <memory unit='MiB'>256</memory><vcpu>1</vcpu>
  <os><type arch='x86_64' machine='pc'>hvm</type>
    <kernel>$VM_DIR/kernel</kernel><initrd>$VM_DIR/initrd.gz</initrd>
    <cmdline>console=ttyS0 rdinit=/init panic=-1</cmdline>
  </os>
  <devices>
    <emulator>/usr/bin/qemu-system-x86_64</emulator>
    <serial type='file'><source path='$LOG'/><target port='0'/></serial>
  </devices>
</domain>
XML
sudo virsh -c qemu:///system create "$OUT/domain.xml"
for ((i=0; i<60; i++)); do
  if sudo test -f "$LOG" && sudo grep -q 'AMD_MOCK_KVM_GUEST_BOOT_OK' "$LOG"; then
    echo 'PASS: libvirt booted Linux userspace with KVM acceleration' | tee "$OUT/result.txt"
    exit 0
  fi
  sleep 1
done
echo 'FAIL: guest did not reach userspace within 60 seconds' | tee "$OUT/result.txt"
exit 1
