#!/usr/bin/env bash
# Provision one ARM64 ERNIC VM worker in an existing Podman Kind cluster.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$HERE/versions.env"
CONTEXT="${KUBE_CONTEXT:-kind-amd-mock}"
NODE="${ERNIC_NODE:-amd-ernic-worker-1}"
LAB="${ERNIC_CONTAINER:-amd-ernic-lab}"
CP="${ERNIC_CONTROL_PLANE:-amd-mock-control-plane}"
SSH_PORT="${ERNIC_SSH_PORT:-2228}"
STATE="${ERNIC_STATE_DIR:-$ROOT/tmp/ernic}"
export KUBE_CONTEXT="$CONTEXT" ERNIC_NODE="$NODE" ERNIC_STATE_DIR="$STATE"
k=(kubectl --context "$CONTEXT")
for bin in podman kubectl helm python3 curl ssh scp ssh-keygen; do command -v "$bin" >/dev/null; done
"${k[@]}" cluster-info >/dev/null
# Reusing an already joined worker is non-destructive.
if "${k[@]}" get node "$NODE" >/dev/null 2>&1; then
 "$HERE/install-network.sh"
 "$HERE/install-gpu.sh"
 exit
fi
[ "$(podman machine ssh uname -m | tr -d '\r')" = aarch64 ] || { echo 'This ERNIC VM setup is currently ARM64 only.' >&2; exit 1; }
RESUME=false
if podman container exists "$LAB"; then
 if [ "${ERNIC_RESUME_UNJOINED:-false}" = true ]; then
  [ -f "$STATE/id_ed25519" ] && [ -f "$STATE/worker.qcow2" ]
  RESUME=true
 else
 echo "Container $LAB exists without joined node $NODE. Inspect $STATE logs; refusing to replace its disk." >&2
 exit 1
 fi
fi
if ! $RESUME; then
mkdir -p "$STATE"
chmod 700 "$STATE"
[ -f "$STATE/id_ed25519" ] || ssh-keygen -q -t ed25519 -N '' -f "$STATE/id_ed25519"
download() {
 local url="$1" file="$2" expected="$3"
 [ -s "$file" ] || curl -fL --retry 3 "$url" -o "$file"
 python3 - "$file" "$expected" <<'PY'
import hashlib,sys
with open(sys.argv[1],'rb') as f:
 h=hashlib.sha256()
 for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
 digest=h.hexdigest()
assert digest==sys.argv[2], (sys.argv[1],digest,'unexpected checksum')
PY
}
if [ "${ERNIC_USE_PREPARED:-true}" = true ]; then
 printf "Pulling prepared worker artifact %s...\n" "$ERNIC_WORKER_IMAGE"
 if [ "${ERNIC_PULL_PREPARED:-true}" = true ]; then
  podman pull "$ERNIC_WORKER_IMAGE"
 else
  podman image exists "$ERNIC_WORKER_IMAGE"
 fi
 artifact="$(podman create --entrypoint /unused "$ERNIC_WORKER_IMAGE")"
 for file in worker-base.img Image.raw initrd manifest.json packages.txt; do
  podman cp "$artifact:/worker/$file" "$STATE/$file"
 done
 podman rm "$artifact" >/dev/null
 python3 - "$STATE" <<'CHECK'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1]);m=json.loads((p/'manifest.json').read_text())
assert m['kubernetes']=='v1.37.0', 'Unexpected Kubernetes worker version'
for name,digest in m['sha256'].items():
 h=hashlib.sha256()
 with (p/name).open('rb') as f:
  for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
 assert h.hexdigest()==digest,name
CHECK
else
 printf "Checking/downloading pinned guest assets (cached on subsequent runs)...\n"
 download "$GUEST_URL" "$STATE/worker-base.img" "$GUEST_SHA256"
 download "$GUEST_KERNEL_URL" "$STATE/vmlinuz" "$GUEST_KERNEL_SHA256"
 download "$GUEST_INITRD_URL" "$STATE/initrd" "$GUEST_INITRD_SHA256"
fi
cp "$HERE/boot-worker.sh" "$HERE/extract-kernel.py" "$HERE/configure-guest.sh" "$STATE/"
NODE="$NODE" STATE="$STATE" python3 - <<'PY'
import json,os,pathlib
root=pathlib.Path(os.environ['STATE'])
key=(root/'id_ed25519.pub').read_text().strip()
user={'users':[{'name':'demo','sudo':'ALL=(ALL) NOPASSWD:ALL','shell':'/bin/bash','ssh_authorized_keys':[key]}],'ssh_pwauth':False}
(root/'user-data').write_text('#cloud-config\n'+json.dumps(user)+'\n')
(root/'meta-data').write_text('instance-id: '+os.environ['NODE']+'\nlocal-hostname: '+os.environ['NODE']+'\n')
PY
podman run -d --name "$LAB" --device /dev/net/tun --cap-add NET_ADMIN \
 -p "127.0.0.1:$SSH_PORT:2228" -v "$STATE:/opt/lab" "$ERNIC_LAB_IMAGE"
podman network connect kind "$LAB"
NODE_IP="$(podman inspect "$LAB" --format '{{(index .NetworkSettings.Networks "kind").IPAddress}}')"
CP_IP="$(podman inspect "$CP" --format '{{(index .NetworkSettings.Networks "kind").IPAddress}}')"
[ -n "$NODE_IP" ] && [ -n "$CP_IP" ]
printf '%s\n' "$NODE_IP" > "$STATE/node-ip"
if [ "${ERNIC_USE_PREPARED:-true}" != true ]; then
 podman exec "$LAB" python3 /opt/lab/extract-kernel.py /opt/lab/vmlinuz /opt/lab/Image.raw
