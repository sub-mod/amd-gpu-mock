#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHART="$ROOT/deployments/helm/amd-gpu-mock"
KIND="$ROOT/deployments/kind-node/config-chart"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
helm template kind "$KIND" -f "$ROOT/demo/config.yaml" --show-only templates/kind.yaml > "$WORK/kind"
grep -Fq 'hostPort: 8080' "$WORK/kind"
grep -Fq 'hostPort: 3000' "$WORK/kind"
helm template mock "$CHART" -n amd-mock > "$WORK/default"
grep -Fq 'name: mock-amd-gpu-mock-grafana' "$WORK/default"
grep -Fq 'nodePort: 30300' "$WORK/default"
grep -Fq 'dns_sd_configs:' "$WORK/default"
echo 'PASS default kind and chart expose both dashboards and real exporter telemetry'
helm template kind "$KIND" --show-only templates/kind.yaml \
 --set kind.mockDashboardPort=18080 --set kind.grafanaPort=13000 > "$WORK/custom"
grep -Fq 'hostPort: 18080' "$WORK/custom"
grep -Fq 'hostPort: 13000' "$WORK/custom"
echo 'PASS custom host ports render'
helm template kind "$KIND" --show-only templates/kind.yaml \
 --set dashboard.enabled=false --set monitoring.grafana.enabled=false > "$WORK/off-kind"
! grep -Fq 'extraPortMappings:' "$WORK/off-kind"
helm template mock "$CHART" -n amd-mock \
 --set dashboard.enabled=false --set monitoring.grafana.enabled=false > "$WORK/off-chart"
! grep -Fq 'kind: Secret' "$WORK/off-chart"
! grep -Fq 'nodePort:' "$WORK/off-chart"
echo 'PASS disabling dashboards removes host mappings and Grafana workloads'
helm template mock "$CHART" -n amd-mock --set monitoring.enabled=false > "$WORK/external"
! grep -Fq 'kind: Deployment' "$WORK/external"
echo 'PASS external monitoring excludes bundled Prometheus and Grafana'
if helm template kind "$KIND" --show-only templates/kind.yaml \
 --set kind.grafanaPort=8080 > /dev/null 2>&1; then
 echo 'FAIL duplicate host ports accepted' >&2; exit 1
fi
if helm template mock "$CHART" -n amd-mock --set metricsExporter.enabled=false > /dev/null 2>&1; then
 echo 'FAIL monitoring without exporter accepted' >&2; exit 1
fi
echo 'PASS invalid dashboard/monitoring combinations rejected'
python3 - "$ROOT" <<'PY'
import json,sys
from pathlib import Path
r=Path(sys.argv[1])
s=(r/'deployments/metrics-exporter/grafana-dashboard.yaml').read_text().split('  amd-real-exporter.json: |\n',1)[1]
upstream=json.loads('\n'.join(l[4:] for l in s.splitlines()))
assert upstream == json.loads((r/'deployments/helm/amd-gpu-mock/files/amd-real-exporter.json').read_text())
for src,dst in [('deployments/dra/tiny-llm-demo.yaml','demo/llm/dra.yaml'),('deployments/tiny-llm-demo.yaml','demo/llm/device-plugin.yaml'),('deployments/dra/demo.yaml','demo/dra/claim.yaml'),('deployments/partition-demo.yaml','demo/partitioning/physical-workloads.yaml')]:
 assert (r/src).read_text().replace('  namespace: default\n','') == (r/dst).read_text(),dst
print('PASS demo manifests and bundled dashboard match tested source assets')
PY
