#!/usr/bin/env python3
"""Prove dashboard faults traverse real AMD exporter and Prometheus on CRC."""
from pathlib import Path
import json
import sys
import urllib.parse
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import guard, api, oc, MOCK_NS, wait, get


def http(url, auth=False):
    header = ['--header=Authorization: Basic YWRtaW46YW1kbW9jaw=='] if auth else []
    return json.loads(oc('-n', MOCK_NS, 'exec', 'ds/amd-gpu-mock', '--',
                        'wget', '-qO-', *header, url))


def query(metric):
    data = http('http://amd-gpu-mock-prometheus:9090/api/v1/query?' + urllib.parse.urlencode({'query': metric}))
    assert data['status'] == 'success'
    return [float(r['value'][1]) for r in data['data']['result']]


if __name__ == '__main__':
    guard()
    wait(lambda: len(query('amd_gpu_package_power')) == 8, 'real AMD exporter reports eight GPUs to Prometheus')
    try:
        api('/api/actions/recover?gpu=0', True)
        api('/api/actions/ecc-error?gpu=0&count=7', True)
        wait(lambda: 7 in query('amd_gpu_ecc_uncorrect_total{gpu_id="0"}'),
             'dashboard ECC=7 -> mock AMD SMI -> real AMD exporter -> Prometheus')
        print('ECC_QUERY', query('amd_gpu_ecc_uncorrect_total{gpu_id="0"}'))
    finally:
        api('/api/actions/recover?gpu=0', True)
    wait(lambda: query('amd_gpu_ecc_uncorrect_total{gpu_id="0"}') == [0], 'ECC recovery reaches Prometheus')
    health = http('http://amd-gpu-mock-grafana:3000/api/health')
    assert health['database'] == 'ok'
    sources = http('http://amd-gpu-mock-grafana:3000/api/datasources', True)
    assert any(s['type'] == 'prometheus' for s in sources)
    for name in ['prometheus', 'grafana']:
        pods = get('pods', namespace=MOCK_NS)['items']
        p = next(p for p in pods if p['metadata']['name'].startswith('amd-gpu-mock-' + name + '-'))
        assert p['metadata']['annotations']['openshift.io/scc'] == 'restricted-v2'
    routes = get('routes', namespace=MOCK_NS)['items']
    for route in routes:
        print('ROUTE https://' + route['spec']['host'])
    print('PASS: Grafana healthy and provisioned with Prometheus; Prometheus/Grafana use restricted-v2')
