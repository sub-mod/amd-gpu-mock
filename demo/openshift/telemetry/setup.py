#!/usr/bin/env python3
"""Add published real AMD exporter, Prometheus and Grafana to the CRC mock."""
from pathlib import Path
import subprocess
import sys
import yaml
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import guard, apply, oc, MOCK_NS

if __name__ == '__main__':
    guard()
    text = subprocess.check_output(['helm', 'template', 'amd-gpu-mock',
        'oci://docker.io/submod/amd-gpu-mock', '--version', '0.2.13', '-n', MOCK_NS,
        '-f', str(Path(__file__).resolve().parents[1] / 'tiny-llm/values.yaml'),
        '--set', 'metricsExporter.enabled=true', '--set', 'monitoring.enabled=true'], text=True)
    docs = []
    for d in yaml.safe_load_all(text):
        if not d or not any(s in d['metadata']['name'] for s in ['metrics-exporter', 'prometheus', 'grafana']):
            continue
        if d['kind'] not in ['ClusterRole', 'ClusterRoleBinding']:
            d['metadata']['namespace'] = MOCK_NS
        if d['kind'] == 'DaemonSet':
            d['spec']['template']['spec']['containers'][0]['securityContext'] = {'privileged': True}
        if d['kind'] == 'Deployment':
            tmpl = d['spec']['template']
            tmpl['metadata']['annotations'] = {'openshift.io/required-scc': 'restricted-v2'}
            tmpl['spec']['securityContext'] = {'runAsNonRoot': True, 'seccompProfile': {'type': 'RuntimeDefault'}}
            for c in tmpl['spec']['containers']:
                c['securityContext'] = {'allowPrivilegeEscalation': False, 'capabilities': {'drop': ['ALL']}}
        if d['kind'] == 'Service' and 'grafana' in d['metadata']['name']:
            d['spec']['type'] = 'ClusterIP'
            for port in d['spec']['ports']:
                port.pop('nodePort', None)
        docs.append(d)
    for d in docs:
        if d['kind'] not in ['Deployment', 'DaemonSet']:
            apply(d)
    apply({'apiVersion': 'rbac.authorization.k8s.io/v1', 'kind': 'RoleBinding',
           'metadata': {'name': 'exporter-privileged-scc', 'namespace': MOCK_NS},
           'roleRef': {'apiGroup': 'rbac.authorization.k8s.io', 'kind': 'Role', 'name': 'mock-privileged-scc'},
           'subjects': [{'kind': 'ServiceAccount', 'name': 'amd-gpu-mock-metrics-exporter', 'namespace': MOCK_NS}]})
    for d in docs:
        if d['kind'] in ['Deployment', 'DaemonSet']:
            apply(d)
    oc('-n', MOCK_NS, 'rollout', 'status', 'ds/amd-gpu-mock-metrics-exporter', '--timeout=600s')
    for component in ['prometheus', 'grafana']:
        oc('-n', MOCK_NS, 'rollout', 'status', 'deployment/amd-gpu-mock-' + component, '--timeout=600s')
    apply({'apiVersion': 'route.openshift.io/v1', 'kind': 'Route',
           'metadata': {'name': 'amd-mock-grafana', 'namespace': MOCK_NS},
           'spec': {'to': {'kind': 'Service', 'name': 'amd-gpu-mock-grafana'},
                    'tls': {'termination': 'edge'}}})
    apply({'apiVersion': 'route.openshift.io/v1', 'kind': 'Route',
           'metadata': {'name': 'amd-mock-dashboard', 'namespace': MOCK_NS},
           'spec': {'to': {'kind': 'Service', 'name': 'amd-gpu-mock-metrics'},
                    'tls': {'termination': 'edge'}}})
    print('PASS: real AMD exporter, Prometheus, Grafana and OpenShift Routes ready')
