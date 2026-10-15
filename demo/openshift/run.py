#!/usr/bin/env python3
"""Run individual OpenShift demos in their documented dependency order."""
import argparse
from pathlib import Path
import subprocess
import sys
from common import guard, oc
HERE = Path(__file__).resolve().parent
STAGES = {
    'tiny-llm': 'tiny-llm/run.py', 'multi-gpu': 'multi-gpu/run.py',
    'allocation': 'allocation/run.py', 'faults': 'faults/run.py',
    'profiles': 'profiles/run.py', 'partitioning': 'partitioning/run.py',
    'dra': 'dra/run.py', 'telemetry': 'telemetry/run.py',
    'partition-allocation': 'partition-allocation/run.py',
    'network-preflight': 'gpu-network/preflight.py', 'spur-preflight': 'spur/preflight.py',
    'spur': 'spur/run.py',
    'restore': 'restore-device-plugin.py',
}
if __name__ == '__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('demo',choices=['list',*STAGES])
    args=parser.parse_args()
    if args.demo=='list':
        for name in STAGES:
            detail=' — executable demo'
            if name=='network-preflight': detail=' — prerequisite probe only; see guide for current blocker'
            elif name.endswith('preflight'): detail=' — published image architecture check'
            print(name + detail)
        sys.exit(0)
    guard()
    if args.demo in ['multi-gpu','allocation']:
        if not oc('-n','amd-mock-crc-llm','get','ds','amd-gpu-mock-device-plugin','--ignore-not-found','-o','name').strip():
            raise RuntimeError('Device-plugin demo requires SPX mode: run restore first')
    if args.demo=='partition-allocation':
        oc('delete','namespace','amd-crc-dra','--ignore-not-found','--wait=true','--timeout=120s')
    if args.demo in ['dra','telemetry','spur']:
        if subprocess.run([sys.executable,str(HERE/args.demo/'setup.py')]).returncode:
            sys.exit(1)
    command=[sys.executable,str(HERE/STAGES[args.demo])]
    if args.demo=='tiny-llm': command.append('install')
    sys.exit(subprocess.run(command).returncode)
