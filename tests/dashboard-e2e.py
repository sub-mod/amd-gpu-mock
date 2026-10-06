#!/usr/bin/env python3
"""Verify automatic host access through the quick-start kind mapping."""
import json
import os
import time
from urllib.request import urlopen

base = os.environ.get('DASHBOARD_URL', 'http://127.0.0.1:8080').rstrip('/')
expected = int(os.environ.get('EXPECTED_GPU_COUNT', '8'))

def read(path):
    end = time.monotonic() + 120
    while True:
        try:
            with urlopen(base + path, timeout=5) as response:
                assert response.status == 200
                return response.read().decode()
        except OSError:
            if time.monotonic() >= end:
                raise
            time.sleep(1)

page = read('/')
assert 'AMD GPU Mock' in page and '</html>' in page, 'Dashboard HTML missing'
print('PASS: dashboard HTML reachable from host without port-forward', flush=True)
fleet = json.loads(read('/api/gpus'))['gpus']
assert len(fleet) == expected and len({g['uuid'] for g in fleet}) == expected
print(f'PASS: host dashboard API reports {expected} distinct GPUs', flush=True)
assert len(json.loads(read('/api/profiles'))) == 7
print('PASS: host dashboard profile API responds', flush=True)
assert 'gpu_temperature' in read('/metrics')
print('PASS: host metrics endpoint responds', flush=True)
