#!/usr/bin/env python3
"""Single-node DRA lifecycle tests against an already installed driver."""
import json
import os
import subprocess
import time

NS = os.environ.get('LIFECYCLE_NS', 'amd-dra-lifecycle')
DRIVER_NS = os.environ.get('DRA_NS', 'amd-mock')
KEEP = os.environ.get('KEEP', '0') == '1'
passed = 0

def kubectl(*args, payload=None, check=True):
    result = subprocess.run(['kubectl', *args], input=json.dumps(payload) if payload else None,
                            text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result

def get(kind, name=None, namespace=NS):
    args = ['get', kind]
    if name:
        args.append(name)
    if namespace:
        args += ['-n', namespace]
    return json.loads(kubectl(*args, '-o', 'json').stdout)

def apply(obj):
    kubectl('apply', '-n', NS, '-f', '-', payload=obj)

def until(predicate, description, timeout=120):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(1)
    raise AssertionError('Timed out: ' + description)

def ok(description):
    global passed
    passed += 1
    print('PASS: ' + description, flush=True)

def claim(name, count=1):
    apply({'apiVersion': 'resource.k8s.io/v1', 'kind': 'ResourceClaim',
           'metadata': {'name': name}, 'spec': {'devices': {'requests': [
               {'name': 'gpu', 'exactly': {'deviceClassName': 'gpu.amd.com', 'count': count}}
           ]}}})

def pod(name, claim_name):
    apply({'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': name}, 'spec': {
        'restartPolicy': 'Never', 'terminationGracePeriodSeconds': 2,
        'containers': [{'name': 'demo', 'image': 'docker.io/busybox:1.36',
                        'command': ['sh', '-c', "trap 'exit 0' TERM INT; sleep 3600 & wait"],
                        'resources': {'claims': [{'name': 'gpu'}]}}],
        'resourceClaims': [{'name': 'gpu', 'resourceClaimName': claim_name}]
    }})

def ready(name):
    kubectl('wait', '-n', NS, 'pod/' + name, '--for=condition=Ready', '--timeout=180s')

def delete(kind, name):
    kubectl('delete', '-n', NS, kind, name, '--wait=true', '--timeout=120s')

def allocation(name):
    return get('resourceclaim', name).get('status', {}).get('allocation', {}).get('devices', {}).get('results', [])

def devices(name, count):
    # Count paths and require character devices, rather than mere file names.
    script = f'''test -c /dev/kfd || exit 1
set -- /dev/dri/renderD*; [ "$#" -eq {count} ] || exit 1
for dev in "$@"; do test -c "$dev" || exit 1; done
set -- /dev/dri/card*; [ "$#" -eq {count} ] || exit 1
for dev in "$@"; do test -c "$dev" || exit 1; done'''
    kubectl('exec', '-n', NS, name, '--', 'sh', '-c', script)

def cdi_exists(uid):
    path = '/var/run/cdi/k8s.gpu.amd.com-gpu_' + uid + '.yaml'
    return kubectl('exec', '-n', DRIVER_NS, 'ds/' + ds, '-c', 'plugin', '--',
                   'test', '-e', path, check=False).returncode == 0

if kubectl('get', 'namespace', NS, check=False).returncode == 0:
    raise SystemExit('Use an unused LIFECYCLE_NS; refusing to reuse ' + NS)
plugins = get('daemonsets', namespace=DRIVER_NS)['items']
plugins = [d for d in plugins if d['metadata'].get('labels', {}).get('app.kubernetes.io/component') == 'kubeletplugin']
assert len(plugins) == 1, 'Expected one DRA DaemonSet'
ds = plugins[0]['metadata']['name']
slices = [s for s in get('resourceslices', namespace=None)['items'] if s['spec']['driver'] == 'gpu.amd.com']
nodes = {s['spec']['nodeName'] for s in slices}
assert len(nodes) == 1, 'Exhaustion test requires one mock node'
count = sum(len(s['spec']['devices']) for s in slices)
assert count >= 2, 'Need at least two GPUs'
kubectl('create', 'namespace', NS)
try:
    claim('multi', 2)
    pod('multi', 'multi')
    ready('multi')
    results = allocation('multi')
    assert len(results) == 2 and len({r['device'] for r in results}) == 2
    devices('multi', 2)
    ok('two-GPU claim gets two distinct GPUs and exactly two card/render pairs')
    multi_uid = get('resourceclaim', 'multi')['metadata']['uid']
    assert cdi_exists(multi_uid)
    delete('pod', 'multi')
    until(lambda: not get('resourceclaim', 'multi').get('status', {}).get('reservedFor'), 'reservation released')
    until(lambda: not allocation('multi'), 'explicit claim deallocated')
    until(lambda: not cdi_exists(multi_uid), 'CDI spec removed after last consumer')
    ok('explicit claim object remains but allocation and CDI are released after its last consumer')
    delete('resourceclaim', 'multi')
    until(lambda: not cdi_exists(multi_uid), 'CDI spec removed')
    ok('unprepare removes the deleted claim CDI spec')

    claim('all', count)
    pod('all', 'all')
    ready('all')
    all_results = allocation('all')
    assert len(all_results) == count and len({r['device'] for r in all_results}) == count
    devices('all', count)
    claim('overflow')
    pod('overflow', 'overflow')
    until(lambda: any(e.get('reason') == 'FailedScheduling' and e.get('involvedObject', {}).get('name') == 'overflow'
                      for e in get('events')['items']), 'overflow scheduling rejection')
    assert not allocation('overflow') and get('pod', 'overflow')['status']['phase'] == 'Pending'
    ok('full-pool allocation is exclusive; an additional claim stays unallocated')
    delete('pod', 'all')
    delete('resourceclaim', 'all')
    ready('overflow')
    devices('overflow', 1)
    ok('pending claim starts after the exhausted pool is released')

    retained = allocation('overflow')
    uid = get('resourceclaim', 'overflow')['metadata']['uid']
    kubectl('rollout', 'restart', '-n', DRIVER_NS, 'ds/' + ds)
    kubectl('rollout', 'status', '-n', DRIVER_NS, 'ds/' + ds, '--timeout=180s')
    devices('overflow', 1)
    assert allocation('overflow') == retained and cdi_exists(uid)
    ok('driver restart preserves allocation and its CDI spec')
    # A second consumer of the same explicit claim shares that allocation.
    pod('shared', 'overflow')
    ready('shared')
    devices('shared', 1)
    reservations = get('resourceclaim', 'overflow')['status']['reservedFor']
    assert len(reservations) == 2
    ok('two pods can consume one explicit claim without a second GPU allocation')
    delete('pod', 'shared')
    delete('pod', 'overflow')
    until(lambda: not get('resourceclaim', 'overflow').get('status', {}).get('reservedFor'), 'explicit consumers released')
    until(lambda: not allocation('overflow'), 'last consumer deallocation')
    pod('reuse', 'overflow')
    ready('reuse')
    assert len(allocation('overflow')) == 1
    devices('reuse', 1)
    ok('existing explicit claim is allocated again for a new consumer')
    delete('pod', 'reuse')
    delete('resourceclaim', 'overflow')
    until(lambda: not cdi_exists(uid), 'final CDI cleanup')
    ok('final explicit-claim deletion removes its CDI spec')
    print(f'Results: {passed} passed, 0 failed', flush=True)
finally:
    if not KEEP:
        kubectl('delete', 'namespace', NS, '--wait=false', check=False)
