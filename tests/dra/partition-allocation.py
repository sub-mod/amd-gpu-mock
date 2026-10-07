#!/usr/bin/env python3
"""Prove fixed MI300X DPX/NPS2 same-parent allocation on an installed DRA cluster.
Uses a dedicated namespace; keeps the final two-container demo for inspection.
KUBECONFIG selects the cluster. No current-context mutation.
"""
import json
import os
import subprocess
import time

NS = os.environ.get('PARTITION_NS', 'amd-demo-partition-allocation')

def k(*args, payload=None):
    p = subprocess.run(['kubectl', *args], input=json.dumps(payload) if payload else None,
                       capture_output=True, text=True, check=True)
    return p.stdout

def get(kind, name=None, namespace=NS):
    return json.loads(k('get', kind, *([name] if name else []),
                        *(['-n', namespace] if namespace else []), '-o', 'json'))

def apply(obj):
    k('apply', '-n', NS, '-f', '-', payload=obj)

def wait(fn, message, timeout=180):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if fn():
            print('PASS:', message, flush=True)
            return
        time.sleep(1)
    raise AssertionError(message)

def devices():
    return {d['name']: d for s in get('resourceslices', namespace=None)['items']
            if s['spec']['driver'] == 'gpu.amd.com' for d in s['spec']['devices']}

def parent(d):
    return d['attributes']['resource.kubernetes.io/pciBusID']['string']

def request(name, bdf=None):
    expression = 'device.attributes["gpu.amd.com"].type == "amdgpu-partition"'
    if bdf:
        expression += ' && device.attributes["resource.kubernetes.io"].pciBusID == ' + json.dumps(bdf)
    return {'name': name, 'exactly': {'deviceClassName': 'gpu.amd.com', 'count': 1,
                                     'selectors': [{'cel': {'expression': expression}}]}}

def claim(name, requests, same_parent=False):
    spec = {'requests': requests}
    if same_parent:
        spec['constraints'] = [{'requests': [r['name'] for r in requests],
                                'matchAttribute': 'resource.kubernetes.io/pciBusID'}]
    apply({'apiVersion': 'resource.k8s.io/v1', 'kind': 'ResourceClaim',
           'metadata': {'name': name}, 'spec': {'devices': spec}})

def pod(name, claim_name, containers=None):
    containers = containers or [('consumer', 'gpu')]
    apply({'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': name}, 'spec': {
        'terminationGracePeriodSeconds': 1, 'restartPolicy': 'Never',
        'resourceClaims': [{'name': 'partition', 'resourceClaimName': claim_name}],
        'containers': [{'name': c, 'image': 'docker.io/busybox:1.36',
            'command': ['sh', '-c', 'test -c /dev/kfd; ls -l /dev/kfd /dev/dri; sleep 86400'],
            'resources': {'claims': [{'name': 'partition', 'request': r}]}}
            for c, r in containers]}})

def ready(name):
    k('wait', '-n', NS, 'pod/' + name, '--for=condition=Ready', '--timeout=180s')

def allocated(name):
    return get('resourceclaim', name).get('status', {}).get('allocation', {}).get('devices', {}).get('results', [])

def evidence(pod_name, claim_name, container='consumer', req='gpu'):
    result = [a for a in allocated(claim_name) if a['request'] == req]
    assert len(result) == 1, result
    assert result[0]['driver'] == 'gpu.amd.com'
    d = devices()[result[0]['device']]
    assert d['attributes']['type']['string'] == 'amdgpu-partition', d
    assert d['attributes']['partitionProfile']['string'] == 'dpx_nps2', d
    assert d['capacity']['memory']['value'] == '96Gi', d
    expected = 'renderD' + result[0]['device'].split('-')[-1]
    output = k('exec', '-n', NS, pod_name, '-c', container, '--', 'sh', '-c',
               'test -c /dev/kfd && for f in /dev/dri/renderD*; do test -c "$f" || exit 1; basename "$f"; done')
    assert output.strip().splitlines() == [expected], output
    print(f'EVIDENCE: {pod_name}/{container}: claim={claim_name} request={req} '
          f'device={result[0]["device"]} parent={parent(d)} memory=96Gi render={expected}', flush=True)
    print(k('logs', '-n', NS, pod_name, '-c', container).strip(), flush=True)
    return result[0]['device'], parent(d)


