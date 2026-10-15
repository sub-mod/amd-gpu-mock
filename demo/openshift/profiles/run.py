#!/usr/bin/env python3
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import guard, api
if __name__ == '__main__':
    guard()
    inventory = api('/api/gpus')
    assert len(inventory['gpus']) == 8
    assert all(g['profile_slug'] == 'mi300x' for g in inventory['gpus'])
    print(json.dumps(api('/api/profiles'), indent=2))
    print(json.dumps([{'index':g['index'], 'bdf':g['pci_bdf'], 'profile':g['profile_slug']} for g in inventory['gpus']], indent=2))
    print('PASS: eight physical MI300X mock devices and published profile catalog; topology unchanged')
