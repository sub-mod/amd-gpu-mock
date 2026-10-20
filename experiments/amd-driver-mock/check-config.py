#!/usr/bin/env python3
"""Fail before provisioning when a requested backend is not implemented."""
import json,sys
from pathlib import Path
p=Path(sys.argv[1]) if len(sys.argv)>1 else Path(__file__).with_name('config.json')
c=json.loads(p.read_text())
for key,value in [('backend','library'),('profile','mi300x'),('physicalGPUCount',1),('partition','SPX'),('cluster','amd-hami-driver'),('shareSlots',4)]:
 if c.get(key)!=value:raise SystemExit(f'Unsupported {key}={c.get(key)!r}; tested experiment requires {value!r}')
for key in ['backend','plugin','scheduler']:
 if not isinstance(c.get('images',{}).get(key),str) or not c['images'][key]:raise SystemExit('Missing image: '+key)
print('PASS: explicit library backend, one MI300X/SPX, four HAMi share slots')
