#!/usr/bin/env python3
"""Installed-driver DRA capacity, container-sharing and PCIe-root checks.

Uses normal claims and Pods in a new namespace. Does not modify discovery,
allocation status, driver settings, or existing workloads. Requires two free
GPUs on one node with the same advertised PCIe root. KUBECONFIG selects cluster.
"""
import json
import os
import subprocess
import time

NS = os.environ.get('FOCUSED_NS', 'amd-dra-focused')
KEEP = os.environ.get('KEEP', '0') == '1'
ROOT = 'resource.kubernetes.io/pcieRoot'
DRIVER = 'gpu.amd.com'
passed = 0


def k(*args, payload=None, check=True):
    result = subprocess.run(['kubectl', '--request-timeout=30s', *args],
                            input=json.dumps(payload) if payload is not None else None,
                            capture_output=True, text=True, timeout=240)
    if check and result.returncode:
        raise RuntimeError(result.stderr or result.stdout)
    return result


def get(kind, name=None, namespace=NS):
    return json.loads(k('get', kind, *([name] if name else []),
                        *(['-n', namespace] if namespace else (['-A'] if kind == 'resourceclaims' else [])), '-o', 'json').stdout)


def apply(obj):
    k('apply', '-n', NS, '-f', '-', payload=obj)


def results(name):
    return get('resourceclaim', name).get('status', {}).get('allocation', {}).get('devices', {}).get('results', [])


def request(name='gpu', memory=None, expression=None):
    exactly = {'deviceClassName': DRIVER, 'count': 1}
    if memory:
        exactly['capacity'] = {'requests': {'memory': memory}}
    if expression:
        exactly['selectors'] = [{'cel': {'expression': expression}}]
    return {'name': name, 'exactly': exactly}


def claim(name, requests, constraints=None):
    devices = {'requests': requests}
    if constraints:
        devices['constraints'] = constraints
    apply({'apiVersion': 'resource.k8s.io/v1', 'kind': 'ResourceClaim',
           'metadata': {'name': name}, 'spec': {'devices': devices}})


# Compare path plus major/minor identity, not just a successful ls command.
PROBE = '''set -eu
test -c /dev/kfd
set -- /dev/dri/card*; [ "$#" -eq 1 ]; test -c "$1"
set -- /dev/dri/renderD*; [ "$#" -eq 1 ]; test -c "$1"
stat -c '%n %t:%T' /dev/kfd /dev/dri/card* /dev/dri/renderD*'''


def pod(name, node, sharing=False):
    container = {'name': 'main', 'image': 'docker.io/busybox:1.36',
                 'command': ['sh', '-c', PROBE + '\nsleep 3600'],
                 'resources': {'claims': [{'name': 'gpu'}]}}
    spec = {'restartPolicy': 'Never', 'terminationGracePeriodSeconds': 1,
            'nodeSelector': {'kubernetes.io/hostname': node},
            'resourceClaims': [{'name': 'gpu', 'resourceClaimName': name}],
            'containers': [container]}
    if sharing:
        init = dict(container, name='gpu-check', command=['sh', '-c', PROBE])
        spec['initContainers'] = [init]
    apply({'apiVersion': 'v1', 'kind': 'Pod', 'metadata': {'name': name}, 'spec': spec})


def ready(name):
    k('wait', '-n', NS, 'pod/' + name, '--for=condition=Ready', '--timeout=180s')


def pending(name):
    deadline = time.monotonic() + 120
    while time.monotonic() < deadline:
        p = get('pod', name)
        events = get('events')['items']
        rejected = any(e.get('reason') == 'FailedScheduling' and
                       e.get('involvedObject', {}).get('uid') == p['metadata']['uid']
                       for e in events)
        if rejected:
            assert p['status']['phase'] == 'Pending' and not results(name), p
            # Keep observing after rejection to catch an unexpected allocation.
            for _ in range(5):
                time.sleep(1)
                assert not results(name) and get('pod', name)['status']['phase'] == 'Pending'
            return
        time.sleep(1)
    raise AssertionError('No scheduling rejection for ' + name)


def release(name):
    for kind in ('pod', 'resourceclaim'):
        k('delete', '-n', NS, kind, name, '--wait=true', '--timeout=120s')


def ok(message):
    global passed
    passed += 1
    print('PASS: ' + message, flush=True)


