#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import guard, namespace, get, pod, ready, evidence, wait, delete, GPU, oc
import json

if __name__ == '__main__':
    node = guard()
    ns = 'amd-crc-allocation'
    namespace(ns)
    # Count scheduled consumers, including other demos; preserve their allocations.
    used = sum(int(c.get('resources', {}).get('requests', {}).get(GPU, 0))
               for p in json.loads(oc('get', 'pods', '-A', '-o', 'json'))['items'] if p['spec'].get('nodeName') == node['metadata']['name']
               and p['status']['phase'] not in ['Succeeded', 'Failed']
               for c in p['spec']['containers'])
    available = int(node['status']['allocatable'].get(GPU, 0)) - used
    assert available > 0, 'No free GPU; clean up an earlier allocation demo'
    pod(ns, 'reserve-free-pool', available)
    ready(ns, 'reserve-free-pool')
    original = evidence(ns, 'reserve-free-pool', available)
    pod(ns, 'waiting-consumer')
    wait(lambda: any(c.get('reason') == 'Unschedulable' and 'Insufficient amd.com/gpu' in c.get('message', '')
                     for c in get('pod', 'waiting-consumer', ns)['status'].get('conditions', [])),
         'genuine GPU exhaustion keeps second consumer Pending')
    delete(ns, 'reserve-free-pool')
    ready(ns, 'waiting-consumer')
    assert evidence(ns, 'waiting-consumer', 1) <= original
    print('PASS: release returns a previously allocated GPU to a pending restricted-v2 Pod')
