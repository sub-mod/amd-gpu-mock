#!/usr/bin/env python3
"""Assert real HAMi registration, fractional allocation, exhaustion and reuse."""
import json,subprocess,time,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
KUBE=ROOT/'tmp/hami-main/kubeconfig'
NS='amd-hami-demo'
def k(*args,obj=None,check=True):
 r=subprocess.run(['kubectl','--kubeconfig',str(KUBE),*args],input=None if obj is None else json.dumps(obj),text=True,capture_output=True)
 if check and r.returncode:raise RuntimeError(r.stderr)
 return r.stdout
def get(kind,name=None):return json.loads(k('-n',NS,'get',kind,*([name] if name else []),'-o','json'))
def wait(fn,label,seconds=120):
 end=time.monotonic()+seconds
 while time.monotonic()<end:
  if fn():print('PASS:',label,flush=True);return
  time.sleep(1)
 raise RuntimeError('timeout: '+label)
def apply(obj):print(k('apply','-f','-',obj=obj),end='',flush=True)
def running(name):return get('pod',name)['status'].get('phase')=='Running'
code='''import os,glob,stat,json,time
paths=['/dev/kfd']+glob.glob('/dev/dri/*')
assert any('renderD128' in p for p in paths)
for p in paths:
 assert stat.S_ISCHR(os.stat(p).st_mode),p
 fd=os.open(p,os.O_RDONLY);os.close(fd)
keys=['HSA_CU_MASK','ROCR_VISIBLE_DEVICES','HIP_VISIBLE_DEVICES','HIP_DEVICE_MEMORY_LIMIT_0','LD_AUDIT']
print(json.dumps({'devices':paths,'settings':{k:os.environ.get(k) for k in keys},'native_device_open':True,'gpu_compute':False}),flush=True)
time.sleep(3600)
'''
def pod(name,cores=50,mem=98304):
 return {'apiVersion':'v1','kind':'Pod','metadata':{'name':name,'namespace':NS},'spec':{'restartPolicy':'Never','containers':[{'name':'consumer','image':'docker.io/library/python:3.12-slim','command':['python3','-u','-c',code],'resources':{'limits':{'amd.com/gpu':1,'amd.com/gpucores':cores,'amd.com/gpumem':mem}}}]}}
def evidence(name):
 data=json.loads(k('-n',NS,'logs',name).strip().splitlines()[-1]);p=get('pod',name)
 print('EVIDENCE',name,json.dumps({'podUID':p['metadata']['uid'],'node':p['spec'].get('nodeName'),'scheduler':p['spec']['schedulerName'],'allocation':p['metadata'].get('annotations',{}).get('hami.io/amd-devices-allocated'),'consumer':data}),flush=True)
 assert p['spec']['schedulerName']=='hami-scheduler'
 assert data['settings']['LD_AUDIT']=='/usr/local/vgpu/libamvgpu.so'
 assert data['settings']['HIP_DEVICE_MEMORY_LIMIT_0']=='98304m'
 assert data['native_device_open'] and data['settings']['ROCR_VISIBLE_DEVICES']=='GPU-9c4f000000000001'
 return data
assert k('config','current-context').strip()=='kind-amd-hami-main'
node=get('nodes')['items'][0]
devices=json.loads(node['metadata']['annotations']['hami.io/node-amd-register'])
assert len(devices)==1 and devices[0]['devcore']==304 and devices[0]['devmem']==196608 and devices[0]['count']==4
assert node['status']['allocatable']['amd.com/gpu']=='4'
print('PASS: native HAMi registers one original-profile MI300X: 304 CU, 192 GiB, 4 share slots',flush=True)
if k('get','namespace',NS,'--ignore-not-found','-o','name').strip():raise RuntimeError('demo namespace already exists; clean it explicitly before rerun')
apply({'apiVersion':'v1','kind':'Namespace','metadata':{'name':NS,'labels':{'amd-driver-mock/demo':'true'}}})
for name in ['left','right']:
 apply(pod(name));wait(lambda:running(name),name+' running through HAMi')
left=evidence('left');right=evidence('right')
def cus(mask):
 gpu,ids=mask.split(':',1);assert gpu=='0'
 out=set()
 for part in ids.split(','):
  if '-' in part:
   a,b=map(int,part.split('-'));out.update(range(a,b+1))
  else:out.add(int(part))
 return out
l,r=cus(left['settings']['HSA_CU_MASK']),cus(right['settings']['HSA_CU_MASK'])
assert len(l)==len(r)==152 and not(l&r) and len(l|r)==304
print('PASS: two Pods share one GPU with disjoint 152-CU masks and 96-GiB configured memory limits; no hardware isolation claim',flush=True)
apply(pod('waiting'))
time.sleep(8)
p=get('pod','waiting');assert p['status']['phase']=='Pending' and not p['spec'].get('nodeName')
print('PASS: third Pod remains unbound/Pending when the physical GPU share budget is full',flush=True)
k('-n',NS,'delete','pod','left','--wait=true','--timeout=60s')
wait(lambda:running('waiting'),'released budget admits waiting consumer')
evidence('waiting');assert running('right')
print('PASS: budget reuse while sibling remains Running; real HAMi scheduler and plugin, no forged allocation annotations',flush=True)
