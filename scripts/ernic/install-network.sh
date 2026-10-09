#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
source "$HERE/versions.env"
CONTEXT="${KUBE_CONTEXT:-kind-amd-mock}"
CACHE="${ERNIC_STATE_DIR:-$ROOT/tmp/ernic}"
SRC="$CACHE/network-operator"
mkdir -p "$SRC"
if [ ! -f "$SRC/.source-revision" ]; then
 curl -fsSL "https://api.github.com/repos/ROCm/network-operator/tarball/$NETWORK_OPERATOR_COMMIT" -o "$CACHE/operator.tar.gz"
 tar -xzf "$CACHE/operator.tar.gz" --strip-components=1 -C "$SRC"
 printf '%s\n' "$NETWORK_OPERATOR_COMMIT" > "$SRC/.source-revision"
fi
[ "$(cat "$SRC/.source-revision")" = "$NETWORK_OPERATOR_COMMIT" ]
# The upstream chart hard-codes this ConfigMap and exposes no values override.
# Use a derived chart with one configuration template override; preserve source archive.
CHART="$CACHE/configured-network-chart"
rm -rf "$CHART"
cp -R "$SRC/helm-charts-k8s" "$CHART"
cp "$HERE/plugin-config.yaml" "$CHART/templates/device-plugin-config.yaml"
k=(kubectl --context "$CONTEXT")
"${k[@]}" apply -f "$SRC/helm-charts-k8s/charts/kmm/crds/module-crd.yaml" -f "$SRC/helm-charts-k8s/charts/kmm/crds/nodemodulesconfig-crd.yaml"
helm upgrade --install amd-network "$CHART" --kube-context "$CONTEXT" \
 -n kube-amd-network --create-namespace --set kmm.enabled=false \
 --set installdefaultNFDRule=false --set upgradeCRD=false \
 --set "controllerManager.manager.image.repository=${NETWORK_OPERATOR_IMAGE%:*}" \
 --set "controllerManager.manager.image.tag=${NETWORK_OPERATOR_IMAGE##*:}" \
 --set controllerManager.manager.imagePullPolicy=IfNotPresent \
 --wait --timeout=5m
"${k[@]}" apply -f "$HERE/ernic-discovery.yaml"
NETWORK_PLUGIN_IMAGE="$NETWORK_PLUGIN_IMAGE" python3 - <<'PY' | "${k[@]}" apply -f -
import json,os
print(json.dumps({"apiVersion":"amd.com/v1alpha1","kind":"NetworkConfig","metadata":{"name":"ernic","namespace":"kube-amd-network"},"spec":{"driver":{"enable":False},"devicePlugin":{"enableNodeLabeller":False,"devicePluginImage":os.environ["NETWORK_PLUGIN_IMAGE"],"devicePluginImagePullPolicy":"IfNotPresent"},"metricsExporter":{"enable":False},"secondaryNetwork":{"cniPlugins":{"enable":False}},"selector":{"feature.node.kubernetes.io/amd-nic":"true"}}}))
PY
