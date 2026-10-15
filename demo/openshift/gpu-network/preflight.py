#!/usr/bin/env python3
"""Inspect real CRC host PCI/driver prerequisites; do not fabricate NIC discovery."""
from pathlib import Path
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import guard

if __name__ == '__main__':
    guard()
    script = '''uname -r
echo PCI_IDENTITIES
found=0
for d in /sys/bus/pci/devices/*; do
 test -f "$d/vendor" || continue
 printf '%s ' "$d"; cat "$d/vendor" "$d/device"
 if [ "$(cat "$d/vendor")" = 0x1dd8 ]; then found=1; fi
done
echo ERNIC_ETHERNET_DRIVER
modinfo -F filename ionic || true
echo ERNIC_RDMA_DRIVER
modinfo -F filename ionic_rdma || true
echo RDMA_DEVICES
ls /sys/class/infiniband 2>/dev/null || true
if [ "$found" = 0 ]; then
 echo 'BLOCKED: CRC has no real/emulated Pensando PCI NIC; no NIC allocation proof.'
 exit 2
fi
modinfo ionic_rdma >/dev/null || exit 2
'''
    result = subprocess.run(['oc','debug','node/crc','--','chroot','/host','sh','-c',script], text=True)
    sys.exit(result.returncode)
