#!/usr/bin/env python3
"""Published-cluster demo checks. Run MODE=dra or MODE=device-plugin separately."""
import json
import os
from pathlib import Path
import subprocess
import time

MODE = os.environ.get('MODE', 'dra')
assert MODE in ('dra', 'device-plugin')
ROOT = Path(__file__).resolve().parents[1]

def k(*args):
    return subprocess.check_output(['kubectl', *args], text=True).strip()

def api(path, post=False):
    args = ['wget', '-qO-'] + (['--post-data='] if post else [])
    return json.loads(k('exec', '-n', 'amd-mock', 'ds/amd-gpu-mock', '-c',
                        'node-agent', '--', *args, 'http://localhost:8080' + path))

def gone(label):
    end = time.monotonic() + 120
    while json.loads(k('get', 'pods', '-l', label, '-o', 'json'))['items']:
        assert time.monotonic() < end, 'Demo pods did not clean up'
        time.sleep(1)

def devices(pod, count):
    k('exec', pod, '--', 'sh', '-c',
      f'test -c /dev/kfd && set -- /dev/dri/renderD*; [ "$#" -eq {count} ] && '
      'for d; do test -c "$d" || exit 1; done')

manifest = ROOT / ('deployments/dra/tiny-llm-demo.yaml' if MODE == 'dra'
                   else 'deployments/tiny-llm-demo.yaml')
label = 'tiny-llm-dra' if MODE == 'dra' else 'tiny-llm'
deployment = 'tiny-llm-dra-demo' if MODE == 'dra' else 'tiny-llm-demo'
try:
    k('apply', '-f', str(manifest))
    k('rollout', 'status', 'deployment/' + deployment, '--timeout=180s')
    pod = json.loads(k('get', 'pods', '-l', 'app=' + label, '-o', 'json'))['items'][0]['metadata']['name']
    devices(pod, 1)
    end = time.monotonic() + 30
    while 'LLM service ready.' not in k('logs', pod):
        assert time.monotonic() < end, 'Demo output did not finish'
        time.sleep(1)
    print(f'PASS: {MODE} Tiny LLM scheduled, exact GPU injected, scripted output finished', flush=True)
finally:
    k('delete', '-f', str(manifest), '--ignore-not-found', '--wait=true')
    gone('app=' + label)

# No GPU consumers remain. Partition API is a virtual model, not an allocator.
try:
    for mode, parts in [('DPX', 2), ('CPX', 8), ('QPX', 4), ('SPX', 1), ('CPX', 8), ('SPX', 1)]:
        api('/api/partitions/set?mode=' + mode, True)
        gpus = api('/api/gpus')['gpus']
        assert len(gpus) == 8 * parts
        assert len({g['uuid'] for g in gpus}) == len(gpus)
        assert all(g['memory_total_mb'] == 192 * 1024 // parts for g in gpus)
        assert len({g['pci_bdf'] for g in gpus}) == 8
        if MODE == 'dra':
            slices = json.loads(k('get', 'resourceslices', '-o', 'json'))['items']
            assert sum(len(s['spec'].get('devices', [])) for s in slices) == 8
        else:
            nodes = json.loads(k('get', 'nodes', '-o', 'json'))['items']
            assert int(nodes[0]['status']['allocatable']['amd.com/gpu']) == 8
        print(f'PASS: {MODE} {mode}: {len(gpus)} virtual entries; physical capacity stays 8', flush=True)
finally:
    api('/api/partitions/set?mode=SPX', True)

if MODE == 'device-plugin':
    manifest = ROOT / 'deployments/partition-demo.yaml'
    try:
        k('apply', '-f', str(manifest))
        for deployment in ['llm-inference-a', 'llm-inference-b']:
            k('rollout', 'status', 'deployment/' + deployment, '--timeout=180s')
        pods = json.loads(k('get', 'pods', '-l', 'app=partition-demo', '-o', 'json'))['items']
        assert len(pods) == 4
        allocated = []
        for pod in pods:
            name = pod['metadata']['name']
            devices(name, 1)
            allocated.append(k('exec', name, '--', 'sh', '-c', 'ls /dev/dri/renderD*'))
        assert len(set(allocated)) == 4
        print('PASS: four simultaneous LLM replicas receive four distinct physical GPUs', flush=True)
    finally:
        k('delete', '-f', str(manifest), '--ignore-not-found', '--wait=true')
        gone('app=partition-demo')
