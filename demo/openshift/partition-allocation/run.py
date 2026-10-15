#!/usr/bin/env python3
"""Two restricted containers receive distinct DPX slices of one physical GPU."""
from pathlib import Path
import sys
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from common import guard, get, oc, apply, namespace, wait, MOCK_NS
import json

NS = 'amd-crc-partition-allocation'


def devices():
    return {d['name']:d for s in get('resourceslices')['items'] if s['spec']['driver']=='gpu.amd.com'
            for d in s['spec']['devices']}


if __name__ == '__main__':
    guard()
    # Topology changes require draining every live claim, not changing its status.
    for claim in get('resourceclaims')['items']:
        raise RuntimeError('Drain claims before partitioning: ' + claim['metadata']['name'])
    # Include every namespace in the safety check.
    if json.loads(oc('get', 'resourceclaims', '-A', '-o', 'json'))['items']:
        raise RuntimeError('Delete existing demo consumers and their claims before changing topology')
    ds = get('ds', 'amd-gpu-mock', MOCK_NS)
    args = ds['spec']['template']['spec']['containers'][0]['args']
    args = ['--partition=DPX' if arg.startswith('--partition=') else arg for arg in args]
    oc('-n', MOCK_NS, 'patch', 'ds', 'amd-gpu-mock', '--type=json', '-p', json.dumps([
        {'op':'replace','path':'/spec/template/spec/containers/0/args','value':args}]))
    oc('-n', MOCK_NS, 'rollout', 'status', 'ds/amd-gpu-mock', '--timeout=300s')
    oc('-n', MOCK_NS, 'rollout', 'restart', 'ds/amd-gpu-mock-dra-kubeletplugin')
    oc('-n', MOCK_NS, 'rollout', 'status', 'ds/amd-gpu-mock-dra-kubeletplugin', '--timeout=300s')
    wait(lambda: len(devices()) == 16, 'AMD DRA discovers 16 DPX slices from eight physical GPUs')
    ds = devices()
    assert all(d['attributes']['type']['string']=='amdgpu-partition' for d in ds.values())
    assert all(d['capacity']['memory']['value']=='96Gi' for d in ds.values())
    namespace(NS)
    apply({'apiVersion':'resource.k8s.io/v1','kind':'ResourceClaim','metadata':{'name':'same-gpu','namespace':NS},
           'spec':{'devices':{'requests':[{'name':r,'exactly':{'deviceClassName':'gpu.amd.com'}} for r in ['a','b']],
             'constraints':[{'requests':['a','b'],'matchAttribute':'resource.kubernetes.io/pciBusID'}]}}})
    code="import glob,os,stat,time; paths=glob.glob('/dev/dri/renderD*'); assert len(paths)==1; assert stat.S_ISCHR(os.stat('/dev/kfd').st_mode); print(paths[0],flush=True); time.sleep(86400)"
    apply({'apiVersion':'v1','kind':'Pod','metadata':{'name':'two-slices','namespace':NS,
           'annotations':{'openshift.io/required-scc':'restricted-v2'}},'spec':{
             'restartPolicy':'Never','terminationGracePeriodSeconds':1,
             'securityContext':{'runAsNonRoot':True,'seccompProfile':{'type':'RuntimeDefault'}},
             'resourceClaims':[{'name':'slices','resourceClaimName':'same-gpu'}],
             'containers':[{'name':r,'image':'docker.io/library/python:3.11-slim',
               'command':['python3','-u','-c',code],
               'securityContext':{'allowPrivilegeEscalation':False,'capabilities':{'drop':['ALL']}},
               'resources':{'claims':[{'name':'slices','request':r}]}} for r in ['a','b']]}})
    oc('-n',NS,'wait','pod/two-slices','--for=condition=Ready','--timeout=180s')
    results=get('resourceclaim','same-gpu',NS)['status']['allocation']['devices']['results']
    assert len(results)==2 and len({a['device'] for a in results})==2
    assert len({ds[a['device']]['attributes']['resource.kubernetes.io/pciBusID']['string'] for a in results})==1
    for r in ['a','b']:
        a=next(a for a in results if a['request']==r)
        render=oc('-n',NS,'logs','two-slices','-c',r).strip()
        assert render=='/dev/dri/renderD'+a['device'].split('-')[-1]
        print('EVIDENCE',r,a['device'],render,'memory=96Gi parent='+ds[a['device']]['attributes']['resource.kubernetes.io/pciBusID']['string'])
    assert get('pod','two-slices',NS)['metadata']['annotations']['openshift.io/scc']=='restricted-v2'
    print('PASS: two restricted containers, distinct allocated slices, same physical GPU parent; no real memory isolation or compute claim')