fi
podman exec "$LAB" qemu-img create -f qcow2 -F qcow2 -b /opt/lab/worker-base.img /opt/lab/worker.qcow2 30G
podman exec "$LAB" cloud-localds /opt/lab/seed.img /opt/lab/user-data /opt/lab/meta-data
rm -f "$STATE/boot.exit"
podman exec -d "$LAB" bash -c 'bash /opt/lab/boot-worker.sh; echo $? > /opt/lab/boot.exit'
fi
# Refresh configuration when explicitly resuming a failed unjoined VM.
cp "$HERE/configure-guest.sh" "$STATE/configure-guest.sh"
NODE_IP="$(cat "$STATE/node-ip")"
CP_IP="$(podman inspect "$CP" --format '{{(index .NetworkSettings.Networks "kind").IPAddress}}')"
ssh_args=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o "UserKnownHostsFile=$STATE/known_hosts" -o ConnectTimeout=5 -i "$STATE/id_ed25519")
printf "Booting guest; waiting for SSH (up to 10 minutes). Logs: %s/worker-console.log\n" "$STATE"
ready=false
for attempt in $(seq 1 120); do
 if ssh "${ssh_args[@]}" -p "$SSH_PORT" demo@127.0.0.1 true 2>/dev/null; then ready=true; break; fi
 sleep 5
done
$ready || { echo "Guest SSH not ready; inspect $STATE/worker-console.log and qemu.log" >&2; exit 1; }
printf "Guest SSH ready; configuring Kubernetes runtime...\n"
if [ "${ERNIC_USE_PREPARED:-true}" != true ]; then
 mkdir -p "$STATE/worker-bits"
 podman cp "$CP:/usr/bin/kubeadm" "$STATE/worker-bits/kubeadm"
 podman cp "$CP:/usr/bin/kubelet" "$STATE/worker-bits/kubelet"
 podman cp "$CP:/opt/cni/bin" "$STATE/worker-bits/cni"
 scp "${ssh_args[@]}" -P "$SSH_PORT" -r "$STATE/worker-bits" demo@127.0.0.1:/home/demo/
fi
scp "${ssh_args[@]}" -P "$SSH_PORT" "$STATE/configure-guest.sh" demo@127.0.0.1:/home/demo/
ssh "${ssh_args[@]}" -p "$SSH_PORT" demo@127.0.0.1 "sudo bash /home/demo/configure-guest.sh '$NODE_IP' '$CP_IP' '$CP'" | tee "$STATE/guest-setup.log"
if [ "${ERNIC_PREPARE_ONLY:-false}" = true ]; then
 printf "Guest prepared; stopping before cluster join.\n"
 exit 0
fi
mkdir -p "$STATE/kubeadm-patches"
printf 'cgroupRoot: /\n' > "$STATE/kubeadm-patches/kubeletconfiguration0+merge.yaml"
# Store the short-lived bootstrap credential privately; never print it.
STATE="$STATE" NODE="$NODE" NODE_IP="$NODE_IP" CP_IP="$CP_IP" CP="$CP" python3 - <<'PY'
import json,os,pathlib,subprocess
cmd=subprocess.check_output(['podman','exec',os.environ['CP'],'kubeadm','token','create','--ttl','1h','--print-join-command'],text=True).split()
token=cmd[cmd.index('--token')+1]
ca=cmd[cmd.index('--discovery-token-ca-cert-hash')+1]
cfg={'apiVersion':'kubeadm.k8s.io/v1beta4','kind':'JoinConfiguration','discovery':{'bootstrapToken':{'apiServerEndpoint':os.environ['CP_IP']+':6443','token':token,'caCertHashes':[ca]}},'nodeRegistration':{'name':os.environ['NODE'],'criSocket':'unix:///run/containerd/containerd.sock','kubeletExtraArgs':[{'name':'node-ip','value':os.environ['NODE_IP']}]},'patches':{'directory':'/home/demo/kubeadm-patches'}}
p=pathlib.Path(os.environ['STATE'])/'join-private.json';p.write_text(json.dumps(cfg));p.chmod(0o600)
PY
cleanup_token() {
 STATE="$STATE" CP="$CP" python3 - <<'PY'
import json,os,pathlib,subprocess
p=pathlib.Path(os.environ['STATE'])/'join-private.json'
if p.exists():
 token=json.loads(p.read_text())['discovery']['bootstrapToken']['token'].split('.')[0]
 subprocess.run(['podman','exec',os.environ['CP'],'kubeadm','token','delete',token],stdout=subprocess.DEVNULL)
 p.unlink()
PY
 ssh "${ssh_args[@]}" -p "$SSH_PORT" demo@127.0.0.1 'rm -f ~/join-private.json' || true
}
trap cleanup_token EXIT
scp "${ssh_args[@]}" -P "$SSH_PORT" -r "$STATE/kubeadm-patches" "$STATE/join-private.json" demo@127.0.0.1:/home/demo/
ssh "${ssh_args[@]}" -p "$SSH_PORT" demo@127.0.0.1 'sudo kubeadm join --config /home/demo/join-private.json' | tee "$STATE/join.log"
registered=false
for attempt in $(seq 1 60); do
 if "${k[@]}" get node "$NODE" >/dev/null 2>&1; then registered=true; break; fi
 sleep 5
done
$registered || { echo "Worker did not register within 5 minutes" >&2; exit 1; }
"${k[@]}" wait --for=condition=Ready "node/$NODE" --timeout=300s
"$HERE/install-network.sh"
"${k[@]}" -n kube-amd-network rollout status ds/ernic-device-plugin --timeout=300s
"$HERE/install-gpu.sh"
printf '\nWorker ready. Run ./demo/gpu-network/single-node/run.sh\n'
