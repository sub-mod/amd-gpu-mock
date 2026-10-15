#!/usr/bin/env python3
import json
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import guard, api
if __name__ == '__main__':
    before = guard()['status']['allocatable'].get('amd.com/gpu')
    try:
        changed = api('/api/partitions/set?mode=CPX', True)
        print(json.dumps(changed, indent=2))
        assert api('/api/partitions')['current'] == 'CPX'
        assert guard()['status']['allocatable'].get('amd.com/gpu') == before
        print('PASS: CPX dashboard state changes; schedulable GPU capacity remains unchanged')
    finally:
        api('/api/partitions/set?mode=SPX', True)
        print('PASS: SPX state restored; this is not allocatable hardware slicing')
