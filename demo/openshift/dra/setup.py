#!/usr/bin/env python3
"""Switch this dedicated CRC demo from device plugin to upstream AMD DRA."""
import json
from pathlib import Path
import subprocess
import sys
import yaml
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import guard, oc, get, apply, wait, MOCK_NS, GPU, api


def install():
    guard()
    if len(api('/api/gpus')['gpus']) != 8:
        raise RuntimeError('DRA full-GPU demo requires SPX inventory; run restore first')
    # Remove only known demo workloads, never an unrelated GPU consumer.
    pods = json.loads(oc('get', 'pods', '-A', '-o', 'json'))['items']
    owned = {MOCK_NS, 'amd-crc-multi-gpu', 'amd-crc-allocation'}
    for p in pods:
        if any(GPU in c.get('resources', {}).get('requests', {}) for c in p['spec']['containers']):
            ns, name = p['metadata']['namespace'], p['metadata']['name']
            if ns not in owned:
                raise RuntimeError('Unrelated GPU consumer: ' + ns + '/' + name)
    for p in pods:
        if p['metadata']['namespace'] in owned and any(GPU in c.get('resources', {}).get('requests', {}) for c in p['spec']['containers']):
            print(oc('-n', p['metadata']['namespace'], 'delete', 'pod', p['metadata']['name'], '--wait=true', '--timeout=120s').strip(), flush=True)
    oc('-n', MOCK_NS, 'delete', 'ds', 'amd-gpu-mock-device-plugin', '--ignore-not-found', '--wait=true')
    text = subprocess.check_output(['helm', 'template', 'amd-gpu-mock',
        'oci://docker.io/submod/amd-gpu-mock', '--version', '0.2.13', '-n', MOCK_NS,
        '-f', str(Path(__file__).resolve().parents[1] / 'tiny-llm/values.yaml'),
        '--set', 'devicePlugin.enabled=false', '--set', 'dra.enabled=true',
        '--api-versions', 'security.openshift.io/v1'], text=True)
    docs = [d for d in yaml.safe_load_all(text) if d]
    ds = next(d for d in docs if d['kind'] == 'DaemonSet' and d['metadata']['name'].endswith('-dra-kubeletplugin'))
    # Keep the existing mock agent and its OpenShift namespace/SCC adapter.
    shared = {'ConfigMap', 'Service'}
    for d in docs:
        if d is ds or d['kind'] in shared or d['kind'] == 'DaemonSet':
            continue
        apply(d)
    apply(ds)
    oc('-n', MOCK_NS, 'rollout', 'status', 'ds/' + ds['metadata']['name'], '--timeout=600s')
    wait(lambda: sum(len(s['spec']['devices']) for s in get('resourceslices')['items']
                     if s['spec']['driver'] == 'gpu.amd.com') == 8,
         'unchanged AMD DRA driver advertises eight mock GPUs on OpenShift')


if __name__ == '__main__':
    install()