def main():
    # Read-only preflight before creating any resources.
    healthy = {p['spec']['nodeName'] for p in get('pods', namespace=os.environ.get('DRA_NS', 'amd-mock'))['items']
               if any(c['name'] == 'node-agent' for c in p['spec']['containers'])
               and any(c['type'] == 'Ready' and c['status'] == 'True'
                       for c in p.get('status', {}).get('conditions', []))}
    assert healthy, 'No Ready mock node agents; repair the installed stack before running these tests'
    # Driver readiness can precede its first ResourceSlice publication.
    deadline = time.monotonic() + 120
    while True:
        slices = [s for s in get('resourceslices', namespace=None)['items']
                  if s['spec']['driver'] == DRIVER]
        inventory = {(s['spec']['pool']['name'], d['name']): (s['spec']['nodeName'], d)
                     for s in slices for d in s['spec']['devices']}
        used = {(r['pool'], r['device']) for c in get('resourceclaims', namespace=None)['items']
                for r in c.get('status', {}).get('allocation', {}).get('devices', {}).get('results', [])
                if r['driver'] == DRIVER}
        groups = {}
        for key, (node, d) in inventory.items():
            if key not in used and node in healthy:
                root = d['attributes'][ROOT]['string']
                groups.setdefault((node, root), []).append((key, d))
        candidates = [(key, devices) for key, devices in sorted(groups.items()) if len(devices) >= 2]
        if candidates:
            break
        assert time.monotonic() < deadline, 'Need two free AMD devices on one node with the same PCIe root'
        time.sleep(1)
    (node, root), devices = candidates[0]
    # Device names are scoped to pools; never compare names across nodes alone.
    _, device = devices[0]
    device_selector = ('device.attributes["resource.kubernetes.io"].pciBusID == ' +
                       json.dumps(device['attributes']['resource.kubernetes.io/pciBusID']['string']))
    assert k('get', 'namespace', NS, check=False).returncode != 0, 'Use an unused FOCUSED_NS'
    k('create', 'namespace', NS)
    try:
        print(f'PREFLIGHT node={node} root={root} free_siblings={len(devices)}', flush=True)
        # Exact advertised capacity avoids lossy parsing of Kubernetes quantities.
        memory = device['capacity']['memory']['value']
        claim('memory-fit', [request(memory=memory, expression=device_selector)])
        pod('memory-fit', node)
        ready('memory-fit')
        allocated = results('memory-fit')
        assert len(allocated) == 1
        key = (allocated[0]['pool'], allocated[0]['device'])
        assert inventory[key][0] == node
        assert inventory[key][1]['capacity']['memory']['value'] == memory
        k('exec', '-n', NS, 'memory-fit', '--', 'sh', '-c', PROBE)
        ok(f'memory request {memory} allocates a matching device with CDI injection')
        release('memory-fit')

        # 1 EiB exceeds all supported mock profiles (maximum 192 GiB).
        # Both API acceptance and a scheduler rejection are required for PASS.
        claim('memory-too-large', [request(memory='1Ei', expression=device_selector)])
        pod('memory-too-large', node)
        pending('memory-too-large')
        ok('oversized memory request is accepted but remains Pending and unallocated')
        release('memory-too-large')

        claim('shared-container', [request(expression=device_selector)])
        pod('shared-container', node, sharing=True)
        ready('shared-container')
        assert len(results('shared-container')) == 1
        p = get('pod', 'shared-container')
        assert p['status']['initContainerStatuses'][0]['state']['terminated']['exitCode'] == 0
        init = k('logs', '-n', NS, 'shared-container', '-c', 'gpu-check').stdout.strip()
        main_log = k('logs', '-n', NS, 'shared-container', '-c', 'main').stdout.strip()
        assert init and init == main_log, (init, main_log)
        a = results('shared-container')[0]
        assert 'renderD' + a['device'].split('-')[-1] in init
        print('EVIDENCE init/main device identity:\n' + init, flush=True)
        ok('init and main containers use one allocation and identical card/render/KFD identities')
        release('shared-container')

        root_selector = ('device.attributes["resource.kubernetes.io"].pcieRoot == ' + json.dumps(root))
        requests = [request('left', expression=root_selector), request('right', expression=root_selector)]
        constraint = [{'requests': ['left', 'right'], 'matchAttribute': ROOT}]
        claim('root-match', requests, constraint)
        pod('root-match', node)
        ready('root-match')
        allocations = results('root-match')
        keys = {(a['pool'], a['device']) for a in allocations}
        assert len(allocations) == len(keys) == 2
        assert all(inventory[key][0] == node and inventory[key][1]['attributes'][ROOT]['string'] == root
                   for key in keys)
        print('EVIDENCE same-root allocation: ' + json.dumps(allocations), flush=True)
        ok('two distinct devices satisfy the same-PCIe-root matchAttribute constraint')
        release('root-match')

        # Each selector is satisfiable; equal roots cannot satisfy distinctAttribute.
        # This proves constraint enforcement rather than a nonexistent-root selector.
        claim('root-impossible', requests, [{'requests': ['left', 'right'], 'distinctAttribute': ROOT}])
        pod('root-impossible', node)
        pending('root-impossible')
        ok('individually matching requests with contradictory PCIe-root constraint remain unallocated')
        release('root-impossible')
        print(f'Results: {passed} passed, 0 failed', flush=True)
    except Exception:
        for kind in ('pods', 'resourceclaims', 'events'):
            diagnostic = k('get', kind, '-n', NS, '-o', 'yaml', check=False)
            print(diagnostic.stdout or diagnostic.stderr, flush=True)
        raise
    finally:
        if not KEEP:
            k('delete', 'namespace', NS, '--wait=false', check=False)


if __name__ == '__main__':
    main()
