#!/usr/bin/env python3
"""Deploy native ARM64 Spur on the existing OpenShift mock device-plugin node."""
from pathlib import Path
import base64
import json
import os
import secrets
import subprocess
import sys
import urllib.request
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from common import guard, oc, get, namespace, apply, MOCK_NS, GPU, api

ROOT=Path(__file__).resolve().parents[3]
NS='amd-crc-spur'
PIN='bd28e6395547377cb47c7d911390f99432a5fc73'

if __name__=='__main__':
    node=guard()
    if node['status']['nodeInfo']['architecture']!='arm64':
        raise RuntimeError('This lane validates the native ARM64 image')
    if int(node['status']['allocatable'].get(GPU,0))!=8:
        raise RuntimeError('Restore SPX/device-plugin mode before the Spur demo')
    if not oc('-n',MOCK_NS,'get','ds','amd-gpu-mock-device-plugin','--ignore-not-found','-o','name').strip():
        raise RuntimeError('Device plugin is not installed; restore its demo first')
    if oc('-n',MOCK_NS,'get','ds','amd-gpu-mock-dra-kubeletplugin','--ignore-not-found','-o','name').strip():
        raise RuntimeError('DRA must be stopped before the device-plugin Spur demo')
    inventory=api('/api/gpus')['gpus']
    if len(inventory)!=8 or any(g['profile_slug']!='mi300x' or g['memory_total_mb']!=196608 for g in inventory):
        raise RuntimeError('Requires the eight-GPU MI300X/SPX mock profile')
    # Spur owns its managed GPU pool; unrelated consumers would bypass its queue.
    consumers=[]
    for p in json.loads(oc('get','pods','-A','-o','json'))['items']:
        if p['status']['phase'] not in ['Succeeded','Failed'] and any(GPU in c.get('resources',{}).get('requests',{}) for c in p['spec']['containers']):
            if (p['metadata']['namespace'],p['metadata']['name'])!=(MOCK_NS,'tiny-llm'):
                raise RuntimeError('Clean up the existing GPU consumer: '+p['metadata']['namespace']+'/'+p['metadata']['name'])
            consumers.append(p)
    for p in consumers:
        oc('-n',MOCK_NS,'delete','pod','tiny-llm','--wait=true','--timeout=120s')
    namespace(NS)
    oc('label','node',node['metadata']['name'],'spur.amd.com/managed=true',
       'spur.amd.com/gpu-type=mi300x','spur.amd.com/gpu-memory-mb=196608',
       '--overwrite')
    crd=urllib.request.urlopen('https://raw.githubusercontent.com/ROCm/spur/'+PIN+'/examples/k8s/spurjob-crd.yaml').read().decode()
    oc('apply','-f','-',input=crd)
    oc('wait','--for=condition=Established','crd/spurjobs.spur.amd.com','--timeout=60s')
    if not oc('-n',NS,'get','secret','spur-auth','--ignore-not-found','-o','name').strip():
        apply({'apiVersion':'v1','kind':'Secret','metadata':{'name':'spur-auth','namespace':NS},
               'data':{'jwt-key':base64.b64encode(secrets.token_hex(32).encode()).decode()}})
    apply({'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'spur-config','namespace':NS},
           'data':{'spur.conf':(ROOT/'demo/spur/spur.conf').read_text()}})
    pin=dict(line.split('=',1) for line in (Path(__file__).parent/'versions.env').read_text().splitlines() if line and not line.startswith('#'))
    image=os.environ.get('SPUR_ARM64_IMAGE',pin['SPUR_ARM64_IMAGE'])
    env=dict(os.environ,SPUR_IMAGE=image)
    # Reuse the existing integration configuration; adapt admission and namespace only.
    text=subprocess.check_output([sys.executable,str(ROOT/'demo/spur/manifests.py')],env=env,text=True)
    items=json.loads(text.replace('amd-demo-spur',NS).replace('amd-mock-spur-operator','amd-crc-spur-operator'))['items']
    for d in items:
        if d['kind']=='Deployment':
            tmpl=d['spec']['template']
            tmpl['metadata']['annotations']={'openshift.io/required-scc':'restricted-v2'}
            tmpl['spec']['securityContext']={'runAsNonRoot':True,'seccompProfile':{'type':'RuntimeDefault'}}
            for c in tmpl['spec']['containers']:
                c['securityContext']={'allowPrivilegeEscalation':False,'capabilities':{'drop':['ALL']}}
    for d in items: apply(d)
    for name in ['spurctld','spur-k8s-operator']:
        oc('-n',NS,'rollout','status','deploy/'+name,'--timeout=600s')
    print('PASS: native ARM64 Spur controller/operator ready under restricted-v2')
