#!/usr/bin/env python3
"""Remove the completed Spur presentation and restore Tiny LLM."""
from pathlib import Path
import subprocess
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]))
from common import guard, oc

if __name__=='__main__':
    node=guard()
    ns='amd-crc-spur'
    if oc('get','namespace',ns,'--ignore-not-found','-o','name').strip():
        # Keep the operator alive while it handles SpurJob finalizers.
        oc('-n',ns,'delete','spurjobs','--all','--wait=true','--timeout=120s')
        oc('delete','namespace',ns,'--wait=true','--timeout=120s')
    oc('delete','clusterrolebinding','amd-crc-spur-operator','--ignore-not-found')
    oc('delete','clusterrole','amd-crc-spur-operator','--ignore-not-found')
    oc('label','node',node['metadata']['name'],'spur.amd.com/managed-',
       'spur.amd.com/gpu-type-','spur.amd.com/gpu-memory-mb-')
    subprocess.run([sys.executable,str(Path(__file__).resolve().parents[1]/'tiny-llm/run.py'),'install'],check=True)
    print('PASS: Spur demo removed, Tiny LLM restored; shared SpurJob CRD retained')
