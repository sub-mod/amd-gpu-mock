#!/usr/bin/env bash
# Dedicated optional HAMi environment using main's real node-agent backend.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
source scripts/release.env
source demo/hami/versions.env
runtime="${CONTAINER_RUNTIME:-}"
if [[ -z "$runtime" ]]; then
 if command -v docker >/dev/null && docker info >/dev/null 2>&1; then runtime=docker; else runtime=podman; fi
fi
[[ "$runtime" == docker || "$runtime" == podman ]] || { echo 'CONTAINER_RUNTIME must be docker or podman' >&2; exit 2; }
export KIND_EXPERIMENTAL_PROVIDER="$runtime"
KUBE="$ROOT/tmp/hami-main/kubeconfig"
mkdir -p tmp/hami-main
if kind get clusters 2>/dev/null | grep -qx amd-hami-main; then echo 'Cluster amd-hami-main already exists; run demo/hami/cleanup.sh first' >&2; exit 1; fi
# The setup never builds images or modifies the default kubeconfig.
driver="${HAMI_TEST_DRIVER_IMAGE:-$HAMI_DRIVER_IMAGE}"
"$runtime" run --rm --privileged --entrypoint sh "$driver" -ec 'test -c /dev/cuse || { echo "Host CUSE missing: load cuse in the runtime Linux kernel" >&2; exit 1; }'
demo/hami/fetch.sh
python3 - <<'PY'
import json,os
from pathlib import Path
p=Path('tmp/hami-main')
# Use separate ports so the default quick-start cluster can coexist.
p.joinpath('kind.yaml').write_text(json.dumps({'kind':'Cluster','apiVersion':'kind.x-k8s.io/v1alpha4','nodes':[{'role':'control-plane','extraPortMappings':[{'containerPort':30080,'hostPort':int(os.getenv('HAMI_DASHBOARD_PORT','8081')),'listenAddress':'127.0.0.1'},{'containerPort':30300,'hostPort':int(os.getenv('HAMI_GRAFANA_PORT','3001')),'listenAddress':'127.0.0.1'}]}]}))
PY
kind create cluster --name amd-hami-main --image "docker.io/submod/amd-mock-kind-node:$RELEASE_VERSION" --config tmp/hami-main/kind.yaml --kubeconfig "$KUBE" --wait 120s
plugin="${HAMI_TEST_PLUGIN_IMAGE:-$HAMI_PLUGIN_IMAGE}"
scheduler="${HAMI_TEST_SCHEDULER_IMAGE:-$HAMI_SCHEDULER_IMAGE}"
if [[ "${HAMI_SOURCE_TEST:-0}" == 1 ]]; then
 if [[ "$runtime" == podman ]]; then
  "$runtime" save --format docker-archive -o tmp/hami-main/images.tar "$plugin" "$scheduler" "$driver"
  kind load image-archive tmp/hami-main/images.tar --name amd-hami-main
 else kind load docker-image "$plugin" "$scheduler" "$driver" --name amd-hami-main; fi
 chart_args=(deployments/helm/amd-gpu-mock)
else chart_args=(oci://docker.io/submod/amd-gpu-mock --version "$CHART_VERSION"); fi
helm --kubeconfig "$KUBE" install amd-gpu-mock "${chart_args[@]}" -n amd-mock --create-namespace \
 --set dra.enabled=false --set devicePlugin.enabled=false --set driverMock.enabled=true \
 --set image.repository="${driver%:*}" --set image.tag="${driver##*:}" \
 --set gpu.count=1 --wait --timeout 5m
python3 - "$plugin" "$scheduler" <<'PY'
import json,sys
from pathlib import Path
Path('tmp/hami-main/images.json').write_text(json.dumps({'images':{'plugin':sys.argv[1],'scheduler':sys.argv[2]}}))
PY
python3 demo/hami/deploy.py
scheduler_repo="${scheduler%:*}"; scheduler_tag="${scheduler##*:}"
helm --kubeconfig "$KUBE" upgrade --install hami tmp/hami-main/HAMi/charts/hami -n amd-hami \
 --set devicePlugin.enabled=false --set scheduler.kubeScheduler.image.registry=registry.k8s.io \
 --set scheduler.kubeScheduler.image.repository=kube-scheduler --set 'scheduler.tolerations[0].operator=Exists' \
 --set scheduler.extender.image.registry="${scheduler_repo%%/*}" \
 --set scheduler.extender.image.repository="${scheduler_repo#*/}" --set scheduler.extender.image.tag="$scheduler_tag" --wait --timeout 180s
kubectl --kubeconfig "$KUBE" -n amd-hami set image deploy/hami-scheduler "vgpu-scheduler-extender=$scheduler"
kubectl --kubeconfig "$KUBE" -n amd-hami rollout status deploy/hami-scheduler --timeout=120s
kubectl --kubeconfig "$KUBE" -n amd-hami rollout status ds/amd-gpu-device-plugin-daemonset --timeout=120s
printf 'HAMi ready. Dashboard: http://localhost:%s Grafana: http://localhost:%s\n' "${HAMI_DASHBOARD_PORT:-8081}" "${HAMI_GRAFANA_PORT:-3001}"
printf 'Run: python3 -u demo/hami/verify.py\n'
