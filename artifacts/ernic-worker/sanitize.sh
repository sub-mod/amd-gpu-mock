#!/usr/bin/env bash
# Inside an unjoined build guest only. Never run on an in-use worker.
set -euo pipefail
[ ! -e /etc/kubernetes/kubelet.conf ] || { echo 'Refusing to package a joined worker' >&2; exit 1; }
systemctl disable kubelet
systemctl stop containerd
rm -rf /var/lib/containerd/* /var/lib/kubelet/* /etc/kubernetes
rm -f /etc/netplan/60-ernic.yaml /etc/ssh/ssh_host_* /var/lib/systemd/random-seed
rm -rf /home/demo /root/.ssh /root/.bash_history
userdel -f demo
printf '127.0.0.1 localhost\n::1 localhost ip6-localhost ip6-loopback\n' > /etc/hosts
printf 'amd-ernic-worker\n' > /etc/hostname
printf 'Prepared runtime; configure node before kubeadm join.\n' > /etc/amd-ernic-prepared
apt-get clean
rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*
cloud-init clean --logs --machine-id --seed
journalctl --rotate
journalctl --vacuum-time=1s
find /var/log -type f -exec truncate -s 0 {} +
sync
systemctl poweroff
