#!/usr/bin/env python3
"""Allocated-Pod validation; no allocation env is supplied by this script."""
import json,os,subprocess,time
from pathlib import Path
root=Path(__file__).resolve().parents[3];out=root/'tmp/rocjitsu-results';out.mkdir(parents=True,exist_ok=True)
runtime=os.environ.get('CONTAINER_RUNTIME','podman');kube=root/'tmp/hami/kubeconfig'
def run(a,**kw):return subprocess.check_output(a,text=True,**kw)
def k(*a,**kw):return run(['kubectl','--kubeconfig',str(kube),*a],**kw)
assert k('config','current-context').strip()=='kind-amd-hami-driver'
ns='amd-driver-mock-demo';image=os.environ.get('COMPUTE_IMAGE','docker.io/submod/amd-driver-mock-compute:0.1.0-experiment.1-amd64')
# Inputs are read from the provider's actual original-renderer output.
for name,path in [('shared-properties','sys/class/kfd/kfd/topology/nodes/1/properties'),('shared-smi','smi/gpu0')]:
 (out/name).write_text(run([runtime,'exec','amd-driver-mock-provider','cat','/state/'+path]))
subprocess.run(['python3',str(Path(__file__).with_name('shared-config.py')),str(out/'shared-properties'),str(out/'shared-smi'),str(root/'tmp/rocjitsu-eval/emulation/rocjitsu/configs/gfx942_cdna3_kmd.json'),str(out/'shared-config.json')],check=True)
# Explicit architecture selection for this dedicated lab, not a changed upstream plugin.
subprocess.run([runtime,'run','--rm','--entrypoint','sh','-v','amd-driver-mock-state:/state',image,'-ec','mkdir -p /state/amd64/vgpu; cp /opt/compute/hook/libamvgpu.so /state/amd64/vgpu/'],check=True)
k('create','namespace',ns,'--dry-run=client','-o','yaml')
subprocess.run(['kubectl','--kubeconfig',str(kube),'apply','-f','-'],input=k('create','namespace',ns,'--dry-run=client','-o','yaml'),text=True,check=True)
ds='amd-gpu-device-plugin-daemonset'
prior=json.loads(k('-n','amd-hami','get','ds',ds,'-o','json'))
old=next(e['value'] for e in prior['spec']['template']['spec']['containers'][0]['env'] if e['name']=='HOST_HOOK_PATH')
cmd='''set -eu
for program in limits hip_vector_add_test; do
 /opt/compute/bin/rocjitsu --config /etc/compute/gpu.json -- /usr/bin/env LD_PRELOAD=/opt/compute/lib/libmask-audit.so:/opt/compute/lib/librocjitsu.so /opt/compute/bin/$program
done
echo 'PASS: allocated Pod computation complete'
sleep infinity
'''
objects=[{'apiVersion':'v1','kind':'ConfigMap','metadata':{'name':'rocjitsu-shared-profile','namespace':ns},'data':{'gpu.json':(out/'shared-config.json').read_text()}}]
for side in ['left','right']:
 objects.append({'apiVersion':'v1','kind':'Pod','metadata':{'name':'compute-'+side,'namespace':ns,'labels':{'app':'amd-mock-compute'}},'spec':{'restartPolicy':'Never','terminationGracePeriodSeconds':1,'containers':[{'name':'compute','image':image,'imagePullPolicy':'IfNotPresent','command':['/bin/sh','-ec',cmd],'env':[{'name':'QEMU_GUEST_BASE','value':'0x800000000000'}] if os.environ.get('COMPUTE_QEMU')=='1' else [],'resources':{'limits':{'amd.com/gpu':1,'amd.com/gpucores':50,'amd.com/gpumem':64}},'volumeMounts':[{'name':'config','mountPath':'/etc/compute','readOnly':True}]}],'volumes':[{'name':'config','configMap':{'name':'rocjitsu-shared-profile'}}]}})
(out/'compute-pods.json').write_text(json.dumps({'apiVersion':'v1','kind':'List','items':objects},indent=2))
try:
 print(k('-n','amd-hami','set','env','ds/'+ds,'HOST_HOOK_PATH=/var/lib/amd-driver-mock/amd64'),flush=True)
 print(k('-n','amd-hami','rollout','status','ds/'+ds,'--timeout=120s'),flush=True)
 print(k('apply','-f',str(out/'compute-pods.json')),flush=True)
 for _ in range(120):
  ok=True
  for side in ['left','right']:
   name='compute-'+side
   try:log=k('-n',ns,'logs',name)
   except subprocess.CalledProcessError:ok=False;continue
   (out/(name+'.log')).write_text(log)
   if 'PASS: allocated Pod computation complete' not in log:ok=False
   phase=json.loads(k('-n',ns,'get','pod',name,'-o','json'))['status']['phase']
   if phase=='Failed':raise RuntimeError(name+' failed; see '+str(out/(name+'.log')))
  if ok:break
  time.sleep(2)
 else:raise TimeoutError('compute Pods did not finish')
 allocations=[]
 for side in ['left','right']:
  p=json.loads(k('-n',ns,'get','pod','compute-'+side,'-o','json'))
  allocations.append(p['metadata']['annotations']['hami.io/amd-cu-allocated'])
  log=(out/('compute-'+side+'.log')).read_text()
  assert 'KFD_MASK' in log and 'result=0' in log and 'match=NO' not in log
  assert '[  PASSED  ] 1 test.' in log
  assert 'PASS: HIP memory cap, cumulative accounting, and free/reallocate' in log
 assert allocations[0]!=allocations[1]
 print('PASS: two genuinely allocated Pods, shared identity, memory enforcement, disjoint KFD masks and HIP computation',flush=True)
finally:
 print(k('-n','amd-hami','set','env','ds/'+ds,'HOST_HOOK_PATH='+old),flush=True)
 print(k('-n','amd-hami','rollout','status','ds/'+ds,'--timeout=120s'),flush=True)
