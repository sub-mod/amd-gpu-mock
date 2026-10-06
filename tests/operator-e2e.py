#!/usr/bin/env python3
"""Operator controller/operand scheduling smoke test, not DME metrics validation."""
import json
import os
import subprocess
import time

NS = os.environ.get('OPERATOR_NS', 'kube-amd-gpu')
TEST_NS = 'amd-operator-test'

def k(*args, payload=None):
    result = subprocess.run(['kubectl', *args], input=json.dumps(payload) if payload else None,
                            text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result.stdout

def get(kind, ns=None):
    return json.loads(k('get', kind, *(['-n', ns] if ns else []), '-o', 'json'))['items']

def until(predicate, label, timeout=240):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(2)
    raise AssertionError('Timed out: ' + label)

nodes = get('nodes')
assert len(nodes) == 1 and nodes[0]['status']['nodeInfo']['kubeletVersion'].startswith('v1.37.')
assert not any(x['metadata']['name'] == 'amd-gpu-mock-device-plugin'
               for x in get('daemonsets', 'kube-system')), 'Disable the bundled allocator'
controllers = [d for d in get('deployments', NS)
               if d['metadata'].get('labels', {}).get('control-plane') == 'controller-manager']
assert len(controllers) == 1
controller = controllers[0]
k('rollout', 'status', '-n', NS, 'deployment/' + controller['metadata']['name'], '--timeout=240s')
containers = controller['spec']['template']['spec']['containers']
assert any(e.get('name') == 'SIM_ENABLE' and e.get('value') == 'true'
           for c in containers for e in c.get('env', []))
print('PASS: mock-aware Operator controller is ready with SIM_ENABLE', flush=True)
for operand in ['device-plugin', 'node-labeller']:
    until(lambda: any(operand in d['metadata']['name'] for d in get('daemonsets', NS)), operand + ' creation')
    ds = next(d for d in get('daemonsets', NS) if operand in d['metadata']['name'])
    k('rollout', 'status', '-n', NS, 'ds/' + ds['metadata']['name'], '--timeout=240s')
    pods = [p for p in get('pods', NS) if any(o.get('uid') == ds['metadata']['uid']
            for o in p['metadata'].get('ownerReferences', []))]
    assert pods and all(all(c.get('state', {}).get('terminated', {}).get('exitCode') == 0
                            for c in p['status'].get('initContainerStatuses', [])) for p in pods)
    print('PASS: ' + operand + ' is ready and its init containers succeeded', flush=True)
until(lambda: int(get('nodes')[0]['status']['allocatable'].get('amd.com/gpu', 0)) == 8,
      'Operator device-plugin capacity')
print('PASS: Operator advertises eight MI300X GPUs', flush=True)
k('create', 'namespace', TEST_NS)
try:
    k('apply', '-n', TEST_NS, '-f', '-', payload={'apiVersion': 'v1', 'kind': 'Pod',
      'metadata': {'name': 'gpu'}, 'spec': {'restartPolicy': 'Never', 'terminationGracePeriodSeconds': 1,
      'containers': [{'name': 'test', 'image': 'docker.io/busybox:1.36',
      'command': ['sh', '-c', 'sleep 3600'], 'resources': {'limits': {'amd.com/gpu': 1}}}]}})
    k('wait', '-n', TEST_NS, 'pod/gpu', '--for=condition=Ready', '--timeout=180s')
    k('exec', '-n', TEST_NS, 'gpu', '--', 'sh', '-c',
      'test -c /dev/kfd || exit 1; set -- /dev/dri/renderD*; [ "$#" -eq 1 ] && test -c "$1"')
    print('PASS: Operator-scheduled workload receives exactly one GPU render device', flush=True)
    print('Results: 5 passed, 0 failed', flush=True)
finally:
    if os.environ.get('KEEP', '0') != '1':
        k('delete', 'namespace', TEST_NS, '--wait=false')
