#!/usr/bin/env bash
# Run as root inside the standalone Ubuntu ARM64 worker.
set -euo pipefail
NODE_IP="$1"
CP_IP="$2"
CP_NAME="$3"
export DEBIAN_FRONTEND=noninteractive
# Avoid expensive kernel-image scanning under TCG during first provisioning.
# containerd is explicitly restarted below; this setting affects only this process.
export NEEDRESTART_SUSPEND=1
if [ ! -f /etc/amd-ernic-prepared ]; then
 printf "Installing guest runtime and RDMA discovery tools...\n"
 apt-get update
 apt-get install -y --no-install-recommends containerd iproute2 curl ca-certificates ibverbs-utils rdma-core
else
 printf "Using preinstalled guest runtime and RDMA tools.\n"
fi
if [ -d /home/demo/worker-bits ]; then
install -m755 /home/demo/worker-bits/kubeadm /usr/local/bin/kubeadm
install -m755 /home/demo/worker-bits/kubelet /usr/local/bin/kubelet
mkdir -p /opt/cni/bin /etc/containerd /etc/modules-load.d /etc/sysctl.d
cp /home/demo/worker-bits/cni/* /opt/cni/bin/
fi
printf 'overlay\nbr_netfilter\n' > /etc/modules-load.d/kubernetes.conf
modprobe overlay
modprobe br_netfilter
printf 'net.ipv4.ip_forward=1\nnet.bridge.bridge-nf-call-iptables=1\nnet.bridge.bridge-nf-call-ip6tables=1\n' > /etc/sysctl.d/90-kubernetes.conf
sysctl --system
swapoff -a
if [ ! -s /etc/containerd/config.toml ]; then
 containerd config default > /etc/containerd/config.toml
fi
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl enable --now containerd
systemctl restart containerd
cat > /etc/systemd/system/kubelet.service <<'UNIT'
[Unit]
Description=Kubernetes Kubelet
After=network-online.target containerd.service
Wants=network-online.target
ConditionPathExists=/var/lib/kubelet/config.yaml
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
ExecStart=/usr/local/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS
Restart=always
RestartSec=5
Slice=kubelet.slice
CPUAccounting=true
MemoryAccounting=true
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable kubelet
if ! grep -q "$CP_IP $CP_NAME" /etc/hosts; then
 printf '%s %s\n' "$CP_IP" "$CP_NAME" >> /etc/hosts
fi
cat > /etc/netplan/60-ernic.yaml <<NET
network:
  version: 2
  ethernets:
    enp0s4np0:
      dhcp4: false
      addresses: [$NODE_IP/24]
NET
chmod 600 /etc/netplan/60-ernic.yaml
ip addr replace "$NODE_IP/24" dev enp0s4np0
ip link set enp0s4np0 up
modprobe ionic_rdma
ready=false
for attempt in $(seq 1 60); do
 if compgen -G '/sys/class/infiniband/*' >/dev/null; then ready=true; break; fi
 sleep 2
done
$ready || { echo 'RDMA device did not register within two minutes' >&2; exit 1; }
ibv_devinfo
