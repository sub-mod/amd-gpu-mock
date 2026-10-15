#!/usr/bin/env python3
"""Allocate, prepare, release and reallocate the same device via AMD DRA/CDI."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import guard, namespace, apply, pod, ready, evidence, get, delete, oc, wait

NS = 'amd-crc-dra'


def claim(name, selected=None):
    request = {'name': 'gpu', 'exactly': {'deviceClassName': 'gpu.amd.com'}}
    if selected:
        device = next(d for s in get('resourceslices')['items'] if s['spec']['driver'] == 'gpu.amd.com'
                      for d in s['spec']['devices'] if d['name'] == selected)
        bdf = device['attributes']['resource.kubernetes.io/pciBusID']['string']
        request['exactly']['selectors'] = [{'cel': {'expression':
            'device.attributes["resource.kubernetes.io"].pciBusID == "' + bdf + '"'}}]
    apply({'apiVersion': 'resource.k8s.io/v1', 'kind': 'ResourceClaim',
           'metadata': {'name': name, 'namespace': NS}, 'spec': {'devices': {'requests': [request]}}})


def allocation(name):
    return get('resourceclaim', name, NS)['status']['allocation']['devices']['results'][0]


if __name__ == '__main__':
    guard()
    namespace(NS)
    claim('first-gpu')
    pod(NS, 'first-consumer', claim='first-gpu')
    ready(NS, 'first-consumer')
    first = allocation('first-gpu')
    assert first['driver'] == 'gpu.amd.com'
    expected = '/dev/dri/renderD' + first['device'].split('-')[-1]
    assert evidence(NS, 'first-consumer', 1) == {expected}
    print('ALLOCATED', first, flush=True)
    # Force a second claim to the occupied device: proves scheduler ownership.
    claim('reuse-gpu', first['device'])
    pod(NS, 'reuse-consumer', claim='reuse-gpu')
    wait(lambda: any(c.get('reason') == 'Unschedulable' for c in
                     get('pod', 'reuse-consumer', NS)['status'].get('conditions', [])),
         'second DRA consumer cannot allocate the occupied selected GPU')
    delete(NS, 'first-consumer')
    oc('-n', NS, 'delete', 'resourceclaim', 'first-gpu', '--wait=true')
    ready(NS, 'reuse-consumer')
    second = allocation('reuse-gpu')
    assert first['device'] == second['device']
    assert evidence(NS, 'reuse-consumer', 1) == {expected}
    print('PASS: ResourceSlice -> claim -> scheduler -> AMD NodePrepare -> CRI-O/CDI -> restricted-v2 consumer; selected GPU released and reused')
