#!/usr/bin/env bash
# Maintainer: create an unjoined guest, sanitize, flatten, package, optionally publish.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$ROOT/scripts/ernic/versions.env"
PUSH=false
[ "${1:-}" != --push ] || { PUSH=true; shift; }
[ "$#" -eq 0 ] || { echo "usage: $0 [--push]" >&2; exit 1; }
CP="${ERNIC_CONTROL_PLANE:-amd-mock-control-plane}"
[ "$(podman exec "$CP" kubeadm version -o short)" = v1.37.0 ] || { echo "Artifact 0.1.0 requires Kubernetes v1.37.0 build inputs" >&2; exit 1; }
export ERNIC_NODE=amd-ernic-image-builder ERNIC_CONTAINER=amd-ernic-image-builder
export ERNIC_SSH_PORT=2230 ERNIC_STATE_DIR="${BUILD_STATE_DIR:-$ROOT/tmp/ernic-worker-build}"
export ERNIC_USE_PREPARED=false ERNIC_PREPARE_ONLY=true
if [ "${ERNIC_RESUME_BUILDER:-false}" != true ]; then
 "$ROOT/scripts/ernic/setup.sh"
else
 # Explicit maintainer recovery of this dedicated, unjoined builder only.
 podman container exists "$ERNIC_CONTAINER"
 ssh -o BatchMode=yes -o "UserKnownHostsFile=$ERNIC_STATE_DIR/known_hosts" -i "$ERNIC_STATE_DIR/id_ed25519" -p "$ERNIC_SSH_PORT" demo@127.0.0.1 'test ! -e /etc/kubernetes/kubelet.conf'
 mkdir -p "$ERNIC_STATE_DIR/worker-bits"
 CP="${ERNIC_CONTROL_PLANE:-amd-mock-control-plane}"
 podman cp "$CP:/usr/bin/kubeadm" "$ERNIC_STATE_DIR/worker-bits/kubeadm"
 podman cp "$CP:/usr/bin/kubelet" "$ERNIC_STATE_DIR/worker-bits/kubelet"
 [ -d "$ERNIC_STATE_DIR/worker-bits/cni" ] || podman cp "$CP:/opt/cni/bin" "$ERNIC_STATE_DIR/worker-bits/cni"
 scp -o BatchMode=yes -o "UserKnownHostsFile=$ERNIC_STATE_DIR/known_hosts" -i "$ERNIC_STATE_DIR/id_ed25519" -P "$ERNIC_SSH_PORT" -r "$ERNIC_STATE_DIR/worker-bits" "$ROOT/scripts/ernic/configure-guest.sh" demo@127.0.0.1:/home/demo/
 NODE_IP="$(cat "$ERNIC_STATE_DIR/node-ip")"
 CP_IP="$(podman inspect "$CP" --format '{{(index .NetworkSettings.Networks "kind").IPAddress}}')"
 ssh -o BatchMode=yes -o "UserKnownHostsFile=$ERNIC_STATE_DIR/known_hosts" -i "$ERNIC_STATE_DIR/id_ed25519" -p "$ERNIC_SSH_PORT" demo@127.0.0.1 "sudo bash /home/demo/configure-guest.sh '$NODE_IP' '$CP_IP' '$CP'"
fi
ssh_opts=(-o BatchMode=yes -o "UserKnownHostsFile=$ERNIC_STATE_DIR/known_hosts" -i "$ERNIC_STATE_DIR/id_ed25519" -p "$ERNIC_SSH_PORT")
scp -o BatchMode=yes -o "UserKnownHostsFile=$ERNIC_STATE_DIR/known_hosts" -i "$ERNIC_STATE_DIR/id_ed25519" -P "$ERNIC_SSH_PORT" "$HERE/sanitize.sh" demo@127.0.0.1:/tmp/sanitize.sh
ssh "${ssh_opts[@]}" demo@127.0.0.1 "dpkg-query -W" > "$ERNIC_STATE_DIR/packages.txt"
# SSH can close while the guest powers down; check QEMU exit separately.
ssh "${ssh_opts[@]}" demo@127.0.0.1 'sudo bash /tmp/sanitize.sh' || true
stopped=false
for attempt in $(seq 1 120); do
 if podman exec "$ERNIC_CONTAINER" test -f /opt/lab/boot.exit; then stopped=true; break; fi
 sleep 2
done
$stopped || { echo 'Guest did not shut down; refusing to copy live disk' >&2; exit 1; }
[ "$(cat "$ERNIC_STATE_DIR/boot.exit")" = 0 ]
mkdir -p "$ERNIC_STATE_DIR/artifact"
podman exec "$ERNIC_CONTAINER" qemu-img convert -c -O qcow2 /opt/lab/worker.qcow2 /opt/lab/artifact/worker-base.img
cp "$ERNIC_STATE_DIR/packages.txt" "$ERNIC_STATE_DIR/artifact/"
cp "$ERNIC_STATE_DIR/Image.raw" "$ERNIC_STATE_DIR/initrd" "$ERNIC_STATE_DIR/artifact/"
python3 - "$ERNIC_STATE_DIR/artifact" "$GUEST_SHA256" <<'PY'
import hashlib,json,pathlib,sys
p=pathlib.Path(sys.argv[1]);m={'kubernetes':'v1.37.0','architecture':'arm64','base_guest_sha256':sys.argv[2],'sha256':{}}
for name in ['worker-base.img','Image.raw','initrd','packages.txt']:
 h=hashlib.sha256()
 with (p/name).open('rb') as f:
  for block in iter(lambda:f.read(1024*1024),b''):h.update(block)
 m['sha256'][name]=h.hexdigest()
(p/'manifest.json').write_text(json.dumps(m,indent=2)+'\n')
PY
cp "$HERE/Containerfile" "$ERNIC_STATE_DIR/artifact/Containerfile"
# Stream a clean context: avoid macOS Virtio-FS extended-attribute failures.
COPYFILE_DISABLE=1 tar --no-xattrs -C "$ERNIC_STATE_DIR/artifact" -cf - Containerfile worker-base.img Image.raw initrd manifest.json packages.txt | podman build --platform linux/arm64 -f Containerfile -t "$ERNIC_WORKER_IMAGE" -
if $PUSH; then podman push "$ERNIC_WORKER_IMAGE"; fi
podman rm -f "$ERNIC_CONTAINER"
printf 'Prepared worker artifact: %s\n' "$ERNIC_WORKER_IMAGE"
