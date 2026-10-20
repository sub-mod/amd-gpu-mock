#!/usr/bin/env python3
"""Adapt the pinned upstream HAMi chart to the explicit driver-mock backend."""
import json,subprocess,os
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
KUBE=ROOT/'tmp/hami-main/kubeconfig'
def k(*args):return subprocess.check_output(['kubectl','--kubeconfig',str(KUBE),*args],text=True)
assert k('config','current-context').strip()=='kind-amd-hami-main'
config=json.loads((ROOT/'tmp/hami-main/images.json').read_text())
source=ROOT/'tmp/hami-main/amd-device-plugin'
out=subprocess.check_output(['helm','template','amd-gpu',str(source/'helm/amd-gpu'),'-n','amd-hami','--set','dp.hookInstaller.enabled=false','--set','dp.healthPulse=2','--set','dp.dmemBackend=false','--set','dp.splitCount=4'],text=True)
converted=subprocess.run(['kubectl','--kubeconfig',str(KUBE),'create','--dry-run=client','--validate=false','-f','-','-o','json'],input=out,text=True,capture_output=True,check=True)
objects=[]
remaining=converted.stdout.lstrip()
decoder=json.JSONDecoder()
while remaining:
 obj,end=decoder.raw_decode(remaining)
 objects.extend(obj['items'] if obj.get('kind')=='List' else [obj])
 remaining=remaining[end:].lstrip()
for obj in objects:
 if not obj:continue
 if obj['kind']=='DaemonSet':
  spec=obj['spec']['template']['spec'];spec['tolerations']=[{'operator':'Exists'}]
  c=spec['containers'][0];c['image']=config['images']['plugin'];c['imagePullPolicy']='IfNotPresent'
  c['command']=['/opt/amd-driver-mock/bin/hami-device-plugin'];c.pop('lifecycle',None)
  for e in c['env']:
   if e['name']=='HOST_HOOK_PATH':e['value']='/var/lib/amd-gpu-mock'
  c['env'] += [{'name':'AMD_DRIVER_MOCK_ROOT','value':'/var/lib/amd-gpu-mock'},{'name':'MOCK_AMDSMI_STATE_DIR','value':'/var/lib/amd-gpu-mock/smi'},{'name':'LD_LIBRARY_PATH','value':'/var/lib/amd-gpu-mock/driver/usr/lib64'}]
  spec['initContainers']=[{'name':'stage-hook','image':config['images']['plugin'],'command':['sh','-ec','mkdir -p /state/vgpu; cp /opt/hami/lib/amd/libamvgpu.so /state/vgpu/'],'volumeMounts':[{'name':'driver-mock','mountPath':'/state'}]}]
  c['volumeMounts'].append({'name':'driver-mock','mountPath':'/var/lib/amd-gpu-mock','readOnly':True})
  spec['volumes'].append({'name':'driver-mock','hostPath':{'path':'/var/lib/amd-gpu-mock','type':'Directory'}})
  for v in spec['volumes']:
   if v['name']=='sys':v['hostPath']['path']='/var/lib/amd-gpu-mock/sys'
objects.insert(0,{'apiVersion':'v1','kind':'Namespace','metadata':{'name':'amd-hami'}})
p=ROOT/'tmp/hami-main/plugin-manifest.json';p.write_text(json.dumps({'apiVersion':'v1','kind':'List','items':objects}))
print(k('apply','-f',str(p)))