def cdi_exists(uid):
    return k('exec', '-n', 'amd-mock', 'daemonset/amd-gpu-mock', '--',
             'sh', '-c', f'if test -f /var/run/cdi/k8s.gpu.amd.com-gpu_{uid}.yaml; then echo yes; fi').strip() == 'yes'


def main():
    k('create', 'namespace', NS)
    wait(lambda: len(devices()) == 16, 'AMD driver advertises 16 partitions for 8 physical MI300X GPUs')
    ds = devices()
    parents = {parent(d) for d in ds.values()}
    assert len(parents) == 8
    for address in parents:
        assert sum(parent(d) == address for d in ds.values()) == 2
    for d in ds.values():
        assert d['attributes']['type']['string'] == 'amdgpu-partition'
        assert d['attributes']['partitionProfile']['string'] == 'dpx_nps2'
        assert d['capacity']['memory']['value'] == '96Gi'
        assert d['capacity']['computeUnits']['value'] == '152'
    bdf = sorted({parent(d) for d in ds.values()})[0]
    siblings = {name for name, d in ds.items() if parent(d) == bdf}
    assert len(siblings) == 2, siblings
    for name in ['first', 'second', 'waiting']:
        claim(name, [request('gpu', bdf)])
        pod(name, name)
        if name != 'waiting':
            ready(name)
    first_uid = get('resourceclaim', 'first')['metadata']['uid']
    second_uid = get('resourceclaim', 'second')['metadata']['uid']
    assert cdi_exists(first_uid) and cdi_exists(second_uid)
    first, _ = evidence('first', 'first')
    second, _ = evidence('second', 'second')
    assert {first, second} == siblings
    time.sleep(12)
    assert not allocated('waiting') and get('pod', 'waiting')['status']['phase'] == 'Pending'
    print('PASS: third consumer stays Pending when the selected physical GPU has no free partitions', flush=True)
    k('delete', 'pod', 'first', '-n', NS, '--wait=true')
    # An explicitly created ResourceClaim owns its allocation until it is deleted.
    k('delete', 'resourceclaim', 'first', '-n', NS, '--wait=true')
    wait(lambda: not cdi_exists(first_uid), 'AMD NodeUnprepare removes the released claim CDI file')
    assert cdi_exists(second_uid)
    ready('waiting')
    reused, _ = evidence('waiting', 'waiting')
    assert reused == first
    assert evidence('second', 'second')[0] == second
    print('PASS: released partition is reused while the sibling consumer remains Ready', flush=True)
    old_pods = {p['metadata']['uid'] for p in get('pods', namespace='amd-mock')['items']
                if p['metadata']['labels'].get('app.kubernetes.io/name') == 'dra'}
    assert old_pods
    k('rollout', 'restart', 'daemonset', '-n', 'amd-mock', '-l', 'app.kubernetes.io/name=dra')
    k('rollout', 'status', 'daemonset', '-n', 'amd-mock', '-l', 'app.kubernetes.io/name=dra', '--timeout=180s')
    new_pods = {p['metadata']['uid'] for p in get('pods', namespace='amd-mock')['items']
                if p['metadata']['labels'].get('app.kubernetes.io/name') == 'dra'}
    assert new_pods and old_pods.isdisjoint(new_pods), 'driver pod did not restart'
    assert evidence('second', 'second')[0] == second
    assert evidence('waiting', 'waiting')[0] == reused
    print('PASS: driver restart preserves both live allocations', flush=True)
    for name in ['second', 'waiting']:
        k('delete', 'pod', name, '-n', NS, '--wait=true')
        k('delete', 'resourceclaim', name, '-n', NS, '--wait=true')
    claim('two-slices', [request('left'), request('right')], same_parent=True)
    pod('two-containers', 'two-slices', [('left', 'left'), ('right', 'right')])
    ready('two-containers')
    left, lp = evidence('two-containers', 'two-slices', 'left', 'left')
    right, rp = evidence('two-containers', 'two-slices', 'right', 'right')
    assert left != right and lp == rp
    print('PASS: two containers in one pod receive distinct partitions of the same physical GPU', flush=True)
    print(f'Demo remains Running in namespace {NS}; delete that namespace to release its claims.', flush=True)

if __name__ == '__main__':
    main()
