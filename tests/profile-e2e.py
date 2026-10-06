#!/usr/bin/env python3
"""Physical device-plugin scheduling/fault contracts on a dedicated one-node cluster."""
import json
import os
import subprocess
import time

NS = os.environ.get('MOCK_NS', 'amd-mock')
TEST_NS = os.environ.get('PROFILE_TEST_NS', 'amd-profile-test')
PROFILE = os.environ.get('PROFILE', 'mi300x')
COUNTS = {'mi210': 8, 'mi250x': 16, 'mi300a': 4, 'mi300x': 8,
          'mi325x': 8, 'mi350x': 8, 'mi355x': 8}
passed = 0

def k(*args, payload=None, check=True):
    result = subprocess.run(['kubectl', *args], input=json.dumps(payload) if payload else None,
                            text=True, capture_output=True)
    if check and result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result

def get(kind, name=None, namespace=TEST_NS):
    args = ['get', kind] + ([name] if name else [])
    if namespace:
        args += ['-n', namespace]
    return json.loads(k(*args, '-o', 'json').stdout)

def agent(*args):
    return k('exec', '-n', NS, 'ds/amd-gpu-mock', '-c', 'node-agent', '--', *args).stdout

def api(path, post=False):
    args = ['wget', '-qO-'] + (['--post-data='] if post else [])
    return json.loads(agent(*args, 'http://localhost:8080' + path))

def until(predicate, label, timeout=120):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        if predicate():
            return
        time.sleep(1)
    raise AssertionError('Timed out: ' + label)

def ok(label):
    global passed
    passed += 1
    print('PASS: ' + label, flush=True)

def capacity():
    return int(get('node', node, namespace=None)['status']['allocatable'].get('amd.com/gpu', 0))

def restart_plugin():
    k('rollout', 'restart', '-n', 'kube-system', 'ds/amd-gpu-mock-device-plugin')
    k('rollout', 'status', '-n', 'kube-system', 'ds/amd-gpu-mock-device-plugin', '--timeout=120s')

def pod(name, count):
    k('apply', '-n', TEST_NS, '-f', '-', payload={
        'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': name}, 'spec': {
            'restartPolicy': 'Never', 'terminationGracePeriodSeconds': 1,
            'containers': [{'name': 'test', 'image': 'docker.io/busybox:1.36',
                            'command': ['sh', '-c', "trap 'exit 0' TERM INT; sleep 3600 & wait"],
                            'resources': {'limits': {'amd.com/gpu': count}}}]}})

def ready(name):
    k('wait', '-n', TEST_NS, 'pod/' + name, '--for=condition=Ready', '--timeout=180s')

def delete_pod(name):
    k('delete', '-n', TEST_NS, 'pod', name, '--wait=true', '--timeout=120s')

nodes = get('nodes', namespace=None)['items']
assert len(nodes) == 1, 'Use a dedicated single-node cluster'
node = nodes[0]['metadata']['name']
assert nodes[0]['status']['nodeInfo']['kubeletVersion'].startswith('v1.37.'), 'Requires Kubernetes 1.37'
assert not [x for x in get('daemonsets', namespace=NS)['items']
            if x['metadata'].get('labels', {}).get('app.kubernetes.io/component') == 'kubeletplugin'], 'Disable DRA'
if k('get', 'namespace', TEST_NS, check=False).returncode == 0:
    raise SystemExit('Use an unused PROFILE_TEST_NS')
count = COUNTS[PROFILE]
k('create', 'namespace', TEST_NS)
try:
    catalog = {p['slug']: p for p in api('/api/profiles')}
    fleet = api('/api/gpus')['gpus']
    assert len(fleet) == count == catalog[PROFILE]['gpu_count']
    assert all(g['name'] == catalog[PROFILE]['name'] and g['profile_slug'] == PROFILE and
               g['memory_total_mb'] == catalog[PROFILE]['memory_gb'] * 1024 for g in fleet)
    assert len({g['uuid'] for g in fleet}) == count
    until(lambda: capacity() == count, 'profile resource count')
    ok(PROFILE + ': API identity/memory and allocatable count match the profile')
    pod('one', 1)
    ready('one')
    k('exec', '-n', TEST_NS, 'one', '--', 'sh', '-c',
      'test -c /dev/kfd && set -- /dev/dri/renderD*; [ "$#" -eq 1 ] && test -c "$1"')
    ok('one-GPU consumer receives exactly one render character device')
    delete_pod('one')
    pod('full', count)
    ready('full')
    pod('overflow', 1)
    until(lambda: any(e.get('reason') == 'FailedScheduling' and
                      e.get('involvedObject', {}).get('name') == 'overflow'
                      for e in get('events')['items']), 'exhaustion scheduling rejection')
    assert get('pod', 'overflow')['status']['phase'] == 'Pending'
    ok('full-pool consumer excludes an additional GPU request')
    delete_pod('full')
    ready('overflow')
    delete_pod('overflow')
    ok('pending consumer starts after capacity is released')
    bdf = fleet[0]['pci_bdf']
    api('/api/actions/crash?gpu=0', post=True)
    assert api('/api/gpus')['gpus'][0]['status'] == 'crashed'
    assert agent('cat', '/var/lib/amd-gpu-mock/sys/class/kfd/kfd/topology/nodes/1/ras/fatal_error').strip() == '1'
    agent('sh', '-c', 'test ! -e /var/lib/amd-gpu-mock/sys/module/amdgpu/drivers/pci:amdgpu/' + bdf)
    restart_plugin()
    until(lambda: capacity() == count - 1, 'crashed GPU removed from scheduling')
    ok('crash reaches sysfs and device-plugin capacity after rediscovery')
    api('/api/actions/recover?gpu=0', post=True)
    restart_plugin()
    until(lambda: capacity() == count, 'recovered GPU rediscovered')
    ok('recovery restores physical GPU capacity')
    hot = api('/api/actions/overheat?gpu=0', post=True)
    assert hot['status'] == 'overheating'
    assert int(agent('cat', '/var/lib/amd-gpu-mock/sys/class/drm/card0/device/hwmon/hwmon0/temp1_input')) == hot['temperature_c'] * 1000
    api('/api/actions/recover?gpu=0', post=True)
    ok('overheat reaches the sysfs temperature sensor')
    api('/api/actions/ecc-error?gpu=0', post=True)
    assert int(agent('cat', '/var/lib/amd-gpu-mock/sys/class/kfd/kfd/topology/nodes/1/ras/ecc_uncorrectable')) > 0
    api('/api/actions/recover?gpu=0', post=True)
    assert agent('cat', '/var/lib/amd-gpu-mock/sys/class/kfd/kfd/topology/nodes/1/ras/ecc_uncorrectable').strip() == '0'
    ok('ECC injection and recovery reach sysfs')
    print(f'Results: {passed} passed, 0 failed', flush=True)
finally:
    api('/api/actions/recover?gpu=0', post=True)
    if os.environ.get('KEEP', '0') != '1':
        k('delete', 'namespace', TEST_NS, '--wait=false', check=False)
