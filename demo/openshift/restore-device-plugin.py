#!/usr/bin/env python3
"""Return the dedicated CRC demos to SPX/device-plugin Tiny LLM mode."""
from pathlib import Path
import json
import subprocess
import sys
sys.path.insert(0, str(Path(__file__).resolve().parent))
from common import guard, oc, get, MOCK_NS

if __name__ == '__main__':
    guard()
    owned={'amd-crc-dra','amd-crc-partition-allocation'}
    claims=json.loads(oc('get','resourceclaims','-A','-o','json'))['items']
    if any(c['metadata']['namespace'] not in owned for c in claims):
        raise RuntimeError('Unrelated DRA claim: refusing allocator/topology change')
    for ns in sorted(owned):
        oc('delete','namespace',ns,'--ignore-not-found','--wait=true','--timeout=120s')
    oc('-n',MOCK_NS,'delete','ds','amd-gpu-mock-dra-kubeletplugin','--ignore-not-found','--wait=true')
    for s in get('resourceslices')['items']:
        if s['spec']['driver']=='gpu.amd.com':
            oc('delete','resourceslice',s['metadata']['name'])
    ds=get('ds','amd-gpu-mock',MOCK_NS)
    args=['--partition=SPX' if a.startswith('--partition=') else a
          for a in ds['spec']['template']['spec']['containers'][0]['args']]
    oc('-n',MOCK_NS,'patch','ds','amd-gpu-mock','--type=json','-p',json.dumps([
       {'op':'replace','path':'/spec/template/spec/containers/0/args','value':args}]))
    oc('-n',MOCK_NS,'rollout','status','ds/amd-gpu-mock','--timeout=300s')
    subprocess.run([sys.executable,str(Path(__file__).resolve().parent/'tiny-llm/run.py'),'install'],check=True)
    if oc('-n',MOCK_NS,'get','ds','amd-gpu-mock-metrics-exporter','--ignore-not-found','-o','name').strip():
        oc('-n',MOCK_NS,'rollout','restart','ds/amd-gpu-mock-metrics-exporter')
        oc('-n',MOCK_NS,'rollout','status','ds/amd-gpu-mock-metrics-exporter','--timeout=300s')
    print('PASS: SPX inventory and device-plugin Tiny LLM restored')
