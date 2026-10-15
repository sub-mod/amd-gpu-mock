#!/usr/bin/env python3
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import guard, api, oc, MOCK_NS

if __name__ == '__main__':
    guard()
    def file(path):
        return oc('-n', MOCK_NS, 'exec', 'ds/amd-gpu-mock', '--', 'cat', '/var/lib/amd-gpu-mock/' + path).strip()
    try:
        api('/api/actions/recover?gpu=0', True)
        hot = api('/api/actions/overheat?gpu=0', True)
        assert hot['temperature_c'] == 105
        assert file('sys/class/drm/card0/device/hwmon/hwmon0/temp1_input') == '105000'
        print('PASS: dashboard overheat action -> API state 105C -> synthetic hwmon 105000mC')
        api('/api/actions/recover?gpu=0', True)
        ecc = api('/api/actions/ecc-error?gpu=0&count=7', True)
        assert ecc['ecc_errors'] == 7
        assert file('sys/class/kfd/kfd/topology/nodes/1/ras/ecc_uncorrectable') == '7'
        print('PASS: dashboard ECC action -> API count7 -> KFD RAS counter7')
        api('/api/actions/recover?gpu=0', True)
        busy = api('/api/actions/busy?gpu=0', True)
        assert busy['utilization_pct'] == 85
        print('PASS: busy action changes GPU utilization:', busy['utilization_pct'])
        idle = api('/api/actions/idle?gpu=0', True)
        assert idle['utilization_pct'] == 0
        print('PASS: idle action restores zero utilization')
    finally:
        restored = api('/api/actions/recover?gpu=0', True)
        assert restored['status'] == 'healthy' and restored['ecc_errors'] == 0
        print('PASS: healthy state restored; no workload eviction or remediation claim')
