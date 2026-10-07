#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/release.env"
MOCK_RELEASE="${MOCK_RELEASE:-amd-gpu-mock}"
MOCK_NAMESPACE="${MOCK_NAMESPACE:-amd-mock}"
MONITORING_NAMESPACE="${MONITORING_NAMESPACE:-monitoring}"
CHART="${MOCK_CHART:-oci://$IMAGE_REGISTRY/amd-gpu-mock}"
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update prometheus-community
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
 --version 92.0.0 -f "$ROOT/deployments/metrics-exporter/monitoring-values.yaml" --namespace "$MONITORING_NAMESPACE" --create-namespace \
 --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD:-amdmock}" \
 --set grafana.sidecar.dashboards.searchNamespace=ALL \
 --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
 --wait --timeout 10m
values="$(mktemp)"
trap 'rm -f "$values"' EXIT
helm get values "$MOCK_RELEASE" -n "$MOCK_NAMESPACE" -o yaml > "$values"
args=()
[[ "$CHART" != oci://* ]] || args+=(--version "$CHART_VERSION")
helm upgrade "$MOCK_RELEASE" "$CHART" "${args[@]}" --namespace "$MOCK_NAMESPACE" --reset-values -f "$values" \
 --set image.tag="v$MOCK_IMAGE_VERSION" \
 --set monitoring.enabled=false \
 --set metricsExporter.enabled=true \
 --set metricsExporter.image="$IMAGE_REGISTRY/amd-device-metrics-exporter:$METRICS_EXPORTER_TAG" \
 --set metricsExporter.serviceMonitor.enabled=true \
 --set prometheus.serviceMonitor.enabled=false \
 --wait --timeout 5m
# Rewrite the ConfigMap namespace when users choose a custom monitoring namespace.
sed "s/namespace: monitoring/namespace: $MONITORING_NAMESPACE/" "$ROOT/deployments/metrics-exporter/grafana-dashboard.yaml" | kubectl apply -f -
printf '\nMonitoring installed. Grafana dashboard: AMD GPU Fleet — Device Metrics Exporter\n'
printf 'Access: kubectl -n %s port-forward svc/monitoring-grafana 3000:80\n' "$MONITORING_NAMESPACE"
