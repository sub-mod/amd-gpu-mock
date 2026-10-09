#!/usr/bin/env python3
"""Show real Spur queueing, device-plugin allocation, completion and reuse."""
import json
import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
os.environ['KUBECONFIG'] = os.environ.get('SPUR_KUBECONFIG', str(ROOT / 'tmp/spur/kubeconfig'))
NS = 'amd-demo-spur'


def k(*args, payload=None):
    p = subprocess.run(['kubectl', '--request-timeout=20s', *args],
                       input=json.dumps(payload) if payload is not None else None,
                       text=True, capture_output=True, timeout=240)
    if p.returncode:
        raise RuntimeError(p.stderr or p.stdout)
    return p.stdout


def get(kind, name=None):
    return json.loads(k('get', kind, *([name] if name else []), '-n', NS, '-o', 'json'))


def wait(predicate, message, timeout=180):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            print('PASS: ' + message, flush=True)
            return
        time.sleep(2)
    raise AssertionError('Timed out: ' + message)


def pods(name):
    job_id = get('spurjob', name).get('status', {}).get('spurJobId')
    if job_id is None:
        return []
    return [p for p in get('pods')['items']
            if p['metadata'].get('labels', {}).get('spur.amd.com/job-id') == str(job_id)]


def running(name):
    return any(p.get('status', {}).get('phase') == 'Running' and
               all(c.get('ready') for c in p.get('status', {}).get('containerStatuses', [])) for p in pods(name))


def state(name):
    return get('spurjob', name).get('status', {}).get('state')


def submit(name, count):
    script = f'''set -eu
echo "BEGIN job={name} requested_gpus={count} host=$(hostname)"
test -c /dev/kfd
set -- /dev/dri/renderD*; [ "$#" -eq {count} ]
for d in "$@"; do test -c "$d"; done
stat -c '%n %t:%T' /dev/kfd /dev/dri/renderD*
echo DEVICE_INJECTION_PASS
echo "Waiting for presenter release; no GPU computation is performed."
while [ ! -e /tmp/presenter-release ]; do sleep 1; done
echo JOB_COMPLETED'''
    obj = {'apiVersion': 'spur.amd.com/v1alpha1', 'kind': 'SpurJob',
           'metadata': {'name': name, 'namespace': NS}, 'spec': {
               'name': name, 'image': 'docker.io/busybox:1.36',
               'gpus': {'count': count, 'gpuType': 'mi300x'},
               'cpusPerTask': 1, 'memoryPerNode': '64Mi', 'timeLimit': '10m',
               'command': ['/bin/sh', '-c'], 'args': [script],
               'nodeSelector': {'spur.amd.com/managed': 'true'}}}
    k('create', '-f', '-', payload=obj)


def show(name, count):
    p = pods(name)
    assert len(p) == 1, p
    p = p[0]
    limits = p['spec']['containers'][0]['resources']['limits']
    assert limits['amd.com/gpu'] == str(count), limits
    assert not p['spec'].get('hostPID') and not p['spec'].get('hostNetwork')
    assert not p['spec']['containers'][0].get('securityContext', {}).get('privileged')
    assert not any(v.get('hostPath', {}).get('path', '').startswith('/dev') for v in p['spec'].get('volumes', []))
    output = k('logs', '-n', NS, p['metadata']['name'])
    assert 'DEVICE_INJECTION_PASS' in output, output
    print(f'EVIDENCE SpurJob={name} id={get("spurjob", name)["status"]["spurJobId"]} '
          f'Pod={p["metadata"]["name"]} node={p["spec"]["nodeName"]} amd.com/gpu={count}', flush=True)
    print(output, flush=True)
    return p['metadata']['name']


def release(name, pod_name):
    k('exec', '-n', NS, pod_name, '--', 'touch', '/tmp/presenter-release')
    wait(lambda: state(name) == 'Completed', name + ' reaches Completed through Spur')
    print(k('logs', '-n', NS, pod_name), flush=True)


def main():
    existing = get('spurjobs')['items']
    assert not existing, 'Demo namespace already has SpurJobs; clean up jobs before rerunning'
    nodes = json.loads(k('get', 'nodes', '-l', 'spur.amd.com/managed=true', '-o', 'json'))['items']
    assert len(nodes) == 1, 'This demo requires exactly one managed node'
    capacity = int(nodes[0]['status']['allocatable']['amd.com/gpu'])
    assert capacity >= 1
    print(k('exec', '-n', NS, 'deploy/spurctld', '--', 'spur', '--version'), flush=True)
    submit('hold-pool', capacity)
    wait(lambda: running('hold-pool'), 'Spur creates a running job consuming the whole mock GPU pool')
    first = show('hold-pool', capacity)
    submit('queued-gpu', 1)
    wait(lambda: state('queued-gpu') == 'Pending', 'second SpurJob is Pending while the pool is occupied')
    for _ in range(5):
        time.sleep(2)
        assert state('queued-gpu') == 'Pending' and not pods('queued-gpu'), 'Spur dispatched the blocked job'
    print(k('exec', '-n', NS, 'deploy/spurctld', '--', 'env', 'SPUR_CONTROLLER_ADDR=http://localhost:6817', 'spur', 'queue'), flush=True)
    print('PASS: Spur keeps the second job queued without creating a competing GPU Pod', flush=True)
    release('hold-pool', first)
    wait(lambda: running('queued-gpu'), 'queued job starts after the first job releases the GPU pool')
    second = show('queued-gpu', 1)
    release('queued-gpu', second)
    print(k('get', 'spurjobs,pods', '-n', NS, '-o', 'wide'), flush=True)
    print('PASS: unchanged Spur submission, GPU allocation, queueing, completion and reuse', flush=True)


if __name__ == '__main__':
    main()
