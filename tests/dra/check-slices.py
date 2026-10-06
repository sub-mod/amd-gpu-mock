#!/usr/bin/env python3
"""Validate every advertised device on the mock nodes, from kubectl JSON."""
import json
import re
import sys

expected = int(sys.argv[1])
nodes = set(sys.argv[2:])
slices = [s for s in json.load(sys.stdin)['items']
          if s['spec']['driver'] == 'gpu.amd.com'
          and s['spec'].get('nodeName') in nodes]
devices = []
seen = set()
for item in slices:
    spec = item['spec']
    for device in spec.get('devices', []):
        key = (spec['nodeName'], spec['pool']['name'], device['name'])
        if key in seen:
            raise SystemExit(f'Duplicate device: {key}')
        seen.add(key)
        attributes = device.get('attributes', {})
        for name, kind in [('productName', 'string'), ('driverVersion', 'version'),
                           ('resource.kubernetes.io/pciBusID', 'string'),
                           ('resource.kubernetes.io/pcieRoot', 'string')]:
            if not attributes.get(name, {}).get(kind):
                raise SystemExit(f'{key}: missing {name}.{kind}')
        bdf = attributes['resource.kubernetes.io/pciBusID']['string']
        if not re.fullmatch(r'[0-9a-f]{4}:[0-9a-f]{2}:[0-9a-f]{2}\.[0-7]', bdf):
            raise SystemExit(f'{key}: invalid PCI BDF {bdf}')
        for name in ['computeUnits', 'memory']:
            if not device.get('capacity', {}).get(name, {}).get('value'):
                raise SystemExit(f'{key}: missing {name} capacity')
        devices.append(device)
if len(devices) != expected:
    raise SystemExit(f'Found {len(devices)} devices on mock nodes; expected {expected}')
print(f'Validated attributes and capacities on all {len(devices)} devices')
