#!/usr/bin/env python3
"""Run the existing real Spur queue/allocation proof against CRC."""
import importlib.util
import os
from pathlib import Path
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from common import guard, get

if __name__=='__main__':
    guard()
    # Prevent the Kind presenter from selecting its separate cluster kubeconfig.
    if not os.environ.get('KUBECONFIG'):
        raise RuntimeError('Set KUBECONFIG explicitly to the CRC admin kubeconfig')
    os.environ['SPUR_KUBECONFIG']=os.environ['KUBECONFIG']
    spec=importlib.util.spec_from_file_location('existing_spur_demo',Path(__file__).resolve().parents[2]/'spur/run.py')
    presenter=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(presenter)
    presenter.NS='amd-crc-spur'
    pin=dict(line.split('=',1) for line in (Path(__file__).parent/'versions.env').read_text().splitlines() if line and not line.startswith('#'))
    expected=os.environ.get('SPUR_ARM64_IMAGE',pin['SPUR_ARM64_IMAGE'])
    for p in get('pods',namespace=presenter.NS)['items']:
        if p['metadata']['name'].startswith(('spurctld-','spur-k8s-operator-')):
            assert p['spec']['containers'][0]['image']==expected
            print('RUNTIME_IMAGE',p['metadata']['name'],expected,flush=True)
    original_show=presenter.show
    def show(name,count):
        pod_name=original_show(name,count)
        pod=get('pod',pod_name,presenter.NS)
        assert pod['metadata']['annotations']['openshift.io/scc']=='restricted-v2'
        print('APPLICATION_SCC restricted-v2',flush=True)
        return pod_name
    presenter.show=show
    presenter.main()
    for p in get('pods',namespace=presenter.NS)['items']:
        assert p['metadata']['annotations']['openshift.io/scc']=='restricted-v2'
    print('PASS: ARM64 Spur queueing, GPU allocation, completion and reuse on OpenShift; all Pods restricted-v2',flush=True)
