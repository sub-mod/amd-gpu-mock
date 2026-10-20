#!/usr/bin/env python3
"""Kill the real provider process, then require an actual container restart."""
import json
import os
import subprocess
import time

def k(*args, check=True):
    return subprocess.run(['kubectl', *args], capture_output=True, text=True, check=check).stdout

def snapshot():
    pods=json.loads(k('-n','amd-mock','get','pods','-l','app.kubernetes.io/name=amd-gpu-mock','-o','json'))['items']
    assert len(pods)==1
    return pods[0]

mode=os.environ.get('PROVIDER_RESTART_MODE','unclean')
assert mode in ['unclean','graceful']
signal='KILL' if mode=='unclean' else 'TERM'
before=snapshot()
def inodes():
 return k('-n','amd-mock','exec','ds/amd-gpu-mock','--','stat','-c','%i','/var/lib/amd-gpu-mock/sys','/var/lib/amd-gpu-mock/smi').splitlines()
previous_inodes=inodes()
restarts=before['status']['containerStatuses'][0]['restartCount']
# Terminate node-agent itself, not PID 1; no simulated successful restart.
result=k('-n','amd-mock','exec',before['metadata']['name'],'--','sh','-ec', '''
for p in /proc/[0-9]*/comm; do
 read name < "$p"
 if [ "$name" = node-agent ]; then
  pid=${p#/proc/}; pid=${pid%/comm}
  echo "Killing actual node-agent PID $pid"
  kill -KILL "$pid"
  exit 0
 fi
done
exit 1
'''.replace('kill -KILL','kill -'+signal),check=False)
print(result,flush=True)
end=time.monotonic()+180
while time.monotonic()<end:
    after=snapshot()
    statuses=after['status'].get('containerStatuses',[])
    if statuses and statuses[0]['restartCount']>restarts and statuses[0]['ready']:
        assert after['metadata']['uid']==before['metadata']['uid']
        assert inodes()==previous_inodes, 'mounted sys/SMI directory inodes changed'
        print('PASS actual %s node-agent restart: count %d -> %d; mounted directories preserved, CUSE/API ready' % (mode,restarts,statuses[0]['restartCount']),flush=True)
        break
    time.sleep(2)
else:
    raise TimeoutError('provider did not restart and become ready')
