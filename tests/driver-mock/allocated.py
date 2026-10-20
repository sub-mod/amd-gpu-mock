#!/usr/bin/env python3
"""Prove native opens and libdrm queries inside genuinely allocated Pods."""
import json
import os
import subprocess
import time

MODE = os.environ.get('ALLOCATOR', 'dra')
IMAGE = os.environ.get('DRIVER_IMAGE', 'local/amd-gpu-mock-driver:test')
NS = 'amd-driver-consumer-test'

def k(*args, payload=None):
    return subprocess.check_output(['kubectl', *args], input=json.dumps(payload) if payload else None, text=True)

def apply(obj):
    k('apply', '-f', '-', payload=obj)

apply({'apiVersion':'v1','kind':'Namespace','metadata':{'name':NS}})
try:
    if MODE == 'dra':
        apply({'apiVersion':'resource.k8s.io/v1','kind':'ResourceClaimTemplate',
               'metadata':{'name':'gpu','namespace':NS},'spec':{'spec':{'devices':{'requests':[
                   {'name':'gpu','exactly':{'deviceClassName':'gpu.amd.com'}}]}}}})
    spec = {'restartPolicy':'Never','containers':[{'name':'consumer','image':IMAGE,
            'imagePullPolicy':'Never','command':['sh','-ec', '''
set -- /dev/dri/renderD*
test "$#" = 1
test -c "$1"
exec 3<>/dev/kfd
driver-probe "$1" 304 206158430208 'AMD Instinct MI300X'
echo 'PASS: allocated workload native KFD/render access and libdrm capacity'
'''], 'volumeMounts':[{'name':'state','mountPath':'/var/lib/amd-gpu-mock','readOnly':True}]}],
            'volumes':[{'name':'state','hostPath':{'path':'/var/lib/amd-gpu-mock','type':'Directory'}}]}
    if MODE == 'dra':
        spec['resourceClaims']=[{'name':'gpu','resourceClaimTemplateName':'gpu'}]
        spec['containers'][0]['resources']={'claims':[{'name':'gpu'}]}
    else:
        spec['containers'][0]['resources']={'limits':{'amd.com/gpu':1}}
    apply({'apiVersion':'v1','kind':'Pod','metadata':{'name':'consumer','namespace':NS},'spec':spec})
    end=time.monotonic()+180
    while time.monotonic()<end:
        p=json.loads(k('get','pod','consumer','-n',NS,'-o','json'))
        if p['status']['phase'] in ['Succeeded','Failed']:
            logs=k('logs','consumer','-n',NS);print(logs,flush=True)
            assert p['status']['phase']=='Succeeded',p['status']
            assert 'PASS: allocated workload native KFD/render access and libdrm capacity' in logs
            break
        time.sleep(2)
    else:
        raise TimeoutError('allocated consumer did not complete')
finally:
    k('delete','namespace',NS,'--wait=true','--timeout=120s')
