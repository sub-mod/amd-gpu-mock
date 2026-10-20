#!/usr/bin/env bash
# Disposable, single-node library-backend lab. Does not alter the normal cluster.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXP="$ROOT/experiments/amd-driver-mock"
CONFIG="${DRIVER_MOCK_CONFIG:-$EXP/config.json}"
runtime="${CONTAINER_RUNTIME:-podman}"
source "$EXP/versions.env"
python3 "$EXP/check-config.py" "$CONFIG"
image() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["images"][sys.argv[2]])' "$CONFIG" "$1"; }
backend="$(image backend)"; plugin="$(image plugin)"; scheduler="$(image scheduler)"
cd "$ROOT"
mkdir -p tmp/hami
if [[ "$runtime" = podman ]]; then export KIND_EXPERIMENTAL_PROVIDER=podman; volume_options=dev; else export KIND_EXPERIMENTAL_PROVIDER=docker; volume_options=rw; fi
if kind get clusters 2>/dev/null | grep -qx amd-hami-driver; then echo 'Existing amd-hami-driver cluster; use cleanup.sh before a fresh install' >&2; exit 1; fi
if "$runtime" volume inspect amd-driver-mock-state >/dev/null 2>&1; then echo 'Existing experiment volume; use cleanup.sh before a fresh install' >&2; exit 1; fi
if [[ "${DRIVER_MOCK_SKIP_PULL:-0}" != 1 ]]; then
 for img in "$backend" "$plugin" "$scheduler"; do "$runtime" pull "$img"; done
fi
"$runtime" run --rm --privileged "$backend" sh -ec 'test -c /dev/cuse || { echo "Host CUSE is unavailable; see HOST.md" >&2; exit 1; }'
for item in "amd-device-plugin:$HAMI_AMD_COMMIT" "HAMi:$HAMI_COMMIT"; do
 repo="${item%%:*}"; pin="${item#*:}"; dest="tmp/hami/$repo"
 if [[ ! -d "$dest/.git" ]]; then git clone --depth 1 "https://github.com/Project-HAMi/$repo.git" "$dest"; fi
 [[ -z "$(git -C "$dest" status --porcelain)" ]] || { echo "Modified upstream checkout: $dest" >&2; exit 1; }
 git -C "$dest" fetch --depth 1 origin "$pin"
 git -C "$dest" checkout --detach "$pin"
done
"$runtime" volume create amd-driver-mock-state
"$runtime" run --rm -v "amd-driver-mock-state:/state:$volume_options" "$backend" /opt/amd-driver-mock/bin/render-profile --profile /profiles/mi300x.yaml --root /state
"$runtime" run --rm --entrypoint sh -v "amd-driver-mock-state:/state:$volume_options" "$plugin" -ec 'mkdir -p /state/vgpu; cp /opt/hami/lib/amd/libamvgpu.so /state/vgpu/'
"$runtime" run -d --name amd-driver-mock-provider --privileged -v "amd-driver-mock-state:/state:$volume_options" -e AMD_DRIVER_MOCK_ROOT=/state -e MOCK_AMDSMI_STATE_DIR=/state/smi "$backend" sh /src/tests/provider.sh
for i in {1..50}; do "$runtime" exec amd-driver-mock-provider test -f /state/ready && break; sleep .2; done
"$runtime" exec amd-driver-mock-provider test -f /state/ready
mountpoint="$("$runtime" volume inspect amd-driver-mock-state --format '{{.Mountpoint}}')"
python3 - "$mountpoint" <<'PY' > tmp/hami/kind.yaml
import json,sys
print(json.dumps({'kind':'Cluster','apiVersion':'kind.x-k8s.io/v1alpha4','nodes':[{'role':'control-plane','extraMounts':[{'hostPath':sys.argv[1],'containerPath':'/var/lib/amd-driver-mock'}]}]}))
PY
kind create cluster --name amd-hami-driver --image "$KIND_NODE_IMAGE" --config tmp/hami/kind.yaml --kubeconfig tmp/hami/kubeconfig --wait 120s
if [[ "${DRIVER_MOCK_SKIP_PULL:-0}" = 1 ]]; then
 if [[ "$runtime" = podman ]]; then
  "$runtime" save --format docker-archive -o tmp/hami/allocation-images.tar "$plugin" "$scheduler"
  kind load image-archive tmp/hami/allocation-images.tar --name amd-hami-driver
 else
  kind load docker-image "$plugin" "$scheduler" --name amd-hami-driver
 fi
fi
"$runtime" exec amd-hami-driver-control-plane sh -ec 'mkdir -p /dev/dri; for path in dri/card0 dri/renderD128 kfd; do test -e /dev/$path || touch /dev/$path; mount --bind /var/lib/amd-driver-mock/dev/$path /dev/$path; done'
DRIVER_MOCK_CONFIG="$CONFIG" python3 "$EXP/deploy.py"
scheduler_repo="${scheduler%:*}"; scheduler_tag="${scheduler##*:}"
helm --kubeconfig tmp/hami/kubeconfig upgrade --install hami tmp/hami/HAMi/charts/hami -n amd-hami \
 --set devicePlugin.enabled=false --set scheduler.kubeScheduler.image.registry=registry.k8s.io \
 --set scheduler.kubeScheduler.image.repository=kube-scheduler --set 'scheduler.tolerations[0].operator=Exists' \
 --set scheduler.extender.image.registry="${scheduler_repo%%/*}" \
 --set scheduler.extender.image.repository="${scheduler_repo#*/}" \
 --set scheduler.extender.image.tag="$scheduler_tag" --wait --timeout 180s
# Reconcile the exact configured scheduler reference after chart installation.
kubectl --kubeconfig tmp/hami/kubeconfig -n amd-hami set image deploy/hami-scheduler "vgpu-scheduler-extender=$scheduler"
kubectl --kubeconfig tmp/hami/kubeconfig -n amd-hami rollout status deploy/hami-scheduler --timeout=120s
kubectl --kubeconfig tmp/hami/kubeconfig -n amd-hami rollout status ds/amd-gpu-device-plugin-daemonset --timeout=120s
printf 'Ready. Run: python3 experiments/amd-driver-mock/verify.py\n'
