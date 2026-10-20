#!/usr/bin/env python3
"""Exercise the optional backend against the real renderer and real CUSE."""
import json
import os
from pathlib import Path
import subprocess
import time
import urllib.request

RUNTIME = os.environ.get('CONTAINER_RUNTIME', 'podman')
IMAGE = os.environ.get('DRIVER_IMAGE', 'localhost/amd-gpu-mock-driver:dev')
NAME = 'amd-main-cuse-check'
PORT = os.environ.get('DRIVER_TEST_PORT', '18080')
ROOT = '/var/lib/amd-gpu-mock'

def run(*args):
    return subprocess.check_output(list(args), text=True)

def api(path):
    with urllib.request.urlopen('http://127.0.0.1:' + PORT + path, timeout=10) as f:
        return json.load(f)

def wait_ready():
    for _ in range(120):
        try:
            return api('/api/gpus')
        except (OSError, ValueError):
            time.sleep(.25)
    raise RuntimeError('provider did not become ready')

def probe(index, cu, memory, name, unavailable=False):
    for node in ['card' + str(index), 'renderD' + str(128 + index)]:
        print(run(RUNTIME, 'exec', '-e', 'AMD_DRIVER_MOCK_ROOT=' + ROOT,
                  NAME, 'driver-probe', ROOT + '/dev/dri/' + node,
                  'unavailable' if unavailable else str(cu), str(memory), name), flush=True)

# Never replace an existing container of the same name.
run(RUNTIME, 'run', '-d', '--privileged', '--name', NAME,
    '-p', '127.0.0.1:' + PORT + ':8080', '--entrypoint', 'node-agent', IMAGE,
    '--config=/etc/amd-gpu-mock/profiles/mi300x.yaml',
    '--device-backend=cuse', '--cuse-host-dev=/sandbox-dev', '--root=' + ROOT)
try:
    wait_ready()
    for profile in ['mi210', 'mi250x', 'mi300a', 'mi300x', 'mi325x', 'mi350x', 'mi355x']:
        api('/api/profiles/switch?profile=' + profile)
        gpus = api('/api/gpus')['gpus']
        for i in range(len(gpus)):
            properties = run(RUNTIME, 'exec', NAME, 'cat', ROOT + '/sys/class/kfd/kfd/topology/nodes/' + str(i + 1) + '/properties')
            props = dict(line.split(maxsplit=1) for line in properties.splitlines())
            smi = run(RUNTIME, 'exec', NAME, 'cat', ROOT + '/smi/gpu' + str(i)).splitlines()
            probe(i, int(props['simd_count']) // int(props['simd_per_cu']), int(props['local_mem_size']), smi[1])
        print('PASS all native devices and libdrm capacity: ' + profile, flush=True)
    api('/api/profiles/switch?profile=mi300x')
    api('/api/actions/crash?gpu=0')
    probe(0, 304, 206158430208, 'AMD Instinct MI300X', unavailable=True)
    api('/api/actions/recover?gpu=0')
    probe(0, 304, 206158430208, 'AMD Instinct MI300X')
    print('PASS dashboard fault/recovery preserves CUSE-backed devices', flush=True)
    # Abrupt provider loss leaves no falsely successful open. Restart recreates
    # endpoints and replaces stale major numbers using the persisted marker.
    run(RUNTIME, 'kill', NAME)
    run(RUNTIME, 'start', NAME)
    wait_ready()
    probe(7, 304, 206158430208, 'AMD Instinct MI300X')
    print('PASS unclean provider restart and native device access', flush=True)
finally:
    print(run(RUNTIME, 'logs', NAME), flush=True)
    run(RUNTIME, 'rm', '-f', NAME)
