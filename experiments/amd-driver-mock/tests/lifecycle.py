#!/usr/bin/env python3
"""Real plugin restart and library-level fault -> kubelet health propagation."""
import json,subprocess,time,os
from pathlib import Path
root=Path(__file__).resolve().parents[3]
kube=root/'tmp/hami/kubeconfig'
def k(*args):return subprocess.check_output(['kubectl','--kubeconfig',str(kube),*args],text=True)
def get(kind,name):return json.loads(k('-n','amd-driver-mock-demo','get',kind,name,'-o','json'))
def wait(fn,label):
 for _ in range(90):
  if fn():print('PASS:',label,flush=True);return
  time.sleep(1)
 raise RuntimeError(label)
node='amd-hami-driver-control-plane'
assert k('config','current-context').strip()=='kind-amd-hami-driver'
before={name:get('pod',name)['metadata']['uid'] for name in ['right','waiting']}
k('-n','amd-hami','rollout','restart','ds/amd-gpu-device-plugin-daemonset')
k('-n','amd-hami','rollout','status','ds/amd-gpu-device-plugin-daemonset','--timeout=90s')
wait(lambda:get('node',node)['status']['allocatable'].get('amd.com/gpu')=='4','plugin restart restores four share slots')
for name,uid in before.items():
 p=get('pod',name);assert p['metadata']['uid']==uid and p['status']['phase']=='Running'
print('PASS: both existing consumer Pod identities survive plugin replacement',flush=True)
def fault(value):
 subprocess.run([os.environ.get('CONTAINER_RUNTIME','podman'),'exec','amd-driver-mock-provider','sh','-ec',f'mkdir -p /state/sys/class/kfd/kfd/topology/nodes/1/ras; printf "{value}\\n" > /state/sys/class/kfd/kfd/topology/nodes/1/ras/fatal_error'],check=True)
try:
 fault(1)
 wait(lambda:get('node',node)['status']['allocatable'].get('amd.com/gpu')=='0','simulated fatal state -> libdrm initialization failure -> real HAMi ListAndWatch -> kubelet allocatable=0')
finally:fault(0)
wait(lambda:get('node',node)['status']['allocatable'].get('amd.com/gpu')=='4','recovery restores kubelet share-slot advertisement')
print('Existing processes are not claimed to be evicted or to execute kernels.',flush=True)
