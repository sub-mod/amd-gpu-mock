#!/usr/bin/env python3
"""Real plugin restart and library-level fault -> kubelet health propagation."""
import json,subprocess,time,os
from pathlib import Path
root=Path(__file__).resolve().parents[2]
kube=root/'tmp/hami-main/kubeconfig'
def k(*args):return subprocess.check_output(['kubectl','--kubeconfig',str(kube),*args],text=True)
def get(kind,name):return json.loads(k('-n','amd-hami-demo','get',kind,name,'-o','json'))
def wait(fn,label):
 for _ in range(90):
  if fn():print('PASS:',label,flush=True);return
  time.sleep(1)
 raise RuntimeError(label)
node='amd-hami-main-control-plane'
assert k('config','current-context').strip()=='kind-amd-hami-main'
before={name:get('pod',name)['metadata']['uid'] for name in ['right','waiting']}
k('-n','amd-hami','rollout','restart','ds/amd-gpu-device-plugin-daemonset')
k('-n','amd-hami','rollout','status','ds/amd-gpu-device-plugin-daemonset','--timeout=90s')
wait(lambda:get('node',node)['status']['allocatable'].get('amd.com/gpu')=='4','plugin restart restores four share slots')
for name,uid in before.items():
 p=get('pod',name);assert p['metadata']['uid']==uid and p['status']['phase']=='Running'
print('PASS: both existing consumer Pod identities survive plugin replacement',flush=True)
def fault(value):
 action='crash' if value else 'recover'
 k('-n','amd-mock','exec','ds/amd-gpu-mock','--','wget','-qO-','--post-data=',
   'http://localhost:8080/api/actions/'+action+'?gpu=0')
try:
 fault(1)
 wait(lambda:get('node',node)['status']['allocatable'].get('amd.com/gpu')=='0','simulated fatal state -> libdrm initialization failure -> real HAMi ListAndWatch -> kubelet allocatable=0')
finally:fault(0)
wait(lambda:get('node',node)['status']['allocatable'].get('amd.com/gpu')=='4','recovery restores kubelet share-slot advertisement')
print('Existing processes are not claimed to be evicted or to execute kernels.',flush=True)
